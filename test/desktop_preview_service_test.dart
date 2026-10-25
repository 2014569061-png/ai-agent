import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/desktop_preview_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late DesktopPreviewServer server;
  late HttpClient client;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nexus-preview-');
    await File(p.join(directory.path, 'index.html'))
        .writeAsString('<h1>真实预览</h1>');
    await File(p.join(directory.path, 'style.css'))
        .writeAsString('body { color: blue; }');
    server = DesktopPreviewServer();
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await server.stop();
    await directory.delete(recursive: true);
  });

  test('serves real entry and assets with content types on loopback', () async {
    final url = await server.start(directory.path, 'index.html');
    expect(url.host, '127.0.0.1');
    final response = await (await client.getUrl(url)).close();
    expect(response.statusCode, 200);
    expect(response.headers.contentType?.mimeType, 'text/html');
    expect(await utf8.decoder.bind(response).join(), '<h1>真实预览</h1>');
    final css = await (await client.getUrl(url.resolve('style.css'))).close();
    expect(css.headers.contentType?.mimeType, 'text/css');
    expect(await utf8.decoder.bind(css).join(), contains('color: blue'));
  });

  test('missing files and unsupported method are explicit failures', () async {
    final url = await server.start(directory.path, 'index.html');
    final response =
        await (await client.getUrl(url.resolve('missing.txt'))).close();
    expect(response.statusCode, 404);
    await response.drain<void>();
    final post = await (await client.postUrl(url)).close();
    expect(post.statusCode, 405);
    await post.drain<void>();
  });

  test('rejects out-of-workspace entry and unsafe URL schemes', () async {
    expect(server.start(directory.path, '../outside.html'),
        throwsA(isA<FileSystemException>()));
    for (final value in [
      'javascript:alert(1)',
      'file:///C:/Windows',
      'localhost:3000',
      'https://name:secret@example.com'
    ]) {
      expect(() => DesktopPreviewServer.parseUrl(value), throwsFormatException);
    }
    expect(DesktopPreviewServer.parseUrl('http://localhost:3000').port, 3000);
  });

  test('restart shuts down previous server and serves selected entry',
      () async {
    final first = await server.start(directory.path, 'index.html');
    await File(p.join(directory.path, 'second.html')).writeAsString('second');
    final second = await server.start(directory.path, 'second.html');
    final response = await (await client.getUrl(second)).close();
    expect(await utf8.decoder.bind(response).join(), 'second');
    await server.stop();
    expect(server.url, isNull);
    expect(client.getUrl(first), throwsA(isA<SocketException>()));
  });
}
