import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/update/windows_package_downloader.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.bytes, {this.fail = false});
  final List<int> bytes;
  final bool fail;
  int calls = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls++;
    if (fail) {
      throw DioException(
          requestOptions: options, type: DioExceptionType.connectionError);
    }
    return ResponseBody.fromBytes(bytes, 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late PathProviderPlatform original;
  final zip = ZipEncoder().encode(
      Archive()..addFile(ArchiveFile('mobile_agent.exe', 3, [1, 2, 3])));
  setUp(() async {
    original = PathProviderPlatform.instance;
    root = await Directory.systemTemp.createTemp('nexus-windows-update-');
    PathProviderPlatform.instance = _Paths(root.path);
  });
  tearDown(() async {
    PathProviderPlatform.instance = original;
    await root.delete(recursive: true);
  });
  WindowsPackageDownloader downloader(_Adapter adapter) =>
      WindowsPackageDownloader(Dio()..httpClientAdapter = adapter);
  Future<List<FileSystemEntity>> artifacts() async =>
      root.list(recursive: true).toList();

  test('verified ZIP becomes a complete portable package with no staging files',
      () async {
    final digest = sha256.convert(zip).toString();
    final result = await downloader(_Adapter(zip)).download(
        'https://example.invalid/windows.zip',
        expectedSha256: digest);
    expect(result.success, isTrue);
    expect(await File(result.path!).readAsBytes(), zip);
    expect(p.basename(result.path!), endsWith('-windows-x64.zip'));
    expect((await artifacts()).whereType<File>(), hasLength(1));
    expect((await artifacts()).whereType<Directory>(), hasLength(1));
  });
  test('missing digest fails before any network or disk activity', () async {
    final adapter = _Adapter(zip);
    final result = await downloader(adapter)
        .download('https://example.invalid/windows.zip', expectedSha256: null);
    expect(result.error, contains('缺少 SHA-256'));
    expect(adapter.calls, 0);
    expect(await artifacts(), isEmpty);
  });
  test('mismatch removes the unverified download', () async {
    final result = await downloader(_Adapter(zip)).download(
        'https://example.invalid/windows.zip',
        expectedSha256: sha256.convert([4]).toString());
    expect(result.error, contains('校验失败'));
    expect((await artifacts()).whereType<File>(), isEmpty);
    expect((await artifacts()).whereType<Directory>(), hasLength(1));
  });
  test('a checksum-valid HTML response is still rejected as an invalid ZIP',
      () async {
    final bytes = '<html>error</html>'.codeUnits;
    final result = await downloader(_Adapter(bytes)).download(
        'https://example.invalid/windows.zip',
        expectedSha256: sha256.convert(bytes).toString());
    expect(result.error, contains('压缩包无效'));
    expect((await artifacts()).whereType<File>(), isEmpty);
  });
  test('network failure leaves no incomplete package', () async {
    final result = await downloader(_Adapter(zip, fail: true)).download(
        'https://example.invalid/windows.zip',
        expectedSha256: sha256.convert(zip).toString());
    expect(result.success, isFalse);
    expect((await artifacts()).whereType<File>(), isEmpty);
  });
  test(
      'repeating the download reuses a verified package and preserves unrelated files',
      () async {
    final service = downloader(_Adapter(zip));
    final digest = sha256.convert(zip).toString();
    final first = await service.download('https://example.invalid/windows.zip',
        expectedSha256: digest);
    final unrelated = File(p.join(root.path, 'updates', 'notes.txt'))
      ..writeAsStringSync('keep');
    final second = await service.download('https://example.invalid/windows.zip',
        expectedSha256: digest);
    expect(second.path, first.path);
    expect(unrelated.readAsStringSync(), 'keep');
    expect((await artifacts()).whereType<File>(), hasLength(2));
  });
}
