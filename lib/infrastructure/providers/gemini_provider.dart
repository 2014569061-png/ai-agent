import 'dart:convert';

import 'package:dio/dio.dart';

import '../../domain/models.dart';
import 'http_client.dart';
import 'streaming_provider_base.dart';
import 'provider_config.dart';

/// Google Gemini generateContent 原生适配器。
///
/// 与 OpenAI 不同：角色为 `user`/`model`，工具结果为 `functionResponse` 分块、
/// 认证走 `?key=` 查询参数、系统提示词为顶层 `systemInstruction`、图片用
/// `inlineData`。流式解析从 `candidates[].content.parts[]` 中取文本与函数调用。
class GeminiProvider extends StreamingProviderBase {
  GeminiProvider({required this.config, Dio? dio})
      : super(dio ?? buildHttpClient());

  final ProviderConfig config;

  String get _base => config.baseUrl.replaceAll(RegExp(r'/$'), '');

  Future<String?> testConnection() async {
    try {
      final response = await dio.get<dynamic>(
        '$_base/v1beta/models?pageSize=5&key=${Uri.encodeQueryComponent(config.apiKey)}',
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
    // 先收集 assistant 工具调用的 id → name 映射，供工具结果回填函数名。
    final toolNames = <String, String>{};
    for (final message in request.messages) {
      if (message.role == MessageRole.assistant) {
        for (final call in message.toolCalls) {
          toolNames[call.id] = call.name;
        }
      }
    }

    String? system;
    final contents = <Map<String, dynamic>>[];
    for (final message in request.messages) {
      if (message.role == MessageRole.system) {
        system = message.text;
      } else {
        contents.add(toGeminiMessage(message, toolNames));
      }
    }

    // 思考档位 → Gemini thinkingConfig.thinkingBudget。低=0, 中=8192, 高=32768。
    final thinkingBudget = _supportsThinking(request.model)
        ? _thinkingBudgetFor(request.reasoningEffort)
        : null;

    final payload = {
      'contents': contents,
      if (system != null && system.trim().isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': system.trim()}
          ]
        },
      'generationConfig': {
        'temperature': request.temperature,
        'maxOutputTokens': request.maxTokens,
        'topP': request.topP,
        if (thinkingBudget != null)
          'thinkingConfig': {'thinkingBudget': thinkingBudget},
      },
      if (request.tools.isNotEmpty)
        'tools': [
          {'functionDeclarations': request.tools.map(toGeminiTool).toList()},
        ],
    };

    final url =
        '$_base/v1beta/models/${Uri.encodeComponent(request.model)}:streamGenerateContent'
        '?alt=sse&key=${Uri.encodeQueryComponent(config.apiKey)}';

    final pendingCalls = <ToolCall>[];
    var promptTokens = 0;
    var completionTokens = 0;
    var cachedTokens = 0;
    var stopReason = StopReason.unknown;

    void updateUsage(Map<String, dynamic> usage) {
      final prompt = _asInt(usage['promptTokenCount']);
      if (prompt != null) promptTokens = prompt;
      final completion = _asInt(usage['candidatesTokenCount']);
      if (completion != null) completionTokens = completion;
      final cached = _asInt(usage['cachedContentTokenCount']) ??
          _asInt(usage['cached_content_token_count']);
      if (cached != null) cachedTokens = cached;
    }

    List<UnifiedEvent> onFrame(String data) {
      final json = _parseSseData(data);
      if (json == null) return const [];
      final events = <UnifiedEvent>[];
      final usage = json['usageMetadata'];
      if (usage is Map<String, dynamic>) {
        updateUsage(usage);
      }
      final candidates = json['candidates'] as List<dynamic>? ?? const [];
      for (final candidate in candidates.whereType<Map<String, dynamic>>()) {
        // Gemini 用大写枚举（STOP / MAX_TOKENS / SAFETY / …），
        // MALFORMED_FUNCTION_CALL 等未识别值会落到 unknown，不执行工具。
        final finish = candidate['finishReason'] as String?;
        if (finish != null && finish.isNotEmpty) {
          stopReason = StopReason.parse(finish);
        }
        final content =
            candidate['content'] as Map<String, dynamic>? ?? const {};
        final parts = content['parts'] as List<dynamic>? ?? const [];
        for (final part in parts.whereType<Map<String, dynamic>>()) {
          final text = part['text'] as String?;
          // Gemini thinking parts use thought=true and carry their text in part.text.
          if (text != null && text.isNotEmpty) {
            if (part['thought'] == true) {
              events.add(ReasoningDeltaEvent(text));
            } else {
              events.add(TextDeltaEvent(text));
            }
          }
          final functionCall = part['functionCall'];
          if (functionCall is Map<String, dynamic>) {
            final args = functionCall['args'];
            final parsedArguments = args == null
                ? const <String, dynamic>{}
                : args is Map<String, dynamic>
                    ? args
                    : <String, dynamic>{
                        '_unparsed': jsonEncode(args),
                      };
            pendingCalls.add(ToolCall(
              id: 'gemini-call-${pendingCalls.length}',
              name: functionCall['name'] as String? ?? '',
              arguments: parsedArguments,
            ));
          }
        }
      }
      return events;
    }

    List<UnifiedEvent> finalize() {
      final events = <UnifiedEvent>[];
      for (final call in pendingCalls) {
        events.add(ToolCallEvent(call));
      }
      events.add(UsageEvent(
          promptTokens: promptTokens,
          completionTokens: completionTokens,
          cachedTokens: cachedTokens));
      events.add(CompletedEvent(stopReason: stopReason));
      return events;
    }

    try {
      yield* runStreaming(
        url: url,
        payload: payload,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
        },
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

  /// 将统一消息转换为 Gemini `contents` 中的一条。
  Map<String, dynamic> toGeminiMessage(
      ChatMessage message, Map<String, String> toolNames) {
    if (message.role == MessageRole.tool) {
      return {
        'role': 'function',
        'parts': [
          {
            'functionResponse': {
              'name': toolNames[message.toolCallId] ?? 'tool',
              'response': {'result': message.text},
            },
          },
        ],
      };
    }
    if (message.role == MessageRole.assistant) {
      final parts = <Map<String, dynamic>>[];
      if (message.text.isNotEmpty) parts.add({'text': message.text});
      for (final call in message.toolCalls) {
        parts.add({
          'functionCall': {'name': call.name, 'args': call.arguments},
        });
      }
      if (parts.isEmpty) parts.add({'text': ''});
      return {'role': 'model', 'parts': parts};
    }
    final parts = <Map<String, dynamic>>[];
    for (final part in message.parts) {
      if (part.type == 'image') {
        parts.add({
          'inlineData': {
            'mimeType': part.mimeType ?? 'image/png',
            'data': _stripDataUrl(part.value),
          },
        });
      } else {
        parts.add({'text': part.value});
      }
    }
    if (parts.isEmpty) parts.add({'text': ''});
    return {'role': 'user', 'parts': parts};
  }

  Map<String, dynamic> toGeminiTool(UnifiedTool tool) => {
        'name': tool.name,
        'description': tool.description,
        'parameters': tool.parametersSchema,
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

  /// 把 ReasoningEffort 映射为 Gemini thinkingBudget。
  /// off 时返回 null（不传 thinkingConfig）。
  static bool _supportsThinking(String model) {
    final lower = model.toLowerCase();
    return lower.contains('2.5') || lower.contains('thinking');
  }

  static int? _thinkingBudgetFor(ReasoningEffort effort) {
    switch (effort) {
      case ReasoningEffort.off:
        return null;
      case ReasoningEffort.low:
        return 0;
      case ReasoningEffort.medium:
        return 8192;
      case ReasoningEffort.high:
        return 32768;
    }
  }
}
