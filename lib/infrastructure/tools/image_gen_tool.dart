import 'dart:convert';

import 'package:dio/dio.dart';

import '../../domain/models.dart';
import '../../domain/tool_codes.dart';
import '../../domain/tool_result.dart';
import '../providers/http_client.dart';
import '../providers/provider_config.dart';
import 'tool_registry.dart';

/// 文生图工具（A7）：调用 OpenAI 兼容 `/images/generations` 端点生成图片。
/// 返回值为图片 data URI（b64_json）或图片 URL，由 UI 识别后渲染为图片气泡。
/// 无该端点的 provider（Anthropic/Gemini）会返回 404，工具降级提示不支持。
class ImageGenTool implements AgentTool {
  ImageGenTool({required this.config, Dio? dio})
      : _dio = dio ?? buildHttpClient();

  final ProviderConfig config;
  final Dio _dio;

  @override
  final manifest = const UnifiedTool(
    name: 'generate_image',
    description: '根据文字描述生成一张图片。当用户要求"画/生成一张图"时调用。',
    parametersSchema: {
      'type': 'object',
      'properties': {
        'prompt': {'type': 'string', 'description': '图片描述'},
        'size': {
          'type': 'string',
          'description': '图片尺寸，如 1024x1024',
          'default': '1024x1024'
        },
      },
      'required': ['prompt'],
    },
    risk: ToolRisk.safe,
  );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final prompt = (arguments['prompt'] as String? ?? '').trim();
    if (prompt.isEmpty) {
      return ToolResult.failure(
        code: ToolCodes.invalidArguments,
        message: '请提供图片描述',
      );
    }
    final size = arguments['size'] as String? ?? '1024x1024';
    try {
      final response = await _dio.post<dynamic>(
        '${config.baseUrl.replaceAll(RegExp(r'/$'), '')}/images/generations',
        data: {'model': config.model, 'prompt': prompt, 'n': 1, 'size': size},
        options: Options(headers: {'Authorization': 'Bearer ${config.apiKey}'}),
      );
      final data = response.data;
      if (data is Map<String, dynamic> &&
          data['data'] is List &&
          (data['data'] as List).isNotEmpty) {
        final first = (data['data'] as List).first;
        if (first is Map<String, dynamic> && first['b64_json'] is String) {
          return _imageResult(
              'data:image/png;base64,${first['b64_json']}', prompt, size);
        }
        if (first is Map<String, dynamic> && first['url'] is String) {
          // 部分 provider（OpenAI 等）默认返回 URL；下载并转 data URI，
          // 保证 UI 端可直接渲染为图片气泡。
          final url = first['url'] as String;
          final uri = await _downloadAsDataUri(url);
          if (uri == null) {
            return ToolResult.failure(
              code: ToolCodes.networkUnavailable,
              message: '图像已生成但下载失败，可让用户直接访问：$url',
              data: {'url': url},
            );
          }
          return _imageResult(uri, prompt, size);
        }
      }
      return ToolResult.failure(
        code: ToolCodes.toolError,
        message: '图像生成失败：服务端未返回有效图片',
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return ToolResult.failure(
          code: ToolCodes.platformUnsupported,
          message: '当前模型不支持图像生成（/images/generations 返回 404），'
              '请换用支持该端点的模型',
        );
      }
      return ToolResult.failure(
        code: ToolCodes.networkUnavailable,
        message: '图像生成失败：${error.message ?? '网络错误'}',
      );
    } catch (error) {
      return ToolResult.failure(
        code: ToolCodes.toolError,
        message: '图像生成失败：$error',
      );
    }
  }

  /// data URI 放进 `data.uri`：模型与 UI 都能取到，而 display 摘要不再
  /// 把一整屏 base64 糊到工具结果气泡里。
  ToolResult _imageResult(String uri, String prompt, String size) =>
      ToolResult.success(
        message: '已生成图片（$size）',
        data: {'uri': uri, 'prompt': prompt, 'size': size},
      );

  Future<String?> _downloadAsDataUri(String url) async {
    if (!url.startsWith('http')) return null;
    try {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) return null;
      final mime = response.headers.value('content-type') ?? 'image/png';
      final mimeShort = mime.split(';').first.trim();
      return 'data:$mimeShort;base64,${base64Encode(bytes)}';
    } catch (_) {
      return null;
    }
  }
}
