import 'tts_lifecycle_checks.dart';
import 'assistant_role_checks.dart';
import 'assistant_entry_checks.dart';
import 'assistant_entry_ui_checks.dart';
import 'entry_intent_checks.dart';
import 'speech_capture_ui_checks.dart';
import 'speech_capture_checks.dart';
import 'personal_context_checks.dart';
import 'personal_context_sql_checks.dart';
import 'result_card_checks.dart';
import '../application/workspace_snapshot.dart';
import '../infrastructure/tools/command_tool.dart';
import '../application/project_kind.dart';
import '../application/development_verification.dart';
import 'dart:io';
import '../application/development_run_completion.dart';
import '../application/verification_execution_guard.dart';
import '../application/development_loop_finalizer.dart';
import '../application/headless_executor.dart';
import '../application/background_execution_gateway.dart';
import '../application/modules/module_host.dart';
import '../application/modules/run_profile.dart';
import '../infrastructure/providers/model_route.dart';
import '../infrastructure/providers/provider_config.dart';
import '../application/agent_loop/agent_loop_hooks.dart';
import 'package:dio/dio.dart' show CancelToken;
import '../infrastructure/providers/llm_provider.dart';
import 'approval_scope_ui_checks.dart';
import '../application/run_approval_scope.dart';
import '../domain/approval_action_codec.dart';
import 'dart:async';
import 'package:drift/drift.dart' show Variable;
import '../application/run_controller.dart';
import '../application/persisted_run_fence.dart';
import '../application/agent_executor.dart'
    show
        AgentExecutor,
        AgentEvent,
        AgentStatusEvent,
        ToolResultEvent,
        TextEvent,
        AgentDraftSupersededEvent,
        ContextSnapshotEvent;
import '../application/tool_pipeline/execution_interceptors.dart';
import '../application/tool_pipeline/tool_invocation.dart';
import '../application/tool_pipeline/tool_pipeline.dart';
import '../application/tool_pipeline/tool_run_context.dart';
import '../domain/models.dart';
import '../infrastructure/tools/tool_registry.dart';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:drift/native.dart';
import '../application/task_service.dart';
import '../application/development_execution_service.dart';
import '../domain/tool_result.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/database/run_plan_store.dart';
import '../infrastructure/files/vault_exporter_io.dart';

bool _registered = false;
Future<Map<String, dynamic>>? _activeChecks;
String _activeCase = '';
int _finishedCases = 0;
void registerPlanProtocolChecks() {
  registerPersonalContextSqlChecks();
  if (!kDebugMode || _registered) return;
  _registered = true;
  registerApprovalScopeUiChecks();
  registerSpeechCaptureUiChecks();
  registerAssistantRoleUiChecks();
  registerAssistantEntryUiChecks();
  registerExtension(
      'ext.nexus.planProtocolContract',
      (method, params) async => ServiceExtensionResponse.result(
          jsonEncode(await (_activeChecks ??= _checks()))));
  registerExtension(
      'ext.nexus.planProtocolProgress',
      (method, params) async => ServiceExtensionResponse.result(jsonEncode({
            'activeCase': _activeCase,
            'finished': _finishedCases,
            'fixtureOnly': true
          })));
}

class _Fixture {
  _Fixture(this.db);
  final AppDatabase db;
  late final RunPlanStore store = RunPlanStore(db);
  late final DevelopmentExecutionService service =
      DevelopmentExecutionService(db: db);
  late String taskId;
  late RunPlanToken token;
  int sequence = 0;
  Future<void> init() async {
    final task = await TaskService().create(
        db: db,
        conversationId: 'plan-fixture',
        type: 'general',
        requestJson: '{}');
    taskId = task.id;
    token = await store.bind(taskId: taskId, runId: 'fixture-run');
  }

  TaskControlRequest request(
          {String? clientId,
          String? runId,
          TaskControlKind kind = TaskControlKind.followUp}) =>
      TaskControlRequest(
          taskId: taskId,
          runId: runId ?? token.runId,
          kind: kind,
          clientControlId: clientId ?? 'control-${++sequence}',
          payload: const {'text': 'synthetic correction'});
}

class _CounterGate implements ToolExecutor, ToolApprovalGate {
  int executions = 0, authorizations = 0;
  Future<void> Function()? onExecute;
  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    executions++;
    await onExecute?.call();
    return ToolResult.success(
        message: 'Fixture counter only', effect: ToolEffect.applied);
  }

  @override
  ToolRisk riskForArguments(Map<String, dynamic> arguments) =>
      ToolRisk.requiresConfirmation;
  @override
  bool requiresPreviewPlan(Map<String, dynamic> arguments) => true;
  @override
  Map<String, dynamic>? approvalDetailsFor(Map<String, dynamic> arguments) =>
      {'fixtureOnly': true};
  @override
  Map<String, dynamic> authorizeAfterApproval(Map<String, dynamic> arguments) {
    authorizations++;
    return {...arguments, 'fixtureTicket': true};
  }

  @override
  void rejectApproval(Map<String, dynamic> arguments) {}
}

Future<T> _withFence<T>(
    _Fixture f,
    Future<T> Function(AgentRunController c, PersistedRunFence fence)
        body) async {
  final c = AgentRunController();
  final fence = await PersistedRunFence.open(
      db: f.db, controller: c, taskId: f.taskId, runId: f.token.runId);
  try {
    return await body(c, fence);
  } finally {
    await fence.close();
    c.seal();
  }
}

Future<ToolResult> _pipeline(
  AgentRunController c,
  _CounterGate gate, {
  required int local,
  required int durable,
  String callId = 'durable-fixture-call',
  Future<ToolApproval> Function()? approve,
  Future<void> Function(AgentEvent)? emit,
}) {
  final registration = ToolRegistration(
      spec: const ToolSpec(
          name: 'fixture_gate',
          description: 'Synthetic counter, no platform operations',
          parametersSchema: {'type': 'object'},
          risk: ToolRisk.requiresConfirmation,
          sensitive: true),
      executor: gate);
  return ToolPipeline(defaultToolInterceptors()).run(
      ToolInvocation(
          call: ToolCall(id: callId, name: 'fixture_gate', arguments: const {}),
          registration: registration,
          context: ToolRunContext(
              approvalMode: ApprovalMode.ask,
              emit: emit ?? (_) async {},
              approveTool: (call, risk, sensitive) async {
                final scope = await c.openApproval(call, risk, durable);
                if (scope == null) return ToolApproval.reject;
                return scope.invoke(() async =>
                    approve == null ? ToolApproval.allowOnce : await approve());
              },
              isSuperseded: () => c.controlRevision != local,
              isCancelled: () => c.isCancelled,
              isPaused: () => c.isPaused,
              waitForResume: c.checkpoint,
              verifyPlan: () => c.verifyDurableRevision(durable),
              claimDispatch: (id) => c.claimDurableDispatch(durable, id),
              settleDispatch: (id, result) =>
                  c.settleDurableDispatch(durable, id, result),
              whenSuperseded: c.whenRevisionChanges(local, durable))),
      executeWithTimeout);
}

// Only the OS adapter is synthetic: original terminal/session/verifier/SQL code runs.
class _EmptyVerificationDaemons extends TerminalDaemonPersistence {
  @override
  Future<List<TerminalDaemonRecord>> load() async => [];
  @override
  Future<void> save(Iterable<TerminalDaemonRecord> records) async {}
}

class _VerificationRuntime implements LinuxRuntimeAdapter {
  int calls = 0, stops = 0;
  Future<CommandResult> Function()? onRun;
  Completer<CommandResult>? pending;
  @override
  LinuxRuntimeKind get kind => LinuxRuntimeKind.androidShell;
  @override
  bool get supportsShellSyntax => true;
  @override
  bool get supportsInterpreterEvaluation => false;
  @override
  bool get isRunning => pending != null && !pending!.isCompleted;
  @override
  Future<LinuxRuntimeInfo> inspect() async => const LinuxRuntimeInfo(
      kind: LinuxRuntimeKind.androidShell,
      label: 'Native fixture only',
      available: true,
      detail: 'No OS processes',
      supportsShellSyntax: true);
  @override
  Future<CommandResult> run(LinuxCommandRequest request,
      {required String workingDirectory, required Duration timeout}) async {
    calls++;
    return await onRun?.call() ??
        const CommandResult(output: 'synthetic success', exitCode: 0);
  }

  @override
  void stop() {
    stops++;
    final active = pending;
    if (active != null && !active.isCompleted) {
      active.complete(
          const CommandResult(output: 'synthetic stopped', exitCode: 130));
    }
  }
}

class _VerificationTerminal extends TerminalCommandService {
  _VerificationTerminal(Directory directory, _VerificationRuntime runtime)
      : super(
            workspacePath: directory.path,
            runtime: runtime,
            shellType: 'sh',
            defaultWorkingDirectory: directory.path,
            daemonPersistence: _EmptyVerificationDaemons(),
            jobLogDirectory: directory);
  String? lastSession;
  int opens = 0;
  @override
  Future<TerminalSessionSnapshot> openSession(
      {String? workingDirectory}) async {
    opens++;
    final result = await super.openSession(workingDirectory: workingDirectory);
    lastSession = result.id;
    return result;
  }

  bool get sessionClosed =>
      lastSession == null || session(lastSession!) == null;
}

const _verificationRuntimePlan = DevelopmentVerificationPlan(
    project: ProjectKindDetection(
        kind: ProjectKind.flutter, confidence: 1, signals: []),
    steps: [
      VerificationStep(
          id: 'first', title: 'Synthetic first check', command: 'dart analyze'),
      VerificationStep(
          id: 'second',
          title: 'Synthetic second check',
          command: 'dart format --output=none .')
    ]);

Future<void> _prepareCompletionWorkspace(
    _Fixture f, Directory directory) async {
  await File('${directory.path}/pyproject.toml')
      .writeAsString('[project]\nname = "native-fixture"\nversion = "0.0.0"\n');
  final source = File('${directory.path}/main.py');
  await source.writeAsString('value = 1\n');
  final snapshot =
      await const WorkspaceSnapshotService().capture(directory.path);
  await f.db
      .customStatement('UPDATE tasks SET type=?, request_json=? WHERE id=?', [
    'fixture_implement',
    jsonEncode({
      'taskType': 'fixture_implement',
      'workspacePath': directory.path,
      'prompt': 'Synthetic native completion integration'
    }),
    f.taskId
  ]);
  await TaskService().updateProgress(f.db, f.taskId,
      phase: 'executing',
      runId: f.token.runId,
      planVersion: f.token.version,
      extra: {'workspaceSnapshot': snapshot.toJson()});
  await source.writeAsString('value = 2\n');
}

class _OfflineFixtureRoute implements ModelRoute {
  _OfflineFixtureRoute(this.provider);
  final LlmProvider provider;
  @override
  String get id => 'isolated-offline-fixture';
  @override
  LlmProvider providerFor(ProviderConfig config) => provider;
}

class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.turns);
  final List<Future<List<UnifiedEvent>> Function(UnifiedRequest)> turns;
  final List<UnifiedRequest> requests = [];
  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    final step = requests.length;
    requests.add(UnifiedRequest(
        model: request.model,
        messages: List<ChatMessage>.of(request.messages),
        tools: request.tools,
        temperature: request.temperature,
        maxTokens: request.maxTokens,
        topP: request.topP,
        reasoningEffort: request.reasoningEffort));
    if (step >= turns.length) {
      throw StateError('Synthetic script exhausted; no network fallback');
    }
    for (final event in await turns[step](request)) {
      yield event;
    }
  }
}

Future<List<AgentEvent>> _runScript(
    _ScriptedProvider provider, AgentRunController c, _CounterGate gate,
    {Future<ToolApproval> Function()? approve,
    Future<void> Function(AgentEvent)? observe,
    Future<TurnContinuation?> Function(TurnStoppingContext)?
        beforeFinish}) async {
  final registry = ToolRegistry()
    ..registerPair(
        spec: const ToolSpec(
            name: 'fixture_gate',
            description: 'Counter only',
            parametersSchema: {'type': 'object'},
            risk: ToolRisk.requiresConfirmation),
        executor: gate);
  final events = <AgentEvent>[];
  await for (final event in AgentExecutor(provider: provider, tools: registry)
      .run(
          history: [
        ChatMessage(
            role: MessageRole.user,
            parts: [const MessagePart.text('Synthetic initial goal')])
      ],
          model: 'synthetic-offline-provider',
          maxSteps: 6,
          maxRetries: 0,
          retryBackoff: Duration.zero,
          runController: c,
          beforeFinish: beforeFinish,
          contextBudgetTokens: 32000,
          approveTool: (call, risk, sensitive) async =>
              approve == null ? ToolApproval.allowOnce : await approve())) {
    events.add(event);
    await observe?.call(event);
  }
  return events;
}

List<UnifiedEvent> _scriptDone(String text) => [
      TextDeltaEvent(text),
      const CompletedEvent(stopReason: StopReason.endOfTurn)
    ];
bool _hasSteering(UnifiedRequest request) => request.messages
    .any((m) => m.parts.any((p) => p.value.contains('synthetic correction')));

Future<Map<String, dynamic>> _checks() async {
  final cases = <Map<String, dynamic>>[];
  Future<void> check(
      String name, Future<bool> Function(_Fixture f) body) async {
    _activeCase = name;
    final db = AppDatabase(NativeDatabase.memory());
    try {
      final f = _Fixture(db);
      await f.init();
      cases.add({'name': name, 'passed': await body(f)});
    } catch (_) {
      cases.add({'name': name, 'passed': false, 'unexpectedError': true});
    } finally {
      await db.close();
      _finishedCases++;
    }
  }

  Future<bool> rejects(Future<dynamic> Function() action) async {
    try {
      await action();
      return false;
    } catch (_) {
      return true;
    }
  }

  await check('binding_is_idempotent_for_the_same_active_run', (f) async {
    final again = await f.store.bind(taskId: f.taskId, runId: f.token.runId);
    return again.version == 1 &&
        (await f.store.history(f.taskId)).length == 1 &&
        await f.store.isCurrent(f.token);
  });
  await check(
      'missing_task_cannot_acquire_execution_identity',
      (f) async =>
          rejects(() => f.store.bind(taskId: 'missing', runId: 'no-task-run')));
  await check(
      'another_run_cannot_silently_replace_active_owner',
      (f) async =>
          await rejects(
              () => f.store.bind(taskId: f.taskId, runId: 'foreign-run')) &&
          await f.store.isCurrent(f.token));
  await check('stale_explicit_run_control_is_rejected_without_plan_append',
      (f) async {
    final result = await f.service.submitControl(f.request(runId: 'old-run'));
    return result.status == 'rejected' &&
        (await f.store.history(f.taskId)).length == 1 &&
        await f.store.isCurrent(f.token);
  });
  await check(
      'accepted_control_atomically_supersedes_old_plan_before_consumption',
      (f) async {
    final result = await f.service.submitControl(f.request());
    final head = (await f.store.head(f.taskId))!;
    return result.status == 'pending' &&
        head.token.version == 2 &&
        head.pendingControls &&
        !await f.store.isCurrent(f.token) &&
        await f.store.claim(f.token, 'stale-tool') ==
            RunDispatchClaim.superseded;
  });
  await check('duplicate_control_id_does_not_create_another_plan_version',
      (f) async {
    final request = f.request(clientId: 'same-control');
    await f.service.submitControl(request);
    final duplicate = await f.service.submitControl(request);
    return duplicate.duplicate &&
        (await f.store.history(f.taskId)).length == 2 &&
        (await f.store.head(f.taskId))!.token.version == 2;
  });
  await check('pause_followup_resume_are_consumed_in_persisted_sequence',
      (f) async {
    await f.service.submitControl(f.request(kind: TaskControlKind.pause));
    await f.service.submitControl(f.request());
    await f.service.submitControl(f.request(kind: TaskControlKind.resume));
    final batch = await f.store.consume(f.taskId, f.token.runId);
    return batch.controls.map((r) => r.kind).join(',') ==
            'pause,followUp,resume' &&
        batch.head.state == 'running' &&
        !batch.head.pendingControls &&
        await f.store.isCurrent(batch.head.token);
  });
  await check('wrong_run_cannot_consume_another_execution_inbox', (f) async {
    await f.service.submitControl(f.request());
    return await rejects(() => f.store.consume(f.taskId, 'wrong-run')) &&
        (await f.db.pendingRunControls(taskId: f.taskId)).length == 1;
  });
  await check('consumed_controls_are_not_returned_twice', (f) async {
    await f.service.submitControl(f.request());
    final first = await f.store.consume(f.taskId, f.token.runId);
    final second = await f.store.consume(f.taskId, f.token.runId);
    return first.controls.length == 1 &&
        second.controls.isEmpty &&
        second.head.token.version == first.head.token.version;
  });
  await check('same_tool_call_id_has_at_most_one_dispatch_claim', (f) async {
    final results = await Future.wait([
      f.store.claim(f.token, 'same-call'),
      f.store.claim(f.token, 'same-call')
    ]);
    return results.where((r) => r == RunDispatchClaim.granted).length == 1 &&
        results.where((r) => r == RunDispatchClaim.duplicate).length == 1;
  });
  await check('correction_winning_order_prevents_old_dispatch', (f) async {
    await f.service.submitControl(f.request());
    var dispatches = 0;
    if (await f.store.claim(f.token, 'ordered-call') ==
        RunDispatchClaim.granted) {
      dispatches++;
    }
    return dispatches == 0;
  });
  await check(
      'already_dispatched_completion_is_retained_without_overwriting_new_plan',
      (f) async {
    if (await f.store.claim(f.token, 'in-flight') != RunDispatchClaim.granted) {
      return false;
    }
    await f.service.submitControl(f.request());
    final head = (await f.store.head(f.taskId))!;
    final settled = await f.store.settle(f.token, 'in-flight', ToolEffect.none);
    final after = (await f.store.head(f.taskId))!;
    return settled &&
        after.token.version == head.token.version &&
        after.pendingControls &&
        !await f.store.finish(f.token, 'completed');
  });
  await check('unsettled_dispatch_prevents_claiming_run_finished', (f) async {
    await f.store.claim(f.token, 'unknown-inflight');
    return !await f.store.finish(f.token, 'completed') &&
        (await f.store.head(f.taskId))!.state == 'running';
  });
  await check('dispatch_settlement_is_idempotent', (f) async {
    await f.store.claim(f.token, 'settle-once');
    return await f.store.settle(f.token, 'settle-once', ToolEffect.none) &&
        !await f.store.settle(f.token, 'settle-once', ToolEffect.none) &&
        await f.store.finish(f.token, 'completed');
  });
  await check('persisted_finish_before_control_rejects_late_correction',
      (f) async {
    final results = await Future.wait<dynamic>([
      f.store.finish(f.token, 'completed'),
      f.service.submitControl(f.request())
    ]);
    return results.first == true &&
        (results.last as ControlReceipt).status == 'rejected';
  });
  await check('persisted_control_before_finish_keeps_new_plan_unfinished',
      (f) async {
    await f.service.submitControl(f.request());
    return !await f.store.finish(f.token, 'completed') &&
        (await f.store.head(f.taskId))!.pendingControls;
  });
  await check('explicit_interruption_and_new_run_invalidate_old_identity',
      (f) async {
    await f.store.interrupt(f.token);
    final next = await f.store.bind(
        taskId: f.taskId,
        runId: 'replacement-run',
        expectedPreviousRunId: f.token.runId);
    return next.version == 2 &&
        !await f.store.isCurrent(f.token) &&
        await f.store.isCurrent(next);
  });
  await check('terminal_task_cannot_keep_using_old_plan_token', (f) async {
    await TaskService().updateStatus(f.db, f.taskId, 'completed');
    return !await f.store.isCurrent(f.token) &&
        await f.store.claim(f.token, 'late') == RunDispatchClaim.superseded;
  });
  await check(
      'task_deletion_removes_protocol_rows_and_late_settlement_does_not_resurrect',
      (f) async {
    await f.store.claim(f.token, 'deleted-task-call');
    await f.db.deleteTask(f.taskId);
    return await f.store.head(f.taskId) == null &&
        (await f.store.history(f.taskId)).isEmpty &&
        !await f.store.settle(f.token, 'deleted-task-call', ToolEffect.none) &&
        await f.db.findTask(f.taskId) == null;
  });
  await check(
      'plan_history_is_immutable_against_update',
      (f) async => rejects(() => f.db.customStatement(
          "UPDATE plan_revisions SET kind='cancel' WHERE task_id=?",
          [f.taskId])));
  await check(
      'vault_keeps_history_and_unknown_claim_but_never_reactivates_old_owner',
      (f) async {
    await f.store.claim(f.token, 'backup-unknown');
    final restored = AppDatabase(NativeDatabase.memory());
    try {
      await restoreVault(restored, await buildVaultJson(f.db));
      final store = RunPlanStore(restored);
      final head = (await store.head(f.taskId))!;
      final claims = await restored
          .customSelect('SELECT * FROM run_dispatch_claims')
          .get();
      return head.state == 'interrupted' &&
          !await store.isCurrent(f.token) &&
          (await store.history(f.taskId)).length == 1 &&
          claims.single.read<String>('effect') == 'unknown';
    } finally {
      await restored.close();
    }
  });
  await check(
      'invalid_protocol_backup_is_rejected_before_deleting_existing_task',
      (f) async {
    final rejected = await rejects(() => restoreVault(f.db, {
          'version': 2,
          'runPlanHeads': [
            {
              'taskId': 'missing',
              'runId': 'fake',
              'version': 1,
              'state': 'running',
              'pendingControls': 0
            }
          ]
        }));
    return rejected &&
        await f.db.findTask(f.taskId) != null &&
        await f.store.isCurrent(f.token);
  });
  await check('second_connection_control_commit_invalidates_old_dispatch_token',
      (f) async {
    final dir =
        await Directory.systemTemp.createTemp('nexus-plan-reopen-fixture-');
    AppDatabase? reader, writer;
    try {
      final file = File('${dir.path}/plans.sqlite');
      reader = AppDatabase(NativeDatabase(file));
      final x = _Fixture(reader);
      await x.init();
      writer = AppDatabase(NativeDatabase(file));
      await DevelopmentExecutionService(db: writer).submitControl(x.request());
      if (await x.store.claim(x.token, 'second-connection') !=
          RunDispatchClaim.superseded) {
        return false;
      }
      await reader.close();
      reader = null;
      await writer.close();
      writer = null;
      reader = AppDatabase(NativeDatabase(file));
      final reopened = RunPlanStore(reader);
      final head = (await reopened.head(x.taskId))!;
      return head.pendingControls &&
          head.token.version == 2 &&
          (await reader.pendingRunControls(taskId: x.taskId)).length == 1 &&
          !await reopened.isCurrent(x.token);
    } finally {
      await reader?.close();
      await writer?.close();
      await dir.delete(recursive: true);
    }
  });
  await check('schema_29_upgrade_keeps_tasks_and_creates_protocol', (f) async {
    final dir =
        await Directory.systemTemp.createTemp('nexus-plan-upgrade-fixture-');
    AppDatabase? current;
    try {
      final file = File('${dir.path}/legacy.sqlite');
      current = AppDatabase(NativeDatabase(file));
      final x = _Fixture(current);
      await x.init();
      await current.customStatement('DROP TRIGGER nexus_task_plan_cleanup');
      await current
          .customStatement('DROP TRIGGER nexus_plan_revision_immutable');
      for (final table in [
        'plan_revisions',
        'run_plan_heads',
        'run_dispatch_claims'
      ]) {
        await current.customStatement('DROP TABLE $table');
      }
      await current.customStatement('PRAGMA user_version = 29');
      await current.close();
      current = null;
      current = AppDatabase(NativeDatabase(file));
      final store = RunPlanStore(current);
      if (await current.findTask(x.taskId) == null ||
          await store.head(x.taskId) != null) {
        return false;
      }
      final token = await store.bind(taskId: x.taskId, runId: 'upgraded-run');
      return await store.isCurrent(token) && token.version == 1;
    } finally {
      await current?.close();
      await dir.delete(recursive: true);
    }
  });
  await check(
      'runtime_fence_attaches_existing_controller_to_durable_identity',
      (f) => _withFence(
          f, (c, x) async => c.hasDurableFence && c.durablePlanRevision == 1));
  await check(
      'runtime_pending_control_blocks_old_pipeline_before_approval',
      (f) => _withFence(f, (c, x) async {
            final g = _CounterGate();
            var approvals = 0;
            await f.service.submitControl(f.request());
            final r =
                await _pipeline(c, g, local: 0, durable: 1, approve: () async {
              approvals++;
              return ToolApproval.allowOnce;
            });
            return r.effect == ToolEffect.none &&
                !r.ok &&
                approvals == 0 &&
                g.executions == 0 &&
                g.authorizations == 0;
          }));
  await check(
      'runtime_consumes_correction_once_and_advances_controller',
      (f) => _withFence(f, (c, x) async {
            await f.service.submitControl(f.request());
            await c.synchronize();
            final text = c.drainSteering();
            await c.synchronize();
            return c.durablePlanRevision == 2 &&
                c.controlRevision == 1 &&
                text.length == 1 &&
                c.drainSteering().isEmpty;
          }));
  await check(
      'runtime_obsolete_approval_never_authorizes_or_dispatches',
      (f) => _withFence(f, (c, x) async {
            final g = _CounterGate();
            final r =
                await _pipeline(c, g, local: 0, durable: 1, approve: () async {
              await f.service.submitControl(f.request());
              return ToolApproval.allowOnce;
            });
            return !r.ok &&
                r.effect == ToolEffect.none &&
                g.executions == 0 &&
                g.authorizations == 0;
          }));
  await check(
      'runtime_event_backpressure_cannot_bypass_final_dispatch_claim',
      (f) => _withFence(f, (c, x) async {
            final g = _CounterGate();
            final r = await _pipeline(c, g, local: 0, durable: 1,
                emit: (event) async {
              if (event is AgentStatusEvent &&
                  event.status == RunStatus.executingTool) {
                await f.service.submitControl(f.request());
              }
            });
            return !r.ok &&
                r.effect == ToolEffect.none &&
                g.executions == 0 &&
                g.authorizations == 0;
          }));
  await check(
      'runtime_dispatched_fact_settles_without_overwriting_new_plan',
      (f) => _withFence(f, (c, x) async {
            final g = _CounterGate()
              ..onExecute = () async {
                await f.service.submitControl(f.request());
                await c.synchronize();
              };
            final r = await _pipeline(c, g, local: 0, durable: 1);
            final rows = await f.db.customSelect(
                'SELECT state,effect,plan_version FROM run_dispatch_claims WHERE task_id = ?',
                variables: [Variable(f.taskId)]).get();
            return r.ok &&
                r.effect == ToolEffect.applied &&
                g.executions == 1 &&
                c.durablePlanRevision == 2 &&
                rows.single.read<String>('state') == 'settled' &&
                rows.single.read<int>('plan_version') == 1 &&
                (await f.store.head(f.taskId))!.state == 'running';
          }));
  await check(
      'runtime_duplicate_call_id_does_not_reauthorize_or_execute',
      (f) => _withFence(f, (c, x) async {
            final g = _CounterGate();
            final first = await _pipeline(c, g, local: 0, durable: 1);
            final repeat = await _pipeline(c, g, local: 0, durable: 1);
            return first.ok &&
                !repeat.ok &&
                repeat.effect == ToolEffect.unknown &&
                g.executions == 1 &&
                g.authorizations == 1;
          }));
  await check(
      'runtime_paused_checkpoint_consumes_persisted_resume',
      (f) => _withFence(f, (c, x) async {
            await f.service
                .submitControl(f.request(kind: TaskControlKind.pause));
            await c.synchronize();
            if (!c.isPaused) return false;
            final resume = Future<void>.delayed(
                const Duration(milliseconds: 30), () async {
              await f.service
                  .submitControl(f.request(kind: TaskControlKind.resume));
            });
            await c.checkpoint().timeout(const Duration(seconds: 3));
            await resume;
            return !c.isPaused && c.durablePlanRevision == 3;
          }));
  await check(
      'runtime_persisted_cancel_revokes_original_controller',
      (f) => _withFence(f, (c, x) async {
            await f.service
                .submitControl(f.request(kind: TaskControlKind.cancel));
            await c.synchronize();
            return c.isCancelled &&
                (await f.store.head(f.taskId))!.state == 'cancelled';
          }));
  await check(
      'runtime_finish_losing_to_control_continues_without_early_seal',
      (f) => _withFence(f, (c, x) async {
            await f.service.submitControl(f.request());
            final text = await c.drainDurableSteeringOrSeal();
            if (text.length != 1 || c.isSealed) return false;
            final rest = await c.drainDurableSteeringOrSeal();
            return rest.isEmpty &&
                c.isSealed &&
                (await f.store.head(f.taskId))!.state == 'completed';
          }));
  await check(
      'runtime_checkpoint_waits_for_tracked_local_persistence',
      (f) => _withFence(f, (c, x) async {
            final receipt = Completer<bool>();
            c.trackPersistence(receipt.future);
            var passed = false;
            final checkpoint = c.checkpoint().then((_) {
              passed = true;
            });
            await Future<void>.delayed(const Duration(milliseconds: 10));
            final before = passed;
            receipt.complete(true);
            await checkpoint;
            return !before && passed;
          }));
  await check(
      'runtime_stale_task_snapshots_do_not_replace_current_plan',
      (f) => _withFence(f, (c, x) async {
            await f.service.submitControl(f.request());
            await c.synchronize();
            final tasks = TaskService();
            await tasks.updateStatus(f.db, f.taskId, 'running',
                runId: f.token.runId, planVersion: 2);
            await tasks.updateProgress(f.db, f.taskId,
                phase: 'current-plan', runId: f.token.runId, planVersion: 2);
            await tasks.updateStatus(f.db, f.taskId, 'waiting_approval',
                runId: f.token.runId, planVersion: 1);
            await tasks.updateProgress(f.db, f.taskId,
                phase: 'obsolete', runId: f.token.runId, planVersion: 1);
            await tasks.complete(f.db, f.taskId,
                status: 'completed',
                summary: 'obsolete',
                runId: f.token.runId,
                planVersion: 1);
            return (await f.db.findTask(f.taskId))!.status == 'running' &&
                (await tasks.progress(f.db, f.taskId))['phase'] ==
                    'current-plan';
          }));
  await check(
      'runtime_finished_plan_rejects_late_correction',
      (f) => _withFence(f, (c, x) async {
            await c.drainDurableSteeringOrSeal();
            final receipt = await f.service.submitControl(f.request());
            return c.isSealed && receipt.status == 'rejected';
          }));
  await check('runtime_close_interrupts_and_new_owner_cas_rebinds', (f) async {
    await _withFence(f, (c, x) async => true);
    if ((await f.store.head(f.taskId))!.state != 'interrupted') return false;
    final c = AgentRunController();
    final x = await PersistedRunFence.open(
        db: f.db, controller: c, taskId: f.taskId, runId: 'new-owner');
    try {
      return c.durablePlanRevision == 2 &&
          (await f.store.head(f.taskId))!.token.runId == 'new-owner';
    } finally {
      await x.close();
      c.seal();
    }
  });
  await check(
      'runtime_claim_write_failure_is_fail_closed_before_authorization',
      (f) => _withFence(f, (c, x) async {
            await f.db.customStatement(
                "CREATE TEMP TRIGGER fixture_claim_failure BEFORE INSERT ON run_dispatch_claims BEGIN SELECT RAISE(ABORT,'fixture'); END");
            final g = _CounterGate();
            final r = await _pipeline(c, g, local: 0, durable: 1);
            return !r.ok &&
                r.effect == ToolEffect.unknown &&
                g.executions == 0 &&
                g.authorizations == 0 &&
                r.data?['reason'] == 'dispatch_claim_unconfirmed';
          }));
  await check(
      'runtime_unconfirmed_settlement_preserves_unknown_not_fake_success',
      (f) => _withFence(f, (c, x) async {
            await f.db.customStatement(
                "CREATE TEMP TRIGGER fixture_settle_failure BEFORE UPDATE ON run_dispatch_claims BEGIN SELECT RAISE(ABORT,'fixture'); END");
            final g = _CounterGate();
            final r = await _pipeline(c, g, local: 0, durable: 1);
            return !r.ok &&
                r.effect == ToolEffect.unknown &&
                g.executions == 1 &&
                r.data?['priorEffect'] == 'applied' &&
                !await x.finish();
          }));
  await check(
      'runtime_task_completion_requires_persisted_plan_finish',
      (f) => _withFence(f, (c, x) async {
            final tasks = TaskService();
            await tasks.complete(f.db, f.taskId,
                status: 'completed',
                summary: 'premature',
                runId: f.token.runId,
                planVersion: 1);
            if ((await f.db.findTask(f.taskId))!.status == 'completed') {
              return false;
            }
            await c.drainDurableSteeringOrSeal();
            await tasks.complete(f.db, f.taskId,
                status: 'completed',
                summary: 'confirmed',
                runId: f.token.runId,
                planVersion: 1);
            return (await f.db.findTask(f.taskId))!.status == 'completed';
          }));
  await check(
      'approval_scope_registers_framework_run_plan_and_call_identity',
      (f) => _withFence(f, (c, x) async {
            final scope = (await c.openApproval(
                const ToolCall(
                    id: 'approval-fixture',
                    name: 'fixture_gate',
                    arguments: {}),
                ToolRisk.requiresConfirmation,
                1))!;
            final row = (await f.db.customSelect(
                    'SELECT * FROM run_approval_scopes WHERE request_id=?',
                    variables: [Variable(scope.requestId)]).get())
                .single;
            final valid = row.read<String>('task_id') == f.taskId &&
                row.read<String>('run_id') == f.token.runId &&
                row.read<int>('plan_version') == 1 &&
                row.read<String>('call_id') == 'approval-fixture';
            await scope.invoke(() async => ToolApproval.reject);
            return valid;
          }));
  await check(
      'approval_scope_stale_open_does_not_register_new_request',
      (f) => _withFence(f, (c, x) async {
            await f.service.submitControl(f.request());
            return await c.openApproval(
                        const ToolCall(
                            id: 'old', name: 'fixture_gate', arguments: {}),
                        ToolRisk.requiresConfirmation,
                        1) ==
                    null &&
                (await f.db
                        .customSelect(
                            'SELECT request_id FROM pending_approvals')
                        .get())
                    .isEmpty;
          }));
  await check(
      'approval_scope_notification_first_winner_is_preserved',
      (f) => _withFence(f, (c, x) async {
            final scope = (await c.openApproval(
                const ToolCall(
                    id: 'first', name: 'fixture_gate', arguments: {}),
                ToolRisk.requiresConfirmation,
                1))!;
            final accepted = await scope.decide(ToolApproval.allowOnce);
            final later = await scope.decide(ToolApproval.reject);
            final result =
                await scope.invoke(() async => ToolApproval.allowOnce);
            return accepted && !later && result == ToolApproval.allowOnce;
          }));
  await check(
      'approval_scope_pending_correction_blocks_old_notification_write',
      (f) => _withFence(f, (c, x) async {
            final scope = (await c.openApproval(
                const ToolCall(
                    id: 'pending', name: 'fixture_gate', arguments: {}),
                ToolRisk.requiresConfirmation,
                1))!;
            await f.service.submitControl(f.request());
            final stale = await f.db
                .decidePendingApproval(scope.requestId, approvalApproveAction);
            return !stale &&
                await scope.invoke(() async => ToolApproval.allowOnce) ==
                    ToolApproval.reject;
          }));
  await check(
      'approval_scope_consumed_new_version_cannot_receive_old_allow',
      (f) => _withFence(f, (c, x) async {
            final scope = (await c.openApproval(
                const ToolCall(
                    id: 'consumed', name: 'fixture_gate', arguments: {}),
                ToolRisk.requiresConfirmation,
                1))!;
            await f.service.submitControl(f.request());
            await c.synchronize();
            final stale = await scope.decide(ToolApproval.allowOnce);
            return !stale &&
                await scope.invoke(() async => ToolApproval.allowOnce) ==
                    ToolApproval.reject;
          }));
  await check(
      'approval_scope_revokes_waiter_without_waiting_for_old_ui',
      (f) => _withFence(f, (c, x) async {
            final scope = (await c.openApproval(
                const ToolCall(
                    id: 'revoked', name: 'fixture_gate', arguments: {}),
                ToolRisk.requiresConfirmation,
                1))!;
            final pendingUi = Completer<ToolApproval>();
            final waiting = scope.invoke(() => pendingUi.future);
            await f.service.submitControl(f.request());
            await c.synchronize();
            final result = await waiting.timeout(const Duration(seconds: 2));
            pendingUi.complete(ToolApproval.allowOnce);
            return result == ToolApproval.reject &&
                !c.isPlanToolTrusted('fixture_gate');
          }));
  await check(
      'approval_scope_cancel_revokes_waiter_and_late_action',
      (f) => _withFence(f, (c, x) async {
            final scope = (await c.openApproval(
                const ToolCall(
                    id: 'cancelled', name: 'fixture_gate', arguments: {}),
                ToolRisk.requiresConfirmation,
                1))!;
            final pendingUi = Completer<ToolApproval>();
            final waiting = scope.invoke(() => pendingUi.future);
            await f.service
                .submitControl(f.request(kind: TaskControlKind.cancel));
            await c.synchronize();
            final result = await waiting.timeout(const Duration(seconds: 2));
            pendingUi.complete(ToolApproval.allowOnce);
            return result == ToolApproval.reject &&
                !await f.db.decidePendingApproval(
                    scope.requestId, approvalApproveAction);
          }));
  await check(
      'approval_scope_ttl_rejects_notification_without_touching_owner',
      (f) => _withFence(f, (c, x) async {
            final scope = (await c.openApproval(
                const ToolCall(
                    id: 'expired', name: 'fixture_gate', arguments: {}),
                ToolRisk.requiresConfirmation,
                1))!;
            await f.db.customStatement(
                "UPDATE pending_approvals SET expires_at='2000-01-01T00:00:00' WHERE request_id=?",
                [scope.requestId]);
            final accepted = await scope.decide(ToolApproval.allowOnce);
            return !accepted &&
                await scope.invoke(() async => ToolApproval.allowOnce) ==
                    ToolApproval.reject;
          }));
  await check(
      'approval_scope_timeout_closes_waiter_and_invalidates_ui_future',
      (f) => _withFence(f, (c, x) async {
            final scope = (await c.openApproval(
                const ToolCall(
                    id: 'timeout', name: 'fixture_gate', arguments: {}),
                ToolRisk.requiresConfirmation,
                1))!;
            var closed = false;
            unawaited(scope.invalidated.then((_) {
              closed = true;
            }));
            final ui = Completer<ToolApproval>();
            final result = await scope.invoke(() => ui.future,
                timeout: const Duration(milliseconds: 20));
            await Future<void>.delayed(Duration.zero);
            ui.complete(ToolApproval.allowOnce);
            return result == ToolApproval.reject &&
                closed &&
                !await scope.isCurrent();
          }));
  await check(
      'approval_scope_plan_grant_is_not_global_and_clears_on_correction',
      (f) => _withFence(f, (c, x) async {
            final scope = (await c.openApproval(
                const ToolCall(
                    id: 'grant', name: 'fixture_gate', arguments: {}),
                ToolRisk.requiresConfirmation,
                1))!;
            final result =
                await scope.invoke(() async => ToolApproval.allowSession);
            final before = c.isPlanToolTrusted('fixture_gate');
            final rows = await f.db.customSelect(
                'SELECT plan_version FROM run_plan_grants WHERE task_id=?',
                variables: [Variable(f.taskId)]).get();
            await f.service.submitControl(f.request());
            await c.synchronize();
            return result == ToolApproval.allowSession &&
                before &&
                rows.single.read<int>('plan_version') == 1 &&
                !c.isPlanToolTrusted('fixture_gate');
          }));
  await check(
      'approval_scope_old_ui_cannot_create_grant_for_new_plan',
      (f) => _withFence(f, (c, x) async {
            final scope = (await c.openApproval(
                const ToolCall(
                    id: 'old-grant', name: 'fixture_gate', arguments: {}),
                ToolRisk.requiresConfirmation,
                1))!;
            final result = await scope.invoke(() async {
              await f.service.submitControl(f.request());
              await c.synchronize();
              return ToolApproval.allowAlways;
            });
            return result == ToolApproval.reject &&
                (await f.db.customSelect('SELECT * FROM run_plan_grants').get())
                    .isEmpty &&
                !c.isPlanToolTrusted('fixture_gate');
          }));
  await check(
      'approval_scope_cleanup_removes_handshake_and_scope_mapping',
      (f) => _withFence(f, (c, x) async {
            final scope = (await c.openApproval(
                const ToolCall(
                    id: 'cleanup', name: 'fixture_gate', arguments: {}),
                ToolRisk.requiresConfirmation,
                1))!;
            await scope.invoke(() async => ToolApproval.allowOnce);
            return (await f.db
                        .customSelect('SELECT * FROM pending_approvals')
                        .get())
                    .isEmpty &&
                (await f.db
                        .customSelect('SELECT * FROM run_approval_scopes')
                        .get())
                    .isEmpty &&
                !await scope.decide(ToolApproval.allowOnce);
          }));
  await check(
      'approval_scope_task_deletion_revokes_handshake_and_grants',
      (f) => _withFence(f, (c, x) async {
            final grant = (await c.openApproval(
                const ToolCall(
                    id: 'grant-before-delete',
                    name: 'fixture_gate',
                    arguments: {}),
                ToolRisk.requiresConfirmation,
                1))!;
            await grant.invoke(() async => ToolApproval.allowSession);
            final scope = (await c.openApproval(
                const ToolCall(
                    id: 'delete', name: 'fixture_gate', arguments: {}),
                ToolRisk.requiresConfirmation,
                1))!;
            await f.db.deleteTask(f.taskId);
            final accepted = await scope.decide(ToolApproval.allowOnce);
            await scope.invoke(() async => ToolApproval.allowOnce);
            return !accepted &&
                (await f.db
                        .customSelect('SELECT * FROM run_approval_scopes')
                        .get())
                    .isEmpty &&
                (await f.db.customSelect('SELECT * FROM run_plan_grants').get())
                    .isEmpty;
          }));
  await check(
      'approval_scope_terminal_task_rejects_notification',
      (f) => _withFence(f, (c, x) async {
            final scope = (await c.openApproval(
                const ToolCall(
                    id: 'terminal', name: 'fixture_gate', arguments: {}),
                ToolRisk.requiresConfirmation,
                1))!;
            await f.db.updateTaskStatus(f.taskId, 'cancelled');
            final accepted = await scope.decide(ToolApproval.allowOnce);
            await scope.invoke(() async => ToolApproval.allowOnce);
            return !accepted;
          }));
  await check(
      'approval_scope_foreign_owner_cannot_inherit_old_action',
      (f) => _withFence(f, (c, x) async {
            final scope = (await c.openApproval(
                const ToolCall(
                    id: 'foreign', name: 'fixture_gate', arguments: {}),
                ToolRisk.requiresConfirmation,
                1))!;
            await f.store.interrupt(f.token);
            await f.store.bind(
                taskId: f.taskId,
                runId: 'replacement',
                expectedPreviousRunId: f.token.runId);
            final accepted = await scope.decide(ToolApproval.allowOnce);
            await scope.invoke(() async => ToolApproval.allowOnce);
            return !accepted &&
                (await f.store.head(f.taskId))!.token.runId == 'replacement';
          }));
  await check('approval_scope_legacy_unbound_handshake_keeps_first_winner',
      (f) async {
    await f.db.insertPendingApproval(
        requestId: 'legacy',
        toolName: 'fixture',
        summary: 'fixture',
        risk: 'safe',
        ttl: const Duration(minutes: 1));
    return await f.db.decidePendingApproval('legacy', approvalApproveAction) &&
        !await f.db.decidePendingApproval('legacy', approvalDenyAction);
  });
  await check('approval_scope_legacy_expired_handshake_is_not_approvable',
      (f) async {
    await f.db.insertPendingApproval(
        requestId: 'expired-legacy',
        toolName: 'fixture',
        summary: 'fixture',
        risk: 'safe',
        ttl: const Duration(seconds: -1));
    return !await f.db
        .decidePendingApproval('expired-legacy', approvalApproveAction);
  });
  await check(
      'approval_scope_zone_is_framework_context_not_model_arguments',
      (f) => _withFence(f, (c, x) async {
            final scope = (await c.openApproval(
                const ToolCall(id: 'zone', name: 'fixture_gate', arguments: {
                  '_runApproval': {'planVersion': 999}
                }),
                ToolRisk.requiresConfirmation,
                1))!;
            var matched = false;
            await scope.invoke(() async {
              await Future<void>.delayed(Duration.zero);
              matched = identical(RunApprovalScope.current, scope) &&
                  RunApprovalScope.current!.token.version == 1;
              return ToolApproval.reject;
            });
            return matched && RunApprovalScope.current == null;
          }));
  await check(
      'approval_scope_deleted_parent_cannot_be_reapproved',
      (f) => _withFence(f, (c, x) async {
            final scope = (await c.openApproval(
                const ToolCall(
                    id: 'deleted-parent', name: 'fixture_gate', arguments: {}),
                ToolRisk.requiresConfirmation,
                1))!;
            await f.db.deletePendingApproval(scope.requestId);
            return !await scope.isCurrent() &&
                !await scope.decide(ToolApproval.allowOnce) &&
                await scope.invoke(() async => ToolApproval.allowOnce) ==
                    ToolApproval.reject;
          }));
  await check(
      'approval_scope_clear_all_revokes_temporary_permissions',
      (f) => _withFence(f, (c, x) async {
            final grant = (await c.openApproval(
                const ToolCall(
                    id: 'grant-clear', name: 'fixture_gate', arguments: {}),
                ToolRisk.requiresConfirmation,
                1))!;
            await grant.invoke(() async => ToolApproval.allowSession);
            final scope = (await c.openApproval(
                const ToolCall(
                    id: 'clear-all', name: 'fixture_gate', arguments: {}),
                ToolRisk.requiresConfirmation,
                1))!;
            await f.db.clearAllUserData();
            await scope.invoke(() async => ToolApproval.allowOnce);
            return (await f.db
                        .customSelect('SELECT * FROM run_plan_grants')
                        .get())
                    .isEmpty &&
                (await f.db
                        .customSelect('SELECT * FROM run_approval_scopes')
                        .get())
                    .isEmpty &&
                !await f.db.decidePendingApproval(
                    scope.requestId, approvalApproveAction);
          }));
  await check(
      'agent_loop_queued_correction_is_present_before_first_synthetic_request',
      (f) => _withFence(f, (c, x) async {
            await f.service.submitControl(f.request());
            final g = _CounterGate();
            final p = _ScriptedProvider(
                [(request) async => _scriptDone('current answer')]);
            final events = await _runScript(p, c, g);
            return p.requests.length == 1 &&
                _hasSteering(p.requests.single) &&
                g.executions == 0 &&
                c.isSealed &&
                events.whereType<AgentStatusEvent>().last.status ==
                    RunStatus.completed;
          }));
  await check(
      'agent_loop_stale_model_batch_skips_tool_and_replans_in_same_executor',
      (f) => _withFence(f, (c, x) async {
            final g = _CounterGate();
            final p = _ScriptedProvider([
              (request) async {
                await f.service.submitControl(f.request());
                await c.synchronize();
                return [
                  const ToolCallEvent(ToolCall(
                      id: 'old-loop-call',
                      name: 'fixture_gate',
                      arguments: {})),
                  const CompletedEvent(stopReason: StopReason.toolUse)
                ];
              },
              (request) async => _scriptDone('current answer')
            ]);
            final events = await _runScript(p, c, g);
            final results = events.whereType<ToolResultEvent>().toList();
            return p.requests.length == 2 &&
                _hasSteering(p.requests[1]) &&
                results.length == 1 &&
                results.single.result.effect == ToolEffect.none &&
                g.executions == 0 &&
                g.authorizations == 0 &&
                c.isSealed &&
                (await f.store.head(f.taskId))!.token.version == 2;
          }));
  await check(
      'agent_loop_inflight_fact_retained_but_old_batch_remainder_blocked',
      (f) => _withFence(f, (c, x) async {
            final g = _CounterGate()
              ..onExecute = () async {
                await f.service.submitControl(f.request());
                await c.synchronize();
              };
            final p = _ScriptedProvider([
              (request) async => [
                    const ToolCallEvent(ToolCall(
                        id: 'first-loop-call',
                        name: 'fixture_gate',
                        arguments: {})),
                    const ToolCallEvent(ToolCall(
                        id: 'remaining-loop-call',
                        name: 'fixture_gate',
                        arguments: {})),
                    const CompletedEvent(stopReason: StopReason.toolUse)
                  ],
              (request) async => _scriptDone('replanned answer')
            ]);
            final events = await _runScript(p, c, g);
            final results = events.whereType<ToolResultEvent>().toList();
            return p.requests.length == 2 &&
                results.length == 2 &&
                results.first.result.effect == ToolEffect.applied &&
                results.last.result.effect == ToolEffect.none &&
                results.every((r) => r.metadata['planVersion'] == 1) &&
                g.executions == 1 &&
                g.authorizations == 1 &&
                _hasSteering(p.requests[1]);
          }));
  await check(
      'agent_loop_approval_scope_is_real_framework_zone_and_obsolete_allow_rejected',
      (f) => _withFence(f, (c, x) async {
            final g = _CounterGate();
            var scoped = false;
            final p = _ScriptedProvider([
              (request) async => [
                    const ToolCallEvent(ToolCall(
                        id: 'approval-loop-call',
                        name: 'fixture_gate',
                        arguments: {})),
                    const CompletedEvent(stopReason: StopReason.toolUse)
                  ],
              (request) async => _scriptDone('new answer')
            ]);
            await _runScript(p, c, g, approve: () async {
              scoped = RunApprovalScope.current?.token.version == 1;
              await f.service.submitControl(f.request());
              await c.synchronize();
              return ToolApproval.allowSession;
            });
            return scoped &&
                p.requests.length == 2 &&
                g.executions == 0 &&
                g.authorizations == 0 &&
                (await f.db.customSelect('SELECT * FROM run_plan_grants').get())
                    .isEmpty;
          }));
  await check(
      'agent_loop_superseded_final_draft_does_not_pollute_current_answer',
      (f) => _withFence(f, (c, x) async {
            final g = _CounterGate();
            final answer = StringBuffer();
            final p = _ScriptedProvider([
              (request) async {
                await f.service.submitControl(f.request());
                await c.synchronize();
                return _scriptDone('OBSOLETE_DRAFT');
              },
              (request) async => _scriptDone('CURRENT_ANSWER')
            ]);
            final events = await _runScript(p, c, g, observe: (event) async {
              if (event is AgentDraftSupersededEvent) answer.clear();
              if (event is TextEvent) answer.write(event.text);
            });
            return p.requests.length == 2 &&
                answer.toString() == 'CURRENT_ANSWER' &&
                events.whereType<AgentDraftSupersededEvent>().length == 1 &&
                !p.requests[1].messages.any((m) =>
                    m.role == MessageRole.assistant &&
                    m.parts
                        .any((part) => part.value.contains('OBSOLETE_DRAFT')));
          }));
  await check(
      'agent_loop_control_during_request_backpressure_prevents_old_provider_send',
      (f) => _withFence(f, (c, x) async {
            final g = _CounterGate();
            var changed = false;
            final p = _ScriptedProvider(
                [(request) async => _scriptDone('new answer')]);
            await _runScript(p, c, g, observe: (event) async {
              if (!changed && event is ContextSnapshotEvent) {
                changed = true;
                await f.service.submitControl(f.request());
                await c.synchronize();
              }
            });
            return changed &&
                p.requests.length == 1 &&
                _hasSteering(p.requests.single) &&
                c.isSealed;
          }));
  await check(
      'agent_completion_async_control_wins_without_early_seal',
      (f) => _withFence(f, (c, x) async {
            final p = _ScriptedProvider([
              (r) async => _scriptDone('old'),
              (r) async => _scriptDone('new')
            ]);
            var endings = 0;
            await _runScript(p, c, _CounterGate(),
                beforeFinish: (context) async {
              endings++;
              if (endings == 1) {
                if (c.isSealed) throw StateError('Early seal');
                await f.service.submitControl(f.request());
                await c.synchronize();
              }
              return null;
            });
            return endings == 2 &&
                p.requests.length == 2 &&
                _hasSteering(p.requests[1]) &&
                c.isSealed &&
                (await f.store.head(f.taskId))!.state == 'completed';
          }));
  await check(
      'agent_completion_repair_continues_original_executor_without_new_owner',
      (f) => _withFence(f, (c, x) async {
            final p = _ScriptedProvider([
              (r) async => _scriptDone('draft'),
              (r) async => _scriptDone('verified')
            ]);
            var endings = 0;
            final events = await _runScript(p, c, _CounterGate(),
                beforeFinish: (context) async {
              endings++;
              return endings == 1
                  ? TurnContinuation([
                      ChatMessage(role: MessageRole.user, parts: const [
                        MessagePart.text(
                            'Synthetic bounded repair continuation')
                      ])
                    ], keepAssistantText: false)
                  : null;
            });
            return endings == 2 &&
                p.requests.length == 2 &&
                events.whereType<AgentDraftSupersededEvent>().single.reason ==
                    'completion' &&
                (await f.store.head(f.taskId))!.token.runId == f.token.runId &&
                (await f.store.history(f.taskId)).length == 1;
          }));
  await check(
      'agent_completion_exception_never_reports_persisted_success',
      (f) => _withFence(f, (c, x) async {
            final p = _ScriptedProvider([(r) async => _scriptDone('draft')]);
            try {
              await _runScript(p, c, _CounterGate(),
                  beforeFinish: (context) async {
                throw StateError('Synthetic completion failure');
              });
              return false;
            } catch (_) {
              return !c.isSealed &&
                  (await f.store.head(f.taskId))!.state == 'running';
            }
          }));
  await check(
      'agent_completion_cancel_releases_waiter_without_claiming_success',
      (f) => _withFence(f, (c, x) async {
            final p = _ScriptedProvider([(r) async => _scriptDone('draft')]);
            final pending = Completer<TurnContinuation?>();
            final events = await _runScript(p, c, _CounterGate(),
                beforeFinish: (context) async {
              c.cancel();
              return pending.future;
            }).timeout(const Duration(seconds: 2));
            pending.complete(null);
            return events.whereType<AgentStatusEvent>().last.status ==
                    RunStatus.cancelled &&
                (await f.store.head(f.taskId))!.state != 'completed';
          }));
  await check(
      'agent_completion_unbound_legacy_controller_not_sealed_before_async_hook',
      (f) async {
    final c = AgentRunController();
    final p = _ScriptedProvider(
        [(r) async => _scriptDone('old'), (r) async => _scriptDone('new')]);
    var endings = 0;
    var open = false;
    await _runScript(p, c, _CounterGate(), beforeFinish: (context) async {
      endings++;
      if (endings == 1) {
        open = !c.isSealed;
        c.steer('synthetic correction');
      }
      return null;
    });
    return open && endings == 2 && p.requests.length == 2 && c.isSealed;
  });
  await check(
      'headless_explicit_run_identity_matches_head_record_and_completion_ack',
      (f) async {
    await f.store.interrupt(f.token);
    final p = _ScriptedProvider(
        [(r) async => _scriptDone('HEADLESS_FIXTURE_ANSWER')]);
    final result = await HeadlessExecutor.runDetailed(
        db: f.db,
        config: const ProviderConfig(baseUrl: '', model: 'fixture', apiKey: ''),
        prompt: 'Synthetic identity check',
        taskId: f.taskId,
        runId: 'explicit-headless-owner',
        profile: RunProfile.subagent,
        modules: const ModuleHost([]),
        modelRouter: ModelRouter([_OfflineFixtureRoute(p)]));
    await TaskService().complete(f.db, f.taskId,
        status: 'completed', summary: result.text, runId: result.runId);
    return p.requests.length == 1 &&
        result.runId == 'explicit-headless-owner' &&
        result.planVersion == (await f.store.head(f.taskId))!.token.version &&
        result.succeeded &&
        (await f.store.head(f.taskId))!.token.runId == result.runId &&
        (await f.db.findTask(f.taskId))!.status == 'completed';
  });
  await check('gateway_forwards_caller_identity_into_real_headless_pipeline',
      (f) async {
    await f.store.interrupt(f.token);
    final p =
        _ScriptedProvider([(r) async => _scriptDone('GATEWAY_FIXTURE_ANSWER')]);
    final result = await BackgroundExecutionGateway().run(
        db: f.db,
        config: const ProviderConfig(baseUrl: '', model: 'fixture', apiKey: ''),
        prompt: 'Synthetic gateway identity check',
        taskId: f.taskId,
        runId: 'explicit-gateway-owner',
        profile: RunProfile.subagent,
        modules: const ModuleHost([]),
        modelRouter: ModelRouter([_OfflineFixtureRoute(p)]));
    await TaskService().complete(f.db, f.taskId,
        status: 'completed',
        summary: result.text,
        runId: 'explicit-gateway-owner');
    return p.requests.length == 1 &&
        result.runId == 'explicit-gateway-owner' &&
        result.planVersion == (await f.store.head(f.taskId))!.token.version &&
        result.succeeded &&
        (await f.store.head(f.taskId))!.token.runId == result.runId &&
        (await f.db.findTask(f.taskId))!.status == 'completed';
  });
  await check('finalizer_foreign_owner_is_rejected_before_workspace_access',
      (f) async {
    final before = (await f.db.findTask(f.taskId))!.progressJson;
    final result = await DevelopmentLoopFinalizer().finalize(
        db: f.db,
        taskId: f.taskId,
        runId: 'foreign-owner',
        workspacePath: '/must-not-access-this-fixture-path');
    return !result.verified &&
        result.verificationSkipReason != null &&
        (await f.db.findTask(f.taskId))!.progressJson == before;
  });
  await check('finalizer_pending_control_cannot_publish_old_plan_snapshot',
      (f) async {
    await f.service.submitControl(f.request());
    final before = (await f.db.findTask(f.taskId))!.progressJson;
    final result = await DevelopmentLoopFinalizer().finalize(
        db: f.db,
        taskId: f.taskId,
        runId: f.token.runId,
        planVersion: 1,
        workspacePath: '/must-not-access-this-fixture-path');
    return !result.verified &&
        result.verificationSkipReason != null &&
        (await f.db.findTask(f.taskId))!.progressJson == before;
  });
  await check('finalizer_consumed_new_plan_blocks_explicit_old_revision',
      (f) async {
    await f.service.submitControl(f.request());
    await f.store.consume(f.taskId, f.token.runId);
    final before = (await f.db.findTask(f.taskId))!.progressJson;
    final result = await DevelopmentLoopFinalizer().finalize(
        db: f.db,
        taskId: f.taskId,
        runId: f.token.runId,
        planVersion: 1,
        workspacePath: '/must-not-access-this-fixture-path');
    return !result.verified &&
        result.verificationSkipReason != null &&
        (await f.db.findTask(f.taskId))!.progressJson == before;
  });
  await check('finalizer_deleted_task_cannot_create_or_recover_old_result',
      (f) async {
    await f.db.deleteTask(f.taskId);
    final result = await DevelopmentLoopFinalizer().finalize(
        db: f.db,
        taskId: f.taskId,
        runId: f.token.runId,
        workspacePath: '/must-not-access-this-fixture-path');
    return !result.verified &&
        result.verificationSkipReason != null &&
        await f.db.findTask(f.taskId) == null;
  });
  await check('verification_dispatch_claim_and_settle_wrap_original_action',
      (f) async {
    final guard = PersistedVerificationDispatch(
        store: f.store, token: f.token, prefix: 'verification-native');
    var actions = 0;
    final value = await guard.run('step', () async {
      actions++;
      return 7;
    });
    return value == 7 &&
        actions == 1 &&
        await f.store.finish(f.token, 'completed');
  });
  await check('verification_dispatch_control_wins_before_any_action',
      (f) async {
    await f.service.submitControl(f.request());
    var actions = 0;
    final guard = PersistedVerificationDispatch(
        store: f.store, token: f.token, prefix: 'verification-native');
    return await rejects(() => guard.run('step', () async {
              actions++;
              return 7;
            })) &&
        actions == 0;
  });
  await check(
      'verification_dispatch_inflight_fact_does_not_replace_corrected_plan',
      (f) async {
    final guard = PersistedVerificationDispatch(
        store: f.store, token: f.token, prefix: 'verification-native');
    var actions = 0;
    final value = await guard.run('step', () async {
      actions++;
      await f.service.submitControl(f.request());
      await f.store.consume(f.taskId, f.token.runId);
      return 7;
    });
    final head = (await f.store.head(f.taskId))!;
    return value == 7 &&
        actions == 1 &&
        head.token.version == 2 &&
        head.state == 'running' &&
        !await f.store.finish(f.token, 'completed');
  });
  await check('verification_dispatch_unknown_action_is_not_blindly_replayed',
      (f) async {
    var actions = 0;
    final first = PersistedVerificationDispatch(
        store: f.store, token: f.token, prefix: 'verification-native');
    final failed = await rejects(() => first.run('step', () async {
          actions++;
          throw StateError('Synthetic unknown action');
        }));
    final retry = PersistedVerificationDispatch(
        store: f.store, token: f.token, prefix: 'verification-native');
    return failed &&
        await rejects(() => retry.run('step', () async {
              actions++;
              return 7;
            })) &&
        actions == 1;
  });
  await check('verification_dispatch_cancelled_owner_does_not_claim_or_execute',
      (f) async {
    var actions = 0;
    final guard = PersistedVerificationDispatch(
        store: f.store,
        token: f.token,
        prefix: 'verification-native',
        canContinue: () => false);
    final failed = await rejects(() => guard.run('step', () async {
          actions++;
          return 7;
        }));
    return failed &&
        actions == 0 &&
        (await f.db.customSelect('SELECT * FROM run_dispatch_claims').get())
            .isEmpty;
  });
  await check('verification_dispatch_claim_database_failure_has_zero_actions',
      (f) async {
    await f.db.customStatement(
        "CREATE TEMP TRIGGER fixture_verification_claim_failure BEFORE INSERT ON run_dispatch_claims BEGIN SELECT RAISE(ABORT,'fixture'); END");
    var actions = 0;
    final guard = PersistedVerificationDispatch(
        store: f.store, token: f.token, prefix: 'verification-native');
    return await rejects(() => guard.run('step', () async {
              actions++;
              return 7;
            })) &&
        actions == 0;
  });
  await check('gateway_completion_continuation_keeps_original_headless_owner',
      (f) async {
    await f.store.interrupt(f.token);
    var finishes = 0;
    final p = _ScriptedProvider([
      (r) async => _scriptDone('draft'),
      (r) async => _scriptDone('final answer')
    ]);
    final result = await BackgroundExecutionGateway().run(
        db: f.db,
        config: const ProviderConfig(baseUrl: '', model: 'fixture', apiKey: ''),
        prompt: 'Synthetic bounded completion',
        taskId: f.taskId,
        runId: 'gateway-completion-owner',
        totalTokenBudget: 32000,
        profile: RunProfile.subagent,
        modules: const ModuleHost([]),
        modelRouter: ModelRouter([_OfflineFixtureRoute(p)]),
        beforeFinish: (context) async {
          finishes++;
          return finishes == 1
              ? TurnContinuation([
                  ChatMessage(role: MessageRole.user, parts: const [
                    MessagePart.text('Synthetic completion continuation')
                  ])
                ], keepAssistantText: false)
              : null;
        });
    return p.requests.length == 2 &&
        result.runId == 'gateway-completion-owner' &&
        result.succeeded &&
        result.text == 'final answer' &&
        (await f.store.head(f.taskId))!.token.runId == result.runId;
  });
  await check(
      'gateway_tiny_request_budget_pauses_without_model_dispatch_or_completion',
      (f) async {
    await f.store.interrupt(f.token);
    final p =
        _ScriptedProvider([(r) async => _scriptDone('must-not-be-requested')]);
    var finishes = 0;
    final result = await BackgroundExecutionGateway().run(
        db: f.db,
        config: const ProviderConfig(baseUrl: '', model: 'fixture', apiKey: ''),
        prompt: 'Synthetic strict request budget',
        taskId: f.taskId,
        runId: 'gateway-budget-owner',
        totalTokenBudget: 1,
        profile: RunProfile.subagent,
        modules: const ModuleHost([]),
        modelRouter: ModelRouter([_OfflineFixtureRoute(p)]),
        beforeFinish: (context) async {
          finishes++;
          return null;
        });
    return p.requests.isEmpty &&
        finishes == 0 &&
        result.status == RunStatus.paused &&
        !result.succeeded &&
        (await f.store.head(f.taskId))!.state == 'interrupted';
  });
  await check(
      'completion_allowlist_filters_manifest_and_denies_injected_tool',
      (f) => _withFence(f, (c, x) async {
            final gate = _CounterGate();
            var endings = 0;
            final p = _ScriptedProvider([
              (r) async => _scriptDone('draft'),
              (r) async => [
                    const ToolCallEvent(ToolCall(
                        id: 'injected-repair-tool',
                        name: 'fixture_gate',
                        arguments: {})),
                    const CompletedEvent(stopReason: StopReason.toolUse)
                  ],
              (r) async => _scriptDone('done')
            ]);
            final events =
                await _runScript(p, c, gate, beforeFinish: (context) async {
              endings++;
              return endings == 1
                  ? TurnContinuation(
                      [
                        ChatMessage(
                            role: MessageRole.user,
                            parts: const [MessagePart.text('Bounded repair')])
                      ],
                      keepAssistantText: false,
                      allowedToolNames: const {'read_file'})
                  : null;
            });
            return p.requests.length == 3 &&
                p.requests[1].tools.every((t) => t.name != 'fixture_gate') &&
                gate.executions == 0 &&
                gate.authorizations == 0 &&
                events.whereType<ToolResultEvent>().single.result.effect ==
                    ToolEffect.none &&
                (await f.store.history(f.taskId)).length == 1;
          }));
  await check(
      'development_completion_real_finalizer_runs_before_original_loop_seals',
      (f) => _withFence(f, (c, x) async {
            final directory = await Directory.systemTemp
                .createTemp('nexus-completion-fixture-');
            try {
              var factories = 0;
              final completion = DevelopmentRunCompletion(
                  db: f.db,
                  taskId: f.taskId,
                  runId: f.token.runId,
                  workspacePath: directory.path,
                  terminalFactory: () async {
                    factories++;
                    return null;
                  },
                  repairEnabled: () async => false,
                  canContinue: () => !c.isCancelled);
              final p = _ScriptedProvider([(r) async => _scriptDone('done')]);
              await _runScript(p, c, _CounterGate(),
                  beforeFinish: completion.call);
              return factories == 1 &&
                  completion.latest != null &&
                  !completion.latest!.verified &&
                  !completion.verificationRequested &&
                  c.isSealed &&
                  p.requests.length == 1 &&
                  (await f.store.head(f.taskId))!.state == 'completed' &&
                  (await f.store.history(f.taskId)).length == 1;
            } finally {
              await directory.delete(recursive: true);
            }
          }));
  await check('development_completion_foreign_owner_never_constructs_terminal',
      (f) async {
    var factories = 0;
    final completion = DevelopmentRunCompletion(
        db: f.db,
        taskId: f.taskId,
        runId: 'foreign',
        workspacePath: 'unused',
        terminalFactory: () async {
          factories++;
          return null;
        },
        repairEnabled: () async => true,
        canContinue: () => true);
    final result = await completion
        .call(const TurnStoppingContext(step: 1, finalText: 'draft'));
    return result == null && factories == 0 && completion.latest == null;
  });
  await check(
      'development_completion_pending_control_never_constructs_terminal',
      (f) async {
    await f.service.submitControl(f.request());
    var factories = 0;
    final completion = DevelopmentRunCompletion(
        db: f.db,
        taskId: f.taskId,
        runId: f.token.runId,
        workspacePath: 'unused',
        terminalFactory: () async {
          factories++;
          return null;
        },
        repairEnabled: () async => true,
        canContinue: () => true);
    final result = await completion
        .call(const TurnStoppingContext(step: 1, finalText: 'draft'));
    return result == null &&
        factories == 0 &&
        completion.latest == null &&
        (await f.store.head(f.taskId))!.pendingControls;
  });
  await check(
      'development_completion_drain_joins_cleanup_and_local_revision_revokes',
      (f) async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var valid = true;
    var drained = false;
    final completion = DevelopmentRunCompletion(
        db: f.db,
        taskId: f.taskId,
        runId: f.token.runId,
        workspacePath: 'unused',
        terminalFactory: () async {
          entered.complete();
          await release.future;
          return null;
        },
        repairEnabled: () async => true,
        canContinue: () => true);
    final pending = completion.call(TurnStoppingContext(
        step: 1, finalText: 'draft', canContinue: () => valid));
    await entered.future;
    valid = false;
    final join = completion.drain().then((_) {
      drained = true;
    });
    await Future<void>.delayed(Duration.zero);
    final joinedTooEarly = drained;
    release.complete();
    await pending;
    await join;
    return !joinedTooEarly &&
        drained &&
        completion.latest == null &&
        !completion.verificationRequested;
  });
  await check(
      'agent_completion_obsolete_exception_does_not_fail_accepted_correction',
      (f) => _withFence(f, (c, x) async {
            var endings = 0;
            final p = _ScriptedProvider([
              (r) async => _scriptDone('old'),
              (r) async => _scriptDone('new')
            ]);
            final events = await _runScript(p, c, _CounterGate(),
                beforeFinish: (context) async {
              endings++;
              if (endings == 1) {
                await f.service.submitControl(f.request());
                await c.synchronize();
                throw StateError('Obsolete synthetic verification failure');
              }
              return null;
            });
            return endings == 2 &&
                p.requests.length == 2 &&
                _hasSteering(p.requests[1]) &&
                events.whereType<AgentStatusEvent>().last.status ==
                    RunStatus.completed &&
                (await f.store.head(f.taskId))!.token.version == 2;
          }));
  await check('completion_ack_same_owner_old_version_cannot_finalize_new_plan',
      (f) async {
    await f.service.submitControl(f.request());
    final current = (await f.store.consume(f.taskId, f.token.runId)).head.token;
    await f.store.finish(current, 'completed');
    await TaskService().complete(f.db, f.taskId,
        status: 'completed',
        summary: 'obsolete',
        runId: f.token.runId,
        planVersion: f.token.version);
    final staleRejected =
        (await f.db.findTask(f.taskId))!.status != 'completed';
    await TaskService().complete(f.db, f.taskId,
        status: 'completed',
        summary: 'current',
        runId: current.runId,
        planVersion: current.version);
    return staleRejected &&
        (await f.db.findTask(f.taskId))!.status == 'completed';
  });
  await check(
      'completion_allowlist_new_user_correction_restores_normal_policy',
      (f) => _withFence(f, (c, x) async {
            final gate = _CounterGate();
            var endings = 0;
            final p = _ScriptedProvider([
              (r) async => _scriptDone('draft'),
              (r) async {
                await f.service.submitControl(f.request());
                await c.synchronize();
                return _scriptDone('obsolete');
              },
              (r) async => [
                    const ToolCallEvent(ToolCall(
                        id: 'user-corrected-call',
                        name: 'fixture_gate',
                        arguments: {})),
                    const CompletedEvent(stopReason: StopReason.toolUse)
                  ],
              (r) async => _scriptDone('done')
            ]);
            await _runScript(p, c, gate, beforeFinish: (context) async {
              endings++;
              return endings == 1
                  ? TurnContinuation(
                      [
                        ChatMessage(
                            role: MessageRole.user,
                            parts: const [MessagePart.text('Bounded repair')])
                      ],
                      keepAssistantText: false,
                      allowedToolNames: const {'read_file'})
                  : null;
            });
            return p.requests.length == 4 &&
                p.requests[1].tools.every((t) => t.name != 'fixture_gate') &&
                p.requests[2].tools.any((t) => t.name == 'fixture_gate') &&
                gate.executions == 1 &&
                gate.authorizations == 1;
          }));
  await check('verification_original_service_claims_session_and_each_command',
      (f) async {
    final directory =
        await Directory.systemTemp.createTemp('nexus-verification-fixture-');
    try {
      final runtime = _VerificationRuntime();
      final terminal = _VerificationTerminal(directory, runtime);
      final result = await DevelopmentVerificationService().run(
          service: terminal,
          workspacePath: directory.path,
          plan: _verificationRuntimePlan,
          executionGuard: PersistedVerificationDispatch(
              store: f.store,
              token: f.token,
              prefix: '__native-verification',
              canContinue: () => true),
          canContinue: () => true);
      final rows = await f.db.customSelect(
          'SELECT state FROM run_dispatch_claims WHERE run_id=?',
          variables: [Variable<String>(f.token.runId)]).get();
      return result.success &&
          runtime.calls == 2 &&
          terminal.opens == 1 &&
          terminal.sessionClosed &&
          rows.length == 3 &&
          rows.every((r) => r.data['state'] != 'dispatched');
    } finally {
      await directory.delete(recursive: true);
    }
  });
  await check('verification_original_service_pending_control_opens_no_session',
      (f) async {
    final directory =
        await Directory.systemTemp.createTemp('nexus-verification-fixture-');
    try {
      final runtime = _VerificationRuntime();
      final terminal = _VerificationTerminal(directory, runtime);
      await f.service.submitControl(f.request());
      var revoked = false;
      try {
        await DevelopmentVerificationService().run(
            service: terminal,
            workspacePath: directory.path,
            plan: _verificationRuntimePlan,
            executionGuard: PersistedVerificationDispatch(
                store: f.store,
                token: f.token,
                prefix: '__native-verification',
                canContinue: () => true),
            canContinue: () => true);
      } on VerificationDispatchRevoked {
        revoked = true;
      }
      return revoked &&
          runtime.calls == 0 &&
          terminal.opens == 0 &&
          terminal.sessionClosed;
    } finally {
      await directory.delete(recursive: true);
    }
  });
  await check(
      'verification_original_service_keeps_inflight_fact_and_blocks_next_command',
      (f) async {
    final directory =
        await Directory.systemTemp.createTemp('nexus-verification-fixture-');
    try {
      final runtime = _VerificationRuntime()
        ..onRun = () async {
          await f.service.submitControl(f.request());
          await f.store.consume(f.taskId, f.token.runId);
          return const CommandResult(
              output: 'synthetic completed old check', exitCode: 0);
        };
      final terminal = _VerificationTerminal(directory, runtime);
      var revoked = false;
      try {
        await DevelopmentVerificationService().run(
            service: terminal,
            workspacePath: directory.path,
            plan: _verificationRuntimePlan,
            executionGuard: PersistedVerificationDispatch(
                store: f.store,
                token: f.token,
                prefix: '__native-verification',
                canContinue: () => true),
            canContinue: () => true);
      } on VerificationDispatchRevoked {
        revoked = true;
      }
      final rows = await f.db.customSelect(
          'SELECT state FROM run_dispatch_claims WHERE run_id=?',
          variables: [Variable<String>(f.token.runId)]).get();
      return revoked &&
          runtime.calls == 1 &&
          terminal.sessionClosed &&
          rows.length == 2 &&
          rows.every((r) => r.data['state'] != 'dispatched') &&
          (await f.store.head(f.taskId))!.token.version == 2;
    } finally {
      await directory.delete(recursive: true);
    }
  });
  await check(
      'verification_original_terminal_cancel_stops_only_owned_runtime_and_closes_session',
      (f) async {
    final directory =
        await Directory.systemTemp.createTemp('nexus-verification-fixture-');
    final runtime = _VerificationRuntime();
    try {
      var valid = true;
      final entered = Completer<void>();
      runtime.pending = Completer<CommandResult>();
      runtime.onRun = () async {
        entered.complete();
        return runtime.pending!.future;
      };
      final terminal = _VerificationTerminal(directory, runtime);
      final pending = DevelopmentVerificationService().run(
          service: terminal,
          workspacePath: directory.path,
          plan: _verificationRuntimePlan,
          executionGuard: PersistedVerificationDispatch(
              store: f.store,
              token: f.token,
              prefix: '__native-verification',
              canContinue: () => valid),
          canContinue: () => valid);
      await entered.future.timeout(const Duration(seconds: 2));
      valid = false;
      final result = await pending.timeout(const Duration(seconds: 2));
      return !result.success &&
          runtime.calls == 1 &&
          runtime.stops > 0 &&
          terminal.sessionClosed &&
          result.plan.steps.first.status == VerificationStepStatus.failed;
    } finally {
      if (runtime.isRunning) runtime.stop();
      await directory.delete(recursive: true);
    }
  });
  await check(
      'completion_original_finalizer_verifier_terminal_continue_and_reverify_one_owner',
      (f) => _withFence(f, (c, x) async {
            final directory = await Directory.systemTemp
                .createTemp('nexus-completion-integration-');
            try {
              await _prepareCompletionWorkspace(f, directory);
              final runtime = _VerificationRuntime();
              runtime.onRun = () async => CommandResult(
                  output: runtime.calls == 1
                      ? 'synthetic check failed'
                      : 'synthetic check passed',
                  exitCode: runtime.calls == 1 ? 1 : 0);
              final terminal = _VerificationTerminal(directory, runtime);
              final completion = DevelopmentRunCompletion(
                  db: f.db,
                  taskId: f.taskId,
                  runId: f.token.runId,
                  workspacePath: directory.path,
                  terminalFactory: () async => terminal,
                  repairEnabled: () async => true,
                  canContinue: () => !c.isCancelled);
              final p = _ScriptedProvider([
                (r) async => _scriptDone('draft'),
                (r) async => _scriptDone('rechecked')
              ]);
              await _runScript(p, c, _CounterGate(),
                  beforeFinish: completion.call);
              await completion.drain();
              final progress = await TaskService().progress(f.db, f.taskId);
              final attempts = progress['verificationRepairAttempts'] as List?;
              return p.requests.length == 2 &&
                  runtime.calls == 2 &&
                  terminal.opens == 2 &&
                  terminal.sessionClosed &&
                  completion.latest?.verified == true &&
                  c.isSealed &&
                  (await f.store.history(f.taskId)).length == 1 &&
                  (await f.store.head(f.taskId))!.token.runId ==
                      f.token.runId &&
                  attempts?.length == 1 &&
                  (attempts!.single as Map)['status'] == 'completed';
            } finally {
              await directory.delete(recursive: true);
            }
          }));
  await check(
      'completion_required_verification_failure_never_seals_success',
      (f) => _withFence(f, (c, x) async {
            final directory = await Directory.systemTemp
                .createTemp('nexus-completion-integration-');
            try {
              await _prepareCompletionWorkspace(f, directory);
              final runtime = _VerificationRuntime()
                ..onRun = () async => const CommandResult(
                    output: 'synthetic check failed', exitCode: 1);
              final terminal = _VerificationTerminal(directory, runtime);
              final completion = DevelopmentRunCompletion(
                  db: f.db,
                  taskId: f.taskId,
                  runId: f.token.runId,
                  workspacePath: directory.path,
                  terminalFactory: () async => terminal,
                  repairEnabled: () async => false,
                  canContinue: () => !c.isCancelled);
              final p = _ScriptedProvider([(r) async => _scriptDone('draft')]);
              var rejected = false;
              try {
                await _runScript(p, c, _CounterGate(),
                    beforeFinish: completion.call);
              } on DevelopmentCompletionUnverified {
                rejected = true;
              }
              await completion.drain();
              return rejected &&
                  !c.isSealed &&
                  runtime.calls == 1 &&
                  terminal.sessionClosed &&
                  completion.latest?.verified == false &&
                  (await f.store.head(f.taskId))!.state != 'completed';
            } finally {
              await directory.delete(recursive: true);
            }
          }));
  await check(
      'completion_repeated_failure_obeys_original_persisted_repair_limit',
      (f) => _withFence(f, (c, x) async {
            final directory = await Directory.systemTemp
                .createTemp('nexus-completion-integration-');
            try {
              await _prepareCompletionWorkspace(f, directory);
              final runtime = _VerificationRuntime()
                ..onRun = () async => const CommandResult(
                    output: 'synthetic check failed', exitCode: 1);
              final terminal = _VerificationTerminal(directory, runtime);
              final completion = DevelopmentRunCompletion(
                  db: f.db,
                  taskId: f.taskId,
                  runId: f.token.runId,
                  workspacePath: directory.path,
                  terminalFactory: () async => terminal,
                  repairEnabled: () async => true,
                  canContinue: () => !c.isCancelled);
              final p = _ScriptedProvider([
                (r) async => _scriptDone('draft'),
                (r) async => _scriptDone('still failed')
              ]);
              var rejected = false;
              try {
                await _runScript(p, c, _CounterGate(),
                    beforeFinish: completion.call);
              } on DevelopmentCompletionUnverified {
                rejected = true;
              }
              await completion.drain();
              final progress = await TaskService().progress(f.db, f.taskId);
              final attempts = progress['verificationRepairAttempts'] as List?;
              return rejected &&
                  !c.isSealed &&
                  p.requests.length == 2 &&
                  runtime.calls == 2 &&
                  terminal.sessionClosed &&
                  attempts?.length == 1 &&
                  (attempts!.single as Map)['status'] == 'failed' &&
                  (await f.store.history(f.taskId)).length == 1 &&
                  (await f.store.head(f.taskId))!.state != 'completed';
            } finally {
              await directory.delete(recursive: true);
            }
          }));
  Future<Task> appliedCheckpoint(_Fixture f,
      {String phase = 'completed', int? version = 1}) async {
    final task = (await f.db.findTask(f.taskId))!;
    await f.db.updateTaskSnapshot(task.copyWith(
        progressJson: jsonEncode({
      'phase': phase,
      'runId': f.token.runId,
      if (version != null) 'planVersion': version,
      'summary': 'persisted original result',
      'appliedRunIds': [f.token.runId],
      'checkpoint': {'runId': f.token.runId, 'context': <Object>[]},
    })));
    return (await f.db.findTask(f.taskId))!;
  }

  Future<bool> reconcile(_Fixture f, Task snapshot) =>
      TaskService().reconcileAppliedCheckpoint(f.db,
          snapshot: snapshot, runId: f.token.runId);
  await check('restore_applied_receipt_cannot_complete_live_head', (f) async {
    final snapshot = await appliedCheckpoint(f);
    return !await reconcile(f, snapshot) &&
        (await f.db.findTask(f.taskId))!.progressJson ==
            snapshot.progressJson &&
        (await f.db.findTask(f.taskId))!.status == 'running';
  });
  await check('restore_matching_completed_head_reconciles_atomically',
      (f) async {
    final snapshot = await appliedCheckpoint(f);
    await f.store.finish(f.token, 'completed');
    final accepted = await reconcile(f, snapshot);
    final task = (await f.db.findTask(f.taskId))!;
    final progress = jsonDecode(task.progressJson) as Map;
    return accepted &&
        task.status == 'completed' &&
        !progress.containsKey('checkpoint') &&
        progress['summary'] == 'persisted original result' &&
        task.stateRevision == snapshot.stateRevision + 1 &&
        !await reconcile(f, snapshot);
  });
  await check('restore_applied_failed_receipt_never_promotes_success',
      (f) async {
    final snapshot = await appliedCheckpoint(f, phase: 'failed');
    await f.store.finish(f.token, 'failed');
    return await reconcile(f, snapshot) &&
        (await f.db.findTask(f.taskId))!.status == 'failed';
  });
  await check('restore_applied_cancelled_receipt_stays_cancelled', (f) async {
    final snapshot = await appliedCheckpoint(f, phase: 'cancelled');
    await f.store.finish(f.token, 'cancelled');
    return await reconcile(f, snapshot) &&
        (await f.db.findTask(f.taskId))!.status == 'cancelled';
  });
  await check('restore_same_owner_new_plan_does_not_clear_old_checkpoint',
      (f) async {
    final snapshot = await appliedCheckpoint(f);
    await f.service.submitControl(f.request());
    final batch = await f.store.consume(f.taskId, f.token.runId);
    await f.store.finish(batch.head.token, 'completed');
    return !await reconcile(f, snapshot) &&
        (await f.db.findTask(f.taskId))!.progressJson == snapshot.progressJson;
  });
  await check('restore_new_run_owner_does_not_accept_old_applied_result',
      (f) async {
    final snapshot = await appliedCheckpoint(f);
    await f.store.finish(f.token, 'failed');
    await f.store.bind(
        taskId: f.taskId,
        runId: 'new-owner',
        expectedPreviousRunId: f.token.runId);
    return !await reconcile(f, snapshot) &&
        (await f.db.findTask(f.taskId))!.status == 'running';
  });
  await check('restore_stale_snapshot_cannot_clear_current_checkpoint',
      (f) async {
    final snapshot = await appliedCheckpoint(f);
    await f.store.finish(f.token, 'completed');
    await f.db.updateTaskSnapshot(snapshot.copyWith(updatedAt: DateTime.now()));
    return !await reconcile(f, snapshot) &&
        (await f.db.findTask(f.taskId))!.progressJson == snapshot.progressJson;
  });
  await check('restore_unversioned_applied_result_is_not_completion_proof',
      (f) async {
    final snapshot = await appliedCheckpoint(f, version: null);
    await f.store.finish(f.token, 'completed');
    return !await reconcile(f, snapshot) &&
        (await f.db.findTask(f.taskId))!.status == 'running';
  });
  await check('restore_unknown_applied_phase_is_not_success', (f) async {
    final snapshot = await appliedCheckpoint(f, phase: 'paused');
    await f.store.finish(f.token, 'completed');
    return !await reconcile(f, snapshot);
  });
  await check('task_receipt_persists_version_and_never_inherits_missing_proof',
      (f) async {
    final tasks = TaskService();
    await tasks.complete(f.db, f.taskId,
        status: 'paused',
        summary: 'paused',
        runId: f.token.runId,
        planVersion: f.token.version);
    final saved = await tasks.progress(f.db, f.taskId);
    await tasks.complete(f.db, f.taskId,
        status: 'paused', summary: 'legacy paused', runId: f.token.runId);
    final unversioned = await tasks.progress(f.db, f.taskId);
    return saved['planVersion'] == f.token.version &&
        !unversioned.containsKey('planVersion');
  });
  cases.addAll(await runSpeechCaptureChecks());
  cases.addAll(await runEntryIntentChecks());
  cases.addAll(await runTtsLifecycleChecks());
  cases.addAll(await runAssistantRoleChecks());
  cases.addAll(await runAssistantEntryChecks());
  cases.addAll(await runPersonalContextChecks());
  cases.addAll(await runResultCardChecks());
  return {
    'type': 'PlanProtocolContractChecks',
    'fixtureOnly': true,
    'modelCalls': 0,
    'platformMutations': 0,
    'persistentDataMutations': 0,
    'cases': cases,
    'passed': cases.where((r) => r['passed'] == true).length,
    'total': cases.length
  };
}
