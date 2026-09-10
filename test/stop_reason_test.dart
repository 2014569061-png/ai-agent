import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/providers/anthropic_provider.dart';
import 'package:mobile_agent/infrastructure/providers/gemini_provider.dart';
import 'package:mobile_agent/infrastructure/providers/openai_compatible_provider.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';

const _config =
    ProviderConfig(baseUrl: 'https://example.com', model: 'm', apiKey: 'k');

UnifiedRequest _request(String model) => UnifiedRequest(
      model: model,
      messages: [
        ChatMessage(
            role: MessageRole.user, parts: const [MessagePart.text('hi')]),
      ],
    );

/// 取出流末尾 CompletedEvent 携带的停因。
Future<StopReason> _stopReasonOf(Stream<UnifiedEvent> events) async {
  final list = await events.toList();
  return list.whereType<CompletedEvent>().last.stopReason;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('StopReason.parse', () {
    test('maps OpenAI finish_reason values', () {
      expect(StopReason.parse('tool_calls'), StopReason.toolUse);
      expect(StopReason.parse('stop'), StopReason.endOfTurn);
      expect(StopReason.parse('length'), StopReason.outputLimit);
      expect(StopReason.parse('content_filter'), StopReason.contentFilter);
    });

    test('maps Anthropic stop_reason values', () {
      expect(StopReason.parse('tool_use'), StopReason.toolUse);
      expect(StopReason.parse('end_turn'), StopReason.endOfTurn);
      expect(StopReason.parse('stop_sequence'), StopReason.endOfTurn);
      expect(StopReason.parse('max_tokens'), StopReason.outputLimit);
      expect(StopReason.parse('refusal'), StopReason.contentFilter);
    });

    test('maps Gemini finishReason values case-insensitively', () {
      expect(StopReason.parse('STOP'), StopReason.endOfTurn);
      expect(StopReason.parse('MAX_TOKENS'), StopReason.outputLimit);
      expect(StopReason.parse('SAFETY'), StopReason.contentFilter);
      expect(StopReason.parse('PROHIBITED_CONTENT'), StopReason.contentFilter);
    });

    test('unknown or malformed values never claim toolUse', () {
      // 关键安全属性：识别不出来时必须是 unknown，绝不能被当成“模型想调工具”。
      expect(StopReason.parse(null), StopReason.unknown);
      expect(StopReason.parse(''), StopReason.unknown);
      expect(StopReason.parse('MALFORMED_FUNCTION_CALL'), StopReason.unknown);
      expect(StopReason.parse('something-new'), StopReason.unknown);
      expect(StopReason.parse('  Tool_Calls  '), StopReason.toolUse);
    });
  });

  group('OpenAiCompatibleProvider', () {
    test('captures finish_reason from a delta-empty final frame', () async {
      // 回归：带 finish_reason 的收尾帧 delta 为空，旧解析器会整帧丢弃，
      // 导致停因永远是 unknown。
      final dio = Dio()..httpClientAdapter = _SseAdapter('''
data: {"choices":[{"index":0,"delta":{"content":"hi"}}]}

data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]

''');
      final provider = OpenAiCompatibleProvider(config: _config, dio: dio);
      expect(
        await _stopReasonOf(provider.stream(_request('gpt-4o'))),
        StopReason.endOfTurn,
      );
    });

    test('reports outputLimit when a truncated frame carries tool_calls',
        () async {
      // 最危险的组合：参数被长度上限截断，却夹带 tool_calls。
      // 停因必须如实上报，Phase 1 的门禁据此拒绝执行。
      final dio = Dio()..httpClientAdapter = _SseAdapter('''
data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"delete_file","arguments":"{\\"path\\": \\"/tmp/x"}}]}}]}

data: {"choices":[{"index":0,"delta":{},"finish_reason":"length"}]}

data: [DONE]

''');
      final provider = OpenAiCompatibleProvider(config: _config, dio: dio);
      final events = await provider.stream(_request('gpt-4o')).toList();
      expect(events.whereType<CompletedEvent>().last.stopReason,
          StopReason.outputLimit);
      expect(events.whereType<ToolCallEvent>(), hasLength(1),
          reason: '调用仍然透出，但是否执行由上层按停因决定');
    });

    test('falls back to unknown when the stream never reports a reason',
        () async {
      final dio = Dio()..httpClientAdapter = _SseAdapter('''
data: {"choices":[{"index":0,"delta":{"content":"hi"}}]}

data: [DONE]

''');
      final provider = OpenAiCompatibleProvider(config: _config, dio: dio);
      expect(
        await _stopReasonOf(provider.stream(_request('gpt-4o'))),
        StopReason.unknown,
      );
    });
  });

  group('AnthropicProvider', () {
    test('reads stop_reason from message_delta', () async {
      final dio = Dio()..httpClientAdapter = _SseAdapter('''
data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":12}}

''');
      final provider = AnthropicProvider(config: _config, dio: dio);
      expect(
        await _stopReasonOf(provider.stream(_request('claude-sonnet-4-5'))),
        StopReason.toolUse,
      );
    });

    test('maps max_tokens to outputLimit', () async {
      final dio = Dio()..httpClientAdapter = _SseAdapter('''
data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"}}

''');
      final provider = AnthropicProvider(config: _config, dio: dio);
      expect(
        await _stopReasonOf(provider.stream(_request('claude-sonnet-4-5'))),
        StopReason.outputLimit,
      );
    });
  });

  group('GeminiProvider', () {
    test('reads finishReason from candidates', () async {
      final dio = Dio()..httpClientAdapter = _SseAdapter('''
data: {"candidates":[{"content":{"parts":[{"text":"ok"}]},"finishReason":"MAX_TOKENS"}]}

''');
      final provider = GeminiProvider(config: _config, dio: dio);
      expect(
        await _stopReasonOf(provider.stream(_request('gemini-2.5-pro'))),
        StopReason.outputLimit,
      );
    });

    test('maps STOP to endOfTurn', () async {
      final dio = Dio()..httpClientAdapter = _SseAdapter('''
data: {"candidates":[{"content":{"parts":[{"text":"ok"}]},"finishReason":"STOP"}]}

''');
      final provider = GeminiProvider(config: _config, dio: dio);
      expect(
        await _stopReasonOf(provider.stream(_request('gemini-2.5-pro'))),
        StopReason.endOfTurn,
      );
    });

    test('malformed function call stays unknown so tools are not executed',
        () async {
      final dio = Dio()..httpClientAdapter = _SseAdapter('''
data: {"candidates":[{"finishReason":"MALFORMED_FUNCTION_CALL"}]}

''');
      final provider = GeminiProvider(config: _config, dio: dio);
      expect(
        await _stopReasonOf(provider.stream(_request('gemini-2.5-pro'))),
        StopReason.unknown,
      );
    });
  });

  test('CompletedEvent defaults to unknown for providers that omit it', () {
    // DemoProvider 等不上报停因的实现必须落在保守默认值上。
    expect(const CompletedEvent().stopReason, StopReason.unknown);
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
