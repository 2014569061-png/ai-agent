import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/update/update_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 把下载目录指到临时目录。
class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

/// 假下载适配器：替换网络层，才能在不联网的情况下断言
/// 「摘要不匹配的包绝不交给安装器」这类安全语义。
class _FakeDownloadAdapter implements HttpClientAdapter {
  _FakeDownloadAdapter(this.body);

  final List<int> body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromBytes(body, 200);

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses GitHub SHA-256 sidecar formats', () {
    const digest =
        '4cec4b6b0e26d501e29b884cc401a8962d16527435d1c1ecda69aa67f7d8b3a8';
    expect(UpdateService.parseSha256('$digest  app-release.apk'), digest);
    expect(UpdateService.parseSha256('sha256:$digest'), digest);
    expect(UpdateService.parseSha256('invalid checksum'), isNull);
  });

  group('安装校验默认 fail-closed', () {
    // 这些用例都在校验守卫处就返回，不会发起任何网络请求。
    test('未提供摘要时默认拒绝安装', () async {
      final result = await UpdateService()
          .downloadAndInstallDetailed('https://example.invalid/app.apk');

      expect(result.success, isFalse);
      expect(
        result.message,
        contains('缺少 SHA-256'),
        reason: '默认值必须是「没有摘要就不装」，否则任何忘记传摘要的调用方都会静默失去完整性保护',
      );
    });

    test('摘要格式非法等同于缺失，同样拒绝', () async {
      final result = await UpdateService().downloadAndInstallDetailed(
        'https://example.invalid/app.apk',
        expectedSha256: 'not-a-real-digest',
      );

      expect(result.success, isFalse);
      expect(result.message, contains('缺少 SHA-256'));
    });

    test('空摘要同样拒绝', () async {
      final result = await UpdateService().downloadAndInstallDetailed(
        'https://example.invalid/app.apk',
        expectedSha256: '',
      );

      expect(result.success, isFalse);
      expect(result.message, contains('缺少 SHA-256'));
    });
  });

  group('isNewer', () {
    test('0.8.6.1 对 0.8.6 是更新（第四段可比较）', () {
      expect(UpdateService.isNewer('0.8.6.1', '0.8.6'), isTrue);
    });

    test('0.8.6.2 对 0.8.6.1 是更新', () {
      expect(UpdateService.isNewer('0.8.6.2', '0.8.6.1'), isTrue);
    });

    test('0.8.6.1 对 0.8.6.2 不是更新', () {
      expect(UpdateService.isNewer('0.8.6.1', '0.8.6.2'), isFalse);
    });

    test('相同版本不是更新', () {
      expect(UpdateService.isNewer('0.8.6', '0.8.6'), isFalse);
      expect(UpdateService.isNewer('0.8.6.1', '0.8.6.1'), isFalse);
    });

    test('0.8.7 对 0.8.6 是更新', () {
      expect(UpdateService.isNewer('0.8.7', '0.8.6'), isTrue);
    });

    test('缺段按 0 补位：0.9 对 0.8.6 是更新，0.8 对 0.8.6 不是', () {
      expect(UpdateService.isNewer('0.9', '0.8.6'), isTrue);
      expect(UpdateService.isNewer('0.8', '0.8.6'), isFalse);
    });
  });

  // 这条路径此前没有测试：Dio 写死在字段里，只能人工在真机上验，覆盖率 19%。
  // 它是全应用权限最高的一段代码（装 APK），值得用断言把语义钉住。
  group('下载 → 校验 → 安装', () {
    const channel = MethodChannel('nexus/update');
    late Directory root;
    late List<String> installPaths;

    // 合法 APK 的最小字节：ZIP 魔数 + 填充。
    List<int> apkBytes([int filler = 64]) =>
        <int>[0x50, 0x4b, 0x03, 0x04, ...List<int>.filled(filler, 0x00)];

    UpdateService serviceWith(List<int> body) {
      final dio = Dio();
      dio.httpClientAdapter = _FakeDownloadAdapter(body);
      return UpdateService(dio: dio);
    }

    void mockInstaller(Future<dynamic> Function(MethodCall call) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, handler);
    }

    setUp(() async {
      root = await Directory.systemTemp.createTemp('nexus-update-');
      PathProviderPlatform.instance = _TempPathProvider(root.path);
      installPaths = <String>[];
      mockInstaller((call) async {
        if (call.method == 'installApk') {
          installPaths.add((call.arguments as Map)['path'] as String);
          return <String, dynamic>{'status': 'started'};
        }
        return null;
      });
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      if (root.existsSync()) await root.delete(recursive: true);
    });

    test('摘要匹配时才把安装包交给系统安装器', () async {
      final bytes = apkBytes();
      final digest = sha256.convert(bytes).toString();

      final result = await serviceWith(bytes).downloadAndInstallDetailed(
        'https://example.invalid/app.apk',
        expectedSha256: digest,
      );

      expect(result.success, isTrue);
      expect(result.sha256, digest);
      expect(installPaths, hasLength(1));
      // 交给安装器的必须是校验过的那份文件，而不是「某个路径」。
      final installed = File(installPaths.single);
      expect(installed.existsSync(), isTrue);
      expect(await installed.readAsBytes(), bytes);
    });

    test('摘要不匹配时绝不调用安装器', () async {
      final bytes = apkBytes();

      final result = await serviceWith(bytes).downloadAndInstallDetailed(
        'https://example.invalid/app.apk',
        expectedSha256: sha256.convert(const <int>[1, 2, 3]).toString(),
      );

      expect(result.success, isFalse);
      expect(result.message, contains('校验失败'));
      expect(
        installPaths,
        isEmpty,
        reason: '摘要不符的包一旦落到安装器手里，「校验」就只是装饰',
      );
    });

    test('响应体不是 APK 时被拒绝，同样不调用安装器', () async {
      final result = await serviceWith('<html>404 Not Found</html>'.codeUnits)
          .downloadAndInstallDetailed(
        'https://example.invalid/app.apk',
        expectedSha256: sha256.convert(apkBytes()).toString(),
      );

      expect(result.success, isFalse);
      expect(result.message, contains('无效'));
      expect(installPaths, isEmpty);
    });

    test('系统要求「允许安装未知应用」时原样透出该状态', () async {
      mockInstaller((call) async {
        if (call.method == 'installApk') {
          return <String, dynamic>{'status': 'permission_required'};
        }
        return null;
      });
      final bytes = apkBytes();

      final result = await serviceWith(bytes).downloadAndInstallDetailed(
        'https://example.invalid/app.apk',
        expectedSha256: sha256.convert(bytes).toString(),
      );

      expect(result.success, isFalse);
      expect(result.permissionRequired, isTrue);
      expect(result.message, contains('未知应用'));
    });
  });
}
