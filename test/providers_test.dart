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
    test('clamps thinking budget below max_tokens', () {
      final provider = AnthropicProvider(config: config);
      final payload = provider.buildRequestPayload(UnifiedRequest(
        model: 'claude-sonnet-4-5',
        maxTokens: 2048,
        reasoningEffort: ReasoningEffort.medium,
        messages: [
          ChatMessage(
            role: MessageRole.user,
            parts: const [MessagePart.text('hello')],
          ),
        ],
      ));

      expect(payload['max_tokens'], 2048);
      expect(payload['thinking'], {
        'type': 'enabled',
        'budget_tokens': 2047,
      });
    });

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

    test('marks tools, system and the last message as cache breakpoints', () {
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
          ChatMessage(
            role: MessageRole.assistant,
            parts: const [],
            toolCalls: const [
              ToolCall(id: 'call-1', name: 'calc', arguments: {'a': 1}),
            ],
          ),
          ChatMessage(
            role: MessageRole.tool,
            toolCallId: 'call-1',
            parts: const [MessagePart.text('工具结果')],
          ),
        ],
        tools: const [
          UnifiedTool(
            name: 'tool_a',
            description: 'a',
            parametersSchema: {'type': 'object'},
            risk: ToolRisk.safe,
          ),
          UnifiedTool(
            name: 'tool_b',
            description: 'b',
            parametersSchema: {'type': 'object'},
            risk: ToolRisk.safe,
          ),
        ],
      ));

      // 只在最后一个工具上打断点；多步循环里工具定义不变，断点之前的
      // 前缀可跨步骤复用。
      final tools = payload['tools'] as List;
      expect((tools.last as Map)['cache_control'], {'type': 'ephemeral'});
      expect((tools.first as Map).containsKey('cache_control'), isFalse);

      // 最后一条消息（工具结果）的末块打断点，实现会话增量缓存；更早的
      // 消息不打，避免超过 Anthropic 的 4 个断点上限。
      final messages = payload['messages'] as List;
      final lastBlocks = (messages.last['content'] as List);
      expect((lastBlocks.last as Map)['cache_control'], {'type': 'ephemeral'});
      final earlierBlocks = (messages.first['content'] as List);
      expect(
          (earlierBlocks.first as Map).containsKey('cache_control'), isFalse);

      // tools + system + messages 各一个断点，总数不超过上限 4。
      var breakpoints = 0;
      for (final tool in tools.whereType<Map>()) {
        if (tool.containsKey('cache_control')) breakpoints++;
      }
      for (final block in (payload['system'] as List).whereType<Map>()) {
        if (block.containsKey('cache_control')) breakpoints++;
      }
      for (final message in messages) {
        for (final block in (message['content'] as List).whereType<Map>()) {
          if (block.containsKey('cache_control')) breakpoints++;
        }
      }
      expect(breakpoints, lessThanOrEqualTo(4));
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
    test('uses thinkingLevel for Gemini 3 models', () async {
      final dio = Dio()..httpClientAdapter = _SseAdapter('''
data: {"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}

''');
      final provider = GeminiProvider(config: config, dio: dio);
      await provider
          .stream(UnifiedRequest(
            model: 'gemini-3-flash-preview',
            reasoningEffort: ReasoningEffort.medium,
            messages: [
              ChatMessage(
                role: MessageRole.user,
                parts: const [MessagePart.text('hello')],
              ),
            ],
          ))
          .toList();

      final payload = dio.httpClientAdapter is _SseAdapter
          ? (dio.httpClientAdapter as _SseAdapter).capturedPayloads.single
              as Map<String, dynamic>
          : const <String, dynamic>{};
      final generationConfig = payload['generationConfig'] as Map;
      expect(generationConfig['thinkingConfig'], {'thinkingLevel': 'medium'});
    });

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
    expect(usage.cacheWriteTokens, 20);
    expect(usage.cacheStatsReported, isTrue);
  });

  test('Gemini stream exposes cachedContentTokenCount', () async {
    final dio = Dio()..httpClientAdapter = _SseAdapter('''
data: {"usageMetadata":{"promptTokenCount":200,"candidatesTokenCount":50,"cachedContentTokenCount":120,"thoughtsTokenCount":8},"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}

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
    expect(usage.reasoningTokens, 8);
    expect(usage.cacheStatsReported, isTrue);
  });

  test('Gemini stream without cachedContentTokenCount is not a cache miss',
      () async {
    // 隐式缓存只在命中时携带该字段；字段缺失不能解读为“未命中”。
    final dio = Dio()..httpClientAdapter = _SseAdapter('''
data: {"usageMetadata":{"promptTokenCount":200,"candidatesTokenCount":50},"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}

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
    expect(usage.cachedTokens, 0);
    expect(usage.cacheStatsReported, isFalse);
  });

  test('OpenAI-compatible stream parses DeepSeek cache hit/miss fields',
      () async {
    final dio = Dio()..httpClientAdapter = _SseAdapter('''
data: {"choices":[{"delta":{"content":"ok"}}]}

data: {"choices":[],"usage":{"prompt_cache_hit_tokens":80,"prompt_cache_miss_tokens":20,"completion_tokens":5}}

data: [DONE]

''');
    final provider = OpenAiCompatibleProvider(config: config, dio: dio);
    final events = await provider
        .stream(UnifiedRequest(
          model: 'deepseek-chat',
          messages: [
            ChatMessage(
              role: MessageRole.user,
              parts: const [MessagePart.text('hello')],
            ),
          ],
        ))
        .toList();

    final usage = events.whereType<UsageEvent>().single;
    expect(usage.cachedTokens, 80);
    expect(usage.cacheStatsReported, isTrue);
    // 只有 hit/miss 对、没有 prompt_tokens 时，总数按 hit+miss 还原。
    expect(usage.promptTokens, 100);
    expect(usage.completionTokens, 5);
  });

  test('OpenAI-compatible usage without cache fields is not a cache miss',
      () async {
    final dio = Dio()..httpClientAdapter = _SseAdapter('''
data: {"choices":[{"delta":{"content":"ok"}}]}

data: {"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":7,"completion_tokens_details":{"reasoning_tokens":4}}}

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

    final usage = events.whereType<UsageEvent>().single;
    expect(usage.cachedTokens, 0);
    expect(usage.cacheStatsReported, isFalse);
    expect(usage.reasoningTokens, 4);
  });

  test('OpenAI-compatible stream requests usage via stream_options', () async {
    final dio = Dio()..httpClientAdapter = _SseAdapter('''
data: {"choices":[{"delta":{"content":"ok"}}]}

data: {"choices":[],"usage":{"prompt_tokens":100,"completion_tokens":5,"prompt_tokens_details":{"cached_tokens":80}}}

data: [DONE]

''');
    final provider = OpenAiCompatibleProvider(config: config, dio: dio);
    final events = await provider
        .stream(UnifiedRequest(
          model: 'gpt-4o-mini',
          messages: [
            ChatMessage(
              role: MessageRole.user,
              parts: const [MessagePart.text('hello')],
            ),
          ],
        ))
        .toList();

    final payload = (dio.httpClientAdapter as _SseAdapter)
        .capturedPayloads
        .single as Map<String, dynamic>;
    expect((payload['stream_options'] as Map)['include_usage'], isTrue);

    final usage = events.whereType<UsageEvent>().single;
    expect(usage.cachedTokens, 80);
    expect(usage.cacheStatsReported, isTrue);
  });

  test('OpenAI-compatible stream retries without stream_options on 400',
      () async {
    // 严格按旧规范实现的中转服务会对未知字段 400；此时应去掉该字段降级
    // 重试一次，而不是中断整轮对话。
    final adapter = _QueuedAdapter([
      ResponseBody.fromString(
        '{"error":{"message":"Unrecognized request argument supplied: stream_options"}}',
        400,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        },
      ),
      ResponseBody.fromString(
          '''
data: {"choices":[{"delta":{"content":"ok"}}]}

data: {"choices":[],"usage":{"prompt_tokens":100,"completion_tokens":5,"prompt_tokens_details":{"cached_tokens":80}}}

data: [DONE]

''',
          200,
          headers: {
            Headers.contentTypeHeader: ['text/event-stream']
          }),
    ]);
    final provider = OpenAiCompatibleProvider(
        config: config, dio: Dio()..httpClientAdapter = adapter);
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

    expect(adapter.capturedPayloads, hasLength(2));
    final first = adapter.capturedPayloads[0] as Map<String, dynamic>;
    expect((first['stream_options'] as Map)['include_usage'], isTrue);
    final second = adapter.capturedPayloads[1] as Map<String, dynamic>;
    expect(second.containsKey('stream_options'), isFalse);

    final usage = events.whereType<UsageEvent>().single;
    expect(usage.cachedTokens, 80);
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

  test('OpenAI-compatible stream converts HTTP errors into ProviderErrorEvent',
      () async {
    // 回归护栏：async* 里 `yield*` 会把内层流错误直接转发给消费者，外层
    // catch 拦不到（探针验证过的 Dart 语义）。驱动方式必须是 await for，
    // 否则 DioException 逃逸成上层“未预期异常”，而不是这里的友好错误事件。
    final adapter = _QueuedAdapter([
      ResponseBody.fromString('{"error":{"message":"Incorrect API key"}}', 401,
          headers: {
            Headers.contentTypeHeader: ['application/json']
          }),
    ]);
    final provider = OpenAiCompatibleProvider(
        config: config, dio: Dio()..httpClientAdapter = adapter);
    final events = await provider
        .stream(UnifiedRequest(
          model: 'gpt-4o-mini',
          messages: [
            ChatMessage(
              role: MessageRole.user,
              parts: const [MessagePart.text('hello')],
            ),
          ],
        ))
        .toList();

    final error = events.whereType<ProviderErrorEvent>().single;
    expect(error.statusCode, 401);
    expect(error.message, contains('HTTP 401'));
  });

  test('Anthropic stream converts HTTP errors into ProviderErrorEvent',
      () async {
    final adapter = _QueuedAdapter([
      ResponseBody.fromString('{"error":"invalid x-api-key"}', 401, headers: {
        Headers.contentTypeHeader: ['application/json']
      }),
    ]);
    final provider = AnthropicProvider(
        config: config, dio: Dio()..httpClientAdapter = adapter);
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

    final error = events.whereType<ProviderErrorEvent>().single;
    expect(error.statusCode, 401);
  });

  test('Gemini stream converts HTTP errors into ProviderErrorEvent', () async {
    final adapter = _QueuedAdapter([
      ResponseBody.fromString('{"error":{"message":"API key not valid"}}', 400,
          headers: {
            Headers.contentTypeHeader: ['application/json']
          }),
    ]);
    final provider =
        GeminiProvider(config: config, dio: Dio()..httpClientAdapter = adapter);
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

    final error = events.whereType<ProviderErrorEvent>().single;
    expect(error.statusCode, 400);
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

  /// 捕获每个请求的 payload，供断言请求体字段使用。
  final capturedPayloads = <Object?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    capturedPayloads.add(options.data);
    return ResponseBody.fromString(body, 200, headers: {
      Headers.contentTypeHeader: ['text/event-stream'],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// 按队列依次返回响应（可混排错误码），并捕获每次请求的 payload。
class _QueuedAdapter implements HttpClientAdapter {
  _QueuedAdapter(this.responses);

  final List<ResponseBody> responses;
  final capturedPayloads = <Object?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    capturedPayloads.add(options.data);
    if (responses.isEmpty) {
      throw StateError('unexpected extra request');
    }
    return responses.removeAt(0);
  }

  @override
  void close({bool force = false}) {}
}
