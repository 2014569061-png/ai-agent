import 'dart:convert';

import 'package:dio/dio.dart' show CancelToken;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/agent_executor.dart';
import 'package:mobile_agent/application/collaboration_synthesizer.dart';
import 'package:mobile_agent/application/orchestration_module.dart';
import 'package:mobile_agent/application/collaboration_budget.dart';
import 'package:mobile_agent/application/task_service.dart';
import 'package:mobile_agent/domain/collaboration_models.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/application/collaboration_agent_runner.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/providers/llm_provider.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config_store.dart';
import 'package:mobile_agent/infrastructure/tools/tool_registry.dart';

class _FakeConfigStore extends ProviderConfigStore {
  @override
  Future<ProviderConfig> load() async => const ProviderConfig(
        baseUrl: 'http://localhost',
        model: 'demo-model',
        apiKey: '',
      );
}

class _FakeRunner implements CollaborationAgentRunner {
  @override
  Future<CollaborationAgentOutput> run({
    required CollaborationAgentRole role,
    required String taskPrompt,
    required String context,
    required ProviderConfig config,
    required AppDatabase db,
    String? workspacePath,
    required int maxTokens,
    required AgentCancellationToken cancellationToken,
  }) async {
    final json = jsonEncode({
      'summary': '${role.wireName} 已完成分析',
      'findings': [
        {
          'title': '${role.wireName} 发现',
          'detail': '有证据支持的测试发现',
          'severity': 'info',
          'evidence': ['task.prompt'],
          'recommendation': '补充验证',
        }
      ],
      'actions': ['执行验证'],
      'evidence': ['task.prompt'],
      'nextSteps': ['等待主 Agent 审批'],
      'risks': [],
      'confidence': 0.8,
    });
    return CollaborationAgentOutput(
      role: role,
      text: json,
      inputTokens: 100,
      outputTokens: 80,
      cachedTokens: 20,
    );
  }
}

class _ThrowingRunner implements CollaborationAgentRunner {
  @override
  Future<CollaborationAgentOutput> run({
    required CollaborationAgentRole role,
    required String taskPrompt,
    required String context,
    required ProviderConfig config,
    required AppDatabase db,
    String? workspacePath,
    required int maxTokens,
    required AgentCancellationToken cancellationToken,
  }) async {
    throw StateError('runner exploded');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('structured collaboration models preserve plan and result data', () {
    final plan = const CollaborationPlan(
      runId: 'run-1',
      taskId: 'task-1',
      mode: CollaborationMode.parallel,
      agents: [
        CollaborationAgentSpec(
          id: 'a1',
          role: CollaborationAgentRole.analyzer,
          maxRounds: 1,
          allowedTools: ['read_file'],
        ),
      ],
      budgetTokens: 4000,
      maxAgents: 1,
      maxRounds: 1,
      estimatedTokens: 1000,
      estimatedDurationSeconds: 30,
      contextManifest: ['task.prompt'],
      riskLevel: 'read_only',
    );
    final decoded = CollaborationPlan.decode(plan.encode());
    expect(decoded.runId, 'run-1');
    expect(decoded.agents.single.role, CollaborationAgentRole.analyzer);
    expect(decoded.agents.single.allowedTools, ['read_file']);
  });

  test('collaboration budget blocks an over-limit child start', () {
    const budget = CollaborationBudget(maxTokens: 100);
    expect(budget.canStart(consumedTokens: 90, requestedTokens: 10), isTrue);
    expect(budget.canStart(consumedTokens: 90, requestedTokens: 11), isFalse);
  });

  test('sub agent tool result feeds back before final conclusion', () async {
    final provider = _ChildToolProvider();
    final executor = AgentExecutor(
      provider: provider,
      tools: ToolRegistry()..register(const _ChildReadFileTool()),
    );
    final output = StringBuffer();
    await for (final event in executor.run(
      history: [
        ChatMessage(
          role: MessageRole.user,
          parts: [const MessagePart.text('请审查文件')],
        ),
      ],
      model: 'demo-model',
      maxSteps: 3,
    )) {
      if (event is TextEvent) output.write(event.text);
    }

    expect(provider.sawToolResult, isTrue);
    expect(output.toString(), contains('结论：文件内容正常'));
  });

  test('synthesizer merges findings and reports malformed outputs', () {
    const good = CollaborationAgentOutput(
      role: CollaborationAgentRole.analyzer,
      text:
          '{"summary":"ok","findings":[{"title":"A","detail":"D"}],"actions":["X"],"confidence":0.8}',
      inputTokens: 10,
      outputTokens: 10,
      cachedTokens: 0,
    );
    const bad = CollaborationAgentOutput(
      role: CollaborationAgentRole.reviewer,
      text: 'not json',
      inputTokens: 10,
      outputTokens: 10,
      cachedTokens: 0,
    );
    final result = CollaborationSynthesizer().synthesize(
      reviewerRole: CollaborationAgentRole.reviewer,
      outputs: [good, bad],
    );
    expect(result.findings, hasLength(1));
    expect(result.actions, contains('X'));
    expect(result.disagreements, isNotEmpty);
    expect(result.confidence, 0.8);
  });

  test('orchestration persists role runs, budget usage and synthesis',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final task = await TaskService().create(
      db: db,
      conversationId: 'conversation-1',
      type: 'development:bug_fix',
      requestJson: jsonEncode({
        'prompt': '定位登录崩溃',
        'taskType': 'bug_fix',
        'workspacePath': '',
      }),
    );
    final service = OrchestrationService(
      databaseFuture: Future.value(db),
      configStore: _FakeConfigStore(),
      runner: _FakeRunner(),
    );
    final plan = await service.propose(DevelopmentTaskInput(
      taskId: task.id,
      prompt: '定位登录崩溃',
      taskType: 'bug_fix',
    ));
    expect(plan.agents.length, 4);
    expect(plan.riskLevel, 'read_only');

    final run = await service.start(
      task.id,
      const CollaborationApproval(
        budgetTokens: 4000,
        maxAgents: 4,
        maxRounds: 1,
        mode: CollaborationMode.parallel,
      ),
    );
    expect(run.status, CollaborationStatus.queued);
    CollaborationRun? saved;
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      saved = await db.findCollaborationRun(run.id);
      if (saved?.status ==
          CollaborationStatus.awaitingExecutionApproval.wireName) {
        break;
      }
    }
    expect(
        saved?.status, CollaborationStatus.awaitingExecutionApproval.wireName);
    expect(saved?.consumedTokens, greaterThan(0));
    expect(await db.agentRunsForCollaboration(run.id), hasLength(4));
    final result = await service.result(run.id);
    expect(result.summary, contains('汇总'));
    expect(result.findings, isNotEmpty);
  });

  test('orchestration converges to failed when every child agent throws',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final task = await TaskService().create(
      db: db,
      conversationId: 'conversation-failure',
      type: 'development:bug_fix',
      requestJson: jsonEncode({
        'prompt': 'trigger child failure',
        'taskType': 'bug_fix',
      }),
    );
    final service = OrchestrationService(
      databaseFuture: Future.value(db),
      configStore: _FakeConfigStore(),
      runner: _ThrowingRunner(),
      budget: const CollaborationBudget(maxDuration: Duration(seconds: 1)),
    );
    final run = await service.start(
      task.id,
      const CollaborationApproval(
        budgetTokens: 4000,
        maxAgents: 4,
        maxRounds: 1,
        mode: CollaborationMode.parallel,
      ),
    );
    CollaborationRun? saved;
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      saved = await db.findCollaborationRun(run.id);
      if (saved?.status == CollaborationStatus.failed.wireName) break;
    }
    expect(saved?.status, CollaborationStatus.failed.wireName);
    expect(saved?.error, contains('COLLABORATION_ALL_AGENTS_FAILED'));
  });
}

class _ChildReadFileTool implements AgentTool {
  const _ChildReadFileTool();

  @override
  final manifest = const UnifiedTool(
    name: 'read_file',
    description: 'read only for cross-check',
    parametersSchema: {'type': 'object'},
    risk: ToolRisk.safe,
  );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async =>
      ToolResult.success(
        message: 'fake file content',
        data: {'text': 'fake content'},
      );
}

class _ChildToolProvider implements LlmProvider {
  final requests = <UnifiedRequest>[];
  bool sawToolResult = false;

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    requests.add(request);
    final hasToolResult =
        request.messages.any((message) => message.role == MessageRole.tool);
    if (hasToolResult) {
      final encoded = request.messages
          .where((message) => message.role == MessageRole.tool)
          .map((message) => message.text)
          .join('\n');
      if (encoded.contains('fake content')) sawToolResult = true;
      yield const TextDeltaEvent('结论：文件内容正常');
      yield const CompletedEvent(stopReason: StopReason.endOfTurn);
      return;
    }
    yield const ToolCallEvent(
      ToolCall(
        id: 'read-1',
        name: 'read_file',
        arguments: {'path': 'lib/main.dart'},
      ),
    );
    yield const CompletedEvent(stopReason: StopReason.toolUse);
  }
}
