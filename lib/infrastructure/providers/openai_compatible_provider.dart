import 'dart:convert';

import 'package:dio/dio.dart';

import '../../domain/models.dart';
import 'http_client.dart';
import 'provider_config.dart';
import 'llm_provider.dart';
import 'sse_decoder.dart';

class OpenAiCompatibleProvider implements LlmProvider {
  OpenAiCompatibleProvider({required this.config, Dio? dio})
      : _dio = dio ?? buildHttpClient();

  final ProviderConfig config;
  final Dio _dio;

  bool _supportsReasoning(String model) {
    final lower = model.toLowerCase();
    return lower.startsWith('o1') ||
        lower.startsWith('o3') ||
        lower.startsWith('o4') ||
        lower.contains('reasoning') ||
        lower.contains('deepseek-r1');
  }

  Future<String?> testConnection() async {
    try {
      final response = await _dio.get<dynamic>(
        '${config.baseUrl.replaceAll(RegExp(r'/$'), '')}/models',
        options: Options(headers: {'Authorization': 'Bearer ${config.apiKey}'}),
      );
      if (response.statusCode != 200) {
        return '模型列表接口返回 HTTP ${response.statusCode}';
      }

      // /models 正常不代表实际聊天接口可用；继续执行最小聊天探测。
      final chatResponse = await _dio.post<dynamic>(
        '${config.baseUrl.replaceAll(RegExp(r'/$'), '')}/chat/completions',
        data: {
          'model': config.model,
          'messages': [
            {'role': 'user', 'content': 'ping'},
          ],
          'stream': false,
          'max_tokens': 1,
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
    final response = await _dio.get<dynamic>(
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
    final payload = {
      'model': request.model,
      'messages': request.messages.map(toProviderMessage).toList(),
      'temperature': request.temperature,
      'max_tokens': request.maxTokens,
      'top_p': request.topP,
      'stream': true,
      if (request.tools.isNotEmpty)
        'tools': request.tools.map((tool) => tool.toOpenAiSchema()).toList(),
      // 思考程度：仅 o1/o3/GPT-5 等推理模型支持；其他模型会忽略或 400。
      if (_supportsReasoning(request.model) &&
          request.reasoningEffort != ReasoningEffort.off)
        'reasoning_effort': request.reasoningEffort.name,
    };

    try {
      final response = await _dio.post<ResponseBody>(
        '${config.baseUrl.replaceAll(RegExp(r'/$'), '')}/chat/completions',
        data: payload,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Authorization': 'Bearer ${config.apiKey}',
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          },
        ),
      );

      final stream = response.data?.stream;
      if (stream == null) {
        yield const ProviderErrorEvent(
          'Provider 返回了空响应',
          failureKind: 'protocol',
        );
        return;
      }
      final sse = SseDecoder();
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

      await for (final chunk in stream) {
        for (final data in sse.add(chunk)) {
          final parsed = _parseSseData(data);
          if (parsed == null) continue;
          if (parsed.text != null && parsed.text!.isNotEmpty) {
            yield TextDeltaEvent(parsed.text!);
          }
          if (parsed.reasoning != null && parsed.reasoning!.isNotEmpty) {
            yield ReasoningDeltaEvent(parsed.reasoning!);
          }
          collect(parsed);
          noteStop(parsed);
          if (parsed.usage != null) yield parsed.usage!;
        }
      }
      for (final data in sse.close()) {
        final parsed = _parseSseData(data);
        if (parsed == null) continue;
        if (parsed.text != null && parsed.text!.isNotEmpty) {
          yield TextDeltaEvent(parsed.text!);
        }
        if (parsed.reasoning != null && parsed.reasoning!.isNotEmpty) {
          yield ReasoningDeltaEvent(parsed.reasoning!);
        }
        collect(parsed);
        noteStop(parsed);
        if (parsed.usage != null) yield parsed.usage!;
      }
      for (final accumulator in toolAccumulators.values) {
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
        yield ToolCallEvent(ToolCall(
          id: accumulator.id ?? 'streamed-tool-call',
          name: accumulator.name ?? '',
          arguments: arguments,
        ));
      }
      yield CompletedEvent(stopReason: stopReason);
    } on DioException catch (error) {
      // 主动取消时静默结束，避免把"已取消"渲染成错误提示。
      if (error.type == DioExceptionType.cancel) return;
      final status = error.response?.statusCode;
      final detail = await _readResponseDetail(error.response?.data);
      final message = [
        if (status != null) 'HTTP $status',
        if (detail.isNotEmpty) detail else error.message ?? '网络请求失败',
      ].join(': ');
      yield ProviderErrorEvent(
        message,
        statusCode: status,
        failureKind: error.type.name,
      );
    } catch (error) {
      yield ProviderErrorEvent(
        error.toString(),
        failureKind: error.runtimeType.toString(),
      );
    }
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
          usage: UsageEvent(
            promptTokens: (usage['prompt_tokens'] as num?)?.toInt() ?? 0,
            completionTokens:
                (usage['completion_tokens'] as num?)?.toInt() ?? 0,
            cachedTokens: ((usage['prompt_tokens_details']
                        as Map<String, dynamic>?)?['cached_tokens'] as num?)
                    ?.toInt() ??
                (usage['cached_tokens'] as num?)?.toInt() ??
                0,
          ),
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
