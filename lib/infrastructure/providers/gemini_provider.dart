import 'dart:convert';

import 'package:dio/dio.dart';

import '../../domain/models.dart';
import 'http_client.dart';
import 'llm_provider.dart';
import 'provider_config.dart';

/// Google Gemini generateContent 原生适配器。
///
/// 与 OpenAI 不同：角色为 `user`/`model`，工具结果为 `functionResponse` 分块、
/// 认证走 `?key=` 查询参数、系统提示词为顶层 `systemInstruction`、图片用
/// `inlineData`。流式解析从 `candidates[].content.parts[]` 中取文本与函数调用。
class GeminiProvider implements LlmProvider {
  GeminiProvider({required this.config, Dio? dio}) : _dio = dio ?? buildHttpClient();

  final ProviderConfig config;
  final Dio _dio;

  String get _base => config.baseUrl.replaceAll(RegExp(r'/$'), '');

  Future<String?> testConnection() async {
    try {
      final response = await _dio.get<dynamic>(
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
  Stream<UnifiedEvent> stream(UnifiedRequest request, {CancelToken? cancelToken}) async* {
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
    final thinkingBudget = _thinkingBudgetFor(request.reasoningEffort);

    final payload = {
      'contents': contents,
      if (system != null && system.trim().isNotEmpty)
        'systemInstruction': {'parts': [{'text': system.trim()}]},
      'generationConfig': {
        'temperature': request.temperature,
        'maxOutputTokens': request.maxTokens,
        'topP': request.topP,
        if (thinkingBudget != null) 'thinkingConfig': {'thinkingBudget': thinkingBudget},
      },
      if (request.tools.isNotEmpty)
        'tools': [
          {'functionDeclarations': request.tools.map(toGeminiTool).toList()},
        ],
    };

    final url = '$_base/v1beta/models/${Uri.encodeComponent(request.model)}:streamGenerateContent'
        '?alt=sse&key=${Uri.encodeQueryComponent(config.apiKey)}';

    try {
      final response = await _dio.post<ResponseBody>(
        url,
        data: payload,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          },
        ),
      );
      final stream = response.data?.stream;
      if (stream == null) {
        yield const ProviderErrorEvent('Provider 返回了空响应');
        return;
      }

      var buffer = '';
      final pendingCalls = <ToolCall>[];
      var promptTokens = 0;
      var completionTokens = 0;

      await for (final chunk in stream) {
        buffer += utf8.decode(chunk, allowMalformed: true);
        final lines = buffer.split('\n');
        buffer = lines.removeLast();
        for (final line in lines) {
          final json = _parseSseLine(line.trim());
          if (json == null) continue;
          final usage = json['usageMetadata'];
          if (usage is Map<String, dynamic>) {
            promptTokens = (usage['promptTokenCount'] as num?)?.toInt() ?? promptTokens;
            completionTokens = (usage['candidatesTokenCount'] as num?)?.toInt() ?? completionTokens;
          }
          final candidates = json['candidates'] as List<dynamic>? ?? const [];
          for (final candidate in candidates.whereType<Map<String, dynamic>>()) {
            final content = candidate['content'] as Map<String, dynamic>? ?? const {};
            final parts = content['parts'] as List<dynamic>? ?? const [];
            for (final part in parts.whereType<Map<String, dynamic>>()) {
              final text = part['text'] as String?;
              if (text != null && text.isNotEmpty) {
                yield TextDeltaEvent(text);
              }
              final functionCall = part['functionCall'];
              if (functionCall is Map<String, dynamic>) {
                final args = functionCall['args'];
                pendingCalls.add(ToolCall(
                  id: 'gemini-call-${pendingCalls.length}',
                  name: functionCall['name'] as String? ?? '',
                  arguments: args is Map<String, dynamic> ? args : const {},
                ));
              }
            }
          }
        }
      }
      final trailing = _parseSseLine(buffer.trim());
      if (trailing != null) {
        final usage = trailing['usageMetadata'];
        if (usage is Map<String, dynamic>) {
          promptTokens = (usage['promptTokenCount'] as num?)?.toInt() ?? promptTokens;
          completionTokens = (usage['candidatesTokenCount'] as num?)?.toInt() ?? completionTokens;
        }
      }

      for (final call in pendingCalls) {
        yield ToolCallEvent(call);
      }
      yield UsageEvent(promptTokens: promptTokens, completionTokens: completionTokens);
      yield const CompletedEvent();
    } on DioException catch (error) {
      // 主动取消时静默结束。
      if (error.type == DioExceptionType.cancel) return;
      final message = error.response?.data?.toString() ?? error.message ?? '网络请求失败';
      yield ProviderErrorEvent(message);
    } catch (error) {
      yield ProviderErrorEvent(error.toString());
    }
  }

  /// 将统一消息转换为 Gemini `contents` 中的一条。
  Map<String, dynamic> toGeminiMessage(ChatMessage message, Map<String, String> toolNames) {
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
    if (value.startsWith('data:') && comma >= 0) return value.substring(comma + 1);
    return value;
  }

  Map<String, dynamic>? _parseSseLine(String line) {
    if (!line.startsWith('data:')) return null;
    final data = line.substring(5).trim();
    if (data.isEmpty || data == '[DONE]') return null;
    try {
      return jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 把 ReasoningEffort 映射为 Gemini thinkingBudget。
  /// off 时返回 null（不传 thinkingConfig）。
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
