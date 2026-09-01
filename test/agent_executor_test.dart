import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';

import 'package:mobile_agent/application/agent_executor.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/providers/llm_provider.dart';
import 'package:mobile_agent/infrastructure/providers/openai_compatible_provider.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/infrastructure/files/document_extractor.dart';
import 'package:mobile_agent/infrastructure/tools/core_tools.dart';
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
          parts: [MessagePart.text('你好')],
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
    final executor = AgentExecutor(provider: _ToolRequestProvider(), tools: registry);
    var asked = false;
    final statuses = <RunStatus>[];
    await for (final event in executor.run(
      history: [ChatMessage(role: MessageRole.user, parts: [MessagePart.text('run')])],
      model: 'test',
      approveTool: (call, risk) async {
        asked = true;
        return false;
      },
    )) {
      if (event is AgentStatusEvent) statuses.add(event.status);
    }
    expect(asked, isTrue);
    expect(statuses, contains(RunStatus.cancelled));
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
          MessagePart.image('data:image/png;base64,AAAA', mimeType: 'image/png'),
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
      config: const ProviderConfig(baseUrl: 'https://example.com/v1', model: 'test', apiKey: 'key'),
    );
    final payload = provider.toProviderMessage(ChatMessage(
      role: MessageRole.assistant,
      parts: const [],
      toolCalls: [ToolCall(id: 'call-1', name: 'calculator', arguments: {'expression': '2+2'})],
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

  test('executes multiple tool calls and preserves assistant call context', () async {
    final registry = ToolRegistry()..register(CalculatorTool());
    final provider = _MultiToolProvider();
    final executor = AgentExecutor(provider: provider, tools: registry);
    var requested = 0;
    await for (final event in executor.run(
      history: [ChatMessage(role: MessageRole.user, parts: [MessagePart.text('calculate')])],
      model: 'test',
    )) {
      if (event is ToolRequestedEvent) requested++;
    }
    expect(requested, 2);
    expect(provider.requests, hasLength(2));
    expect(provider.requests[1].messages.any((message) => message.toolCalls.length == 2), isTrue);
  });

  test('core tools return deterministic safe results', () async {
    expect(await GetTimeTool().execute({}), isNotEmpty);
    expect(await JsonQueryTool().execute({'json': '{"user":{"name":"Nexus"}}', 'path': 'user.name'}), '"Nexus"');
  });

  test('http_request tool rejects cloud metadata and link-local addresses', () async {
    final tool = HttpRequestTool();
    expect(await tool.execute({'url': 'http://169.254.169.254/latest/meta-data/'}), contains('安全策略拒绝'));
    expect(await tool.execute({'url': 'https://metadata.google.internal/'}), contains('安全策略拒绝'));
    expect(await tool.execute({'url': 'http://169.254.0.1/'}), contains('安全策略拒绝'));
    expect(await tool.execute({'url': 'ftp://example.com/x'}), 'URL 无效');
  });

  test('forwards temperature, maxTokens and topP into the provider request', () async {
    final registry = ToolRegistry()..register(CalculatorTool());
    final provider = _RecordingProvider();
    final executor = AgentExecutor(provider: provider, tools: registry);
    await for (final _ in executor.run(
      history: [ChatMessage(role: MessageRole.user, parts: [MessagePart.text('hi')])],
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

  test('tool execution failure yields a failed result without throwing', () async {
    final registry = ToolRegistry()..register(_ExplodingTool());
    final provider = _ToolThenTextProvider();
    final executor = AgentExecutor(provider: provider, tools: registry);
    String? toolResult;
    var requested = 0;
    await for (final event in executor.run(
      history: [ChatMessage(role: MessageRole.user, parts: [MessagePart.text('run')])],
      model: 'test',
    )) {
      if (event is ToolResultEvent) toolResult = event.result;
      if (event is ToolRequestedEvent) requested++;
    }
    expect(requested, 1);
    expect(toolResult, startsWith('工具执行失败'));
  });

  test('accumulates token usage reported by the provider', () async {
    final registry = ToolRegistry()..register(CalculatorTool());
    final executor = AgentExecutor(provider: _UsageProvider(), tools: registry);
    var promptTokens = 0;
    var completionTokens = 0;
    await for (final event in executor.run(
      history: [ChatMessage(role: MessageRole.user, parts: [MessagePart.text('hi')])],
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
}

class _MultiToolProvider implements LlmProvider {
  final requests = <UnifiedRequest>[];
  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request, {CancelToken? cancelToken}) async* {
    requests.add(request);
    if (requests.length == 1) {
      yield const ToolCallEvent(ToolCall(id: 'a', name: 'calculator', arguments: {'a': 1, 'b': 2}));
      yield const ToolCallEvent(ToolCall(id: 'b', name: 'calculator', arguments: {'a': 3, 'b': 4}));
    } else {
      yield const TextDeltaEvent('done');
    }
    yield const CompletedEvent();
  }
}

class _ToolRequestProvider implements LlmProvider {
  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request, {CancelToken? cancelToken}) async* {
    yield const ToolCallEvent(ToolCall(id: '1', name: 'risky', arguments: {}));
    yield const CompletedEvent();
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
  Future<String> execute(Map<String, dynamic> arguments) async => 'executed';
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
  Future<String> execute(Map<String, dynamic> arguments) async => throw Exception('boom');
}

class _ToolThenTextProvider implements LlmProvider {
  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request, {CancelToken? cancelToken}) async* {
    final hasToolResult = request.messages.any((m) => m.role == MessageRole.tool);
    if (hasToolResult) {
      yield const TextDeltaEvent('继续完成');
      yield const CompletedEvent();
      return;
    }
    yield const ToolCallEvent(ToolCall(id: '1', name: 'explode', arguments: {}));
    yield const CompletedEvent();
  }
}

class _RecordingProvider implements LlmProvider {
  UnifiedRequest? lastRequest;

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request, {CancelToken? cancelToken}) async* {
    lastRequest = request;
    yield const TextDeltaEvent('ok');
    yield const CompletedEvent();
  }
}

class _UsageProvider implements LlmProvider {
  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request, {CancelToken? cancelToken}) async* {
    yield const TextDeltaEvent('hello');
    yield const UsageEvent(promptTokens: 100, completionTokens: 50);
    yield const CompletedEvent();
  }
}
