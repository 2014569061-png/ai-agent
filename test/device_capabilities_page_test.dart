import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/environment_service.dart';
import 'package:mobile_agent/infrastructure/terminal/linux_runtime.dart';
import 'package:mobile_agent/infrastructure/tools/android_device_tool.dart';
import 'package:mobile_agent/presentation/settings/device_capabilities_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Root probing waits for the user to tap Check', (tester) async {
    final bridge = _FakeDeviceBridge();
    final environment = _FakeEnvironmentService(_environmentSnapshot());

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: DeviceCapabilitiesPage(
            bridge: bridge,
            environmentService: environment,
            isAndroidPlatform: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(bridge.rootStatusCalls, 0);
    expect(find.text('Root 授权'), findsOneWidget);
    expect(find.byTooltip('检查 Root'), findsOneWidget);

    await tester.tap(find.byTooltip('检查 Root'));
    await tester.pumpAndSettle();

    expect(bridge.rootStatusCalls, 1);
    expect(find.text('已授权'), findsOneWidget);
    expect(find.text('Magisk'), findsWidgets);
  });
}

class _FakeDeviceBridge extends AndroidDeviceControlBridge {
  var rootStatusCalls = 0;

  @override
  Future<Map<String, dynamic>> deviceInfo() async => {
        'manufacturer': 'Example',
        'model': 'Phone',
        'androidVersion': '16',
        'sdk': 36,
      };

  @override
  Future<Map<String, dynamic>> systemStatus() async =>
      {'selinuxEnforcing': true};

  @override
  Future<List<Map<String, String>>> listAuthorizedFolders() async => [
        {
          'name': 'Download',
          'uri':
              'content://com.android.externalstorage.documents/tree/primary%3ADownload',
        },
      ];

  @override
  Future<Map<String, dynamic>> rootStatus() async {
    rootStatusCalls++;
    return {
      'rootGranted': true,
      'suPresent': true,
      'manager': 'magisk',
    };
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
