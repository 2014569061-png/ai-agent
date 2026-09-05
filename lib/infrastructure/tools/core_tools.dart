import 'dart:convert';

import 'package:dio/dio.dart';

import '../../domain/models.dart';
import 'tool_registry.dart';

class GetTimeTool implements AgentTool {
  @override
  final manifest = const UnifiedTool(
      name: 'get_time',
      description: '获取当前本地时间。',
      parametersSchema: {'type': 'object', 'properties': {}},
      risk: ToolRisk.safe);
  @override
  Future<String> execute(Map<String, dynamic> arguments) async =>
      DateTime.now().toLocal().toIso8601String();
}

class JsonQueryTool implements AgentTool {
  @override
  final manifest = const UnifiedTool(
      name: 'json_query',
      description: '从 JSON 文本中按点号路径读取字段，例如 user.name。',
      parametersSchema: {
        'type': 'object',
        'properties': {
          'json': {'type': 'string'},
          'path': {'type': 'string'}
        },
        'required': ['json', 'path']
      },
      risk: ToolRisk.safe);
  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    try {
      dynamic current = jsonDecode(arguments['json'] as String? ?? '');
      final path = (arguments['path'] as String? ?? '').trim();
      if (path.isNotEmpty) {
        for (final segment in path.split('.')) {
          if (current is Map<String, dynamic>) {
            current = current[segment];
          } else if (current is List && int.tryParse(segment) != null) {
            current = current[int.parse(segment)];
          } else {
            return '未找到路径：$path';
          }
        }
      }
      return jsonEncode(current);
    } catch (error) {
      return 'JSON 查询失败：$error';
    }
  }
}

class HttpRequestTool implements AgentTool {
  HttpRequestTool({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
            ));
  final Dio _dio;
  @override
  final manifest = const UnifiedTool(
      name: 'http_request',
      description: '向指定 URL 发起 HTTP 请求。可能产生外部副作用，必须审批。',
      parametersSchema: {
        'type': 'object',
        'properties': {
          'url': {'type': 'string'},
          'method': {
            'type': 'string',
            'enum': ['GET', 'POST']
          },
          'body': {'type': 'object'}
        },
        'required': ['url']
      },
      risk: ToolRisk.dangerous);
  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final url = arguments['url'] as String?;
    if (url == null || !url.startsWith('http')) return 'URL 无效';
    final blocked = _blockedUrl(url);
    if (blocked != null) return 'URL 被安全策略拒绝：$blocked';
    final method = (arguments['method'] as String? ?? 'GET').toUpperCase();
    final response = await _dio.request<dynamic>(url,
        data: arguments['body'],
        options: Options(method: method, responseType: ResponseType.json));
    final data = response.data;
    return jsonEncode({'status': response.statusCode, 'data': data});
  }

  /// SSRF 防护：拒绝云元数据 / 链路本地 / 广播地址的直接访问。
  /// 本地回环（localhost/127.0.0.1）保留（本地工具场景），但危险等级
  /// 仍需用户审批。
  static String? _blockedUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return '仅支持 http/https';
    }
    final host = uri.host.toLowerCase().replaceAll('[', '').replaceAll(']', '');
    if (host == '0.0.0.0' || host == '169.254.169.254') return '云元数据/广播地址不可访问';
    // 链路本地 169.254.0.0/16（含各大云厂商元数据服务）
    if (host.startsWith('169.254.')) return '链路本地地址不可访问';
    if (host.endsWith('.internal') || host.endsWith('.local')) {
      return '内网域名不可访问';
    }
    return null;
  }
}

class WebSearchTool implements AgentTool {
  WebSearchTool({required this.apiKey, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
            ));
  final String apiKey;
  final Dio _dio;
  @override
  final manifest = const UnifiedTool(
      name: 'web_search',
      description: '联网搜索公开信息并返回摘要。',
      parametersSchema: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
          'maxResults': {'type': 'integer'}
        },
        'required': ['query']
      },
      risk: ToolRisk.requiresConfirmation);
  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    if (apiKey.trim().isEmpty) return '未配置 Tavily API Key';
    final response =
        await _dio.post<dynamic>('https://api.tavily.com/search', data: {
      'api_key': apiKey,
      'query': arguments['query'],
      'max_results': arguments['maxResults'] ?? 5
    });
    return jsonEncode(response.data);
  }
}

/// 长期记忆写入工具。写入逻辑通过回调注入（由 ChatController 连接 MemoryService），
/// 保持工具层对 Riverpod/数据库无直接依赖。
class RememberTool implements AgentTool {
  RememberTool({required this.onRemember});
  final Future<void> Function(String content) onRemember;

  @override
  final manifest = const UnifiedTool(
    name: 'remember',
    description: '将一条需要长期记住的事实写入记忆。当用户要求"记住……"时调用。',
    parametersSchema: {
      'type': 'object',
      'properties': {
        'content': {'type': 'string', 'description': '要记住的内容'},
      },
      'required': ['content'],
    },
    risk: ToolRisk.safe,
  );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final content = (arguments['content'] as String? ?? '').trim();
    if (content.isEmpty) return '内容为空，未写入';
    await onRemember(content);
    return '已记住：$content';
  }
}
