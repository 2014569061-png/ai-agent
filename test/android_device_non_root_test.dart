import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/infrastructure/tools/android_device_tool.dart';

Future<ToolResult> _executeAfterPreview(
  AndroidDeviceTool tool,
  Map<String, dynamic> arguments,
) async {
  final preview = await tool.execute({...arguments, 'preview': true});
  if (!preview.ok) return preview;
  final planId = preview.data?['planId'];
  if (planId is! String) return preview;
  return tool.execute(
    tool.authorizeAfterApproval({...arguments, 'planId': planId}),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const control = MethodChannel('nexus/device_control');
  const backup = MethodChannel('nexus/device_backup');
  final calls = <MethodCall>[];
  final tool = AndroidDeviceTool();
  final routes = <String, dynamic>{
    'shell': 'shizuku',
    'rootUid': null,
    'storage': 'app',
    'storageDataLocalTmp': 'shizuku',
  };
  Object? wifiResponse;

  setUp(() {
    calls.clear();
    wifiResponse = {'applied': true, 'executedVia': 'shizuku'};
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(control, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'privilegeStatus':
          return {
            'root': {'rootGranted': false, 'probed': true},
            'shizuku': {
              'running': true,
              'permissionGranted': true,
              'uid': 2000
            },
            'permissions': {'allFilesAccess': true},
            'networkFilter': {'enabled': false},
            'routes': routes,
          };
        case 'setWifi':
          if (wifiResponse is PlatformException) throw wifiResponse!;
          return wifiResponse;
        case 'setAppNetworkBlock':
          return {
            'applied': true,
            'executedVia': 'vpn',
            'blocked': call.arguments['enabled'],
            'previouslyBlocked': false,
          };
        case 'setHostsBlock':
          return {'applied': true, 'executedVia': 'vpn'};
        case 'openSpecialPermission':
          return {
            'opened': true,
            'kind': call.arguments['kind'],
            'userActionRequired': true,
          };
      }
      return null;
    });
    messenger.setMockMethodCallHandler(backup, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'backupAppData':
          return {
            'backupId': 'apk-20260924-101010-abcd',
            'apkCount': 3,
            'totalBytes': 4096,
            'executedVia': 'app',
          };
        case 'inspectBackup':
          return {
            'backupId': call.arguments['backupId'],
            'kind': 'apk',
            'packageName': 'com.example.chat',
            'entryCount': 3,
            'signatureMatches': true,
          };
        case 'restoreAppData':
          return {
            'restored': false,
            'installRequested': true,
            'userActionRequired': true,
            'executedVia': 'package_installer',
            'packageName': 'com.example.chat',
            'apkCount': 3,
            'message': '请在系统安装界面确认',
          };
      }
      return null;
    });
  });

  test('preview never calls native code and explains unknown routes', () async {
    final preview = await tool.execute({
      'action': 'set_wifi',
      'enabled': false,
      'preview': true,
    });

    expect(preview.ok, isTrue);
    expect(calls, isEmpty);
    final route = preview.data?['executionRoute'] as Map;
    expect(route['requirement'], 'shell');
    expect(route['route'], 'unknown');
    expect(route['fallback'], contains('Wi-Fi'));
  });

  test('privilege_status refreshes the route snapshot used by previews',
      () async {
    final status = await tool.execute({'action': 'privilege_status'});
    expect(status.ok, isTrue);
    expect(calls.single.method, 'privilegeStatus');
    calls.clear();

    final wifi = await tool.execute({
      'action': 'set_wifi',
      'enabled': true,
      'preview': true,
    });
    final cache = await tool.execute({
      'action': 'clear_app_cache',
      'packageName': 'com.example.chat',
      'preview': true,
    });
    final kill = await tool.execute({
      'action': 'kill_process',
      'pid': 4242,
      'processName': 'com.example.chat',
      'preview': true,
    });
    final sdcard = await tool.execute({
      'action': 'directory_size',
      'path': '/sdcard/Download',
      'preview': true,
    });

    expect(calls, isEmpty);
    expect((wifi.data?['executionRoute'] as Map)['route'], 'shizuku');
    final cacheRoute = cache.data?['executionRoute'] as Map;
    expect(cacheRoute['route'], 'fallback');
    expect(cacheRoute['fallback'], contains('应用详情页'));
    expect(
      (kill.data?['executionRoute'] as Map)['label'],
      contains('执行会失败'),
    );
    expect((sdcard.data?['executionRoute'] as Map)['route'], 'app');
  });

  test('settings-page fallbacks are reported as not yet applied', () async {
    wifiResponse = {
      'applied': false,
      'executedVia': 'settings',
      'userActionRequired': true,
      'message': '已打开 Wi-Fi 面板，请手动切换',
    };

    final result = await _executeAfterPreview(tool, {
      'action': 'set_wifi',
      'enabled': true,
    });

    expect(result.ok, isTrue);
    expect(result.effect, ToolEffect.unknown);
    expect(result.message, startsWith('尚未直接生效'));
    expect(result.message, contains('Wi-Fi 面板'));
    expect(result.data?['executedVia'], 'settings');
  });

  test('missing privilege maps to ROOT_REQUIRED with native details', () async {
    wifiResponse = PlatformException(
      code: 'PRIVILEGE_REQUIRED',
      message: '该操作需要 Root 或已授权的 Shizuku',
      details: {'shizukuInstalled': false},
    );

    final result = await _executeAfterPreview(tool, {
      'action': 'set_wifi',
      'enabled': true,
    });

    expect(result.ok, isFalse);
    expect(result.code, ToolCodes.rootRequired);
    expect(result.data?['nativeCode'], 'PRIVILEGE_REQUIRED');
    expect(result.data?['shizukuInstalled'], isFalse);
  });

  test('risk tiers for non-root actions', () {
    expect(
      tool.riskForArguments({'action': 'privilege_status'}),
      ToolRisk.safe,
    );
    expect(
      tool.riskForArguments({'action': 'network_filter_status'}),
      ToolRisk.safe,
    );
    expect(
      tool.riskForArguments({
        'action': 'set_app_network_block',
        'packageName': 'com.example.chat',
        'enabled': true,
      }),
      ToolRisk.dangerous,
    );
    expect(
      tool.riskForArguments({
        'action': 'grant_privileged_permissions',
      }),
      ToolRisk.dangerous,
    );
    expect(
      tool.riskForArguments({
        'action': 'open_special_permission',
        'permissionKind': 'all_files',
      }),
      ToolRisk.requiresConfirmation,
    );
    expect(
      tool.riskForArguments({
        'action': 'backup_app_data',
        'packageName': 'com.example.chat',
        'scope': 'apk',
      }),
      ToolRisk.requiresConfirmation,
    );
    expect(
      tool.riskForArguments({
        'action': 'backup_app_data',
        'packageName': 'com.example.chat',
        'scope': 'full',
      }),
      ToolRisk.dangerous,
    );
  });

  test('app network block runs through the local VPN after preview', () async {
    final preview = await tool.execute({
      'action': 'set_app_network_block',
      'packageName': 'com.example.chat',
      'enabled': true,
      'preview': true,
    });
    expect(preview.data?['reversible'], isTrue);
    expect(preview.data?['rollback'], contains('反转 enabled'));
    expect(calls, isEmpty);

    final result = await _executeAfterPreview(tool, {
      'action': 'set_app_network_block',
      'packageName': 'com.example.chat',
      'enabled': true,
    });
    expect(result.ok, isTrue);
    expect(result.effect, ToolEffect.applied);
    expect(result.data?['executedVia'], 'vpn');
    expect(calls.single.method, 'setAppNetworkBlock');
  });

  test('hosts block reports the VPN fallback', () async {
    final result = await _executeAfterPreview(tool, {
      'action': 'set_hosts_block',
      'domain': 'ads.example.com',
      'enabled': true,
    });
    expect(result.ok, isTrue);
    expect(result.message, contains('本地 VPN'));
  });

  test('open_special_permission validates the kind and stays applied',
      () async {
    final rejected = await tool.execute({
      'action': 'open_special_permission',
      'permissionKind': 'root_shell',
      'preview': true,
    });
    expect(rejected.ok, isFalse);

    final opened = await _executeAfterPreview(tool, {
      'action': 'open_special_permission',
      'permissionKind': 'all_files',
    });
    expect(opened.ok, isTrue);
    expect(opened.effect, ToolEffect.applied);
    expect(calls.single.arguments['kind'], 'all_files');
  });

  test('APK backup and installer restore need no root', () async {
    final preview = await tool.execute({
      'action': 'backup_app_data',
      'packageName': 'com.example.chat',
      'scope': 'apk',
      'preview': true,
    });
    expect(preview.data?['target'], contains('安装包'));
    expect(preview.data?.containsKey('command'), isFalse);
    expect(preview.data?.containsKey('executionRoute'), isFalse);

    final backedUp = await _executeAfterPreview(tool, {
      'action': 'backup_app_data',
      'packageName': 'com.example.chat',
      'scope': 'apk',
    });
    expect(backedUp.ok, isTrue);
    expect(backedUp.message, contains('3 个 APK'));

    calls.clear();
    final restored = await _executeAfterPreview(tool, {
      'action': 'restore_app_data',
      'backupId': 'apk-20260924-101010-abcd',
    });
    expect(restored.ok, isTrue);
    expect(restored.effect, ToolEffect.unknown);
    expect(restored.message, contains('系统安装界面'));
    expect(
      calls.map((call) => call.method),
      ['inspectBackup', 'restoreAppData'],
    );
  });
}
