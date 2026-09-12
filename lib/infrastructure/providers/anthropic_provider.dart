import 'dart:convert';

import 'package:dio/dio.dart';

import '../../domain/models.dart';
import 'http_client.dart';
import 'streaming_provider_base.dart';
import 'provider_config.dart';

/// Anthropic Messages API 原生适配器。
///
/// 与 OpenAI 兼容协议不同：system 为顶层字段、content 为分块列表、
/// 工具结果为 `tool_result` 块、认证用 `x-api-key` 头。流式解析按
/// `message_start / content_block_start / content_block_delta / message_delta`
/// 事件类型累积文本与工具调用。
class AnthropicProvider extends StreamingProviderBase {
  AnthropicProvider({required this.config, Dio? dio})
      : super(dio ?? buildHttpClient());

  static const _apiVersion = '2023-06-01';
  final ProviderConfig config;

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
      final response = await dio.get<dynamic>(
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
    final payload = buildRequestPayload(request, stream: true);

    final toolAccumulators = <int, _AnthropicToolAcc>{};
    var inputTokens = 0;
    var cacheCreationTokens = 0;
    var cacheReadTokens = 0;
    var outputTokens = 0;
    var stopReason = StopReason.unknown;

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

    List<UnifiedEvent> onFrame(String data) {
      final json = _parseSseData(data);
      if (json == null) return const [];
      final events = <UnifiedEvent>[];
      final type = json['type'] as String?;
      if (type == 'message_start') {
        final message = json['message'] as Map<String, dynamic>? ?? const {};
        updateUsage(message['usage'] as Map<String, dynamic>? ?? const {});
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
          if (text.isNotEmpty) events.add(TextDeltaEvent(text));
        } else if (delta['type'] == 'thinking_delta') {
          final thinking = delta['thinking'] as String? ?? '';
          if (thinking.isNotEmpty) events.add(ReasoningDeltaEvent(thinking));
        } else if (delta['type'] == 'input_json_delta') {
          toolAccumulators
              .putIfAbsent(index, _AnthropicToolAcc.new)
              .arguments
              .write(delta['partial_json'] ?? '');
        }
      } else if (type == 'message_delta') {
        updateUsage(json['usage'] as Map<String, dynamic>? ?? const {});
        // stop_reason 在 message_delta.delta 里，是能否执行工具调用的判据。
        final delta = json['delta'] as Map<String, dynamic>? ?? const {};
        final raw = delta['stop_reason'] as String?;
        if (raw != null && raw.isNotEmpty) {
          stopReason = StopReason.parse(raw);
        }
      }
      return events;
    }

    List<UnifiedEvent> finalize() {
      final events = <UnifiedEvent>[];
      final sortedIndexes = toolAccumulators.keys.toList()..sort();
      for (final index in sortedIndexes) {
        final acc = toolAccumulators[index]!;
        final rawArgs = acc.arguments.toString();
        Map<String, dynamic> args;
        try {
          final decoded = jsonDecode(rawArgs.isEmpty ? '{}' : rawArgs);
          args = decoded is Map<String, dynamic>
              ? decoded
              : {'_unparsed': rawArgs};
        } catch (_) {
          // 参数不完整时必须交给 AgentExecutor 拦截，不能降级为空对象后误执行。
          args = {'_unparsed': rawArgs};
        }
        events.add(ToolCallEvent(ToolCall(
          id: acc.id ?? 'anthropic-tool-$index',
          name: acc.name ?? '',
          arguments: args,
        )));
      }
      events.add(UsageEvent(
          promptTokens: inputTokens + cacheCreationTokens + cacheReadTokens,
          completionTokens: outputTokens,
          cachedTokens: cacheReadTokens));
      events.add(CompletedEvent(stopReason: stopReason));
      return events;
    }

    try {
      yield* runStreaming(
        url: _endpoint,
        payload: payload,
        headers: _headers,
        cancelToken: cancelToken,
        onFrame: onFrame,
        finalize: finalize,
      );
    } on DioException catch (error) {
      // 主动取消时静默结束。
      if (error.type == DioExceptionType.cancel) return;
      final message =
          error.response?.data?.toString() ?? error.message ?? '网络请求失败';
      yield ProviderErrorEvent(
        message,
        statusCode: error.response?.statusCode,
        failureKind: error.type.name,
      );
    } catch (error) {
      yield ProviderErrorEvent(
        error.toString(),
        failureKind: error.runtimeType.toString(),
      );
    }
  }

  /// 构建 Anthropic 请求体并给稳定的 system 提示词打上缓存边界。
  ///
  /// system 使用 content block 而不是裸字符串，既兼容普通请求，也让
  /// Anthropic 能复用长会话前缀；模型消息本身仍按原顺序逐条发送。
  Map<String, dynamic> buildRequestPayload(UnifiedRequest request,
      {bool stream = true}) {
    String? system;
    final messages = <Map<String, dynamic>>[];
    for (final message in request.messages) {
      if (message.role == MessageRole.system) {
        final text = message.text.trim();
        if (text.isNotEmpty) {
          system = system == null ? text : '$system\n$text';
        }
      } else {
        messages.add(toAnthropicMessage(message));
      }
    }

    // 思考档位 → Anthropic thinking.budget_tokens。低=2048, 中=8192, 高=16384。
    final thinking = _buildThinking(request.reasoningEffort);
    return {
      'model': request.model,
      'max_tokens': request.maxTokens,
      // Anthropic rejects temperature/top_p when extended thinking is enabled.
      if (thinking == null) ...{
        'temperature': request.temperature,
        'top_p': request.topP,
      },
      'stream': stream,
      if (thinking != null) 'thinking': thinking,
      if (system != null)
        'system': [
          {
            'type': 'text',
            'text': system,
            'cache_control': {'type': 'ephemeral'},
          },
        ],
      'messages': messages,
      if (request.tools.isNotEmpty)
        'tools': request.tools.map(toAnthropicTool).toList(),
    };
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
