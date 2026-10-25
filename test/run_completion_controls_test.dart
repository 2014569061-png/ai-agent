import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/agent_executor.dart';
import 'package:mobile_agent/application/agent_loop/token_budget.dart';
import 'package:mobile_agent/application/background_execution_gateway.dart';
import 'package:mobile_agent/application/task_service.dart';
import 'package:mobile_agent/application/compaction_recovery.dart';
import 'package:mobile_agent/application/context_window.dart';
import 'package:mobile_agent/application/development_verification.dart';
import 'package:mobile_agent/application/execution_lease_service.dart';
import 'package:mobile_agent/application/headless_executor.dart';
import 'package:mobile_agent/application/history_compactor.dart';
import 'package:mobile_agent/application/project_kind.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/providers/llm_provider.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/infrastructure/providers/model_route.dart';
import 'package:mobile_agent/infrastructure/terminal/host_process_runtime_adapter.dart';
import 'package:mobile_agent/infrastructure/tools/command_tool.dart';
import 'package:mobile_agent/infrastructure/tools/tool_registry.dart';
import 'package:mobile_agent/infrastructure/tools/workspace_tools.dart';
import 'package:mobile_agent/infrastructure/tools/sub_agent_tool.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../tool/agent_live_acceptance.dart';

ChatMessage _user(String text) =>
    ChatMessage(role: MessageRole.user, parts: [MessagePart.text(text)]);

class _Provider implements LlmProvider {
  _Provider(this.respond);
  final Stream<UnifiedEvent> Function(UnifiedRequest) respond;
  final requests = <UnifiedRequest>[];
  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) {
    requests.add(request);
    return respond(request);
  }
}

class _BlockingRuntime implements LinuxRuntimeAdapter {
  final started = Completer<void>();
  final finish = Completer<CommandResult>();
  final commands = <String>[];
  int stops = 0;
  @override
  LinuxRuntimeKind get kind => LinuxRuntimeKind.hostProcess;
  @override
  bool get supportsShellSyntax => false;
  @override
  bool get supportsInterpreterEvaluation => false;
  @override
  bool get isRunning => started.isCompleted && !finish.isCompleted;
  @override
  Future<LinuxRuntimeInfo> inspect() async => const LinuxRuntimeInfo(
      kind: LinuxRuntimeKind.hostProcess,
      label: 'test',
      available: true,
      detail: '');
  @override
  Future<CommandResult> run(LinuxCommandRequest request,
      {required String workingDirectory, required Duration timeout}) {
    commands.add(request.commandLine);
    if (!started.isCompleted) started.complete();
    return finish.future;
  }

  @override
  void stop() {
    stops++;
    if (!finish.isCompleted) {
      finish.complete(const CommandResult(output: 'stopped', exitCode: 0));
    }
  }
}

class _Route implements ModelRoute {
  _Route(this.provider);
  final LlmProvider provider;
  @override
  String get id => 'scripted-acceptance';
  @override
  LlmProvider providerFor(ProviderConfig config) => provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'verification cancellation stops the running command and skips later checks',
      () async {
    final dir = await Directory.systemTemp.createTemp('nexus-cancel-');
    addTearDown(() => dir.delete(recursive: true));
    final runtime = _BlockingRuntime();
    final service = TerminalCommandService(
        workspacePath: dir.path,
        runtime: runtime,
        jobLogDirectory: Directory(p.join(dir.path, 'logs')));
    var proceed = true;
    final future = DevelopmentVerificationService().run(
        service: service,
        workspacePath: dir.path,
        canContinue: () => proceed,
        plan: const DevelopmentVerificationPlan(
            project: ProjectKindDetection(
                kind: ProjectKind.python, confidence: 1, signals: []),
            steps: [
              VerificationStep(
                  id: 'first', title: 'first', command: 'python slow.py'),
              VerificationStep(
                  id: 'next', title: 'next', command: 'python next.py')
            ]));
    await runtime.started.future;
    proceed = false;
    final result = await future.timeout(const Duration(seconds: 3));
    expect(runtime.stops, 1);
    expect(runtime.commands, ['python slow.py']);
    expect(result.success, isFalse);
    expect(result.plan.steps.first.exitCode, 130);
    expect(result.plan.steps.last.status, VerificationStepStatus.pending);
  });

  test('cancelled queued command cannot stop the current runtime owner',
      () async {
    final dir = await Directory.systemTemp.createTemp('nexus-queue-');
    addTearDown(() => dir.delete(recursive: true));
    final runtime = _BlockingRuntime();
    final service =
        TerminalCommandService(workspacePath: dir.path, runtime: runtime);
    final first = service.run('python first.py');
    await runtime.started.future;
    final second = service.run('python second.py', canContinue: () => false);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(runtime.stops, 0);
    runtime.finish.complete(const CommandResult(output: 'done', exitCode: 0));
    expect((await first).succeeded, isTrue);
    expect((await second).notExecuted, isTrue);
    expect(runtime.commands, ['python first.py']);
  });

  test(
      'same task cannot replace a live run; nested repair borrows the outer lease',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final task = await TaskService().create(
      db: db,
      conversationId: 'lease-fixture',
      requestJson: '{}',
    );
    final guard = await WorkspaceLeaseGuard.open(
        db: db,
        workspacePath: '/tmp/lease-test',
        taskId: task.id,
        runId: 'outer',
        onLost: () => fail('lease lost'));
    addTearDown(guard.close);
    final key = guard.lease.resourceKey;
    await expectLater(
        const ExecutionLeaseService()
            .acquire(db: db, resourceKey: key, taskId: task.id, runId: 'other'),
        throwsA(isA<ExecutionLeaseConflict>()));
    await BackgroundExecutionGateway().run(
        db: db,
        config: const ProviderConfig(
            baseUrl: 'https://unused.invalid', model: 'test', apiKey: ''),
        prompt: 'repair',
        taskId: task.id,
        workspacePath: '/tmp/lease-test',
        leaseGuard: guard,
        execute: () async => const HeadlessRunResult(
            text: 'done',
            status: RunStatus.completed,
            inputTokens: 0,
            outputTokens: 0,
            cachedTokens: 0));
    expect(
        (await db.findExecutionLease(key))!.ownerToken, guard.lease.ownerToken);
    await guard.close();
    expect(await db.findExecutionLease(key), isNull);
  });

  test('borrowed lease rejects another workspace before dispatch', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final task = await TaskService().create(
      db: db,
      conversationId: 'lease-fixture',
      requestJson: '{}',
    );
    final guard = await WorkspaceLeaseGuard.open(
        db: db,
        workspacePath: '/tmp/one',
        taskId: task.id,
        runId: 'outer',
        onLost: () {});
    addTearDown(guard.close);
    await expectLater(
        BackgroundExecutionGateway().run(
            db: db,
            config: const ProviderConfig(
                baseUrl: 'https://unused.invalid', model: 'test', apiKey: ''),
            prompt: 'repair',
            taskId: task.id,
            workspacePath: '/tmp/two',
            leaseGuard: guard,
            execute: () async => throw StateError('must not dispatch')),
        throwsA(isA<ExecutionLeaseConflict>()));
  });

  test('token ledger caps requests and conservatively charges missing usage',
      () async {
    final provider = _Provider((_) async* {
      yield const CompletedEvent();
    });
    final request = UnifiedRequest(
        model: 'test', messages: [_user('hello')], maxTokens: 1000);
    final input = TokenBudgetProvider.inputReservation(request);
    final budgeted = TokenBudgetProvider(provider, input + 100);
    await budgeted.stream(request).drain<void>();
    expect(provider.requests.single.maxTokens, 100);
    final retry = await budgeted.stream(request).toList();
    expect(provider.requests, hasLength(1));
    expect((retry.single as ProviderErrorEvent).failureKind,
        TokenBudgetProvider.exhausted);
    expect(budgeted.spent, input + 100);
  });

  test(
      'reported input+output usage settles once without double counting cache or reasoning',
      () async {
    final provider = _Provider((_) async* {
      yield const UsageEvent(
          promptTokens: 100,
          completionTokens: 50,
          cachedTokens: 40,
          reasoningTokens: 20);
      yield const CompletedEvent();
    });
    final budgeted = TokenBudgetProvider(provider, 5000);
    final request = UnifiedRequest(
        model: 'test', messages: [_user('hello')], maxTokens: 1000);
    await budgeted.stream(request).drain<void>();
    await budgeted.stream(request).drain<void>();
    expect(budgeted.spent, 300);
  });

  test(
      'zero or incomplete usage never refunds the reservation of a failed request',
      () async {
    for (final count in [0, 20]) {
      final provider = _Provider((_) async* {
        yield UsageEvent(promptTokens: count, completionTokens: 0);
        yield const ProviderErrorEvent('unavailable', statusCode: 503);
      });
      final request = UnifiedRequest(
          model: 'test', messages: [_user('hello')], maxTokens: 100);
      final cost = TokenBudgetProvider.inputReservation(request) + 100;
      final budgeted = TokenBudgetProvider(provider, cost);
      await budgeted.stream(request).drain<void>();
      await budgeted.stream(request).drain<void>();
      expect(provider.requests, hasLength(1));
      expect(budgeted.spent, cost);
    }
  });

  test(
      'budget exhaustion retains a structured child stop reason and partial result',
      () async {
    final result = await SubAgentTool(onRun: (_, __, ___) async {
      throw const SubAgentFailure(ToolCodes.tokenBudgetExhausted,
          partialText: 'Already inspected two files',
          inputTokens: 300,
          outputTokens: 100);
    }).execute({'prompt': 'inspect'});
    expect(result.ok, isFalse);
    expect(result.code, ToolCodes.tokenBudgetExhausted);
    expect(result.data!['stopReason'], 'cumulative_token_budget');
    expect(result.data!['partialSummary'], 'Already inspected two files');
  });

  test('automatic retries consume the same budget and pause with a checkpoint',
      () async {
    final provider = _Provider((_) async* {
      yield const ProviderErrorEvent('temporarily unavailable',
          statusCode: 503);
    });
    final events =
        await AgentExecutor(provider: provider, tools: ToolRegistry()).run(
            history: [_user('continue')],
            model: 'test',
            maxTokens: 100,
            totalTokenBudget: 700,
            retryBackoff: Duration.zero).toList();
    expect(provider.requests, hasLength(2));
    final paused = events.whereType<AgentBudgetExhaustedEvent>().single;
    expect(paused.reason, AgentPauseReason.tokenBudget);
    expect(paused.context.last.text, 'continue');
    expect(events.whereType<AgentStatusEvent>().last.status, RunStatus.paused);
  });

  test(
      'summary and main request share one ledger and cannot get a fresh budget',
      () async {
    final history = [_user('old ${'中' * 5000}'), _user('continue')];
    Stream<UnifiedEvent> respond(UnifiedRequest _) async* {
      yield const TextDeltaEvent('Original goal, pending TODO');
      yield const CompletedEvent();
    }

    final probe = _Provider(respond);
    await AgentExecutor(provider: probe, tools: ToolRegistry())
        .run(
            history: history,
            model: 'test',
            contextBudgetTokens: 4000,
            maxTokens: 512)
        .drain<void>();
    final summaryCost =
        TokenBudgetProvider.inputReservation(probe.requests.first) +
            probe.requests.first.maxTokens;
    final provider = _Provider(respond);
    final events =
        await AgentExecutor(provider: provider, tools: ToolRegistry())
            .run(
                history: history,
                model: 'test',
                contextBudgetTokens: 4000,
                maxTokens: 512,
                totalTokenBudget: summaryCost)
            .toList();
    expect(provider.requests, hasLength(1));
    expect(provider.requests.single.tools, isEmpty);
    expect(events.whereType<AgentBudgetExhaustedEvent>().single.reason,
        AgentPauseReason.tokenBudget);
  });

  test(
      'compaction rereads latest rules and five files, bounded; unseen files need reread',
      () async {
    final dir = await Directory.systemTemp.createTemp('nexus-recover-');
    addTearDown(() => dir.delete(recursive: true));
    final sandbox = WorkspaceSandbox(dir.path, requireReadBeforeWrite: true);
    final registry = ToolRegistry()..register(ReadFileTool(sandbox: sandbox));
    await File(p.join(dir.path, 'NEXUS.md'))
        .writeAsString('Current workspace rules');
    final calls = <ToolCall>[];
    for (var i = 0; i < 6; i++) {
      await File(p.join(dir.path, '$i.txt')).writeAsString('latest-$i');
      await registry.find('read_file')!.execute({'path': '$i.txt'});
      calls.add(ToolCall(
          id: 'read-$i', name: 'read_file', arguments: {'path': '$i.txt'}));
    }
    await File(p.join(dir.path, '5.txt'))
        .writeAsString('external edit latest-5');
    final recovery =
        await CompactionRecovery(registry, currentPlan: () => 'TODO validate')
            .recover([
      ChatMessage(
          role: MessageRole.assistant, parts: const [], toolCalls: calls)
    ], 5000);
    expect(recovery, contains('Current workspace rules'));
    expect(recovery, contains('TODO validate'));
    expect(recovery, contains('external edit latest-5'));
    expect(recovery, contains('latest-1'));
    expect(recovery, isNot(contains('latest-0')));
    expect(recovery.length, lessThanOrEqualTo(5000));
    expect(
        (await WriteFileTool(sandbox: sandbox)
                .execute({'path': '5.txt', 'content': 'oops'}))
            .code,
        ToolCodes.readRequired);
  });

  test('recovery is injected only after successful summary and fits the window',
      () async {
    var recoveries = 0;
    final window = ContextWindow(maxTokens: 4000);
    final history = [_user('old ${'中' * 7000}'), _user('continue')];
    Future<String> recover(List<ChatMessage> _, int max) async {
      recoveries++;
      return 'fresh file contents';
    }

    final failed = await HistoryCompactor().apply(history,
        window: window, summarize: (_, __) async => null, recover: recover);
    expect(recoveries, 0);
    expect(failed.any((m) => m.text == ContextWindow.compactionNotice), isTrue);
    final compacted = await HistoryCompactor().apply(history,
        window: window,
        summarize: (_, __) async => 'goal and TODO',
        recover: recover);
    expect(recoveries, 1);
    expect(
        compacted.map((m) => m.text).join(), contains('fresh file contents'));
    expect(
        compacted.fold<int>(
            0, (sum, m) => sum + ContextWindow.estimateTokens(m)),
        lessThanOrEqualTo(window.maxTokens));
  });

  test('real host cancellation terminates a long-running process', () async {
    var ancestor = File(Platform.resolvedExecutable).parent;
    String? dart;
    for (var i = 0; i < 8; i++) {
      final candidate = p.join(ancestor.path, 'dart-sdk', 'bin',
          Platform.isWindows ? 'dart.exe' : 'dart');
      if (await File(candidate).exists()) {
        dart = candidate;
        break;
      }
      ancestor = ancestor.parent;
    }
    expect(dart, isNotNull);
    final dir = await Directory.systemTemp.createTemp('nexus-host-cancel-');
    addTearDown(() => dir.delete(recursive: true));
    final script = File(p.join(dir.path, 'slow.dart'));
    await script.writeAsString(
        "import 'dart:io';\nFuture<void> main() async { File('ready').writeAsStringSync('yes'); await Future<void>.delayed(const Duration(seconds: 20)); File('escaped').writeAsStringSync('bad'); }");
    final runtime = HostProcessRuntimeAdapter();
    addTearDown(runtime.stop);
    final execution = runtime.run(
        LinuxCommandRequest(
            commandLine: 'dart slow.dart',
            executable: dart!,
            normalizedCommand: 'dart',
            arguments: [script.path]),
        workingDirectory: dir.path,
        timeout: const Duration(seconds: 25));
    for (var i = 0;
        i < 100 && !File(p.join(dir.path, 'ready')).existsSync();
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(File(p.join(dir.path, 'ready')).existsSync(), isTrue);
    runtime.stop();
    final result = await execution.timeout(const Duration(seconds: 5));
    expect(result.exitCode, isNot(0));
    expect(File(p.join(dir.path, 'escaped')).existsSync(), isFalse);
  });

  test(
      'end-to-end fixture edits, fails real Node checks, repairs and verifies under one lease',
      () async {
    final provider = _Provider((request) async* {
      final turnStart = request.messages
          .lastIndexWhere((message) => message.role == MessageRole.user);
      final turn = request.messages.skip(turnStart);
      final injected = turn.first.text.contains('这是故障注入阶段');
      final tools = turn.where((m) => m.role == MessageRole.tool).toList();
      if (tools.isEmpty) {
        yield ToolCallEvent(ToolCall(
            id: injected ? 'inject-read' : 'repair-read',
            name: 'read_file',
            arguments: {'path': 'value.js'}));
        yield const CompletedEvent(stopReason: StopReason.toolUse);
      } else if (tools.length == 1) {
        yield ToolCallEvent(ToolCall(
            id: injected ? 'inject-edit' : 'repair-edit',
            name: 'edit_file',
            arguments: {
              'path': 'value.js',
              'targetContent': injected ? '=> 2' : '=> 3',
              'replacementContent': injected ? '=> 3' : '=> 4',
            }));
        yield const CompletedEvent(stopReason: StopReason.toolUse);
      } else {
        yield const TextDeltaEvent('修改完成，等待宿主验证');
        yield const CompletedEvent(stopReason: StopReason.endOfTurn);
      }
      yield const UsageEvent(promptTokens: 100, completionTokens: 20);
    });
    final report = await runAgentAcceptance(
        config: const ProviderConfig(
            baseUrl: 'https://unused.invalid', model: 'scripted', apiKey: ''),
        router: ModelRouter([_Route(provider)]));
    expect(report['status'], 'passed', reason: report.toString());
    expect(report['repairs'], 1);
    expect(report['leaseHeldThroughFinalization'], isTrue);
    expect(provider.requests, hasLength(6));
  });
}
