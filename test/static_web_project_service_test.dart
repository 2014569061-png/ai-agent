import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/static_web_project_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory fixture, workspace;
  late StaticWebPreviewServer preview;
  const service = StaticWebProjectService();

  setUp(() async {
    final parent = Directory('local/temp/static-web-tests');
    await parent.create(recursive: true);
    fixture = await parent.createTemp('case-');
    workspace = await Directory(p.join(fixture.path, 'site')).create();
    await File(p.join(workspace.path, 'index.html')).writeAsString(
        '<!doctype html><link rel="stylesheet" href="styles.css"><h1>手机网页</h1>');
    await File(p.join(workspace.path, 'styles.css'))
        .writeAsString('h1 {color:red}');
    preview = StaticWebPreviewServer();
  });
  tearDown(() async {
    await preview.stop();
    await fixture.delete(recursive: true);
  });

  Future<(int, String)> get(Uri uri,
      {String method = 'GET', String? host}) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, uri);
      if (host != null) request.headers.set(HttpHeaders.hostHeader, host);
      final response = await request.close();
      return (response.statusCode, await utf8.decoder.bind(response).join());
    } finally {
      client.close(force: true);
    }
  }

  test('preview serves current HTML and relative assets without a terminal',
      () async {
    final uri = await preview.start(workspace.path);
    expect(uri.host, '127.0.0.1');
    expect((await get(uri)).$2, contains('手机网页'));
    expect((await get(uri.resolve('styles.css'))).$2, 'h1 {color:red}');
    await File(p.join(workspace.path, 'styles.css'))
        .writeAsString('h1 {color:blue}');
    expect((await get(uri.resolve('styles.css'))).$2, 'h1 {color:blue}');
    expect((await get(uri, method: 'HEAD')).$2, isEmpty);
  });

  test(
      'preview rejects missing capability, wrong host, writes and private paths',
      () async {
    await File(p.join(workspace.path, '.env.json'))
        .writeAsString('{"secret":true}');
    await File(p.join(fixture.path, 'secret.json'))
        .writeAsString('{"outside":true}');
    final uri = await preview.start(workspace.path);
    expect((await get(uri.resolve('/'))).$1, 404);
    expect((await get(uri, host: 'untrusted.example')).$1, 403);
    expect((await get(uri, method: 'POST')).$1, 405);
    expect((await get(uri.resolve('.env.json'))).$1, 404);
    expect((await get(Uri.parse('$uri..%2fsecret.json'))).$1, 404);
    expect((await get(uri.resolve('missing.css'))).$1, 404);
  });

  test('stop revokes the old listener and a new start gets a fresh capability',
      () async {
    final old = await preview.start(workspace.path);
    await preview.stop();
    expect(preview.url, isNull);
    await expectLater(get(old), throwsA(isA<SocketException>()));
    final next = await preview.start(workspace.path);
    expect(next.path, isNot(old.path));
    expect((await get(next)).$1, 200);
  });

  test('stop during start cannot publish a late listener', () async {
    final starting = preview.start(workspace.path);
    await preview.stop();
    await expectLater(starting, throwsStateError);
    expect(preview.url, isNull);
  });

  test('review and ZIP contain only reviewed web assets, with relative paths',
      () async {
    await File(p.join(workspace.path, '.env')).writeAsString('PRIVATE=secret');
    await File(p.join(workspace.path, 'README.md'))
        .writeAsString('instructions');
    final deps =
        await Directory(p.join(workspace.path, 'node_modules')).create();
    await File(p.join(deps.path, 'dependency.js')).writeAsString('dependency');
    final review = await service.review(workspace.path);
    expect(review.files.map((file) => file.path), ['index.html', 'styles.css']);
    expect(review.excluded, 3);
    // New files cannot slip into the already reviewed delivery.
    await File(p.join(workspace.path, 'new.js')).writeAsString('new');
    final zip = await service.export(
        review, File(p.join(fixture.path, 'delivery.zip')));
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    expect(
        archive.files.map((file) => file.name), ['index.html', 'styles.css']);
    expect(utf8.decode(archive.files.first.content), contains('手机网页'));
  });

  test('changed or removed reviewed files prevent publishing a stale ZIP',
      () async {
    final review = await service.review(workspace.path);
    final destination = File(p.join(fixture.path, 'delivery.zip'));
    await File(p.join(workspace.path, 'styles.css')).writeAsString('new value');
    await expectLater(service.export(review, destination), throwsStateError);
    expect(await destination.exists(), isFalse);
    await File(p.join(workspace.path, 'styles.css')).delete();
    await expectLater(service.export(review, destination),
        throwsA(isA<FileSystemException>()));
  });

  test(
      'export never overwrites an existing file or writes into the source project',
      () async {
    final review = await service.review(workspace.path);
    final destination = File(p.join(fixture.path, 'delivery.zip'));
    await destination.writeAsString('existing');
    await expectLater(service.export(review, destination), throwsStateError);
    expect(await destination.readAsString(), 'existing');
    await expectLater(
        service.export(review, File(p.join(workspace.path, 'delivery.zip'))),
        throwsStateError);
  });

  test('missing entry and oversized assets fail instead of claiming delivery',
      () async {
    await File(p.join(workspace.path, 'index.html')).delete();
    await expectLater(
        service.review(workspace.path), throwsA(isA<FileSystemException>()));
    await expectLater(
        preview.start(workspace.path), throwsA(isA<FileSystemException>()));
    await File(p.join(workspace.path, 'index.html'))
        .writeAsString('<h1>ok</h1>');
    final large = await File(p.join(workspace.path, 'large.js'))
        .open(mode: FileMode.write);
    await large.truncate(StaticWebProjectService.maxFileBytes + 1);
    await large.close();
    await expectLater(
        service.review(workspace.path), throwsA(isA<FileSystemException>()));
  });
}
