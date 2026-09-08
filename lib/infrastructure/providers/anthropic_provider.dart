import 'dart:convert';

import 'package:dio/dio.dart';

import '../../domain/models.dart';
import 'http_client.dart';
import 'llm_provider.dart';
import 'provider_config.dart';
import 'sse_decoder.dart';

/// Anthropic Messages API 原生适配器。
///
/// 与 OpenAI 兼容协议不同：system 为顶层字段、content 为分块列表、
/// 工具结果为 `tool_result` 块、认证用 `x-api-key` 头。流式解析按
/// `message_start / content_block_start / content_block_delta / message_delta`
/// 事件类型累积文本与工具调用。
class AnthropicProvider implements LlmProvider {
  AnthropicProvider({required this.config, Dio? dio})
      : _dio = dio ?? buildHttpClient();

  static const _apiVersion = '2023-06-01';
  final ProviderConfig config;
  final Dio _dio;

  String get _endpoint =>
      '${config.baseUrl.replaceAll(RegExp(r'/$'), '')}/v1/messages';

  Map<String, dynamic> get _headers => {
        'x-api-key': config.apiKey,
        'anthropic-version': _apiVersion,
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      };

  Future<String?> testConnection() async {
    try {
      final response = await _dio.get<dynamic>(
        '${config.baseUrl.replaceAll(RegExp(r'/$'), '')}/v1/models',
        options: Options(headers: _headers),
      );
      if (response.statusCode == 200) return null;
      return '服务返回 HTTP ${response.statusCode}';
    } on DioException catch (error) {
      final detail = error.response?.data?.toString();
      return detail?.isNotEmpty == true ? detail : (error.message ?? '网络请求失败');
    } catch (error) {
      return error.toString();
    }
  }

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    String? system;
    final messages = <Map<String, dynamic>>[];
    for (final message in request.messages) {
      if (message.role == MessageRole.system) {
        system = message.text;
      } else {
        messages.add(toAnthropicMessage(message));
      }
    }

    // 思考档位 → Anthropic thinking.budget_tokens。低=2048, 中=8192, 高=16384。
    final thinking = _buildThinking(request.reasoningEffort);

    final payload = {
      'model': request.model,
      'max_tokens': request.maxTokens,
      // Anthropic rejects temperature/top_p when extended thinking is enabled.
      if (thinking == null) ...{
        'temperature': request.temperature,
        'top_p': request.topP,
      },
      'stream': true,
      if (thinking != null) 'thinking': thinking,
      if (system != null && system.trim().isNotEmpty) 'system': system.trim(),
      'messages': messages,
      if (request.tools.isNotEmpty)
        'tools': request.tools.map(toAnthropicTool).toList(),
    };

    try {
      final response = await _dio.post<ResponseBody>(
        _endpoint,
        data: payload,
        cancelToken: cancelToken,
        options: Options(responseType: ResponseType.stream, headers: _headers),
      );
      final stream = response.data?.stream;
      if (stream == null) {
        yield const ProviderErrorEvent('Provider 返回了空响应');
        return;
      }

      final sse = SseDecoder();
      final toolAccumulators = <int, _AnthropicToolAcc>{};
      var inputTokens = 0;
      var cacheCreationTokens = 0;
      var cacheReadTokens = 0;
      var outputTokens = 0;

      void updateUsage(Map<String, dynamic> usage) {
        final input = _asInt(usage['input_tokens']);
        if (input != null) inputTokens = input;
        final cacheCreation = _asInt(usage['cache_creation_input_tokens']);
        if (cacheCreation != null) cacheCreationTokens = cacheCreation;
        final cacheRead = _asInt(usage['cache_read_input_tokens']);
        if (cacheRead != null) cacheReadTokens = cacheRead;
        final output = _asInt(usage['output_tokens']);
        if (output != null) outputTokens = output;
      }

      await for (final chunk in stream) {
        for (final data in sse.add(chunk)) {
          final json = _parseSseData(data);
          if (json == null) continue;
          final type = json['type'] as String?;
          if (type == 'message_start') {
            final message =
                json['message'] as Map<String, dynamic>? ?? const {};
            final usage = message['usage'] as Map<String, dynamic>? ?? const {};
            updateUsage(usage);
          } else if (type == 'content_block_start') {
            final block =
                json['content_block'] as Map<String, dynamic>? ?? const {};
            if (block['type'] == 'tool_use') {
              final index = json['index'] as int? ?? 0;
              toolAccumulators[index] = _AnthropicToolAcc(
                id: block['id'] as String?,
                name: block['name'] as String?,
              );
            }
          } else if (type == 'content_block_delta') {
            final delta = json['delta'] as Map<String, dynamic>? ?? const {};
            final index = json['index'] as int? ?? 0;
            if (delta['type'] == 'text_delta') {
              final text = delta['text'] as String? ?? '';
              if (text.isNotEmpty) yield TextDeltaEvent(text);
            } else if (delta['type'] == 'thinking_delta') {
              final thinking = delta['thinking'] as String? ?? '';
              if (thinking.isNotEmpty) yield ReasoningDeltaEvent(thinking);
            } else if (delta['type'] == 'input_json_delta') {
              toolAccumulators
                  .putIfAbsent(index, _AnthropicToolAcc.new)
                  .arguments
                  .write(delta['partial_json'] ?? '');
            }
          } else if (type == 'message_delta') {
            final usage = json['usage'] as Map<String, dynamic>? ?? const {};
            updateUsage(usage);
          }
        }
      }
      for (final data in sse.close()) {
        final trailing = _parseSseData(data);
        if (trailing != null && trailing['type'] == 'message_delta') {
          final usage = trailing['usage'] as Map<String, dynamic>? ?? const {};
          updateUsage(usage);
        }
      }

      final sortedIndexes = toolAccumulators.keys.toList()..sort();
      for (final index in sortedIndexes) {
        final acc = toolAccumulators[index]!;
        final rawArgs = acc.arguments.toString();
        Map<String, dynamic> args = const {};
        try {
          final decoded = jsonDecode(rawArgs.isEmpty ? '{}' : rawArgs);
          if (decoded is Map<String, dynamic>) args = decoded;
        } catch (_) {
          // 参数不完整时保持空对象
        }
        yield ToolCallEvent(ToolCall(
          id: acc.id ?? 'anthropic-tool-$index',
          name: acc.name ?? '',
          arguments: args,
        ));
      }
      yield UsageEvent(
          promptTokens: inputTokens + cacheCreationTokens + cacheReadTokens,
          completionTokens: outputTokens,
          cachedTokens: cacheReadTokens);
      yield const CompletedEvent();
    } on DioException catch (error) {
      // 主动取消时静默结束。
      if (error.type == DioExceptionType.cancel) return;
      final message =
          error.response?.data?.toString() ?? error.message ?? '网络请求失败';
      yield ProviderErrorEvent(message);
    } catch (error) {
      yield ProviderErrorEvent(error.toString());
    }
  }

  /// 将统一消息转换为 Anthropic Messages API 的 message 结构。
  Map<String, dynamic> toAnthropicMessage(ChatMessage message) {
    if (message.role == MessageRole.tool) {
      return {
        'role': 'user',
        'content': [
          {
            'type': 'tool_result',
            'tool_use_id': message.toolCallId,
            'content': message.text
          },
        ],
      };
    }
    if (message.role == MessageRole.assistant) {
      final blocks = <Map<String, dynamic>>[];
      if (message.text.isNotEmpty) {
        blocks.add({'type': 'text', 'text': message.text});
      }
      for (final call in message.toolCalls) {
        blocks.add({
          'type': 'tool_use',
          'id': call.id,
          'name': call.name,
          'input': call.arguments
        });
      }
      return {
        'role': 'assistant',
        'content': blocks.isEmpty
            ? [
                const {'type': 'text', 'text': ''}
              ]
            : blocks,
      };
    }
    final content = <Map<String, dynamic>>[];
    for (final part in message.parts) {
      if (part.type == 'image') {
        content.add({
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': part.mimeType ?? 'image/png',
            'data': _stripDataUrl(part.value),
          },
        });
      } else {
        content.add({'type': 'text', 'text': part.value});
      }
    }
    return {
      'role': 'user',
      'content': content.isEmpty
          ? [
              const {'type': 'text', 'text': ''}
            ]
          : content,
    };
  }

  Map<String, dynamic> toAnthropicTool(UnifiedTool tool) => {
        'name': tool.name,
        'description': tool.description,
        'input_schema': tool.parametersSchema,
      };

  String _stripDataUrl(String value) {
    final comma = value.indexOf(',');
    if (value.startsWith('data:') && comma >= 0) {
      return value.substring(comma + 1);
    }
    return value;
  }

  Map<String, dynamic>? _parseSseData(String data) {
    data = data.trim();
    if (data.isEmpty || data == '[DONE]') return null;
    try {
      return jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static int? _asInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value');

  /// 把 ReasoningEffort 映射为 Anthropic Messages API 的 `thinking` 块。
  /// off 时返回 null（调用方不传该字段，保持默认行为）。
  static Map<String, dynamic>? _buildThinking(ReasoningEffort effort) {
    switch (effort) {
      case ReasoningEffort.off:
        return null;
      case ReasoningEffort.low:
        return {'type': 'enabled', 'budget_tokens': 2048};
      case ReasoningEffort.medium:
        return {'type': 'enabled', 'budget_tokens': 8192};
      case ReasoningEffort.high:
        return {'type': 'enabled', 'budget_tokens': 16384};
    }
  }
}

class _AnthropicToolAcc {
  _AnthropicToolAcc({this.id, this.name});
  String? id;
  String? name;
  final arguments = StringBuffer();
}
