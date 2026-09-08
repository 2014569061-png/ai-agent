import 'dart:io';
import 'dart:async';

void main() async {
  Directory dir = Directory('mobile_agent/build/web');
  if (!dir.existsSync()) {
    dir = Directory('build/web');
  }
  if (!dir.existsSync()) {
    stdout.writeln('[!] 错误: 未找到 Web 产物目录，请先编译项目！');
    exit(1);
  }

  HttpServer? server;
  int port = 8080;
  for (var p = 8080; p < 8090; p++) {
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, p);
      port = p;
      break;
    } catch (_) {}
  }

  if (server == null) {
    stdout.writeln('[!] 无法绑定端口 8080-8090');
    exit(1);
  }

  stdout.writeln('=======================================================');
  stdout.writeln('       🚀 NEXUS Agent Web 本地服务已启动');
  stdout.writeln('=======================================================');
  stdout.writeln(' * 访问地址: http://localhost:$port');
  stdout.writeln(' * Web WASM 跨域隔离支持: 已启用 (COOP/COEP)');
  stdout.writeln(' * 提示: 按 Ctrl + C 可停止服务');
  stdout.writeln('=======================================================');

  Timer(const Duration(milliseconds: 1200), () {
    final url = 'http://localhost:$port';
    stdout.writeln('\n[✓] 正在自动打开浏览器: $url');
    if (Platform.isWindows) {
      Process.run('cmd', ['/c', 'start', '', url]);
    } else if (Platform.isMacOS) {
      Process.run('open', [url]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [url]);
    }
  });

  await for (HttpRequest request in server) {
    request.response.headers.set('Cross-Origin-Opener-Policy', 'same-origin');
    request.response.headers
        .set('Cross-Origin-Embedder-Policy', 'require-corp');
    request.response.headers
        .set('Cache-Control', 'no-cache, no-store, must-revalidate');

    String reqPath = request.uri.path;
    if (reqPath == '/' || reqPath.isEmpty) reqPath = '/index.html';

    final cleanPath = reqPath.split('?').first;
    var file = File('${dir.path}$cleanPath');

    if (!await file.exists()) {
      if (!cleanPath.contains('.')) {
        file = File('${dir.path}/index.html');
      }
    }

    if (await file.exists()) {
      final ext = file.path.split('.').last.toLowerCase();
      switch (ext) {
        case 'html':
          request.response.headers.contentType = ContentType.html;
          break;
        case 'js':
        case 'mjs':
          request.response.headers.contentType =
              ContentType('application', 'javascript', charset: 'utf-8');
          break;
        case 'wasm':
          request.response.headers.contentType =
              ContentType('application', 'wasm');
          break;
        case 'css':
          request.response.headers.contentType =
              ContentType('text', 'css', charset: 'utf-8');
          break;
        case 'json':
          request.response.headers.contentType = ContentType.json;
          break;
        case 'png':
          request.response.headers.contentType = ContentType('image', 'png');
          break;
        case 'jpg':
        case 'jpeg':
          request.response.headers.contentType = ContentType('image', 'jpeg');
          break;
        case 'svg':
          request.response.headers.contentType =
              ContentType('image', 'svg+xml');
          break;
        case 'ico':
          request.response.headers.contentType = ContentType('image', 'x-icon');
          break;
        case 'otf':
          request.response.headers.contentType = ContentType('font', 'otf');
          break;
        case 'ttf':
          request.response.headers.contentType = ContentType('font', 'ttf');
          break;
      }
      await file.openRead().pipe(request.response);
    } else {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('404 Not Found');
      await request.response.close();
    }
  }
}
