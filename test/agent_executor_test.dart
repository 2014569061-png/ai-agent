import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:mobile_agent/application/agent_executor.dart';
import 'package:mobile_agent/application/context_window.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/infrastructure/providers/llm_provider.dart';
import 'package:mobile_agent/infrastructure/providers/openai_compatible_provider.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/infrastructure/files/document_extractor.dart';
import 'package:mobile_agent/infrastructure/tools/core_tools.dart';
import 'package:mobile_agent/infrastructure/tools/plan_tool.dart';
import 'package:mobile_agent/infrastructure/tools/tool_registry.dart';

void main() {
  test('demo provider completes an agent run with streamed text', () async {
    final registry = ToolRegistry()..register(CalculatorTool());
    final executor = AgentExecutor(
      provider: DemoProvider(),
      tools: registry,
    );
    final output = StringBuffer();

    await for (final event in executor.run(
      history: [
        ChatMessage(
          role: MessageRole.user,
          parts: [const MessagePart.text('你好')],
        ),
      ],
      model: 'demo-model',
    )) {
      if (event is TextEvent) output.write(event.text);
    }

    expect(output.toString(), contains('演示响应'));
  });

  test('requires approval before a risky tool executes', () async {
    final registry = ToolRegistry()..register(_RiskyTool());
    final executor =
        AgentExecutor(provider: _ToolRequestProvider(), tools: registry);
    var asked = false;
    final statuses = <RunStatus>[];
    ToolResult? rejected;
    await for (final event in executor.run(
      history: [
        ChatMessage(
            role: MessageRole.user, parts: [const MessagePart.text('run')])
      ],
      model: 'test',
      approveTool: (call, risk, sensitive) async {
        asked = true;
        return ToolApproval.reject;
      },
    )) {
      if (event is AgentStatusEvent) statuses.add(event.status);
      if (event is ToolResultEvent) rejected = event.result;
    }
    expect(asked, isTrue);
    expect(statuses, isNot(contains(RunStatus.cancelled)));
    expect(rejected?.code, ToolCodes.approvalRejected);
    expect(rejected?.ok, isFalse);
  });

  test('sensitive tool always requires approval even in full access + trusted',
      () async {
    final registry = ToolRegistry()..register(_SensitiveTool());
    final executor =
        AgentExecutor(provider: _SensitiveToolProvider(), tools: registry);
    var asked = false;
    await for (final event in executor.run(
      history: [
        ChatMessage(
            role: MessageRole.user, parts: [const MessagePart.text('run')])
      ],
      model: 'test',
      approvalMode: ApprovalMode.fullAccess,
      isToolTrusted: (name, risk) => true,
      approveTool: (call, risk, sensitive) async {
        asked = true;
        expect(sensitive, isTrue);
        return ToolApproval.reject;
      },
    )) {
      if (event is ApprovalRequiredEvent) {
        expect(event.risk, ToolRisk.dangerous);
      }
    }
    // fullAccess + 全局信任都不应绕过敏感工具的逐次审批。
    expect(asked, isTrue);
  });

  test('continues execution after an approved plan', () async {
    final registry = ToolRegistry()
      ..register(ManagePlanTool(onPlanUpdated: (_) async {}))
      ..register(CalculatorTool());
    final provider = _ApprovedPlanProvider();
    var approved = false;

    await for (final _ in AgentExecutor(
      provider: provider,
      tools: registry,
    ).run(
      history: [
        ChatMessage(
            role: MessageRole.user, parts: [const MessagePart.text('执行')])
      ],
      model: 'test',
      confirmPlan: (calls, text) async {
        approved = calls.any((call) => call.name == 'manage_plan');
        return true;
      },
    )) {}

    expect(approved, isTrue);
    expect(provider.continuationSeen, isTrue);
    expect(provider.requests.length, 3);
  });

  test('serializes image parts as OpenAI multimodal content', () {
    final provider = OpenAiCompatibleProvider(
      config: const ProviderConfig(
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-4o-mini',
        apiKey: 'test',
      ),
    );
    final payload = provider.toProviderMessage(
      ChatMessage(
        role: MessageRole.user,
        parts: const [
          MessagePart.text('看这张图'),
          MessagePart.image('data:image/png;base64,AAAA',
              mimeType: 'image/png'),
        ],
      ),
    );

    expect(payload['role'], 'user');
    final content = payload['content'] as List<dynamic>;
    expect(content, hasLength(2));
    expect(content[0], {'type': 'text', 'text': '看这张图'});
    expect(content[1], {
      'type': 'image_url',
      'image_url': {'url': 'data:image/png;base64,AAAA'},
    });
  });

  test('serializes assistant tool calls for the next agent turn', () {
    final provider = OpenAiCompatibleProvider(
      config: const ProviderConfig(
          baseUrl: 'https://example.com/v1', model: 'test', apiKey: 'key'),
    );
    final payload = provider.toProviderMessage(ChatMessage(
      role: MessageRole.assistant,
      parts: const [],
      toolCalls: [
        const ToolCall(
            id: 'call-1', name: 'calculator', arguments: {'expression': '2+2'})
      ],
    ));
    expect(payload['content'], isNull);
    expect(payload['tool_calls'], [
      {
        'id': 'call-1',
        'type': 'function',
        'function': {'name': 'calculator', 'arguments': '{"expression":"2+2"}'},
      },
    ]);
  });

  test('extracts UTF-8 text documents through the shared extractor', () {
    const extractor = DocumentExtractor();
    final text = extractor.extractText(
      fileName: 'notes.md',
      bytes: Uint8List.fromList([35, 32, 72, 105]),
    );
    expect(text, '# Hi');
  });

  test('damaged PDF attachment returns null instead of throwing', () {
    const extractor = DocumentExtractor();
    // 随机字节不是合法 PDF：构造器应被兜底，返回 null 而非抛异常。
    final result = extractor.extractText(
      fileName: 'broken.pdf',
      bytes: Uint8List.fromList(List.generate(64, (i) => i)),
    );
    expect(result, isNull);
  });

  test('executes multiple tool calls and preserves assistant call context',
      () async {
    final registry = ToolRegistry()..register(CalculatorTool());
    final provider = _MultiToolProvider();
    final executor = AgentExecutor(provider: provider, tools: registry);
    var requested = 0;
    await for (final event in executor.run(
      history: [
        ChatMessage(
            role: MessageRole.user,
            parts: [const MessagePart.text('calculate')])
      ],
      model: 'test',
    )) {
      if (event is ToolRequestedEvent) requested++;
    }
    expect(requested, 2);
    expect(provider.requests, hasLength(2));
    expect(
        provider.requests[1].messages
            .any((message) => message.toolCalls.length == 2),
        isTrue);
  });

  test('rejects tool calls attached to an output-limited model turn', () async {
    final tool = _CountingTool();
    final registry = ToolRegistry()..register(tool);
    final provider = _OutputLimitProvider();
    final results = <ToolResult>[];

    await for (final event in AgentExecutor(
      provider: provider,
      tools: registry,
    ).run(
      history: [
        ChatMessage(
            role: MessageRole.user, parts: [const MessagePart.text('run')])
      ],
      model: 'test',
      maxSteps: 2,
    )) {
      if (event is ToolResultEvent) results.add(event.result);
    }

    expect(tool.executions, 0);
    expect(results, hasLength(1));
    expect(results.single.code, ToolCodes.truncatedToolCall);
    expect(results.single.effect, ToolEffect.none);
    final followUp = provider.requests.last;
    final assistantCalls = followUp.messages
        .where((message) => message.role == MessageRole.assistant)
        .expand((message) => message.toolCalls)
        .toList();
    final toolResults = followUp.messages
        .where((message) => message.role == MessageRole.tool)
        .toList();
    expect(assistantCalls.map((call) => call.id), contains('partial-1'));
    expect(toolResults.map((message) => message.toolCallId),
        contains('partial-1'));
  });

  test('does not execute an explicitly truncated tool argument', () async {
    final tool = _CountingTool();
    final registry = ToolRegistry()..register(tool);
    final results = <ToolResult>[];
    await for (final event in AgentExecutor(
      provider: _TruncatedArgumentProvider(),
      tools: registry,
    ).run(
      history: [
        ChatMessage(
            role: MessageRole.user, parts: [const MessagePart.text('run')])
      ],
      model: 'test',
      maxSteps: 2,
    )) {
      if (event is ToolResultEvent) results.add(event.result);
    }
    expect(tool.executions, 0);
    expect(results.single.code, ToolCodes.truncatedToolCall);
    expect(results.single.effect, ToolEffect.none);
  });

  test('core tools return deterministic safe results', () async {
    final time = await GetTimeTool().execute({});
    expect(time.ok, isTrue);
    expect(time.data?['text'], isNotEmpty);
    final query = await JsonQueryTool()
        .execute({'json': '{"user":{"name":"Nexus"}}', 'path': 'user.name'});
    expect(query.ok, isTrue);
    expect(query.data?['text'], '"Nexus"');
  });

  test('http_request tool rejects cloud metadata and link-local addresses',
      () async {
    final tool = HttpRequestTool();
    final metadata =
        await tool.execute({'url': 'http://169.254.169.254/latest/meta-data/'});
    expect(metadata.ok, isFalse);
    expect(metadata.code, ToolCodes.permissionRequired);
    expect(metadata.message, contains('安全策略拒绝'));
    final internal =
        await tool.execute({'url': 'https://metadata.google.internal/'});
    expect(internal.ok, isFalse);
    expect(internal.code, ToolCodes.permissionRequired);
    expect(internal.message, contains('安全策略拒绝'));
    final linkLocal = await tool.execute({'url': 'http://169.254.0.1/'});
    expect(linkLocal.ok, isFalse);
    expect(linkLocal.code, ToolCodes.permissionRequired);
    expect(linkLocal.message, contains('安全策略拒绝'));
    final invalid = await tool.execute({'url': 'ftp://example.com/x'});
    expect(invalid.ok, isFalse);
    expect(invalid.code, ToolCodes.invalidArguments);
    expect(invalid.message, contains('URL 无效'));
  });

  test('forwards temperature, maxTokens and topP into the provider request',
      () async {
    final registry = ToolRegistry()..register(CalculatorTool());
    final provider = _RecordingProvider();
    final executor = AgentExecutor(provider: provider, tools: registry);
    await for (final _ in executor.run(
      history: [
        ChatMessage(
            role: MessageRole.user, parts: [const MessagePart.text('hi')])
      ],
      model: 'test',
      temperature: 0.3,
      maxTokens: 512,
      topP: 0.8,
    )) {}
    final request = provider.lastRequest!;
    expect(request.temperature, 0.3);
    expect(request.maxTokens, 512);
    expect(request.topP, 0.8);
  });

  test('tool execution failure yields a failed result without throwing',
      () async {
    final registry = ToolRegistry()..register(_ExplodingTool());
    final provider = _ToolThenTextProvider();
    final executor = AgentExecutor(provider: provider, tools: registry);
    ToolResult? toolResult;
    var requested = 0;
    await for (final event in executor.run(
      history: [
        ChatMessage(
            role: MessageRole.user, parts: [const MessagePart.text('run')])
      ],
      model: 'test',
    )) {
      if (event is ToolResultEvent) toolResult = event.result;
      if (event is ToolRequestedEvent) requested++;
    }
    expect(requested, 1);
    expect(toolResult?.ok, isFalse);
    expect(toolResult?.code, 'TOOL_ERROR');
    expect(toolResult?.effect, ToolEffect.unknown);
  });

  test('accumulates token usage reported by the provider', () async {
    final registry = ToolRegistry()..register(CalculatorTool());
    final executor = AgentExecutor(provider: _UsageProvider(), tools: registry);
    var promptTokens = 0;
    var completionTokens = 0;
    await for (final event in executor.run(
      history: [
        ChatMessage(
            role: MessageRole.user, parts: [const MessagePart.text('hi')])
      ],
      model: 'test',
    )) {
      if (event is AgentUsageEvent) {
        promptTokens = event.promptTokens;
        completionTokens = event.completionTokens;
      }
    }
    expect(promptTokens, 100);
    expect(completionTokens, 50);
  });

  test('drops older turns once the context budget is exceeded', () async {
    final registry = ToolRegistry()..register(CalculatorTool());
    final provider = _RecordingProvider();
    final executor = AgentExecutor(provider: provider, tools: registry);
    await for (final _ in executor.run(
      history: [
        ChatMessage(role: MessageRole.user, parts: [
          const MessagePart.text('old message that should be dropped')
        ]),
        ChatMessage(
            role: MessageRole.user, parts: [const MessagePart.text('new')]),
      ],
      model: 'test',
      contextBudgetTokens: 12,
    )) {}
    final sent = provider.lastRequest!.messages;
    expect(
        sent.any((m) =>
            m.role == MessageRole.user &&
            m.text == 'old message that should be dropped'),
        isFalse);
    expect(sent.any((m) => m.text == 'new'), isTrue);
  });

  test('retries a failed request when nothing has been emitted yet', () async {
    final registry = ToolRegistry()..register(CalculatorTool());
    final provider = _FlakyErrorProvider();
    final executor = AgentExecutor(provider: provider, tools: registry);
    final output = StringBuffer();
    await for (final event in executor.run(
      history: [
        ChatMessage(
            role: MessageRole.user, parts: [const MessagePart.text('hi')])
      ],
      model: 'test',
      maxRetries: 2,
      retryBackoff: const Duration(milliseconds: 5),
    )) {
      if (event is TextEvent) output.write(event.text);
    }
    expect(output.toString(), '恢复成功');
    expect(provider.calls, 2);
  });

  test('gives up after exhausting maxRetries', () async {
    final registry = ToolRegistry()..register(CalculatorTool());
    final provider = _FlakyErrorProvider(alwaysFail: true);
    final executor = AgentExecutor(provider: provider, tools: registry);
    var error = '';
    await for (final event in executor.run(
      history: [
        ChatMessage(
            role: MessageRole.user, parts: [const MessagePart.text('hi')])
      ],
      model: 'test',
      maxRetries: 2,
      retryBackoff: const Duration(milliseconds: 5),
    )) {
      if (event is AgentErrorEvent) error = event.message;
    }
    expect(error, contains('持续失败'));
    expect(provider.calls, 3);
  });

  test('does not retry after partial content has been streamed', () async {
    final registry = ToolRegistry()..register(CalculatorTool());
    final provider = _PartialThenErrorProvider();
    final executor = AgentExecutor(provider: provider, tools: registry);
    final output = StringBuffer();
    var error = '';
    await for (final event in executor.run(
      history: [
        ChatMessage(
            role: MessageRole.user, parts: [const MessagePart.text('hi')])
      ],
      model: 'test',
      maxRetries: 2,
      retryBackoff: const Duration(milliseconds: 5),
    )) {
      if (event is TextEvent) output.write(event.text);
      if (event is AgentErrorEvent) error = event.message;
    }
    expect(provider.calls, 1);
    expect(output.toString(), '部分');
    expect(error, contains('上游挂了'));
  });

  test('reaching maxSteps yields a recoverable paused state, not an error',
      () async {
    final registry = ToolRegistry()..register(CalculatorTool());
    final executor = AgentExecutor(
      provider: _ToolLoopProvider(),
      tools: registry,
    );
    final statuses = <RunStatus>[];
    AgentBudgetExhaustedEvent? budget;
    var errors = 0;
    await for (final event in executor.run(
      history: [
        ChatMessage(
            role: MessageRole.user, parts: [const MessagePart.text('loop')])
      ],
      model: 'test',
      maxSteps: 2,
    )) {
      if (event is AgentStatusEvent) statuses.add(event.status);
      if (event is AgentBudgetExhaustedEvent) budget = event;
      if (event is AgentErrorEvent) errors++;
    }
    expect(errors, 0);
    expect(statuses, contains(RunStatus.paused));
    expect(budget, isNotNull);
    final budgetEvent = budget!;
    expect(budgetEvent.maxSteps, 2);
    // 续跑上下文应携带用户消息与工具结果，供从断点续跑。
    expect(budgetEvent.context.any((m) => m.role == MessageRole.user), isTrue);
    expect(budgetEvent.context.any((m) => m.role == MessageRole.tool), isTrue);
  });

  test('resuming from a paused run carries the saved context forward',
      () async {
    final registry = ToolRegistry()..register(CalculatorTool());
    AgentBudgetExhaustedEvent? budget;
    await for (final event in AgentExecutor(
      provider: _ToolLoopProvider(),
      tools: registry,
    ).run(
      history: [
        ChatMessage(
            role: MessageRole.user, parts: [const MessagePart.text('loop')])
      ],
      model: 'test',
      maxSteps: 1,
    )) {
      if (event is AgentBudgetExhaustedEvent) budget = event;
    }
    expect(budget, isNotNull);

    final resumeProvider = _ResumeVerifyingProvider();
    await for (final _ in AgentExecutor(
      provider: resumeProvider,
      tools: registry,
    ).run(
      history: budget!.context,
      model: 'test',
      maxSteps: 2,
    )) {}
    // 续跑传入暂停时保存的上下文作为 history，模型直接看到此前的工具结果，
    // 不需要重新执行工具。
    final sent = resumeProvider.requests.single.messages;
    expect(sent.any((m) => m.role == MessageRole.tool), isTrue);
    expect(sent.any((m) => m.role == MessageRole.user), isTrue);
  });

  test('registerPair keeps an independent executor through projection', () {
    final executor = _StandaloneExecutor();
    final registry = ToolRegistry()
      ..registerPair(
        spec: const ToolSpec(
          name: 'standalone',
          description: '独立执行器',
          parametersSchema: {
            'type': 'object',
            'properties': {
              'value': {
                'type': 'string',
                'enum': ['ok']
              },
            },
            'required': ['value'],
          },
          risk: ToolRisk.safe,
        ),
        executor: executor,
      );

    expect(registry.find('standalone'), isNull);
    expect(registry.findRegistration('standalone')?.executor, same(executor));

    final projected = registry.project(const ToolCapabilitySnapshot());
    expect(projected.findRegistration('standalone')?.executor, same(executor));
    expect(
      projected.findRegistration('standalone')?.spec.parametersSchema,
      isNot(
          same(registry.findRegistration('standalone')!.spec.parametersSchema)),
    );
  });

  test('AgentExecutor runs a ToolSpec plus independent ToolExecutor pair',
      () async {
    final toolExecutor = _StandaloneExecutor();
    final registry = ToolRegistry()
      ..registerPair(
        spec: const ToolSpec(
          name: 'standalone',
          description: '独立执行器',
          parametersSchema: {
            'type': 'object',
            'properties': {
              'value': {'type': 'string'},
            },
            'required': ['value'],
          },
          risk: ToolRisk.safe,
        ),
        executor: toolExecutor,
      );
    final provider = _StandaloneToolProvider();
    ToolResult? result;

    await for (final event in AgentExecutor(
      provider: provider,
      tools: registry,
    ).run(
      history: [
        ChatMessage(
            role: MessageRole.user, parts: [const MessagePart.text('run')])
      ],
      model: 'test',
    )) {
      if (event is ToolResultEvent) result = event.result;
    }

    expect(toolExecutor.calls, 1);
    expect(result?.ok, isTrue);
    expect(result?.message, '独立执行器已运行');
    expect(provider.requests.length, 2);
  });

  test('a hung tool times out and yields a TIMEOUT failure instead of hanging',
      () async {
    final hangingExecutor = _HangingExecutor();
    final registry = ToolRegistry()
      ..registerPair(
        spec: const ToolSpec(
          name: 'hangs',
          description: '永不完成的假工具',
          parametersSchema: {'type': 'object'},
          risk: ToolRisk.safe,
          timeout: Duration(milliseconds: 50),
        ),
        executor: hangingExecutor,
      );
    final provider = _HangingToolProvider();
    ToolResult? result;

    await for (final event in AgentExecutor(
      provider: provider,
      tools: registry,
    ).run(
      history: [
        ChatMessage(
            role: MessageRole.user, parts: [const MessagePart.text('run')])
      ],
      model: 'test',
    )) {
      if (event is ToolResultEvent) result = event.result;
    }

    // 工具确实被调用了，但等待被 50ms 超时中断，回合继续而不是无限挂住。
    expect(hangingExecutor.calls, 1);
    expect(result?.ok, isFalse);
    expect(result?.code, ToolCodes.timeout);
    expect(result?.effect, ToolEffect.unknown);
    expect(result?.message, contains('超时'));
    expect(provider.requests.length, 2);
  });

  test('default tool timeout is 2 minutes; a spec override survives projection',
      () {
    const manifest = UnifiedTool(
      name: 'x',
      description: 'x',
      parametersSchema: {'type': 'object'},
      risk: ToolRisk.safe,
    );
    expect(manifest.timeout, const Duration(seconds: 120));

    final executor = _StandaloneExecutor();
    final registry = ToolRegistry()
      ..registerPair(
        spec: const ToolSpec(
          name: 'y',
          description: 'y',
          parametersSchema: {'type': 'object'},
          risk: ToolRisk.safe,
          timeout: Duration(minutes: 10),
        ),
        executor: executor,
      );
    expect(registry.findRegistration('y')!.spec.timeout,
        const Duration(minutes: 10));

    final projected = registry.project(const ToolCapabilitySnapshot());
    expect(projected.findRegistration('y')!.spec.timeout,
        const Duration(minutes: 10));
    expect(projected.manifests.single.timeout, const Duration(minutes: 10));
  });
}

class _StandaloneExecutor implements ToolExecutor {
  int calls = 0;

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    calls++;
    return ToolResult.success(message: '独立执行器已运行');
  }
}

class _HangingExecutor implements ToolExecutor {
  int calls = 0;

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) {
    calls++;
    // 永不完成：模拟卡死的终端命令 / 网络工具。
    return Completer<ToolResult>().future;
  }
}

class _HangingToolProvider implements LlmProvider {
  final requests = <UnifiedRequest>[];

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    requests.add(request);
    if (requests.length == 1) {
      yield const ToolCallEvent(
          ToolCall(id: 'hang-1', name: 'hangs', arguments: {}));
      yield const CompletedEvent(stopReason: StopReason.toolUse);
      return;
    }
    yield const TextDeltaEvent('done');
    yield const CompletedEvent(stopReason: StopReason.endOfTurn);
  }
}

class _StandaloneToolProvider implements LlmProvider {
  final requests = <UnifiedRequest>[];

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    requests.add(request);
    if (requests.length == 1) {
      yield const ToolCallEvent(ToolCall(
        id: 'standalone-1',
        name: 'standalone',
        arguments: {'value': 'ok'},
      ));
      yield const CompletedEvent(stopReason: StopReason.toolUse);
      return;
    }
    yield const TextDeltaEvent('done');
    yield const CompletedEvent(stopReason: StopReason.endOfTurn);
  }
}

class _CountingTool implements AgentTool {
  int executions = 0;

  @override
  final manifest = const UnifiedTool(
    name: 'counting',
    description: 'test counting tool',
    parametersSchema: {'type': 'object'},
    risk: ToolRisk.safe,
  );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    executions++;
    return ToolResult.text('executed');
  }
}

class _OutputLimitProvider implements LlmProvider {
  final requests = <UnifiedRequest>[];

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    requests.add(request);
    if (requests.length == 1) {
      yield const ToolCallEvent(
        ToolCall(id: 'partial-1', name: 'counting', arguments: {'value': 1}),
      );
      yield const CompletedEvent(stopReason: StopReason.outputLimit);
      return;
    }
    yield const TextDeltaEvent('replanned');
    yield const CompletedEvent(stopReason: StopReason.endOfTurn);
  }
}

class _TruncatedArgumentProvider implements LlmProvider {
  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    if (request.messages.any((message) => message.role == MessageRole.tool)) {
      yield const TextDeltaEvent('replanned');
      yield const CompletedEvent(stopReason: StopReason.endOfTurn);
      return;
    }
    yield const ToolCallEvent(ToolCall(
      id: 'truncated-1',
      name: 'counting',
      arguments: {ContextWindow.truncatedArgumentMark: true},
    ));
    yield const CompletedEvent(stopReason: StopReason.toolUse);
  }
}

class _MultiToolProvider implements LlmProvider {
  final requests = <UnifiedRequest>[];
  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    requests.add(request);
    if (requests.length == 1) {
      yield const ToolCallEvent(
          ToolCall(id: 'a', name: 'calculator', arguments: {'a': 1, 'b': 2}));
      yield const ToolCallEvent(
          ToolCall(id: 'b', name: 'calculator', arguments: {'a': 3, 'b': 4}));
    } else {
      yield const TextDeltaEvent('done');
    }
    yield const CompletedEvent(stopReason: StopReason.toolUse);
  }
}

class _ToolLoopProvider implements LlmProvider {
  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    yield const ToolCallEvent(
        ToolCall(id: 'loop', name: 'calculator', arguments: {'a': 1, 'b': 2}));
    yield const CompletedEvent(stopReason: StopReason.toolUse);
  }
}

class _ResumeVerifyingProvider implements LlmProvider {
  final requests = <UnifiedRequest>[];

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    requests.add(request);
    yield const TextDeltaEvent('resumed');
    yield const CompletedEvent(stopReason: StopReason.endOfTurn);
  }
}

class _ToolRequestProvider implements LlmProvider {
  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    yield const ToolCallEvent(ToolCall(id: '1', name: 'risky', arguments: {}));
    yield const CompletedEvent(stopReason: StopReason.toolUse);
  }
}

class _SensitiveTool implements AgentTool {
  @override
  final manifest = const UnifiedTool(
    name: 'sensitive_fixture',
    description: 'test sensitive',
    parametersSchema: {'type': 'object'},
    risk: ToolRisk.dangerous,
    sensitive: true,
  );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async =>
      ToolResult.text('executed');
}

class _SensitiveToolProvider implements LlmProvider {
  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    yield const ToolCallEvent(
        ToolCall(id: '1', name: 'sensitive_fixture', arguments: {}));
    yield const CompletedEvent(stopReason: StopReason.toolUse);
  }
}

class _ApprovedPlanProvider implements LlmProvider {
  final requests = <UnifiedRequest>[];
  bool continuationSeen = false;

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    requests.add(request);
    if (requests.length == 1) {
      yield const ToolCallEvent(ToolCall(
        id: 'plan-1',
        name: 'manage_plan',
        arguments: {
          'steps': [
            {'id': 's1', 'description': '执行计算'},
          ],
        },
      ));
      yield const CompletedEvent(stopReason: StopReason.toolUse);
      return;
    }
    if (requests.length == 2) {
      continuationSeen = request.messages.any((message) =>
          message.role == MessageRole.user && message.text.contains('[计划已确认]'));
      if (continuationSeen) {
        yield const ToolCallEvent(ToolCall(
            id: 'calc-1', name: 'calculator', arguments: {'a': 1, 'b': 2}));
      } else {
        yield const TextDeltaEvent('提前结束');
      }
      yield CompletedEvent(
          stopReason:
              continuationSeen ? StopReason.toolUse : StopReason.endOfTurn);
      return;
    }
    yield const TextDeltaEvent('计划执行完成');
    yield const CompletedEvent(stopReason: StopReason.endOfTurn);
  }
}

class _RiskyTool implements AgentTool {
  @override
  final manifest = const UnifiedTool(
    name: 'risky',
    description: 'test',
    parametersSchema: {'type': 'object'},
    risk: ToolRisk.requiresConfirmation,
  );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async =>
      ToolResult.text('executed');
}

class _ExplodingTool implements AgentTool {
  @override
  final manifest = const UnifiedTool(
    name: 'explode',
    description: 'always fails',
    parametersSchema: {'type': 'object'},
    risk: ToolRisk.safe,
  );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async =>
      throw Exception('boom');
}

class _ToolThenTextProvider implements LlmProvider {
  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    final hasToolResult =
        request.messages.any((m) => m.role == MessageRole.tool);
    if (hasToolResult) {
      yield const TextDeltaEvent('继续完成');
      yield const CompletedEvent(stopReason: StopReason.endOfTurn);
      return;
    }
    yield const ToolCallEvent(
        ToolCall(id: '1', name: 'explode', arguments: {}));
    yield const CompletedEvent(stopReason: StopReason.toolUse);
  }
}

class _RecordingProvider implements LlmProvider {
  UnifiedRequest? lastRequest;

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    lastRequest = request;
    yield const TextDeltaEvent('ok');
    yield const CompletedEvent(stopReason: StopReason.endOfTurn);
  }
}

class _UsageProvider implements LlmProvider {
  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    yield const TextDeltaEvent('hello');
    yield const UsageEvent(promptTokens: 100, completionTokens: 50);
    yield const CompletedEvent(stopReason: StopReason.endOfTurn);
  }
}

class _FlakyErrorProvider implements LlmProvider {
  _FlakyErrorProvider({this.alwaysFail = false});
  final bool alwaysFail;
  int calls = 0;

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    calls++;
    if (alwaysFail || calls == 1) {
      yield ProviderErrorEvent('持续失败（第 $calls 次）');
      return;
    }
    yield const TextDeltaEvent('恢复成功');
    yield const CompletedEvent(stopReason: StopReason.endOfTurn);
  }
}

class _PartialThenErrorProvider implements LlmProvider {
  int calls = 0;

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    calls++;
    yield const TextDeltaEvent('部分');
    yield const ProviderErrorEvent('上游挂了');
  }
}
