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
          cachedTokens: cacheReadTokens,
          cacheWriteTokens: cacheCreationTokens,
          // Anthropic 的 usage 总是携带 cache_read/cache_creation 字段
          //（未命中时为 0），因此 0 命中可以如实解读为“未命中”。
          cacheStatsReported: true));
      events.add(CompletedEvent(stopReason: stopReason));
      return events;
    }

    try {
      // await for 而非 yield*：yield* 会把内层错误直接转发给消费者，
      // 外层 catch 拦不到，DioException 就无法转换成 ProviderErrorEvent。
      await for (final event in runStreaming(
        url: _endpoint,
        payload: payload,
        headers: _headers,
        cancelToken: cancelToken,
        onFrame: onFrame,
        finalize: finalize,
      )) {
        yield event;
      }
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

  /// 构建 Anthropic 请求体并布置前缀缓存断点。
  ///
  /// Anthropic 按 `tools → system → messages` 的层级做前缀缓存，缓存只覆盖
  /// 到最后一个 `cache_control` 断点为止。只给 system 打断点时，多步 Agent
  /// 循环里不断增长的消息历史永远无法复用，这是 Claude 通道成本偏高的主要
  /// 原因。这里布置 3 个断点（上限 4）：工具定义末尾、system 末尾、最后一条
  /// 消息的末尾，实现会话增量缓存——消息只追加不修改，下一轮请求即可整体
  /// 复用本轮写入的前缀。
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

    final toolSchemas = request.tools.map(toAnthropicTool).toList();
    if (toolSchemas.isNotEmpty) {
      toolSchemas.last['cache_control'] = const {'type': 'ephemeral'};
    }
    _markTrailingCacheBreakpoint(messages);

    // Older Claude 4.5 models use manual extended thinking.  Newer Claude
    // 4.6+ / 5 models use adaptive thinking and reject `type: enabled`.
    final thinking = _buildThinking(request.model,
        request.reasoningEffort, maxTokens: request.maxTokens);
    final isAdaptiveThinking = thinking?['type'] == 'adaptive';
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
      if (isAdaptiveThinking && request.reasoningEffort != ReasoningEffort.auto)
        'output_config': {'effort': request.reasoningEffort.name},
      if (system != null)
        'system': [
          {
            'type': 'text',
            'text': system,
            'cache_control': {'type': 'ephemeral'},
          },
        ],
      'messages': messages,
      if (toolSchemas.isNotEmpty) 'tools': toolSchemas,
    };
  }

  /// 给最后一条消息的最后一个 content block 打缓存断点。工具结果块
  /// （tool_result/tool_use）与普通文本块都支持 `cache_control`。
  static void _markTrailingCacheBreakpoint(
      List<Map<String, dynamic>> messages) {
    for (final message in messages.reversed) {
      final content = message['content'];
      if (content is List && content.isNotEmpty) {
        final block = content.last;
        if (block is Map<String, dynamic>) {
          block['cache_control'] = const {'type': 'ephemeral'};
          return;
        }
      }
    }
  }

  /// 将统一消息转换为 Anthropic Messages API 的 message 结构。
  ///
  /// content block 必须显式声明为 `Map<String, dynamic>`：纯文本块会被推断
  /// 成 `Map<String, String>`，尾部分级缓存断点需要往块里写 `cache_control`
  /// （Map 值），`Map<String, String>` 会直接抛类型错误。
  Map<String, dynamic> toAnthropicMessage(ChatMessage message) {
    if (message.role == MessageRole.tool) {
      return {
        'role': 'user',
        'content': [
          <String, dynamic>{
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
        blocks.add(<String, dynamic>{'type': 'text', 'text': message.text});
      }
      for (final call in message.toolCalls) {
        blocks.add(<String, dynamic>{
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
                <String, dynamic>{'type': 'text', 'text': ''}
              ]
            : blocks,
      };
    }
    final content = <Map<String, dynamic>>[];
    for (final part in message.parts) {
      if (part.type == 'image') {
        content.add(<String, dynamic>{
          'type': 'image',
          'source': <String, dynamic>{
            'type': 'base64',
            'media_type': part.mimeType ?? 'image/png',
            'data': _stripDataUrl(part.value),
          },
        });
      } else {
        content.add(<String, dynamic>{'type': 'text', 'text': part.value});
      }
    }
    return {
      'role': 'user',
      'content': content.isEmpty
          ? [
              <String, dynamic>{'type': 'text', 'text': ''}
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

  /// Maps a reasoning preference to Anthropic's `thinking` block.
  ///
  /// The budget is capped below [maxTokens] because Anthropic rejects a
  /// request when the two values are equal or the budget is larger.
  static Map<String, dynamic>? _buildThinking(String model,
      ReasoningEffort effort,
      {required int maxTokens}) {
    if (effort == ReasoningEffort.auto ||
        effort == ReasoningEffort.off ||
        maxTokens <= 1 ||
        !_supportsThinking(model)) {
      return null;
    }
    if (_usesAdaptiveThinking(model)) {
      return const {'type': 'adaptive'};
    }
    // Anthropic requires manual thinking budgets to be >= 1024 and strictly
    // less than max_tokens.  If the caller leaves too little output room,
    // omit thinking instead of generating a guaranteed 400 request.
    if (maxTokens <= 1024) {
      return null;
    }
    int budget;
    switch (effort) {
      case ReasoningEffort.low:
        budget = 2048;
        break;
      case ReasoningEffort.medium:
        budget = 8192;
        break;
      case ReasoningEffort.high:
        budget = 16384;
        break;
      case ReasoningEffort.off:
      case ReasoningEffort.auto:
        return null;
    }
    budget = budget.clamp(1024, maxTokens - 1).toInt();
    return {
      'type': 'enabled',
      'budget_tokens': budget,
    };
  }

  static bool _supportsThinking(String model) {
    final normalized = model.toLowerCase().replaceAll('.', '-').replaceAll('_', '-');
    return RegExp(r'claude-(?:opus|sonnet|haiku)-(?:4|5)(?:-|$)')
        .hasMatch(normalized);
  }

  static bool _usesAdaptiveThinking(String model) {
    final normalized = model.toLowerCase().replaceAll('.', '-').replaceAll('_', '-');
    return normalized.contains('4-6') ||
        normalized.contains('4-7') ||
        normalized.contains('4-8') ||
        RegExp(r'claude-(?:opus|sonnet|haiku)-5(?:-|$)')
            .hasMatch(normalized);
  }
}

class _AnthropicToolAcc {
  _AnthropicToolAcc({this.id, this.name});
  String? id;
  String? name;
  final arguments = StringBuffer();
}
