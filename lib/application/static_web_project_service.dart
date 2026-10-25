import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

class WebProjectFile {
  const WebProjectFile(this.path, this.bytes, this.hash);
  final String path;
  final int bytes;
  final String hash;
}

/// A review identifies exact bytes. Export never silently substitutes newer
/// edits, and files added after review are not included in that export.
class WebProjectReview {
  WebProjectReview._(this.workspace, List<WebProjectFile> files, this.excluded)
      : files = List.unmodifiable(files);
  final String workspace;
  final List<WebProjectFile> files;
  final int excluded;
  int get bytes => files.fold(0, (total, file) => total + file.bytes);
}

class StaticWebProjectService {
  const StaticWebProjectService();
  static const maxFiles = 1000;
  static const maxBytes = 32 * 1024 * 1024;
  static const maxFileBytes = 8 * 1024 * 1024;
  static const _types = {
    '.html': 'text/html; charset=utf-8',
    '.htm': 'text/html; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.js': 'text/javascript; charset=utf-8',
    '.mjs': 'text/javascript; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.svg': 'image/svg+xml',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.avif': 'image/avif',
    '.ico': 'image/x-icon',
    '.woff': 'font/woff',
    '.woff2': 'font/woff2',
    '.ttf': 'font/ttf',
    '.wasm': 'application/wasm',
    '.webmanifest': 'application/manifest+json',
    '.mp3': 'audio/mpeg',
    '.mp4': 'video/mp4',
    '.webm': 'video/webm',
  };
  static const _excludedDirectories = {
    'node_modules',
    'build',
    'coverage',
    '__pycache__',
    'local',
  };

  static bool _allowed(String relative) {
    final parts = relative.split('/');
    return relative.isNotEmpty &&
        !p.posix.isAbsolute(relative) &&
        !relative.contains('\\') &&
        !relative.contains('\x00') &&
        parts.every((part) =>
            part.isNotEmpty &&
            !part.startsWith('.') &&
            !_excludedDirectories.contains(part)) &&
        _types.containsKey(p.posix.extension(relative).toLowerCase());
  }

  Future<Uint8List> _read(String root, String relative) async {
    if (!_allowed(relative)) throw const FileSystemException('不是可交付的网页资源');
    final path = p.joinAll([root, ...relative.split('/')]);
    final resolved = await File(path).resolveSymbolicLinks();
    if (!p.isWithin(root, resolved)) {
      throw const FileSystemException('网页资源超出项目目录');
    }
    final file = File(resolved);
    if (await file.length() > maxFileBytes) {
      throw const FileSystemException('单个网页资源不能超过 8 MiB');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (bytes.length + chunk.length > maxFileBytes) {
        throw const FileSystemException('网页资源读取超出大小限制');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  Future<WebProjectReview> review(String workspace) async {
    final root = await Directory(workspace).resolveSymbolicLinks();
    final queue = <(Directory, int)>[(Directory(root), 0)];
    final files = <WebProjectFile>[];
    var excluded = 0, visited = 0, total = 0;
    for (var i = 0; i < queue.length; i++) {
      final (directory, depth) = queue[i];
      await for (final entity in directory.list(followLinks: false)) {
        if (++visited > 6000) throw StateError('项目条目过多，请选择较小的网页目录');
        final name = p.basename(entity.path);
        if (name.startsWith('.') || _excludedDirectories.contains(name)) {
          excluded++;
          continue;
        }
        if (entity is Directory) {
          if (depth >= 16) throw StateError('网页目录层级过深');
          queue.add((entity, depth + 1));
        } else if (entity is File) {
          final relative =
              p.relative(entity.path, from: root).replaceAll('\\', '/');
          if (!_allowed(relative)) {
            excluded++;
            continue;
          }
          if (files.length >= maxFiles) throw StateError('最多交付 1000 个网页资源');
          final bytes = await _read(root, relative);
          total += bytes.length;
          if (total > maxBytes) throw StateError('网页资源合计不能超过 32 MiB');
          files.add(WebProjectFile(
              relative, bytes.length, sha256.convert(bytes).toString()));
        } else {
          // Links are not followed or bundled, even if their targets are local.
          excluded++;
        }
      }
    }
    if (!files.any((file) => file.path == 'index.html')) {
      throw const FileSystemException('项目根目录缺少 index.html');
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return WebProjectReview._(root, files, excluded);
  }

  Future<File> export(WebProjectReview review, File destination) async {
    if (p.isWithin(review.workspace, p.absolute(destination.path)) ||
        await destination.exists()) {
      throw StateError('请使用项目目录之外的新成果文件');
    }
    final archive = Archive();
    for (final entry in review.files) {
      final bytes = await _read(review.workspace, entry.path);
      if (bytes.length != entry.bytes ||
          sha256.convert(bytes).toString() != entry.hash) {
        throw StateError('文件已变化：${entry.path}。请刷新文件核对后再保存');
      }
      archive.addFile(ArchiveFile(entry.path, bytes.length, bytes));
    }
    final encoded = ZipEncoder().encode(archive);
    await destination.parent.create(recursive: true);
    // The caller owns a unique temporary directory; no source file is replaced.
    return destination.writeAsBytes(encoded, flush: true);
  }
}

/// Dependency-free, live static preview. Only a random loopback capability URL
/// serves allowed web assets; no shell, directory listing or native JS bridge.
class StaticWebPreviewServer {
  HttpServer? _server;
  Uri? _url;
  int _generation = 0;
  Uri? get url => _url;

  Future<Uri> start(String workspace) async {
    final generation = ++_generation;
    final previous = _server;
    _server = null;
    _url = null;
    await previous?.close(force: true);
    final root = await Directory(workspace).resolveSymbolicLinks();
    await const StaticWebProjectService()._read(root, 'index.html');
    final random = Random.secure();
    final token =
        base64Url.encode(List.generate(24, (_) => random.nextInt(256)));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (generation != _generation) {
      await server.close(force: true);
      throw StateError('网页预览已取消');
    }
    _server = server;
    _url = Uri.parse('http://127.0.0.1:${server.port}/$token/');
    server.listen(
        (request) => unawaited(_serve(request, root, token, server.port)),
        onError: (Object _) {
      /* A failed connection does not stop the preview. */
    });
    return _url!;
  }

  Future<void> _serve(
      HttpRequest request, String root, String token, int port) async {
    final response = request.response;
    try {
      if (request.headers.value(HttpHeaders.hostHeader) != '127.0.0.1:$port') {
        response.statusCode = HttpStatus.forbidden;
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final segments = request.uri.pathSegments;
      if (segments.isEmpty || segments.first != token) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final relative =
          segments.skip(1).where((part) => part.isNotEmpty).join('/');
      final entry = relative.isEmpty ? 'index.html' : relative;
      final bytes = await const StaticWebProjectService()._read(root, entry);
      response.headers.set(
          HttpHeaders.contentTypeHeader,
          StaticWebProjectService
              ._types[p.posix.extension(entry).toLowerCase()]!);
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      response.headers.set('X-Content-Type-Options', 'nosniff');
      response.headers.set('Referrer-Policy', 'no-referrer');
      response.contentLength = bytes.length;
      if (request.method == 'GET') response.add(bytes);
    } on FileSystemException {
      response.statusCode = HttpStatus.notFound;
    } catch (_) {
      response.statusCode = HttpStatus.internalServerError;
    } finally {
      try {
        await response.close();
      } catch (_) {/* Client disconnected. */}
    }
  }

  Future<void> stop() async {
    ++_generation;
    final server = _server;
    _server = null;
    _url = null;
    await server?.close(force: true);
  }
}
