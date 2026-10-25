import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/update/update_service.dart';
import 'package:mobile_agent/infrastructure/update/windows_package_downloader.dart';
import 'package:mobile_agent/presentation/settings/update_sheet.dart';

class _WindowsUpdate extends UpdateService {
  _WindowsUpdate({this.fail = false})
      : super(targetPlatform: TargetPlatform.windows);
  final bool fail;
  int calls = 0;
  @override
  Future<WindowsPackageDownloadResult> downloadWindowsPackage(String url,
      {required String? expectedSha256,
      void Function(double progress)? onProgress}) async {
    calls++;
    onProgress?.call(1);
    return fail
        ? const WindowsPackageDownloadResult.failure('校验失败')
        : const WindowsPackageDownloadResult.success('C:/updates/windows.zip');
  }

  @override
  Future<UpdateInstallResult> downloadAndInstallDetailed(String url,
      {void Function(double progress)? onProgress,
      String? expectedSha256,
      bool requireSha256 = true}) async {
    throw StateError('Windows must not invoke the APK installer');
  }
}

void main() {
  Future<void> show(WidgetTester tester, _WindowsUpdate service) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: UpdateSheet(
      info: const UpdateInfo(
          version: '0.9.1',
          notes: '',
          windowsZipUrl: 'https://example.invalid/windows.zip',
          sha256: 'digest'),
      service: service,
    ))));
  }

  testWidgets(
      'Windows update presents portable upgrade instructions and download result',
      (tester) async {
    final service = _WindowsUpdate();
    await show(tester, service);
    expect(find.text('下载并安装'), findsNothing);
    expect(find.textContaining('解压到新目录'), findsOneWidget);
    await tester.tap(find.text('下载 Windows 更新包'));
    await tester.pumpAndSettle();
    expect(service.calls, 1);
    expect(find.text('打开下载位置'), findsOneWidget);
    expect(find.textContaining('校验通过'), findsOneWidget);
    expect(find.textContaining('已拉起系统安装'), findsNothing);
  });
  testWidgets('failed Windows download shows the error and allows retry',
      (tester) async {
    final service = _WindowsUpdate(fail: true);
    await show(tester, service);
    await tester.tap(find.text('下载 Windows 更新包'));
    await tester.pumpAndSettle();
    expect(find.text('校验失败'), findsOneWidget);
    expect(find.text('打开下载位置'), findsNothing);
    await tester.tap(find.text('下载 Windows 更新包'));
    await tester.pumpAndSettle();
    expect(service.calls, 2);
  });

  testWidgets(
      'long Windows release notes fit a narrow bottom sheet with large text',
      (tester) async {
    tester.view.physicalSize = const Size(900, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        builder: (_) => MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                                textScaler: const TextScaler.linear(2)),
                            child: UpdateSheet(
                                info: UpdateInfo(
                                    version: '0.9.1',
                                    notes: List.filled(20, '这是完整的新版本更新说明。')
                                        .join('\n'),
                                    windowsZipUrl:
                                        'https://example.invalid/windows.zip'),
                                service: _WindowsUpdate()))),
                    child: const Text('检查更新'))))));
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('下载 Windows 更新包'), findsOneWidget);
  });
}
