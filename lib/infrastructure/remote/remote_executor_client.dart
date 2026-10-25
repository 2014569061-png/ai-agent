import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Authenticated, bounded transport. Redirects must not forward credentials.
/// This client never starts a job merely because a connection was restored.
class RemoteExecutorClient {
  RemoteExecutorClient(
      {required this.endpoint, required this.token, http.Client? client})
      : _client = client {
    if (!endpoint.hasAuthority ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        !{'', '/'}.contains(endpoint.path) ||
        !{'http', 'https'}.contains(endpoint.scheme)) {
      throw const FormatException('远程地址格式无效，不得包含凭证、查询参数或额外路径');
    }
    if (endpoint.scheme == 'http' &&
        !{'127.0.0.1', 'localhost', '10.0.2.2', '[::1]', '::1'}
            .contains(endpoint.host)) {
      throw const FormatException('明文 HTTP 仅用于本机或 Android 模拟器宿主地址');
    }
    if (token.trim().length < 32 || RegExp(r'[\r\n]').hasMatch(token)) {
      throw const FormatException('请输入本机执行器生成的有效令牌');
    }
  }

  final Uri endpoint;
  final String token;
  final http.Client? _client;

  Future<Map<String, dynamic>> handshake() => _request('GET', 'handshake');
  Future<Map<String, dynamic>> jobs() => _request('GET', 'jobs');
  Future<Map<String, dynamic>> job(String id) {
    _validateJobId(id);
    return _request('GET', 'jobs/$id');
  }

  Future<Map<String, dynamic>> logs(String id) {
    _validateJobId(id);
    return _request('GET', 'jobs/$id/logs');
  }

  /// Caller must persist requestId/runId and complete the shared approval flow
  /// before submitting a side-effectful host-configured task.
  Future<Map<String, dynamic>> submit(
          {required String requestId,
          required String runId,
          required String task}) =>
      _request('POST', 'jobs',
          {'requestId': requestId, 'runId': runId, 'task': task});

  Future<Map<String, dynamic>> cancel(String id) {
    _validateJobId(id);
    return _request('POST', 'jobs/$id/cancel');
  }

  void _validateJobId(String id) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
      throw const FormatException('无效的远程作业编号');
    }
  }

  Future<Map<String, dynamic>> _request(String method, String path,
      [Map<String, dynamic>? body]) async {
    final client = _client ?? http.Client();
    try {
      final request = http.Request(method, endpoint.resolve(path))
        ..followRedirects = false
        ..headers['Authorization'] = 'Bearer ${token.trim()}'
        ..headers['Accept'] = 'application/json';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final response =
          await client.send(request).timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // Server response bodies may contain logs/secrets. Do not display them.
        throw StateError(switch (response.statusCode) {
          401 || 403 => '远程认证失败或令牌已撤销',
          409 => '远程资源冲突，请先查询已有作业',
          429 => '远程队列已满，请稍后查询',
          _ => '远程请求失败（HTTP ${response.statusCode}）',
        });
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk
          in response.stream.timeout(const Duration(seconds: 8))) {
        if (bytes.length + chunk.length > 1024 * 1024) {
          throw const FormatException('远程响应超过大小上限');
        }
        bytes.add(chunk);
      }
      final value = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (value is! Map<String, dynamic>) {
        throw const FormatException('远程响应不是有效对象');
      }
      return value;
    } on TimeoutException {
      throw StateError('远程连接超时；提交结果可能未知，请按原编号查询，不要自动重发');
    } finally {
      if (_client == null) client.close();
    }
  }
}
