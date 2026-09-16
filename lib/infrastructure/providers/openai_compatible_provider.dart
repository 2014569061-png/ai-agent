import 'dart:convert';

import 'package:dio/dio.dart';

import '../../domain/models.dart';
import '../../domain/unique_id.dart';
import 'http_client.dart';
import 'provider_config.dart';
import 'streaming_provider_base.dart';

class OpenAiCompatibleProvider extends StreamingProviderBase {
  OpenAiCompatibleProvider({required this.config, Dio? dio})
      : super(dio ?? buildHttpClient());

  final ProviderConfig config;

  /// 是否发送 `stream_options.include_usage`。流式请求不显式要求时，多数
  /// OpenAI 兼容服务不会返回收尾 usage chunk，缓存命中统计就永远拿不到。
  /// 个别严格按旧规范实现的服务会对未知字段返回 400，此时置为 false 并
  /// 在本次请求内降级重试（实例按运行期创建，同一 Provider 后续步骤不再
  /// 重复踩坑）。
  bool _streamOptionsSupported = true;

  bool _supportsReasoning(String model) {
    final lower = model.toLowerCase();
    return lower.startsWith('o1') ||
        lower.startsWith('o3') ||
        lower.startsWith('o4') ||
        lower.startsWith('gpt-5') ||
        lower.contains('reasoning') ||
        lower.contains('deepseek-r1');
  }

  Future<String?> testConnection() async {
    try {
      final response = await dio.get<dynamic>(
        '${config.baseUrl.replaceAll(RegExp(r'/$'), '')}/models',
        options: Options(headers: {'Authorization': 'Bearer ${config.apiKey}'}),
      );
      if (response.statusCode != 200) {
        return '模型列表接口返回 HTTP ${response.statusCode}';
      }

      // /models 正常不代表实际聊天接口可用；继续执行最小聊天探测。
      final chatResponse = await dio.post<dynamic>(
        '${config.baseUrl.replaceAll(RegExp(r'/$'), '')}/chat/completions',
        data: {
          'model': config.model,
          'messages': [
            {'role': 'user', 'content': 'ping'},
          ],
          'stream': false,
          _maxOutputTokenField(config.model): 1,
        },
        options: Options(headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
        }),
      );
      if (chatResponse.statusCode == 200) return null;
      return '聊天接口返回 HTTP ${chatResponse.statusCode}: ${chatResponse.data}';
    } on DioException catch (error) {
      final detail = error.response?.data?.toString();
      return detail?.isNotEmpty == true ? detail : (error.message ?? '网络请求失败');
    } catch (error) {
      return error.toString();
    }
  }

  Future<List<ModelInfo>> listModels() async {
    final response = await dio.get<dynamic>(
      '${config.baseUrl.replaceAll(RegExp(r'/$'), '')}/models',
      options: Options(headers: {'Authorization': 'Bearer ${config.apiKey}'}),
    );
    final data =
        response.data is Map<String, dynamic> ? response.data['data'] : null;
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final id = item['id'] as String? ?? '';
          final lower = id.toLowerCase();
          return ModelInfo(
            id: id,
            ownedBy: item['owned_by'] as String?,
            capabilities: ModelCapabilities(
              vision: lower.contains('vision') ||
                  lower.contains('4o') ||
                  lower.contains('gemini') ||
                  lower.contains('claude-3'),
              tools: !lower.contains('embedding') &&
                  !lower.contains('tts') &&
                  !lower.contains('whisper'),
            ),
          );
        })
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    var includeUsage = _streamOptionsSupported;

    final reasoningModel = _supportsReasoning(request.model);
    Map<String, dynamic> buildPayload() => {
          'model': request.model,
          'messages': request.messages.map(toProviderMessage).toList(),
          // o-series / GPT-5 style reasoning models use the newer output
          // limit field and reject sampling controls such as temperature.
          if (!reasoningModel) ...{
            'temperature': request.temperature,
            'top_p': request.topP,
            'max_tokens': request.maxTokens,
          } else
            _maxOutputTokenField(request.model): request.maxTokens,
          'stream': true,
          if (includeUsage) 'stream_options': {'include_usage': true},
          if (request.tools.isNotEmpty)
            'tools':
                request.tools.map((tool) => tool.toOpenAiSchema()).toList(),
          // 思考程度：仅 o1/o3/GPT-5 等推理模型支持；其他模型会忽略或 400。
          if (reasoningModel &&
              request.reasoningEffort != ReasoningEffort.off &&
              request.reasoningEffort != ReasoningEffort.auto)
            'reasoning_effort': request.reasoningEffort.name,
        };

    final toolAccumulators = <int, _ToolAccumulator>{};
    var nextToolIndex = 0;
    var stopReason = StopReason.unknown;
    // finish_reason 可能出现在任意一帧（含 delta 为空的收尾帧），逐帧记录，
    // 后到的覆盖先到的。
    void noteStop(_SseChunk parsed) {
      final raw = parsed.finishReason;
      if (raw != null && raw.isNotEmpty) {
        stopReason = StopReason.parse(raw);
      }
    }

    void collect(_SseChunk parsed) {
      for (final fragment in parsed.tools) {
        final index = fragment.index ?? nextToolIndex++;
        final accumulator =
            toolAccumulators.putIfAbsent(index, _ToolAccumulator.new);
        if (fragment.id != null) accumulator.id = fragment.id;
        if (fragment.name != null && fragment.name!.isNotEmpty) {
          accumulator.name = fragment.name;
        }
        if (fragment.arguments != null) {
          accumulator.arguments.write(fragment.arguments);
        }
      }
    }

    List<UnifiedEvent> onFrame(String data) {
      final parsed = _parseSseData(data);
      if (parsed == null) return const [];
      final events = <UnifiedEvent>[];
      if (parsed.text != null && parsed.text!.isNotEmpty) {
        events.add(TextDeltaEvent(parsed.text!));
      }
      if (parsed.reasoning != null && parsed.reasoning!.isNotEmpty) {
        events.add(ReasoningDeltaEvent(parsed.reasoning!));
      }
      collect(parsed);
      noteStop(parsed);
      if (parsed.usage != null) events.add(parsed.usage!);
      return events;
    }

    List<UnifiedEvent> finalize() {
      final events = <UnifiedEvent>[];
      toolAccumulators.forEach((index, accumulator) {
        final rawArguments = accumulator.arguments.toString();
        Map<String, dynamic> arguments;
        try {
          final decoded =
              jsonDecode(rawArguments.isEmpty ? '{}' : rawArguments);
          arguments = decoded is Map<String, dynamic> ? decoded : const {};
        } catch (_) {
          // 参数跨 chunk 分片（如转义符被切半）拼接后可能不合 JSON。
          // 单个工具解析失败不应中断整轮对话：降级保留原始参数交给上层处理。
          arguments = {'_unparsed': rawArguments};
        }
        events.add(ToolCallEvent(ToolCall(
          // 部分中转/兼容服务流式返回不携带 tool_call id。兜底 id 必须按
          // 调用唯一：执行层按 id 关联结果与活动行，固定值会让终端的失败
          // 结果覆盖同回合所有工具的展示（真实事故：skills_read 行显示
          // terminal 的“命令以退出码 1 结束”）。
          id: (accumulator.id != null && accumulator.id!.isNotEmpty)
              ? accumulator.id!
              : UniqueId.generate('call'),
          name: accumulator.name ?? '',
          arguments: arguments,
        )));
      });
      events.add(CompletedEvent(stopReason: stopReason));
      return events;
    }

    var attempt = 0;
    while (true) {
      attempt++;
      try {
        // 必须用 await for 驱动内层流：async* 里 `yield*` 会把内层错误
        // 直接转发给消费者，外层 try/catch 拦不到（探针验证过的 Dart
        // 语义），下面的 stream_options 降级重试和 ProviderErrorEvent
        // 转换就都不会发生。
        await for (final event in runStreaming(
          url:
              '${config.baseUrl.replaceAll(RegExp(r'/$'), '')}/chat/completions',
          payload: buildPayload(),
          headers: {
            'Authorization': 'Bearer ${config.apiKey}',
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          },
          cancelToken: cancelToken,
          onFrame: onFrame,
          finalize: finalize,
        )) {
          yield event;
        }
        return;
      } on DioException catch (error) {
        // 主动取消时静默结束，避免把"已取消"渲染成错误提示。
        if (error.type == DioExceptionType.cancel) return;
        final detail = await _readResponseDetail(error.response?.data);
        // 400 拒绝发生在建连阶段（尚未产出任何事件），去掉 stream_options
        // 重试一次不会造成已流出的内容重复。仅识别明确点名该字段的错误，
        // 避免把其他 400 也归因于此。
        if (attempt == 1 && _isStreamOptionsRejection(error, detail)) {
          _streamOptionsSupported = false;
          includeUsage = false;
          continue;
        }
        final status = error.response?.statusCode;
        final message = [
          if (status != null) 'HTTP $status',
          if (detail.isNotEmpty) detail else error.message ?? '网络请求失败',
        ].join(': ');
        yield ProviderErrorEvent(
          message,
          statusCode: status,
          failureKind: error.type.name,
        );
        return;
      } catch (error) {
        yield ProviderErrorEvent(
          error.toString(),
          failureKind: error.runtimeType.toString(),
        );
        return;
      }
    }
  }

  String _maxOutputTokenField(String model) =>
      _supportsReasoning(model) ? 'max_completion_tokens' : 'max_tokens';

  /// 识别“服务端不认识 stream_options/include_usage”类错误。严格按旧
  /// 规范实现的中转服务会以 400（部分用 422）拒绝未知字段。
  static bool _isStreamOptionsRejection(DioException error, String detail) {
    if (error.type != DioExceptionType.badResponse) return false;
    final status = error.response?.statusCode;
    if (status != null && status != 400 && status != 422) return false;
    final lower = detail.toLowerCase();
    return lower.contains('stream_options') || lower.contains('include_usage');
  }

  Future<String> _readResponseDetail(dynamic data) async {
    if (data == null) return '';
    if (data is ResponseBody) {
      try {
        final bytes = await data.stream.toList();
        return utf8.decode(bytes.expand((chunk) => chunk).toList(),
            allowMalformed: true);
      } catch (_) {
        return '';
      }
    }
    return data.toString();
  }

  /// Converts the unified message representation to OpenAI-compatible JSON.
  ///
  /// Keeping this conversion public makes the wire format independently
  /// testable without issuing a network request.
  Map<String, dynamic> toProviderMessage(ChatMessage message) {
    final hasMultimodal =
        message.parts.any((p) => p.type != 'text' && p.value.isNotEmpty);
    if (!hasMultimodal) {
      return {
        'role': message.role.name,
        'content': (message.toolCalls.isNotEmpty && message.text.isEmpty)
            ? null
            : message.text,
        if (message.toolCalls.isNotEmpty)
          'tool_calls': message.toolCalls
              .map((call) => {
                    'id': call.id,
                    'type': 'function',
                    'function': {
                      'name': call.name,
                      'arguments': jsonEncode(call.arguments),
                    },
                  })
              .toList(),
        if (message.toolCallId != null) 'tool_call_id': message.toolCallId,
      };
    }

    // 多模态内容：图片/音频/视频统一归一为 data URL（对齐 Anthropic/Gemini），
    // 避免上层因部分 provider 要求 base64 而行为不一致。文本统一由下方循环
    // 逐 part 输出，避免重复（message.text 会把非文本 part 折叠成 "[图片]"）。
    final content = <Map<String, dynamic>>[];
    for (final part in message.parts) {
      if (part.type == 'text') {
        if (part.value.isNotEmpty) {
          content.add({'type': 'text', 'text': part.value});
        }
        continue;
      }
      if (part.value.isEmpty) continue;
      if (part.type == 'image') {
        content.add({
          'type': 'image_url',
          'image_url': {
            'url': _toDataUrl(part.value, part.mimeType ?? 'image/png'),
          },
        });
      } else if (part.type == 'audio') {
        content.add({
          'type': 'input_audio',
          'input_audio': {
            'data': _stripDataUrl(part.value),
            'format': _audioFormat(part.mimeType),
          },
        });
      } else if (part.type == 'video') {
        // OpenAI 尚未开放视频输入；转成 base64 data URL 交给支持视频的上游。
        content.add({
          'type': 'video_url',
          'video_url': {
            'url': _toDataUrl(part.value, part.mimeType ?? 'video/mp4')
          },
        });
      } else {
        content.add({'type': 'text', 'text': part.value});
      }
    }
    return {
      'role': message.role.name,
      'content': content,
      if (message.toolCallId != null) 'tool_call_id': message.toolCallId,
    };
  }

  /// 把带 `data:<mime>;base64,` 前缀的 value 转成可直接交给上游的 data URL；
  /// 已是 http(s) 外链则原样返回。
  String _toDataUrl(String value, String mimeType) {
    if (value.startsWith('data:') ||
        value.startsWith('http://') ||
        value.startsWith('https://')) {
      return value;
    }
    return 'data:$mimeType;base64,$value';
  }

  /// 去掉 `data:<mime>;base64,` 前缀，返回纯 base64 载荷。
  String _stripDataUrl(String value) {
    final comma = value.indexOf(',');
    if (value.startsWith('data:') && comma != -1) {
      return value.substring(comma + 1);
    }
    return value;
  }

  /// 从 mime type 推断音频格式（OpenAI input_audio.format 仅支持 wav/mp3）。
  String _audioFormat(String? mimeType) {
    final mime = mimeType ?? '';
    if (mime.contains('wav')) return 'wav';
    return 'mp3';
  }

  /// 统一解析 OpenAI 兼容生态的各种缓存/推理统计字段：
  /// - OpenAI: `prompt_tokens_details.cached_tokens`
  /// - DeepSeek: `prompt_cache_hit_tokens` / `prompt_cache_miss_tokens`
  /// - Azure: `input_tokens_details.cached_tokens`
  /// - Anthropic 中转: `cache_read_input_tokens` / `cache_creation_input_tokens`
  /// - 部分中转: `cached_tokens`
  ///
  /// 字段缺失时 cachedTokens 记 0 且 [UsageEvent.cacheStatsReported] 为
  /// false，上层据此区分“Provider 没给缓存统计”与“真的未命中”，不能把
  /// 前者当命中率展示。
  static UsageEvent parseUsage(Map<String, dynamic> usage) {
    int? field(String key) {
      final value = usage[key];
      if (value is num) return value.toInt();
      return int.tryParse('$value');
    }

    int? nested(String mapKey, String valueKey) {
      final nestedMap = usage[mapKey];
      if (nestedMap is! Map) return null;
      final value = nestedMap[valueKey];
      if (value is num) return value.toInt();
      return int.tryParse('$value');
    }

    final hit = field('prompt_cache_hit_tokens');
    final miss = field('prompt_cache_miss_tokens');
    final cached = nested('prompt_tokens_details', 'cached_tokens') ??
        hit ??
        nested('input_tokens_details', 'cached_tokens') ??
        field('cache_read_input_tokens') ??
        field('cached_tokens');
    final cacheWrite = field('cache_creation_input_tokens');
    final reasoning = nested('completion_tokens_details', 'reasoning_tokens') ??
        field('reasoning_tokens');
    return UsageEvent(
      // DeepSeek 部分模型只回 hit/miss 对，不回 prompt_tokens 总数。
      promptTokens: field('prompt_tokens') ??
          ((hit != null && miss != null) ? hit + miss : 0),
      completionTokens: field('completion_tokens') ?? 0,
      cachedTokens: cached ?? 0,
      cacheWriteTokens: cacheWrite ?? 0,
      reasoningTokens: reasoning ?? 0,
      cacheStatsReported: cached != null || cacheWrite != null,
    );
  }

  _SseChunk? _parseSseData(String data) {
    data = data.trim();
    if (data == '[DONE]' || data.isEmpty) return null;
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final choices = json['choices'] as List<dynamic>? ?? const [];
      final first = choices.isEmpty
          ? const <String, dynamic>{}
          : choices.first as Map<String, dynamic>;
      final finishReason = first['finish_reason'] as String?;
      final usage = json['usage'];
      if (usage is Map<String, dynamic>) {
        return _SseChunk(
          finishReason: finishReason,
          usage: parseUsage(usage),
        );
      }
      if (choices.isEmpty) {
        return finishReason == null
            ? null
            : _SseChunk(finishReason: finishReason);
      }
      final delta = first['delta'] as Map<String, dynamic>? ?? const {};
      final content = delta['content'] as String?;
      // 推理模型的思考增量：DeepSeek-R1 用 reasoning_content，OpenAI o 系列部分用 reasoning。
      final reasoning = (delta['reasoning_content'] as String?) ??
          (delta['reasoning'] as String?);
      final toolCalls = delta['tool_calls'] as List<dynamic>?;
      if (toolCalls != null && toolCalls.isNotEmpty) {
        return _SseChunk(
          text: content,
          reasoning: reasoning,
          finishReason: finishReason,
          tools: toolCalls.map((item) {
            final tool = item as Map<String, dynamic>;
            final function =
                tool['function'] as Map<String, dynamic>? ?? const {};
            return _ToolFragment(
                index: tool['index'] as int?,
                id: tool['id'] as String?,
                name: function['name'] as String?,
                arguments: function['arguments'] as String?);
          }).toList(growable: false),
        );
      }
      if ((content != null && content.isNotEmpty) ||
          (reasoning != null && reasoning.isNotEmpty)) {
        return _SseChunk(
            text: content, reasoning: reasoning, finishReason: finishReason);
      }
      // 只剩结束原因的收尾帧。
      if (finishReason != null) return _SseChunk(finishReason: finishReason);
    } catch (_) {
      return null;
    }
    return null;
  }
}

class _SseChunk {
  const _SseChunk(
      {this.text,
      this.reasoning,
      this.tools = const [],
      this.usage,
      this.finishReason});

  final String? text;
  final String? reasoning;
  final List<_ToolFragment> tools;
  final UsageEvent? usage;

  /// 本帧携带的 finish_reason。它通常出现在 delta 为空的最后一帧，
  /// 必须单独取出，否则会被“无内容即忽略”的分支丢掉。
  final String? finishReason;
}

class _ToolFragment {
  const _ToolFragment({this.index, this.id, this.name, this.arguments});
  final int? index;
  final String? id;
  final String? name;
  final String? arguments;
}

class _ToolAccumulator {
  String? id;
  String? name;
  final arguments = StringBuffer();
}
