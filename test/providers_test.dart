import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/providers/anthropic_provider.dart';
import 'package:mobile_agent/infrastructure/providers/gemini_provider.dart';
import 'package:mobile_agent/infrastructure/providers/openai_compatible_provider.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const config =
      ProviderConfig(baseUrl: 'https://example.com', model: 'm', apiKey: 'k');

  group('AnthropicProvider', () {
    test('system prompt uses an ephemeral prompt-cache boundary', () {
      final provider = AnthropicProvider(config: config);
      final payload = provider.buildRequestPayload(UnifiedRequest(
        model: 'claude-sonnet-4-5',
        messages: [
          ChatMessage(
            role: MessageRole.system,
            parts: const [MessagePart.text('长期系统提示')],
          ),
          ChatMessage(
            role: MessageRole.user,
            parts: const [MessagePart.text('你好')],
          ),
        ],
      ));

      expect(payload['system'], [
        {
          'type': 'text',
          'text': '长期系统提示',
          'cache_control': {'type': 'ephemeral'},
        },
      ]);
      expect(payload['messages'], hasLength(1));
    });

    test('converts a user text message into content blocks', () {
      final provider = AnthropicProvider(config: config);
      final result = provider.toAnthropicMessage(ChatMessage(
        role: MessageRole.user,
        parts: const [MessagePart.text('你好')],
      ));
      expect(result['role'], 'user');
      expect(result['content'], [
        {'type': 'text', 'text': '你好'},
      ]);
    });

    test('converts assistant tool calls into tool_use blocks', () {
      final provider = AnthropicProvider(config: config);
      final result = provider.toAnthropicMessage(ChatMessage(
        role: MessageRole.assistant,
        parts: const [],
        toolCalls: [
          const ToolCall(id: 'call-1', name: 'calculator', arguments: {'a': 1})
        ],
      ));
      expect(result['role'], 'assistant');
      expect(result['content'], [
        {
          'type': 'tool_use',
          'id': 'call-1',
          'name': 'calculator',
          'input': {'a': 1}
        },
      ]);
    });

    test('converts tool results into tool_result blocks', () {
      final provider = AnthropicProvider(config: config);
      final result = provider.toAnthropicMessage(ChatMessage(
        role: MessageRole.tool,
        toolCallId: 'call-1',
        parts: const [MessagePart.text('3')],
      ));
      expect(result['role'], 'user');
      expect(result['content'], [
        {'type': 'tool_result', 'tool_use_id': 'call-1', 'content': '3'},
      ]);
    });

    test('maps tool schema to input_schema', () {
      final provider = AnthropicProvider(config: config);
      final result = provider.toAnthropicTool(const UnifiedTool(
        name: 'get_time',
        description: 'time',
        parametersSchema: {'type': 'object', 'properties': {}},
        risk: ToolRisk.safe,
      ));
      expect(result['name'], 'get_time');
      expect(result['input_schema'], {'type': 'object', 'properties': {}});
    });
  });

  group('GeminiProvider', () {
    test('converts a user message into parts', () {
      final provider = GeminiProvider(config: config);
      final result = provider.toGeminiMessage(
          ChatMessage(
            role: MessageRole.user,
            parts: const [MessagePart.text('你好')],
          ),
          const {});
      expect(result['role'], 'user');
      expect(result['parts'], [
        {'text': '你好'},
      ]);
    });

    test('converts assistant tool calls into functionCall parts', () {
      final provider = GeminiProvider(config: config);
      final result = provider.toGeminiMessage(
          ChatMessage(
            role: MessageRole.assistant,
            parts: const [],
            toolCalls: [
              const ToolCall(
                  id: 'call-1', name: 'calculator', arguments: {'a': 1})
            ],
          ),
          const {});
      expect(result['role'], 'model');
      expect(result['parts'], [
        {
          'functionCall': {
            'name': 'calculator',
            'args': {'a': 1}
          },
        },
      ]);
    });

    test('converts tool results into functionResponse parts with resolved name',
        () {
      final provider = GeminiProvider(config: config);
      final result = provider.toGeminiMessage(
        ChatMessage(
            role: MessageRole.tool,
            toolCallId: 'call-1',
            parts: const [MessagePart.text('3')]),
        const {'call-1': 'calculator'},
      );
      expect(result['role'], 'function');
      expect(result['parts'], [
        {
          'functionResponse': {
            'name': 'calculator',
            'response': {'result': '3'}
          },
        },
      ]);
    });

    test('maps tool schema to functionDeclarations parameter', () {
      final provider = GeminiProvider(config: config);
      final result = provider.toGeminiTool(const UnifiedTool(
        name: 'json_query',
        description: 'query',
        parametersSchema: {'type': 'object'},
        risk: ToolRisk.safe,
      ));
      expect(result['name'], 'json_query');
      expect(result['parameters'], {'type': 'object'});
    });
  });

  test('Anthropic stream exposes cache read and total input tokens', () async {
    final dio = Dio()..httpClientAdapter = _SseAdapter('''
data: {"type":"message_start","message":{"usage":{"input_tokens":100,"cache_creation_input_tokens":20,"cache_read_input_tokens":30}}}

data: {"type":"message_delta","usage":{"output_tokens":40}}

''');
    final provider = AnthropicProvider(config: config, dio: dio);
    final events = await provider
        .stream(UnifiedRequest(
          model: 'claude-sonnet-4-5',
          messages: [
            ChatMessage(
              role: MessageRole.user,
              parts: const [MessagePart.text('hello')],
            ),
          ],
        ))
        .toList();

    final usage = events.whereType<UsageEvent>().single;
    expect(usage.promptTokens, 150);
    expect(usage.cachedTokens, 30);
    expect(usage.completionTokens, 40);
  });

  test('Gemini stream exposes cachedContentTokenCount', () async {
    final dio = Dio()..httpClientAdapter = _SseAdapter('''
data: {"usageMetadata":{"promptTokenCount":200,"candidatesTokenCount":50,"cachedContentTokenCount":120},"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}

''');
    final provider = GeminiProvider(config: config, dio: dio);
    final events = await provider
        .stream(UnifiedRequest(
          model: 'gemini-2.5-pro',
          messages: [
            ChatMessage(
              role: MessageRole.user,
              parts: const [MessagePart.text('hello')],
            ),
          ],
        ))
        .toList();

    final usage = events.whereType<UsageEvent>().single;
    expect(usage.promptTokens, 200);
    expect(usage.cachedTokens, 120);
    expect(usage.completionTokens, 50);
  });

  test(
      'OpenAI-compatible stream assigns unique ids when relay omits tool_call ids',
      () async {
    // 部分中转服务流式返回不带 tool_call id。id 若兜底成同一个固定值，
    // 执行层按 id 关联的结果与活动行会全部串线（真实事故）。
    final dio = Dio()..httpClientAdapter = _SseAdapter(r'''
data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"terminal","arguments":"{\"command\":\"ls\"}"}},{"index":1,"function":{"name":"skills_read","arguments":"{\"skill\":\"android-build\"}"}}]}}]}

data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}

data: [DONE]

''');
    final provider = OpenAiCompatibleProvider(config: config, dio: dio);
    final events = await provider
        .stream(UnifiedRequest(
          model: 'relay-model',
          messages: [
            ChatMessage(
              role: MessageRole.user,
              parts: const [MessagePart.text('hello')],
            ),
          ],
        ))
        .toList();

    final calls = events.whereType<ToolCallEvent>().toList();
    expect(calls, hasLength(2));
    expect(calls[0].call.id, isNotEmpty);
    expect(calls[1].call.id, isNotEmpty);
    expect(calls[0].call.id, isNot(equals(calls[1].call.id)));
    expect(calls.map((c) => c.call.name), ['terminal', 'skills_read']);
  });

  group('ProviderConfig.isConfigured', () {
    test('local model without api key is considered configured', () {
      const local = ProviderConfig(
          baseUrl: 'http://localhost:11434/v1', model: 'llama3.2', apiKey: '');
      expect(local.isConfigured, isTrue);
    });

    test('cloud provider without api key is not configured', () {
      const cloud = ProviderConfig(
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o-mini',
          apiKey: '');
      expect(cloud.isConfigured, isFalse);
    });

    test('empty model is never configured', () {
      const empty = ProviderConfig(
          baseUrl: 'http://localhost:11434/v1', model: '', apiKey: '');
      expect(empty.isConfigured, isFalse);
    });
  });

  test('ignores malformed persisted provider profiles', () async {
    SharedPreferences.setMockInitialValues({
      'provider.profiles': '{not-json',
    });

    final profiles = await ProviderConfigStore().loadAll();

    expect(profiles, isEmpty);
  });
}

class _SseAdapter implements HttpClientAdapter {
  _SseAdapter(this.body);

  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(body, 200, headers: {
      Headers.contentTypeHeader: ['text/event-stream'],
    });
  }

  @override
  void close({bool force = false}) {}
}
