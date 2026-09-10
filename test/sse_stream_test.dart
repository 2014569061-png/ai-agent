import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/providers/openai_compatible_provider.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/infrastructure/providers/sse_decoder.dart';

/// SSE 流式解析端到端测试：本地 HttpServer 模拟 OpenAI 兼容上游，
/// 覆盖文本增量 / 推理增量 / 跨分片工具调用拼装 / usage 统计。
void main() {
  test('openai-compatible provider parses streamed SSE end to end', () async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.bufferOutput = false;
      void chunk(String data) => request.response.write(data);
      chunk('data: {"choices":[{"delta":{"content":"你"}}]}\n\n');
      await request.response.flush();
      chunk('data: {"choices":[{"delta":{"content":"好"}}]}\n\n');
      await request.response.flush();
      chunk('data: {"choices":[{"delta":{"reasoning_content":"思考中"}}]}\n\n');
      await request.response.flush();
      chunk('data: {"choices":[{"delta":{"tool_calls":[{"index":0,'
          '"id":"call-1","type":"function",'
          '"function":{"name":"calculator","arguments":"{\\"a\\":"}}]}}]}\n\n');
      await request.response.flush();
      chunk('data: {"choices":[{"delta":{"tool_calls":[{"index":0,'
          '"function":{"arguments":"1,\\"b\\":2}"}}]}}]}\n\n');
      await request.response.flush();
      chunk('data: {"choices":[{"delta":{}}],'
          '"usage":{"prompt_tokens":11,"completion_tokens":7}}\n\n');
      await request.response.flush();
      chunk('data: [DONE]\n\n');
      await request.response.close();
    });

    final provider = OpenAiCompatibleProvider(
      config: ProviderConfig(
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        model: 'test-model',
        apiKey: 'test',
      ),
    );

    final text = StringBuffer();
    final reasoning = StringBuffer();
    ToolCall? call;
    var promptTokens = 0;
    var completionTokens = 0;
    await for (final event in provider.stream(UnifiedRequest(
      model: 'test-model',
      messages: [
        ChatMessage(role: MessageRole.user, parts: [MessagePart.text('hi')])
      ],
    ))) {
      if (event is TextDeltaEvent) text.write(event.text);
      if (event is ReasoningDeltaEvent) reasoning.write(event.text);
      if (event is ToolCallEvent) call = event.call;
      if (event is UsageEvent) {
        promptTokens = event.promptTokens;
        completionTokens = event.completionTokens;
      }
    }

    expect(text.toString(), '你好');
    expect(reasoning.toString(), '思考中');
    expect(call, isNotNull);
    expect(call!.id, 'call-1');
    expect(call.name, 'calculator');
    expect(call.arguments, {'a': 1, 'b': 2});
    expect(promptTokens, 11);
    expect(completionTokens, 7);
  });

  test('malformed SSE lines are skipped instead of breaking the stream',
      () async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.bufferOutput = false;
      request.response.write('data: {broken json\n\n');
      await request.response.flush();
      request.response.write('event: ping\n\n');
      await request.response.flush();
      request.response
          .write('data: {"choices":[{"delta":{"content":"ok"}}]}\n\n');
      await request.response.flush();
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });

    final provider = OpenAiCompatibleProvider(
      config: ProviderConfig(
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        model: 'test-model',
        apiKey: 'test',
      ),
    );

    final text = StringBuffer();
    await for (final event in provider.stream(UnifiedRequest(
      model: 'test-model',
      messages: [
        ChatMessage(role: MessageRole.user, parts: [MessagePart.text('hi')])
      ],
    ))) {
      if (event is TextDeltaEvent) text.write(event.text);
    }
    expect(text.toString(), 'ok');
  });

  test('SSE decoder preserves UTF-8 characters split across network chunks',
      () {
    final source = utf8.encode(
        'data: {"choices":[{"delta":{"content":"你好"}}]}\r\n\r\ndata: [DONE]\r\n\r\n');
    final split =
        utf8.encode('data: {"choices":[{"delta":{"content":"').length + 1;
    final decoder = SseDecoder();
    final payloads = <String>[
      ...decoder.add(source.sublist(0, split)),
      ...decoder.add(source.sublist(split)),
      ...decoder.close(),
    ];

    expect(payloads, hasLength(2));
    expect(payloads.first, contains('你好'));
    expect(payloads.last, '[DONE]');
  });
}
