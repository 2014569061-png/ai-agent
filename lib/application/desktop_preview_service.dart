import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'desktop_workbench_service.dart';

/// Serves an explicitly selected web artifact on loopback only. Every request
/// resolves symlinks and must stay inside the artifact directory.
class DesktopPreviewServer {
  HttpServer? _server;
  int _generation = 0;
  Uri? get url =>
      _server == null ? null : Uri.parse('http://127.0.0.1:${_server!.port}/');

  Future<Uri> start(String workspace, String entry) async {
    final generation = ++_generation;
    final previous = _server;
    _server = null;
    await previous?.close(force: true);
    final resolved =
        await const DesktopWorkspaceFiles().resolve(workspace, entry);
    if (p.extension(resolved).toLowerCase() != '.html') {
      throw const FileSystemException('请选择 HTML 入口文件');
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (generation != _generation) {
      await server.close(force: true);
      throw StateError('预览请求已取消');
    }
    _server = server;
    server.listen(
        (request) => unawaited(
            _serve(request, p.dirname(resolved), p.basename(resolved))),
        onError: (Object error) {
      /* Individual connection failures are isolated. */
    });
    return url!;
  }

  static Uri parseUrl(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('请输入完整的 http:// 或 https:// 地址');
    }
    return uri;
  }

  Future<void> _serve(
      HttpRequest request, String directory, String entry) async {
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final segments = request.uri.pathSegments;
      if (segments
          .any((s) => s == '..' || s.contains('\\') || s.contains('\x00'))) {
        request.response.statusCode = HttpStatus.forbidden;
        return;
      }
      final path = segments.where((s) => s.isNotEmpty).join('/');
      final resolved = await const DesktopWorkspaceFiles()
          .resolve(directory, path.isEmpty ? entry : path);
      if (await FileSystemEntity.isDirectory(resolved)) {
        request.response.statusCode = HttpStatus.notFound;
        return;
      }
      const types = {
        '.html': 'text/html',
        '.css': 'text/css',
        '.js': 'text/javascript',
        '.json': 'application/json',
        '.svg': 'image/svg+xml',
        '.png': 'image/png',
        '.jpg': 'image/jpeg',
        '.jpeg': 'image/jpeg',
        '.webp': 'image/webp',
        '.ico': 'image/x-icon',
        '.wasm': 'application/wasm',
        '.woff': 'font/woff',
        '.woff2': 'font/woff2'
      };
      request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          types[p.extension(resolved).toLowerCase()] ??
              'application/octet-stream');
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      if (request.method == 'GET') {
        await request.response.addStream(File(resolved).openRead());
      }
    } on FileSystemException {
      request.response.statusCode = HttpStatus.notFound;
    } catch (_) {
      request.response.statusCode = HttpStatus.internalServerError;
    } finally {
      await request.response.close();
    }
  }

  Future<void> stop() async {
    _generation++;
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }
}
