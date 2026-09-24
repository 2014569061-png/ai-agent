import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/agent_executor.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/providers/anthropic_provider.dart';
import 'package:mobile_agent/infrastructure/providers/gemini_provider.dart';
import 'package:mobile_agent/infrastructure/providers/llm_provider.dart';
import 'package:mobile_agent/infrastructure/providers/openai_compatible_provider.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/infrastructure/tools/tool_registry.dart';

const _config = ProviderConfig(
  baseUrl: 'https://provider.invalid',
  model: 'test-model',
  apiKey: 'test-only',
);

List<Map<String, dynamic>> _frames(
    String provider, Map<String, dynamic>? usage) {
  switch (provider) {
    case 'gemini':
      return [
        {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'ok'}
                ]
              },
              'finishReason': 'STOP',
            }
          ],
          if (usage != null) 'usageMetadata': usage,
        }
      ];
    case 'anthropic':
      return [
        {
          'type': 'message_start',
          'message': {if (usage != null) 'usage': usage}
        },
        {
          'type': 'content_block_delta',
          'delta': {'type': 'text_delta', 'text': 'ok'}
        },
        {
          'type': 'message_delta',
          'delta': {'stop_reason': 'end_turn'}
        },
      ];
    default:
      return [
        {
          'choices': [
            {
              'delta': {'content': 'ok'},
              'finish_reason': 'stop'
            }
          ],
          if (usage != null) 'usage': usage,
        }
      ];
  }
}

LlmProvider _provider(String name, List<Map<String, dynamic>> frames) {
  final adapter =
      _SseAdapter(frames.map((f) => 'data: ${jsonEncode(f)}\n\n').join());
  final dio = Dio()..httpClientAdapter = adapter;
  switch (name) {
    case 'gemini':
      return GeminiProvider(config: _config, dio: dio);
    case 'anthropic':
      return AnthropicProvider(config: _config, dio: dio);
    default:
      return OpenAiCompatibleProvider(config: _config, dio: dio);
  }
}

Future<AgentUsageEvent> _execute(LlmProvider provider) async {
  final events =
      await AgentExecutor(provider: provider, tools: ToolRegistry()).run(
    history: [
      ChatMessage(
          role: MessageRole.user, parts: const [MessagePart.text('test')])
    ],
    model: 'test-model',
    maxRetries: 0,
  ).toList();
  expect(events.whereType<TextEvent>().map((e) => e.text).join(), 'ok');
  return events.whereType<AgentUsageEvent>().last;
}

void main() {
  for (final name in ['openai', 'gemini', 'anthropic']) {
    test('$name: absent usage is not reported as measured zero', () async {
      final usage = await _execute(_provider(name, _frames(name, null)));
      expect(usage.usageReported, isFalse);
      expect(usage.cacheStatsReported, isFalse);
    });

    test('$name: an empty usage map is not a measurement', () async {
      final usage = await _execute(_provider(name, _frames(name, {})));
      expect(usage.usageReported, isFalse);
      expect(usage.cacheStatsReported, isFalse);
    });

    test('$name: explicit zero tokens are a measurement, not cache statistics',
        () async {
      final zero = switch (name) {
        'gemini' => {'promptTokenCount': 0, 'candidatesTokenCount': 0},
        'anthropic' => {'input_tokens': 0, 'output_tokens': 0},
        _ => {'prompt_tokens': 0, 'completion_tokens': 0},
      };
      final usage = await _execute(_provider(name, _frames(name, zero)));
      expect(usage.usageReported, isTrue);
      expect(usage.cacheStatsReported, isFalse);
      expect(usage.promptTokens, 0);
      expect(usage.completionTokens, 0);
    });
  }

  test('OpenAI preserves text, reasoning, tools and usage in the same frame',
      () async {
    final provider = _provider('openai', [
      {
        'choices': [
          {
            'delta': {
              'content': 'tail',
              'reasoning_content': 'reason',
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'call-1',
                  'type': 'function',
                  'function': {
                    'name': 'calculator',
                    'arguments': '{"expression":"1+1"}'
                  },
                }
              ],
            },
            'finish_reason': 'tool_calls',
          }
        ],
        'usage': {'prompt_tokens': 3, 'completion_tokens': 2},
      }
    ]);
    final events = await provider
        .stream(const UnifiedRequest(model: 'test', messages: []))
        .toList();
    expect(events.whereType<TextDeltaEvent>().single.text, 'tail');
    expect(events.whereType<ReasoningDeltaEvent>().single.text, 'reason');
    final call = events.whereType<ToolCallEvent>().single.call;
    expect(call.id, 'call-1');
    expect(call.arguments, {'expression': '1+1'});
    expect(events.whereType<UsageEvent>().single.promptTokens, 3);
    expect(events.whereType<CompletedEvent>().single.stopReason,
        StopReason.toolUse);
  });

  test('Anthropic only reports cache statistics when supplied', () async {
    final usage = await _execute(_provider(
        'anthropic',
        _frames('anthropic', {
          'input_tokens': 2,
          'output_tokens': 1,
          'cache_read_input_tokens': 0,
          'cache_creation_input_tokens': 0,
        })));
    expect(usage.usageReported, isTrue);
    expect(usage.cacheStatsReported, isTrue);
  });
}

class _SseAdapter implements HttpClientAdapter {
  _SseAdapter(this.body);
  final String body;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString(body, 200, headers: {
        Headers.contentTypeHeader: ['text/event-stream']
      });
  @override
  void close({bool force = false}) {}
}
