import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/environment_service.dart';
import 'package:mobile_agent/infrastructure/terminal/linux_runtime.dart';
import 'package:mobile_agent/infrastructure/tools/android_device_tool.dart';
import 'package:mobile_agent/presentation/settings/device_capabilities_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_FakePrivilegeBridge> pumpPage(
    WidgetTester tester,
    Map<String, dynamic> status,
  ) async {
    tester.view.physicalSize = const Size(1200, 8000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bridge = _FakePrivilegeBridge(status);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: DeviceCapabilitiesPage(
            bridge: bridge,
            environmentService: _FakeEnvironmentService(_environmentSnapshot()),
            isAndroidPlatform: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return bridge;
  }

  testWidgets('non-root sections load without probing su', (tester) async {
    final bridge = await pumpPage(tester, {
      'root': {'rootGranted': false, 'probed': false},
      'shizuku': {'installed': true, 'running': false},
      'permissions': {
        'allFilesAccess': false,
        'usageAccess': true,
        'notificationPolicy': true,
        'writeSettings': true,
        'installPackages': true,
        'bluetoothConnect': true,
        'vpnPrepared': true,
        'writeSecureSettings': false,
        'readLogs': true,
      },
      'networkFilter': {'enabled': false, 'domains': [], 'apps': []},
      'routes': {'shell': null, 'rootUid': null, 'storage': null},
    });

    expect(bridge.rootStatusCalls, 0);
    expect(bridge.probeRootArguments, [false]);
    expect(find.text('Shizuku'), findsOneWidget);
    expect(find.text('未运行'), findsOneWidget);
    expect(find.text('打开'), findsOneWidget);
    expect(find.text('仅降级'), findsOneWidget);
    expect(find.textContaining('（Root 未检查）'), findsOneWidget);
    expect(find.text('所有文件访问'), findsOneWidget);
    // WRITE_SECURE_SETTINGS 只能经特权通道授予，没有“去授权”入口。
    expect(find.text('去授权'), findsOneWidget);
    expect(find.text('未启用'), findsOneWidget);

    await tester.tap(find.text('去授权'));
    await tester.pumpAndSettle();

    expect(bridge.openedPermissions, ['all_files']);
    expect(find.text('已打开系统页面，完成后返回此页会自动刷新'), findsOneWidget);
    expect(bridge.probeRootArguments, [false, false]);
  });

  testWidgets('granted Shizuku shows its route and VPN rules', (tester) async {
    final bridge = await pumpPage(tester, {
      'root': {'rootGranted': false, 'probed': true},
      'shizuku': {
        'installed': true,
        'running': true,
        'permissionGranted': true,
        'mode': 'adb',
      },
      'permissions': {'allFilesAccess': true},
      'networkFilter': {
        'enabled': true,
        'running': true,
        'mode': 'dns',
        'domains': ['ads.example.com'],
        'apps': ['com.example.chat'],
        'limitations': ['域名屏蔽基于 DNS'],
      },
      'routes': {'shell': 'shizuku', 'rootUid': null, 'storage': 'app'},
    });

    expect(find.text('可用 · ADB 模式'), findsOneWidget);
    expect(find.text('授予权限'), findsOneWidget);
    expect(
      find.textContaining('系统命令：Shizuku · 需 uid 0：无（降级） · 共享存储：应用权限'),
      findsOneWidget,
    );
    expect(find.text('运行中'), findsOneWidget);
    expect(find.textContaining('ads.example.com'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(bridge.filterToggles, [false]);
  });
}

class _FakePrivilegeBridge extends AndroidDeviceControlBridge {
  _FakePrivilegeBridge(this.status);

  final Map<String, dynamic> status;
  var rootStatusCalls = 0;
  final probeRootArguments = <bool>[];
  final openedPermissions = <String>[];
  final filterToggles = <bool>[];

  @override
  Future<Map<String, dynamic>> deviceInfo() async =>
      {'manufacturer': 'Example', 'model': 'Phone', 'sdk': 36};

  @override
  Future<Map<String, dynamic>> systemStatus() async =>
      {'selinuxEnforcing': true};

  @override
  Future<List<Map<String, String>>> listAuthorizedFolders() async => [];

  @override
  Future<Map<String, dynamic>> rootStatus() async {
    rootStatusCalls++;
    return {'rootGranted': false};
  }

  @override
  Future<Map<String, dynamic>> privilegeStatus({bool probeRoot = true}) async {
    probeRootArguments.add(probeRoot);
    return status;
  }

  @override
  Future<Map<String, dynamic>> openSpecialPermission(String kind) async {
    openedPermissions.add(kind);
    return {'opened': true, 'kind': kind, 'userActionRequired': true};
  }

  @override
  Future<Map<String, dynamic>> setNetworkFilterEnabled(bool enabled) async {
    filterToggles.add(enabled);
    return {'applied': true, 'enabled': enabled};
  }
}

class _FakeEnvironmentService extends EnvironmentService {
  _FakeEnvironmentService(this.snapshot);

  final EnvironmentSnapshot snapshot;

  @override
  void invalidate() {}

  @override
  Future<EnvironmentSnapshot> inspect({bool force = false}) async => snapshot;
}

EnvironmentSnapshot _environmentSnapshot() {
  const runtime = LinuxRuntimeInfo(
    kind: LinuxRuntimeKind.androidShell,
    label: 'Android Shell',
    available: true,
    detail: 'Android Shell 可用',
  );
  return EnvironmentSnapshot(
    selected: runtime,
    candidates: const [runtime],
    architecture: 'arm64',
    freeBytes: null,
    checkedAt: DateTime(2026, 9, 24),
    tools: const [],
    templates: const [],
    candidateStatuses: const [
      EnvironmentCandidateStatus(runtime: runtime),
    ],
  );
}
