import 'dart:convert';

import 'package:dio/dio.dart';

import '../../domain/models.dart';
import 'http_client.dart';
import 'provider_config.dart';
import 'llm_provider.dart';

class OpenAiCompatibleProvider implements LlmProvider {
  OpenAiCompatibleProvider({required this.config, Dio? dio}) : _dio = dio ?? buildHttpClient();

  final ProviderConfig config;
  final Dio _dio;

  /// 仅对已知支持 `stream_options.include_usage` 的服务商开启用量上报，
  /// 避免严格校验参数的第三方兼容端点因未知字段报 400。
  bool get _requestsUsage {
    final host = Uri.tryParse(config.baseUrl)?.host.toLowerCase() ?? '';
    return host.contains('openai.com') ||
        host.contains('openrouter.ai') ||
        host.contains('deepseek.com') ||
        host.contains('groq.com') ||
        host.contains('together.xyz');
  }

  Future<String?> testConnection() async {
    try {
      final response = await _dio.get<dynamic>(
        '${config.baseUrl.replaceAll(RegExp(r'/$'), '')}/models',
        options: Options(headers: {'Authorization': 'Bearer ${config.apiKey}'}),
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

  Future<List<ModelInfo>> listModels() async {
    final response = await _dio.get<dynamic>(
      '${config.baseUrl.replaceAll(RegExp(r'/$'), '')}/models',
      options: Options(headers: {'Authorization': 'Bearer ${config.apiKey}'}),
    );
    final data = response.data is Map<String, dynamic> ? response.data['data'] : null;
    if (data is! List) return const [];
    return data.whereType<Map<String, dynamic>>().map((item) {
      final id = item['id'] as String? ?? '';
      final lower = id.toLowerCase();
      return ModelInfo(
        id: id,
        ownedBy: item['owned_by'] as String?,
        capabilities: ModelCapabilities(
          vision: lower.contains('vision') || lower.contains('4o') || lower.contains('gemini') || lower.contains('claude-3'),
          tools: !lower.contains('embedding') && !lower.contains('tts') && !lower.contains('whisper'),
        ),
      );
    }).where((item) => item.id.isNotEmpty).toList();
  }

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request, {CancelToken? cancelToken}) async* {
    final payload = {
      'model': request.model,
      'messages': request.messages.map(toProviderMessage).toList(),
      'temperature': request.temperature,
      'max_tokens': request.maxTokens,
      'top_p': request.topP,
      'stream': true,
      if (request.tools.isNotEmpty)
        'tools': request.tools.map((tool) => tool.toOpenAiSchema()).toList(),
      if (_requestsUsage) 'stream_options': {'include_usage': true},
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
        yield const ProviderErrorEvent('Provider 返回了空响应');
        return;
      }
      var buffer = '';
      final toolAccumulators = <int, _ToolAccumulator>{};
      var nextToolIndex = 0;
      void collect(_SseChunk parsed) {
        for (final fragment in parsed.tools) {
          final index = fragment.index ?? nextToolIndex++;
          final accumulator = toolAccumulators.putIfAbsent(index, _ToolAccumulator.new);
          if (fragment.id != null) accumulator.id = fragment.id;
          if (fragment.name != null && fragment.name!.isNotEmpty) accumulator.name = fragment.name;
          if (fragment.arguments != null) accumulator.arguments.write(fragment.arguments);
        }
      }
      await for (final chunk in stream) {
        buffer += utf8.decode(chunk, allowMalformed: true);
        final lines = buffer.split('\n');
        buffer = lines.removeLast();
        for (final line in lines) {
          final parsed = _parseSseLine(line.trim());
          if (parsed == null) continue;
          if (parsed.text != null && parsed.text!.isNotEmpty) yield TextDeltaEvent(parsed.text!);
          collect(parsed);
          if (parsed.usage != null) yield parsed.usage!;
        }
      }
      final parsed = _parseSseLine(buffer.trim());
      if (parsed != null) {
        if (parsed.text != null && parsed.text!.isNotEmpty) yield TextDeltaEvent(parsed.text!);
        collect(parsed);
        if (parsed.usage != null) yield parsed.usage!;
      }
      for (final accumulator in toolAccumulators.values) {
        final rawArguments = accumulator.arguments.toString();
        final decoded = jsonDecode(rawArguments.isEmpty ? '{}' : rawArguments);
        yield ToolCallEvent(ToolCall(
          id: accumulator.id ?? 'streamed-tool-call',
          name: accumulator.name ?? '',
          arguments: decoded is Map<String, dynamic> ? decoded : const {},
        ));
      }
      yield const CompletedEvent();
    } on DioException catch (error) {
      // 主动取消时静默结束，避免把"已取消"渲染成错误提示。
      if (error.type == DioExceptionType.cancel) return;
      final message = error.response?.data?.toString() ?? error.message ?? '网络请求失败';
      yield ProviderErrorEvent(message);
    } catch (error) {
      yield ProviderErrorEvent(error.toString());
    }
  }

  /// Converts the unified message representation to OpenAI-compatible JSON.
  ///
  /// Keeping this conversion public makes the wire format independently
  /// testable without issuing a network request.
  Map<String, dynamic> toProviderMessage(ChatMessage message) => {
        'role': message.role.name,
        'content': message.parts.any((part) => part.type == 'image')
            ? message.parts.map((part) => part.type == 'image'
                ? {'type': 'image_url', 'image_url': {'url': part.value}}
                : {'type': 'text', 'text': part.value}).toList()
            : (message.toolCalls.isNotEmpty && message.text.isEmpty ? null : message.text),
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

  _SseChunk? _parseSseLine(String line) {
    if (!line.startsWith('data:')) return null;
    final data = line.substring(5).trim();
    if (data == '[DONE]' || data.isEmpty) return null;
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final usage = json['usage'];
      if (usage is Map<String, dynamic>) {
        return _SseChunk(
          usage: UsageEvent(
            promptTokens: (usage['prompt_tokens'] as num?)?.toInt() ?? 0,
            completionTokens: (usage['completion_tokens'] as num?)?.toInt() ?? 0,
          ),
        );
      }
      final choices = json['choices'] as List<dynamic>? ?? const [];
      if (choices.isEmpty) return null;
      final delta = choices.first['delta'] as Map<String, dynamic>? ?? const {};
      final content = delta['content'] as String?;
      final toolCalls = delta['tool_calls'] as List<dynamic>?;
      if (toolCalls != null && toolCalls.isNotEmpty) {
        return _SseChunk(
          text: content,
          tools: toolCalls.map((item) {
            final tool = item as Map<String, dynamic>;
            final function = tool['function'] as Map<String, dynamic>? ?? const {};
            return _ToolFragment(index: tool['index'] as int?, id: tool['id'] as String?, name: function['name'] as String?, arguments: function['arguments'] as String?);
          }).toList(growable: false),
        );
      }
      if (content != null && content.isNotEmpty) return _SseChunk(text: content);
    } catch (_) {
      return null;
    }
    return null;
  }
}

class _SseChunk {
  const _SseChunk({this.text, this.tools = const [], this.usage});

  final String? text;
  final List<_ToolFragment> tools;
  final UsageEvent? usage;
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
