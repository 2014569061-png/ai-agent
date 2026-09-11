import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/collaboration_models.dart';
import 'collaboration_agent_runner.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/providers/provider_config_store.dart';
import 'agent_executor.dart';
import 'collaboration_budget.dart';
import 'collaboration_synthesizer.dart';
import 'task_service.dart';
import 'task_template_service.dart';
import 'providers.dart';

abstract interface class OrchestrationModule {
  Future<CollaborationPlan> propose(DevelopmentTaskInput task);
  Future<CollaborationRunSnapshot> start(
      String taskId, CollaborationApproval approval);
  Stream<CollaborationEvent> watch(String runId);
  Future<void> cancel(String runId);
  Future<void> approveExecution(String runId);
  Future<CollaborationResult> result(String runId);
}

final orchestrationModuleProvider = Provider<OrchestrationModule>((ref) {
  return OrchestrationService(
    databaseFuture: ref.watch(databaseProvider.future),
    configStore: ref.watch(providerConfigStoreProvider),
  );
});

class OrchestrationService implements OrchestrationModule {
  OrchestrationService({
    required this.databaseFuture,
    required this.configStore,
    CollaborationAgentRunner? runner,
    this.budget = const CollaborationBudget(),
    TaskTemplateService? templates,
    CollaborationSynthesizer? synthesizer,
  })  : runner = runner ?? const HeadlessCollaborationAgentRunner(),
        templates = templates ?? TaskTemplateService(),
        synthesizer = synthesizer ?? CollaborationSynthesizer();

  final Future<AppDatabase> databaseFuture;
  final ProviderConfigStore configStore;
  final CollaborationAgentRunner runner;
  final CollaborationBudget budget;
  final TaskTemplateService templates;
  final CollaborationSynthesizer synthesizer;
  final Map<String, StreamController<CollaborationEvent>> _controllers = {};
  final Map<String, AgentCancellationToken> _cancellation = {};

  @override
  Future<CollaborationPlan> propose(DevelopmentTaskInput task) async {
    final now = DateTime.now().microsecondsSinceEpoch;
    final runId = 'collab-$now';
    final template = templates.forTask(task);
    final roles = _rolesFor(task.taskType);
    final maxAgents = roles.length.clamp(2, budget.maxAgents).toInt();
    final agents = roles
        .take(maxAgents)
        .map((role) => CollaborationAgentSpec(
              id: '$runId-${role.wireName}',
              role: role,
              maxRounds: 1,
              contextManifest: _contextManifest(task, template),
              allowedTools: role.allowedTools,
            ))
        .toList(growable: false);
    return CollaborationPlan(
      runId: runId,
      taskId: task.taskId,
      mode: CollaborationMode.parallel,
      agents: agents,
      budgetTokens: 4000,
      maxAgents: maxAgents,
      maxRounds: 1,
      estimatedTokens: 1800 * agents.length,
      estimatedDurationSeconds: 90,
      contextManifest: _contextManifest(task, template),
      riskLevel: 'read_only',
    );
  }

  @override
  Future<CollaborationRunSnapshot> start(
      String taskId, CollaborationApproval approval) async {
    final db = await databaseFuture;
    final task = await db.findTask(taskId);
    if (task == null) {
      throw StateError('开发任务不存在：$taskId');
    }
    final request = _decode(task.requestJson);
    final input = DevelopmentTaskInput(
      taskId: taskId,
      prompt: request['prompt']?.toString() ?? '',
      taskType: request['taskType']?.toString() ?? 'general',
      workspacePath: request['workspacePath']?.toString(),
      model: request['model']?.toString(),
    );
    final proposal = await propose(input);
    final bounded = budget.clamp(approval);
    final agents =
        proposal.agents.take(bounded.maxAgents).toList(growable: false);
    final plan = CollaborationPlan(
      runId: proposal.runId,
      taskId: taskId,
      mode: approval.mode,
      agents: agents,
      budgetTokens: bounded.maxTokens,
      maxAgents: bounded.maxAgents,
      maxRounds: bounded.maxRounds,
      estimatedTokens: proposal.estimatedTokens,
      estimatedDurationSeconds: proposal.estimatedDurationSeconds,
      contextManifest: proposal.contextManifest,
      riskLevel: proposal.riskLevel,
    );
    final now = DateTime.now();
    final run = CollaborationRun(
      id: plan.runId,
      taskId: taskId,
      mode: plan.mode.wireName,
      status: CollaborationStatus.queued.wireName,
      budgetTokens: bounded.maxTokens,
      consumedTokens: 0,
      maxAgents: agents.length,
      maxRounds: bounded.maxRounds,
      currentRound: 0,
      planJson: plan.encode(),
      resultJson: null,
      error: null,
      createdAt: now,
      updatedAt: now,
    );
    await db.saveCollaborationRun(run);
    await TaskService().updateProgress(
      db,
      taskId,
      phase: CollaborationStatus.queued.wireName,
      extra: {'collaborationRunId': plan.runId},
    );
    _emit(run.id, CollaborationRunEvent(run.id, _snapshot(run, plan: plan)));
    unawaited(_execute(run, plan, input));
    return _snapshot(run, plan: plan);
  }

  @override
  Stream<CollaborationEvent> watch(String runId) {
    final controller = _controllers.putIfAbsent(
        runId, () => StreamController<CollaborationEvent>.broadcast());
    return controller.stream;
  }

  @override
  Future<void> cancel(String runId) async {
    _cancellation.putIfAbsent(runId, AgentCancellationToken.new).cancel();
    final db = await databaseFuture;
    final run = await db.findCollaborationRun(runId);
    if (run == null || _terminal(run.status)) return;
    final cancelled = run.copyWith(
      status: CollaborationStatus.cancelled.wireName,
      updatedAt: DateTime.now(),
    );
    await db.saveCollaborationRun(cancelled);
    await TaskService().updateStatus(db, run.taskId, 'cancelled');
    _emit(runId, CollaborationRunEvent(runId, _snapshot(cancelled)));
  }

  @override
  Future<void> approveExecution(String runId) async {
    final db = await databaseFuture;
    final run = await db.findCollaborationRun(runId);
    if (run == null) throw StateError('协作运行不存在：$runId');
    if (run.status != CollaborationStatus.awaitingExecutionApproval.wireName) {
      return;
    }
    final completed = run.copyWith(
      status: CollaborationStatus.completed.wireName,
      updatedAt: DateTime.now(),
    );
    await db.saveCollaborationRun(completed);
    await TaskService().updateStatus(db, run.taskId, 'completed');
    _emit(runId, CollaborationRunEvent(runId, _snapshot(completed)));
  }

  @override
  Future<CollaborationResult> result(String runId) async {
    final db = await databaseFuture;
    final run = await db.findCollaborationRun(runId);
    if (run == null) throw StateError('协作运行不存在：$runId');
    return CollaborationResult.decode(run.resultJson);
  }

  Future<void> _execute(CollaborationRun run, CollaborationPlan plan,
      DevelopmentTaskInput input) async {
    final deadline = DateTime.now().add(budget.maxDuration);
    AppDatabase? db;
    final token = _cancellation.putIfAbsent(run.id, AgentCancellationToken.new);
    var timedOut = false;
    try {
      db = await databaseFuture;
      final config = await configStore.load();
      var current = run.copyWith(
        status: CollaborationStatus.discussing.wireName,
        currentRound: 0,
        updatedAt: DateTime.now(),
      );
      await db.saveCollaborationRun(current);
      _emit(run.id,
          CollaborationRunEvent(run.id, _snapshot(current, plan: plan)));

      var context = _contextFor(input);
      final outputs = <CollaborationAgentOutput>[];
      final slots = (plan.agents.length * plan.maxRounds) + 1;
      final perAgentBudget =
          (plan.budgetTokens ~/ slots).clamp(200, 2000).toInt();
      CollaborationAgentOutput timeoutOutput(CollaborationAgentRole role) =>
          CollaborationAgentOutput(
            role: role,
            text: '协作子 Agent 超过总时长预算，未继续执行',
            inputTokens: 0,
            outputTokens: 0,
            cachedTokens: 0,
            failed: true,
            error: 'COLLABORATION_TIMEOUT',
          );

      Future<CollaborationAgentOutput> invokeAgent(
          CollaborationAgentSpec spec, String agentContext) async {
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) {
          timedOut = true;
          token.cancel();
          return timeoutOutput(spec.role);
        }
        try {
          return await runner
              .run(
            role: spec.role,
            taskPrompt: input.prompt,
            context: agentContext,
            config: config,
            db: db!,
            workspacePath: input.workspacePath,
            maxTokens: perAgentBudget,
            cancellationToken: token,
          )
              .timeout(remaining, onTimeout: () {
            timedOut = true;
            token.cancel();
            return timeoutOutput(spec.role);
          });
        } catch (error) {
          // 单个子 Agent 出错时保留结构化失败，不能让整个协作 run 卡在 running。
          return CollaborationAgentOutput(
            role: spec.role,
            text: '协作子 Agent 执行失败：$error',
            inputTokens: 0,
            outputTokens: 0,
            cachedTokens: 0,
            failed: true,
            error: 'COLLABORATION_AGENT_ERROR',
          );
        }
      }

      for (var round = 1; round <= plan.maxRounds; round++) {
        if (token.isCancelled) return;
        if (DateTime.now().isAfter(deadline)) {
          timedOut = true;
          token.cancel();
          return;
        }
        current = current.copyWith(
          status: CollaborationStatus.discussing.wireName,
          currentRound: round,
          updatedAt: DateTime.now(),
        );
        await db.saveCollaborationRun(current);
        _emit(run.id,
            CollaborationRunEvent(run.id, _snapshot(current, plan: plan)));
        await TaskService().updateProgress(db, input.taskId,
            phase: CollaborationStatus.discussing.wireName,
            extra: {'collaborationRunId': run.id, 'round': round});

        final roundOutputs = <CollaborationAgentOutput>[];
        final pending =
            <Future<(String, CollaborationAgentRun, CollaborationAgentOutput)>
                Function()>[];
        // 先在主线程预留每个并发槽位的最大预算，再创建 Future。若只在
        // Future 内读取 current.consumedTokens，多个并行 Agent 会同时看到旧值
        // 并共同越过上限。
        var reservedTokens = current.consumedTokens;
        for (final spec in plan.agents) {
          if (token.isCancelled) break;
          final agentRunId = '${run.id}:${spec.id}:$round';
          final existing = await _findAgentRun(db, run.id, agentRunId);
          if (existing?.status == 'completed') {
            final stored = _outputFromStored(spec.role, existing!);
            outputs.add(stored);
            roundOutputs.add(stored);
            continue;
          }
          final agentRun = CollaborationAgentRun(
            id: agentRunId,
            collaborationRunId: run.id,
            role: spec.role.wireName,
            agentProfileId: null,
            status: 'running',
            round: round,
            contextManifest: jsonEncode(spec.contextManifest),
            allowedTools: jsonEncode(spec.allowedTools),
            inputDigest: HeadlessCollaborationAgentRunner.digest(
                '$context\n${input.prompt}'),
            outputSummary: null,
            failureReason: null,
            inputTokens: 0,
            outputTokens: 0,
            cachedTokens: 0,
            startedAt: DateTime.now(),
            finishedAt: null,
          );
          await db.saveCollaborationAgentRun(agentRun);
          _emit(
              run.id,
              CollaborationAgentEvent(
                  run.id, agentRunId, spec.role, 'running', null));
          final canReserve = budget.canStart(
                consumedTokens: reservedTokens,
                requestedTokens: perAgentBudget,
              ) &&
              reservedTokens + perAgentBudget <= plan.budgetTokens;
          if (canReserve) reservedTokens += perAgentBudget;
          pending.add(() async {
            if (!canReserve) {
              final skipped = CollaborationAgentOutput(
                role: spec.role,
                text: '协作预算已耗尽，未启动该只读 Agent',
                inputTokens: 0,
                outputTokens: 0,
                cachedTokens: 0,
                failed: true,
                error: 'COLLABORATION_BUDGET_EXHAUSTED',
              );
              return (agentRunId, agentRun, skipped);
            }
            final output = await invokeAgent(spec, context);
            return (agentRunId, agentRun, output);
          });
        }

        final completedRuns =
            <(String, CollaborationAgentRun, CollaborationAgentOutput)>[];
        if (plan.mode == CollaborationMode.parallel) {
          completedRuns.addAll(await Future.wait(pending.map((run) => run())));
        } else {
          for (final run in pending) {
            completedRuns.add(await run());
          }
        }
        for (final item in completedRuns) {
          final agentRunId = item.$1;
          final agentRun = item.$2;
          final output = item.$3;
          outputs.add(output);
          roundOutputs.add(output);
          final completed = agentRun.copyWith(
            status: output.failed ? 'failed' : 'completed',
            outputSummary: Value(_truncate(output.text, 12000)),
            failureReason: Value(output.error),
            inputTokens: output.inputTokens,
            outputTokens: output.outputTokens,
            cachedTokens: output.cachedTokens,
            finishedAt: Value(DateTime.now()),
          );
          await db.saveCollaborationAgentRun(completed);
          await db.saveCollaborationMessage(CollaborationMessage(
            id: '$agentRunId:message',
            collaborationRunId: run.id,
            senderAgentRunId: agentRunId,
            recipientRole: 'synthesizer',
            round: round,
            contentDigest: HeadlessCollaborationAgentRunner.digest(output.text),
            content: _truncate(output.text, 12000),
            artifactRefs: '[]',
            createdAt: DateTime.now(),
          ));
          current = current.copyWith(
            consumedTokens: current.consumedTokens + output.totalTokens,
            updatedAt: DateTime.now(),
          );
          await db.saveCollaborationRun(current);
          _emit(
              run.id,
              CollaborationAgentEvent(
                  run.id,
                  agentRunId,
                  CollaborationAgentRoleX.parse(item.$2.role),
                  completed.status,
                  _truncate(output.text, 4000)));
        }
        if (roundOutputs.isNotEmpty && round < plan.maxRounds) {
          context =
              '$context\n\n上一轮结构化摘要：\n${_truncate(roundOutputs.map((item) => '${item.role.wireName}: ${item.text}').join('\n'), 16000)}';
        }
      }
      if (timedOut || DateTime.now().isAfter(deadline)) {
        timedOut = true;
        token.cancel();
        return;
      }
      if (token.isCancelled) return;
      if (outputs.isEmpty || outputs.every((output) => output.failed)) {
        throw StateError('COLLABORATION_ALL_AGENTS_FAILED');
      }
      current = current.copyWith(
        status: CollaborationStatus.synthesizing.wireName,
        updatedAt: DateTime.now(),
      );
      await db.saveCollaborationRun(current);
      _emit(run.id,
          CollaborationRunEvent(run.id, _snapshot(current, plan: plan)));
      final result = synthesizer.synthesize(
        reviewerRole: CollaborationAgentRole.reviewer,
        outputs: outputs,
      );
      await db.saveCollaborationArtifact(CollaborationArtifact(
        id: '${run.id}:synthesis',
        collaborationRunId: run.id,
        producerAgentRunId: '${run.id}:synthesizer',
        type: 'synthesis',
        payloadJson: result.encode(),
        evidenceRefs: jsonEncode(result.evidence),
        confidence: result.confidence,
        createdAt: DateTime.now(),
      ));
      await db.saveCollaborationMessage(CollaborationMessage(
        id: '${run.id}:synthesis-message',
        collaborationRunId: run.id,
        senderAgentRunId: '${run.id}:synthesizer',
        recipientRole: null,
        round: 1,
        contentDigest: HeadlessCollaborationAgentRunner.digest(result.summary),
        content: _truncate(result.summary, 12000),
        artifactRefs: jsonEncode(['${run.id}:synthesis']),
        createdAt: DateTime.now(),
      ));
      final finished = current.copyWith(
        status: CollaborationStatus.awaitingExecutionApproval.wireName,
        resultJson: Value(result.encode()),
        updatedAt: DateTime.now(),
      );
      await db.saveCollaborationRun(finished);
      await TaskService().updateStatus(db, input.taskId, 'waiting_approval');
      await TaskService().updateProgress(db, input.taskId,
          phase: CollaborationStatus.awaitingExecutionApproval.wireName,
          summary: result.summary,
          structuredResult: StructuredTaskResult(
            summary: result.summary,
            findings:
                result.findings.map((finding) => finding.toJson()).toList(),
            actions: result.actions,
            evidence: result.evidence,
            nextSteps: result.nextSteps,
            risks: result.risks,
          ),
          extra: {
            'collaborationRunId': run.id,
            'confidence': result.confidence
          });
      _emit(
          run.id,
          CollaborationRunEvent(
              run.id, _snapshot(finished, plan: plan, result: result)));
    } catch (error) {
      final database = db;
      if (database != null) {
        await _markFailed(
          database,
          run,
          plan,
          input.taskId,
          '协作执行异常：$error',
        );
      }
    } finally {
      final database = db;
      if (timedOut && database != null) {
        await _markFailed(
          database,
          run,
          plan,
          input.taskId,
          '协作执行超过 ${budget.maxDuration.inSeconds} 秒时长预算',
        );
      }
      _cancellation.remove(run.id);
    }
  }

  Future<void> _markFailed(
    AppDatabase db,
    CollaborationRun original,
    CollaborationPlan plan,
    String taskId,
    String message,
  ) async {
    try {
      final current = await db.findCollaborationRun(original.id);
      if (current == null || _terminal(current.status)) return;
      final failed = current.copyWith(
        status: CollaborationStatus.failed.wireName,
        error: Value(message),
        updatedAt: DateTime.now(),
      );
      await db.saveCollaborationRun(failed);
      await TaskService().updateStatus(db, taskId, 'failed');
      _emit(original.id,
          CollaborationRunEvent(original.id, _snapshot(failed, plan: plan)));
      _emit(original.id, CollaborationErrorEvent(original.id, message));
    } catch (_) {
      // 状态收敛本身也可能遇到数据库错误，不能把异常继续抛回后台任务。
    }
  }

  Future<CollaborationAgentRun?> _findAgentRun(
      AppDatabase db, String runId, String id) async {
    final rows = await db.agentRunsForCollaboration(runId);
    for (final row in rows) {
      if (row.id == id) return row;
    }
    return null;
  }

  CollaborationAgentOutput _outputFromStored(
      CollaborationAgentRole role, CollaborationAgentRun row) {
    return CollaborationAgentOutput(
      role: role,
      text: row.outputSummary ?? '',
      inputTokens: row.inputTokens,
      outputTokens: row.outputTokens,
      cachedTokens: row.cachedTokens,
      failed: row.status != 'completed',
      error: row.failureReason,
    );
  }

  List<CollaborationAgentRole> _rolesFor(String taskType) {
    switch (taskType) {
      case 'code_review':
        return const [
          CollaborationAgentRole.analyzer,
          CollaborationAgentRole.reviewer,
          CollaborationAgentRole.tester,
        ];
      case 'bug_fix':
        return const [
          CollaborationAgentRole.planner,
          CollaborationAgentRole.analyzer,
          CollaborationAgentRole.tester,
          CollaborationAgentRole.reviewer,
        ];
      case 'release_check':
        return const [
          CollaborationAgentRole.planner,
          CollaborationAgentRole.tester,
          CollaborationAgentRole.reviewer,
        ];
      default:
        return const [
          CollaborationAgentRole.planner,
          CollaborationAgentRole.analyzer,
          CollaborationAgentRole.reviewer,
        ];
    }
  }

  List<String> _contextManifest(
          DevelopmentTaskInput task, TaskTemplate template) =>
      [
        'task.prompt',
        'task.type:${task.taskType}',
        if (task.workspacePath != null) 'workspace.root',
        ...template.requiredInputs.map((item) => 'input:$item'),
      ];

  String _contextFor(DevelopmentTaskInput task) {
    final workspace = task.workspacePath?.trim();
    return [
      '任务类型：${task.taskType}',
      if (workspace != null && workspace.isNotEmpty) '工作区：$workspace',
      '协作约束：只读、最小上下文、不得产生外部副作用。',
    ].join('\n');
  }

  CollaborationRunSnapshot _snapshot(CollaborationRun run,
      {CollaborationPlan? plan, CollaborationResult? result}) {
    return CollaborationRunSnapshot(
      id: run.id,
      taskId: run.taskId,
      mode: CollaborationModeX.parse(run.mode),
      status: CollaborationStatusX.parse(run.status),
      budgetTokens: run.budgetTokens,
      consumedTokens: run.consumedTokens,
      maxAgents: run.maxAgents,
      maxRounds: run.maxRounds,
      currentRound: run.currentRound,
      createdAt: run.createdAt,
      updatedAt: run.updatedAt,
      plan: plan ?? CollaborationPlan.decode(run.planJson),
      result: result ?? CollaborationResult.decode(run.resultJson),
      error: run.error,
    );
  }

  bool _terminal(String status) => {
        CollaborationStatus.completed.wireName,
        CollaborationStatus.failed.wireName,
        CollaborationStatus.cancelled.wireName,
      }.contains(status);

  void _emit(String runId, CollaborationEvent event) {
    final controller = _controllers.putIfAbsent(
        runId, () => StreamController<CollaborationEvent>.broadcast());
    if (!controller.isClosed) controller.add(event);
  }

  Map<String, dynamic> _decode(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  String _truncate(String value, int limit) =>
      value.length <= limit ? value : '${value.substring(0, limit)}…';
}
