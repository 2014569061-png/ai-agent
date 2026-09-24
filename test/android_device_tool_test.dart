import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/tools/android_device_tool.dart';
import 'package:mobile_agent/infrastructure/tools/tool_registry.dart';

Future<dynamic> _executeAfterPreview(
  AndroidDeviceTool tool,
  Map<String, dynamic> arguments,
) async {
  final preview = await tool.execute({...arguments, 'preview': true});
  if (!preview.ok) return preview;
  final planId = preview.data?['planId'];
  if (planId is! String) return preview;
  final executionArguments = tool.authorizeAfterApproval({
    ...arguments,
    'planId': planId,
  });
  return tool.execute(executionArguments);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('nexus/device_control');
  final calls = <MethodCall>[];
  final tool = AndroidDeviceTool();
  final previewTool = AndroidDevicePreviewTool(deviceTool: tool);
  final privateDataPreviewTool = AndroidAppPrivateDataPreviewTool();
  final privateDataTool = AndroidAppPrivateDataTool();
  Map<String, dynamic>? batchOperationResponse;

  setUp(() {
    calls.clear();
    batchOperationResponse = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'listApps':
          return [
            {'packageName': 'com.example.chat', 'label': 'Chat'}
          ];
        case 'launchAppByName':
          return {
            'status': 'started',
            'label': '微信',
            'packageName': 'com.example.wechat',
          };
        case 'rootStatus':
          return {'rootGranted': true, 'suPresent': true, 'manager': 'magisk'};
        case 'deviceInfo':
          return {'manufacturer': 'Test', 'model': 'Phone', 'sdk': 35};
        case 'storageInfo':
          return {'totalBytes': 1000, 'availableBytes': 500};
        case 'networkInfo':
          return {
            'connected': true,
            'validated': true,
            'metered': false,
            'transports': ['wifi'],
            'vpn': false,
            'dnsServers': ['192.168.1.1', '2001:db8::1'],
            'domains': 'example.local',
            'httpProxy': {'host': 'proxy.local', 'port': 8080},
          };
        case 'runningProcesses':
          return [
            {'processName': 'com.example.chat', 'pid': 42}
          ];
        case 'foregroundApps':
          return [
            {'processName': 'com.example.chat', 'pid': 42, 'importance': 100}
          ];
        case 'logcatTail':
          return {'text': 'Activity started'};
        case 'crashLogs':
          return {
            'packageName': 'com.example.chat',
            'text': 'FATAL EXCEPTION: main\nProcess: com.example.chat',
            'truncated': false,
            'completed': true,
          };
        case 'appInfo':
          return {
            'packageName': 'com.example.chat',
            'label': 'Chat',
            'versionName': '1.0',
            'enabled': true,
          };
        case 'systemStatus':
          return {
            'batteryPercent': 76,
            'memoryTotalBytes': 1000,
            'memoryAvailableBytes': 400,
            'kernelVersion': 'test-kernel',
            'selinuxEnforcing': true,
            'cpu': {'cores': 8},
            'temperatures': const [],
            'mounts': const [],
          };
        case 'trafficInfo':
          return {
            'appRxBytes': 100,
            'appTxBytes': 50,
            'totalRxBytes': 1000,
            'totalTxBytes': 500,
          };
        case 'traceroute':
          return {
            'host': 'example.com',
            'output': '1 192.168.1.1',
            'completed': true,
            'exitCode': 0,
          };
        case 'systemSettings':
          return {
            'brightness': 0.5,
            'autoRotate': true,
            'musicVolume': 0.4,
            'ringVolume': 0.7,
            'wifiEnabled': true,
            'bluetoothEnabled': false,
            'airplaneModeEnabled': false,
            'locationEnabled': true,
            'doNotDisturbEnabled': false,
            'fontScale': 1.0,
            'refreshRates': [60.0, 120.0],
            'peakRefreshRate': 120.0,
            'minRefreshRate': 60.0,
            'animationScales': {
              'window': 1.0,
              'transition': 1.0,
              'animator': 1.0,
            },
          };
        case 'setBrightness':
          return {'value': 0.8};
        case 'setVolume':
          return {'stream': 'music', 'value': 0.6};
        case 'setAutoRotate':
          return {'enabled': false};
        case 'setWifi':
        case 'setBluetooth':
        case 'setAirplaneMode':
        case 'setLocationEnabled':
        case 'setDoNotDisturb':
          return {'applied': true, 'output': ''};
        case 'setRefreshRate':
          return {'refreshRate': 120.0, 'supported': true};
        case 'setFontScale':
          return {'fontScale': 1.1};
        case 'setAnimationScale':
          return {'applied': true};
        case 'openDefaultAppsSettings':
        case 'openDoNotDisturbSettings':
        case 'openNotificationSettings':
          return {'opened': true, 'userActionRequired': true};
        case 'directorySize':
          return {'path': '/data/local/tmp', 'bytes': 2048};
        case 'portProbe':
          return {
            'host': 'example.com',
            'port': 443,
            'reachable': true,
            'elapsedMs': 12
          };
        case 'restartApp':
          return {'applied': true, 'packageName': 'com.example.chat'};
        case 'appPermissions':
          return {
            'packageName': 'com.example.chat',
            'permissions': [
              {'name': 'android.permission.INTERNET', 'granted': true}
            ]
          };
        case 'recentApps':
          return [
            {'id': 1, 'packageName': 'com.example.chat'}
          ];
        case 'setAppAlias':
          return {'alias': '工作聊天', 'packageName': 'com.example.chat'};
        case 'listAppAliases':
          return [
            {'alias': '工作聊天', 'packageName': 'com.example.chat'}
          ];
        case 'launchDeepLink':
          return {
            'started': true,
            'packageName': 'com.example.chat',
            'uri': 'chat://inbox',
          };
        case 'stopApp':
        case 'clearAppCache':
          return {'applied': true, 'output': ''};
        case 'readRootFile':
          return {
            'path': '/data/local/tmp/report.txt',
            'content': 'ok',
            'truncated': false,
            'bytes': 2,
          };
        case 'inspectAppPrivateData':
          final arguments = call.arguments as Map;
          return arguments['operation'] == 'read'
              ? {
                  'packageName': arguments['packageName'],
                  'path':
                      '/data/user/0/com.example.chat/shared_prefs/settings.xml',
                  'content': '<settings />',
                  'truncated': false,
                  'bytes': 12,
                }
              : {
                  'packageName': arguments['packageName'],
                  'path': '/data/user/0/com.example.chat',
                  'text': 'shared_prefs',
                  'truncated': false,
                };
        case 'listRootFiles':
          return {
            'path': '/data/local/tmp',
            'text': 'drwx------ 2 root root 4096 report',
            'truncated': false,
          };
        case 'writeRootFile':
        case 'deleteRootFile':
        case 'moveRootFile':
          return {'applied': true, 'output': ''};
        case 'networkProbe':
          return {
            'host': 'example.com',
            'resolved': true,
            'reachable': true,
            'address': '93.184.216.34',
            'elapsedMs': 20,
          };
        case 'compressRootFiles':
        case 'extractRootArchive':
          return {'applied': true, 'output': ''};
        case 'searchFilesFiltered':
          return {
            'needsFolderPermission': false,
            'files': [
              {
                'name': 'contract.pdf',
                'uri': 'content://tree/1/document/2',
                'modifiedAtMs': '1700000000000',
              }
            ],
            'truncated': false,
            'indexUsed': true,
            'indexRefreshedRoots': 1,
            'indexComplete': true,
            'indexUpdatedAtMs': 1700000000000,
          };
        case 'refreshSearchIndex':
          return {
            'needsFolderPermission': false,
            'indexedRoots': 1,
            'indexedDocuments': 12,
            'complete': true,
          };
        case 'setFirewallPortRule':
          return {
            'applied': true,
            'output':
                'ipv4=applied ipv6=applied protocol=tcp port=443 enabled=true',
          };
        case 'setHostsBlock':
          return {
            'applied': true,
            'output':
                'hosts=/system/etc/hosts domain=www.example.com enabled=true',
          };
        case 'fileOperation':
          return {
            'applied': true,
            'operation': (call.arguments as Map)['operation'],
            'sourceUri': (call.arguments as Map)['uri'],
            'resultUri': 'content://tree/1/document/renamed',
          };
        case 'fileOperationBatch':
          final arguments = call.arguments as Map;
          final uris = (arguments['uris'] as List).cast<String>();
          return batchOperationResponse ??
              {
                'operation': arguments['operation'],
                'totalCount': uris.length,
                'appliedCount': uris.length,
                'failedCount': 0,
                'partial': false,
                'results': [
                  for (final uri in uris)
                    {
                      'sourceUri': uri,
                      'status': 'applied',
                      'resultUri': uri,
                    },
                ],
              };
        case 'listAuthorizedFolders':
          return [
            {'uri': 'content://tree/1', 'name': 'Documents'}
          ];
        case 'shareFile':
          return null;
        case 'searchFiles':
          return {
            'needsFolderPermission': false,
            'indexUsed': true,
            'files': [
              {'name': 'contract.pdf', 'uri': 'content://tree/1/document/2'}
            ],
          };
        default:
          return {'started': true};
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('lists launchable applications through the Android bridge', () async {
    final result = await tool.execute({'action': 'list_apps'});

    expect(result.ok, isTrue);
    expect(result.data?['apps'], hasLength(1));
    expect(calls.single.method, 'listApps');
  });

  test('launches the selected package', () async {
    final result = await _executeAfterPreview(tool, {
      'action': 'launch_app',
      'packageName': 'com.example.chat',
    });

    expect(result.ok, isTrue);
    expect(result.hasSideEffect, isTrue);
    expect(calls.single.arguments, {'packageName': 'com.example.chat'});
  });

  test('reads root capability without executing a root action', () async {
    final result = await tool.execute({'action': 'root_status'});

    expect(result.ok, isTrue);
    expect(result.data?['rootGranted'], isTrue);
    expect(calls.single.method, 'rootStatus');
  });

  test('planner previews do not issue executable tickets', () async {
    const arguments = {
      'action': 'delete_root_file',
      'path': '/data/local/tmp/report.txt',
    };
    final preview = await previewTool.execute(arguments);
    final planId = preview.data?['planId'] as String;
    final attemptedExecution = await tool.execute({
      ...arguments,
      'planId': planId,
    });
    final approvalDetails = tool.approvalDetailsFor({
      ...arguments,
      'planId': planId,
    });

    expect(previewTool.manifest.risk, ToolRisk.safe);
    expect(preview.ok, isTrue);
    expect(preview.data?['target'], '/data/local/tmp/report.txt');
    expect(preview.data?['riskClass'], 'dangerous');
    expect(preview.data?.containsKey('previewId'), isFalse);
    expect(attemptedExecution.ok, isFalse);
    expect(approvalDetails?['target'], '/data/local/tmp/report.txt');
    expect(approvalDetails?['command'], contains('rm -f'));
    expect(calls, isEmpty);

    tool.rejectApproval({...arguments, 'planId': planId});
    expect(
      tool.approvalDetailsFor({...arguments, 'planId': planId}),
      isNull,
    );
  });

  test('device risk is classified per action and root action', () {
    expect(
      tool.riskForArguments({'action': 'system_status'}),
      ToolRisk.safe,
    );
    expect(
      tool.riskForArguments({'action': 'set_brightness', 'value': 0.5}),
      ToolRisk.requiresConfirmation,
    );
    expect(
      tool.riskForArguments({
        'action': 'delete_root_file',
        'path': '/data/local/tmp/report.txt',
      }),
      ToolRisk.dangerous,
    );
    expect(
      tool.riskForArguments({
        'action': 'delete_root_file',
        'path': '/data/local/tmp/report.txt',
        'preview': true,
      }),
      ToolRisk.safe,
    );
  });

  test('reads device and app information', () async {
    final device = await tool.execute({'action': 'device_info'});
    final app = await tool.execute({
      'action': 'app_info',
      'packageName': 'com.example.chat',
    });

    expect(device.data?['model'], 'Phone');
    expect(app.data?['versionName'], '1.0');
    expect(calls.map((call) => call.method), ['deviceInfo', 'appInfo']);
  });

  test('controls an app only with a validated package name', () async {
    final stopped = await _executeAfterPreview(tool, {
      'action': 'stop_app',
      'packageName': 'com.example.chat',
    });
    final cleared = await _executeAfterPreview(tool, {
      'action': 'clear_app_cache',
      'packageName': 'com.example.chat',
    });
    final rejected = await tool.execute({
      'action': 'stop_app',
      'packageName': 'not a package',
    });

    expect(stopped.ok, isTrue);
    expect(cleared.ok, isTrue);
    expect(rejected.ok, isFalse);
    expect(calls.map((call) => call.method), ['stopApp', 'clearAppCache']);
  });

  test('previews process termination with PID and verifies identity arguments',
      () async {
    final preview = await tool.execute({
      'action': 'kill_process',
      'pid': 42,
      'processName': 'com.example.chat',
      'packageName': 'com.example.chat',
      'preview': true,
    });
    expect(preview.ok, isTrue);
    expect(preview.data?['target'], contains('PID：42'));
    expect(preview.data?['target'], contains('ActivityManager 进程列表'));
    expect(preview.data?['executionPlan'], contains('/proc/42/cmdline'));
    expect(preview.data?['executionPlan'], contains('SIGTERM'));
    expect(preview.data?['command'], isNull);
    expect(calls, isEmpty);

    final terminated = await _executeAfterPreview(tool, {
      'action': 'kill_process',
      'pid': 42,
      'processName': 'com.example.chat',
    });
    final protected = await tool.execute({
      'action': 'kill_process',
      'pid': 42,
      'processName': 'system_server',
    });

    expect(terminated.ok, isTrue);
    expect(calls.single.method, 'killProcess');
    expect(calls.single.arguments, {
      'pid': 42,
      'processName': 'com.example.chat',
    });
    expect(protected.ok, isFalse);
    expect(calls, hasLength(1));
  });

  test('cache preview preserves app data and never invokes pm clear', () async {
    final result = await tool.execute({
      'action': 'clear_app_cache',
      'packageName': 'com.example.chat',
      'preview': true,
    });

    expect(result.ok, isTrue);
    expect(result.data?['target'], '应用包名：com.example.chat');
    expect(result.data?['impact'], contains('不删除账号、设置或数据库'));
    expect(result.data?['command'], isNull);
    expect(result.data?['executionPlan'], contains('cache'));
    expect(result.data?['executionPlan'], contains('code_cache'));
    expect(result.data?['executionPlan'], isNot(contains('pm clear')));
    expect(result.data?['scope'], contains('cache 与 code_cache'));
    expect(calls, isEmpty);
  });

  test('root file reads require a matching preview and allowlisted path',
      () async {
    const arguments = {
      'action': 'read_root_file',
      'path': '/data/local/tmp/report.txt',
    };
    final direct = await tool.execute(arguments);
    final preview = await tool.execute({...arguments, 'preview': true});
    final planId = preview.data?['planId'] as String;
    final executionArguments = tool.authorizeAfterApproval({
      ...arguments,
      'planId': planId,
    });
    final result = await tool.execute(executionArguments);
    final rejectedPreview = await tool.execute({
      'action': 'read_root_file',
      'path': '/data/data/com.example.secret/token',
      'preview': true,
    });

    expect(direct.ok, isFalse);
    expect(preview.ok, isTrue);
    expect(preview.data?['target'], '/data/local/tmp/report.txt');
    expect(preview.data?['scope'], contains('64 KiB'));
    expect(preview.data?['command'], contains('cat --'));
    expect(preview.data?['riskClass'], 'dangerous');
    expect(result.ok, isTrue);
    expect(rejectedPreview.ok, isFalse);
    expect(calls.single.method, 'readRootFile');
  });

  test('root directory queries preview exact bounded commands', () async {
    final size = await tool.execute({
      'action': 'directory_size',
      'path': '/data/local/tmp',
      'preview': true,
    });
    final listing = await tool.execute({
      'action': 'list_root_files',
      'path': '/sdcard/Download',
      'preview': true,
    });
    final invalid = await tool.execute({
      'action': 'directory_size',
      'path': '/data/system',
      'preview': true,
    });

    expect(size.ok, isTrue);
    expect(size.data?['target'], '/data/local/tmp');
    expect(size.data?['command'], contains('du -sk'));
    expect(size.data?['scope'], contains('子项'));
    expect(listing.ok, isTrue);
    expect(listing.data?['target'], '/sdcard/Download');
    expect(listing.data?['command'], contains('ls -la'));
    expect(listing.data?['scope'], contains('32 KiB'));
    expect(invalid.ok, isFalse);
    expect(calls, isEmpty);
  });

  test('lists only allowlisted root directories', () async {
    final result = await _executeAfterPreview(tool, {
      'action': 'list_root_files',
      'path': '/data/local/tmp',
    });
    final rejected = await tool.execute({
      'action': 'list_root_files',
      'path': '/data/system',
    });

    expect(result.ok, isTrue);
    expect(result.data?['text'], contains('report'));
    expect(rejected.ok, isFalse);
    expect(calls.single.method, 'listRootFiles');
  });

  test('supports bounded root file mutations', () async {
    final written = await _executeAfterPreview(tool, {
      'action': 'write_root_file',
      'path': '/data/local/tmp/report.txt',
      'content': 'ok',
    });
    final moved = await _executeAfterPreview(tool, {
      'action': 'move_root_file',
      'source': '/data/local/tmp/report.txt',
      'destination': '/data/local/tmp/report.old',
    });
    final deleted = await _executeAfterPreview(tool, {
      'action': 'delete_root_file',
      'path': '/data/local/tmp/report.old',
    });
    final rejected = await tool.execute({
      'action': 'delete_root_file',
      'path': '/data/local/tmp',
    });

    expect(written.ok, isTrue);
    expect(moved.ok, isTrue);
    expect(deleted.ok, isTrue);
    expect(rejected.ok, isFalse);
    expect(calls.map((call) => call.method),
        ['writeRootFile', 'moveRootFile', 'deleteRootFile']);
  });

  test('runs a validated network probe', () async {
    final result = await tool.execute({
      'action': 'network_probe',
      'host': 'example.com',
    });
    final rejected = await tool.execute({
      'action': 'network_probe',
      'host': 'example.com; id',
    });

    expect(result.ok, isTrue);
    expect(result.data?['reachable'], isTrue);
    expect(rejected.ok, isFalse);
    expect(calls.single.method, 'networkProbe');
  });

  test('compresses and extracts only allowlisted root paths', () async {
    final compressed = await _executeAfterPreview(tool, {
      'action': 'compress_root_files',
      'sources': ['/data/local/tmp/report.txt'],
      'destination': '/data/local/tmp/report.tar.gz',
    });
    final extracted = await _executeAfterPreview(tool, {
      'action': 'extract_root_archive',
      'archive': '/data/local/tmp/report.tar.gz',
      'destination': '/data/local/tmp/out',
    });
    final rejected = await tool.execute({
      'action': 'compress_root_files',
      'sources': ['/data/system'],
      'destination': '/data/local/tmp/report.tar.gz',
    });

    expect(compressed.ok, isTrue);
    expect(extracted.ok, isTrue);
    expect(rejected.ok, isFalse);
    expect(calls.map((call) => call.method),
        ['compressRootFiles', 'extractRootArchive']);
  });

  test('filters authorized files and shares SAF files', () async {
    final filtered = await tool.execute({
      'action': 'search_files_filtered',
      'query': 'contract',
      'extension': '.pdf',
      'modifiedAfterMs': 1600000000000,
    });
    final shared = await _executeAfterPreview(tool, {
      'action': 'share_file',
      'uri': 'content://tree/1/document/2',
    });

    expect(filtered.ok, isTrue);
    expect(filtered.data?['files'], hasLength(1));
    expect(filtered.data?['indexUsed'], isTrue);
    expect(shared.ok, isTrue);
    expect(shared.hasSideEffect, isTrue);
  });

  test('refreshes the SAF file index through the native bridge', () async {
    final result = await tool.execute({'action': 'refresh_file_index'});

    expect(result.ok, isTrue);
    expect(result.data?['indexedRoots'], 1);
    expect(result.data?['complete'], isTrue);
    expect(calls.single.method, 'refreshSearchIndex');
  });

  test('previews SAF file changes and only accepts content URIs', () async {
    final preview = await tool.execute({
      'action': 'file_operation',
      'operation': 'delete',
      'uri': 'content://tree/1/document/2',
      'preview': true,
    });
    expect(preview.ok, isTrue);
    expect(preview.data?['riskClass'], 'dangerous');
    expect(preview.data?['target'], contains('content://tree/1/document/2'));
    expect(calls, isEmpty);

    final rename = await _executeAfterPreview(tool, {
      'action': 'file_operation',
      'operation': 'rename',
      'uri': 'content://tree/1/document/2',
      'newName': 'renamed.pdf',
    });
    final invalid = await tool.execute({
      'action': 'file_operation',
      'operation': 'rename',
      'uri': 'file:///sdcard/secret.txt',
      'newName': '../escape.txt',
      'preview': true,
    });

    expect(rename.ok, isTrue);
    expect(rename.data?['resultUri'], 'content://tree/1/document/renamed');
    expect(invalid.ok, isFalse);
    expect(calls.single.method, 'fileOperation');
    expect(calls.single.arguments, {
      'operation': 'rename',
      'uri': 'content://tree/1/document/2',
      'newName': 'renamed.pdf',
    });
  });

  test(
      'previews and executes bounded SAF batch operations with normalized URIs',
      () async {
    const sourceUris = [
      'content://tree/1/document/2',
      'content://tree/1/document/3',
    ];
    final preview = await tool.execute({
      'action': 'file_operation',
      'operation': 'copy',
      'uris': sourceUris,
      'destinationUri': ' content://tree/1/document/folder ',
      'preview': true,
    });
    expect(preview.ok, isTrue);
    expect(preview.data?['riskClass'], 'requiresConfirmation');
    expect(preview.data?['impact'], contains('2 个文件'));
    expect(calls, isEmpty);

    final result = await _executeAfterPreview(tool, {
      'action': 'file_operation',
      'operation': 'copy',
      'uris': [
        ' content://tree/1/document/2 ',
        'content://tree/1/document/3',
      ],
      'destinationUri': ' content://tree/1/document/folder ',
    });

    expect(result.ok, isTrue);
    expect(result.data?['appliedCount'], 2);
    expect(calls.single.method, 'fileOperationBatch');
    expect(calls.single.arguments, {
      'operation': 'copy',
      'uris': sourceUris,
      'destinationUri': 'content://tree/1/document/folder',
    });
  });

  test('rejects malformed, duplicate, and oversized SAF batches', () async {
    final duplicate = await tool.execute({
      'action': 'file_operation',
      'operation': 'delete',
      'uris': [
        'content://tree/1/document/2',
        ' content://tree/1/document/2 ',
      ],
    });
    final malformed = await tool.execute({
      'action': 'file_operation',
      'operation': 'delete',
      'uris': ['content://tree/1/document/2', 42],
    });
    final oversized = await tool.execute({
      'action': 'file_operation',
      'operation': 'delete',
      'uris': List.generate(
        101,
        (index) => 'content://tree/1/document/$index',
      ),
    });

    expect(duplicate.ok, isFalse);
    expect(malformed.ok, isFalse);
    expect(oversized.ok, isFalse);
    expect(calls, isEmpty);
  });

  test('reports partial SAF batch results without claiming full success',
      () async {
    batchOperationResponse = {
      'operation': 'delete',
      'totalCount': 2,
      'appliedCount': 1,
      'failedCount': 1,
      'partial': true,
      'results': [
        {
          'sourceUri': 'content://tree/1/document/2',
          'status': 'applied',
          'resultUri': '',
        },
        {
          'sourceUri': 'content://tree/1/document/3',
          'status': 'failed',
          'error': 'provider rejected the operation',
        },
      ],
    };

    final result = await _executeAfterPreview(tool, {
      'action': 'file_operation',
      'operation': 'delete',
      'uris': [
        'content://tree/1/document/2',
        'content://tree/1/document/3',
      ],
    });

    expect(result.ok, isTrue);
    expect(result.message, contains('部分完成'));
    expect(result.message, contains('成功 1 个，失败 1 个'));
    expect(result.hasSideEffect, isTrue);
    expect(result.data?['failedCount'], 1);
  });

  test('lists authorized folders for supported SAF destination selection',
      () async {
    final result = await tool.execute({'action': 'list_authorized_folders'});

    expect(result.ok, isTrue);
    expect(result.data?['folders'], hasLength(1));
    expect(calls.single.method, 'listAuthorizedFolders');
  });

  test('reads storage, processes, and logcat diagnostics', () async {
    final storage = await tool.execute({'action': 'storage_info'});
    final processes = await tool.execute({'action': 'running_processes'});
    final logcat = await tool.execute({'action': 'logcat_tail', 'lines': 20});

    expect(storage.data?['availableBytes'], 500);
    expect(processes.data?['processes'], hasLength(1));
    expect(logcat.data?['text'], contains('Activity'));
  });

  test('reads bounded crash logs with optional package filtering', () async {
    final result = await tool.execute({
      'action': 'crash_logs',
      'packageName': 'com.example.chat',
    });
    final rejected = await tool.execute({
      'action': 'crash_logs',
      'packageName': 'bad package',
    });

    expect(result.ok, isTrue);
    expect(result.data?['text'], contains('FATAL EXCEPTION'));
    expect(rejected.ok, isFalse);
  });

  test('reads foreground applications from process diagnostics', () async {
    final result = await tool.execute({'action': 'foreground_apps'});

    expect(result.ok, isTrue);
    expect(result.data?['apps'], hasLength(1));
    expect(calls.single.method, 'foregroundApps');
  });

  test('reads expanded system and app diagnostics', () async {
    final status = await tool.execute({'action': 'system_status'});
    final size = await _executeAfterPreview(tool, {
      'action': 'directory_size',
      'path': '/data/local/tmp',
    });
    final permissions = await tool.execute({
      'action': 'app_permissions',
      'packageName': 'com.example.chat',
    });
    final recent = await tool.execute({'action': 'recent_apps'});

    expect(status.data?['batteryPercent'], 76);
    expect(size.data?['bytes'], 2048);
    expect(permissions.data?['permissions'], hasLength(1));
    expect(recent.data?['apps'], hasLength(1));
  });

  test('supports restart and port probing', () async {
    final restarted = await _executeAfterPreview(tool, {
      'action': 'restart_app',
      'packageName': 'com.example.chat',
    });
    final probe = await tool.execute({
      'action': 'port_probe',
      'host': 'example.com',
      'port': 443,
    });

    expect(restarted.ok, isTrue);
    expect(restarted.hasSideEffect, isTrue);
    expect(probe.data?['reachable'], isTrue);
  });

  test('previews high-risk hosts edits and validates a plain domain', () async {
    const arguments = {
      'action': 'set_hosts_block',
      'domain': ' WWW.Example.com ',
      'enabled': true,
    };
    final preview = await tool.execute({...arguments, 'preview': true});

    expect(preview.ok, isTrue);
    expect(preview.data?['riskClass'], 'dangerous');
    expect(preview.data?['target'], contains('www.example.com'));
    expect(preview.data?['scope'], contains('/system/etc/hosts'));
    expect(preview.data?['command'], isNull);
    expect(preview.data?['rollback'], contains('反转 enabled'));
    expect(calls, isEmpty);

    final executionArguments = tool.authorizeAfterApproval({
      ...arguments,
      'planId': preview.data?['planId'],
    });
    final result = await tool.execute(executionArguments);
    final invalid = await tool.execute({
      ...arguments,
      'domain': 'https://example.com',
      'preview': true,
    });

    expect(result.ok, isTrue);
    expect(calls.single.method, 'setHostsBlock');
    expect(calls.single.arguments, {
      'domain': 'www.example.com',
      'enabled': true,
    });
    expect(invalid.ok, isFalse);
  });

  test('previews firewall port rules and restricts protocol and port',
      () async {
    const arguments = {
      'action': 'set_firewall_port_rule',
      'protocol': 'tcp',
      'port': 443,
      'enabled': true,
    };
    final preview = await tool.execute({...arguments, 'preview': true});

    expect(preview.ok, isTrue);
    expect(preview.data?['riskClass'], 'dangerous');
    expect(preview.data?['target'], contains('TCP 443'));
    expect(preview.data?['command'], isNull);
    expect(preview.data?['executionPlan'], contains('iptables'));
    expect(preview.data?['rollback'], contains('反转 enabled'));
    expect(calls, isEmpty);

    final executionArguments = tool.authorizeAfterApproval({
      ...arguments,
      'planId': preview.data?['planId'],
    });
    final result = await tool.execute(executionArguments);
    final invalid = await tool.execute({
      ...arguments,
      'port': 65536,
      'preview': true,
    });

    expect(result.ok, isTrue);
    expect(result.message, contains('IPv4/IPv6'));
    expect(calls.single.method, 'setFirewallPortRule');
    expect(calls.single.arguments, {
      'protocol': 'tcp',
      'port': 443,
      'enabled': true,
    });
    expect(invalid.ok, isFalse);
  });

  test('reads traffic and traceroute diagnostics', () async {
    final traffic = await tool.execute({'action': 'traffic_info'});
    final route = await tool.execute({
      'action': 'traceroute',
      'host': 'example.com',
    });

    expect(traffic.data?['totalRxBytes'], 1000);
    expect(route.data?['completed'], isTrue);
  });

  test('reads and changes bounded system settings', () async {
    final settings = await tool.execute({'action': 'system_settings'});
    final brightness = await _executeAfterPreview(tool, {
      'action': 'set_brightness',
      'value': 0.8,
    });
    final volume = await _executeAfterPreview(tool, {
      'action': 'set_volume',
      'stream': 'music',
      'value': 0.6,
    });
    final rotate = await _executeAfterPreview(tool, {
      'action': 'set_auto_rotate',
      'enabled': false,
    });
    final rejected = await tool.execute({
      'action': 'set_brightness',
      'value': 1.5,
    });

    expect(settings.data?['brightness'], 0.5);
    expect(settings.data?['wifiEnabled'], isTrue);
    expect(settings.data?['refreshRates'], [60.0, 120.0]);
    expect(brightness.hasSideEffect, isTrue);
    expect(volume.ok, isTrue);
    expect(rotate.ok, isTrue);
    expect(rejected.ok, isFalse);
  });

  test('controls connectivity toggles with individual dangerous previews',
      () async {
    final airplanePreview = await tool.execute({
      'action': 'set_airplane_mode',
      'enabled': true,
      'preview': true,
    });
    expect(airplanePreview.ok, isTrue);
    expect(airplanePreview.data?['riskClass'], 'dangerous');
    expect(airplanePreview.data?['impact'], contains('切断远程控制'));
    expect(airplanePreview.data?['command'],
        'su -c "cmd connectivity airplane-mode enable"');

    final wifi = await _executeAfterPreview(tool, {
      'action': 'set_wifi',
      'enabled': false,
    });
    final bluetooth = await _executeAfterPreview(tool, {
      'action': 'set_bluetooth',
      'enabled': true,
    });
    final location = await _executeAfterPreview(tool, {
      'action': 'set_location',
      'enabled': false,
    });
    final dnd = await _executeAfterPreview(tool, {
      'action': 'set_do_not_disturb',
      'enabled': true,
    });

    expect(wifi.hasSideEffect, isTrue);
    expect(bluetooth.ok, isTrue);
    expect(location.ok, isTrue);
    expect(dnd.ok, isTrue);
    expect(
      calls.map((call) => call.method),
      ['setWifi', 'setBluetooth', 'setLocationEnabled', 'setDoNotDisturb'],
    );
  });

  test('previews DNS refresh, VPN settings, and allowlisted service restart',
      () async {
    final dns = await tool.execute({
      'action': 'refresh_dns',
      'preview': true,
    });
    final vpn = await tool.execute({
      'action': 'open_vpn_settings',
      'preview': true,
    });
    final service = await tool.execute({
      'action': 'restart_service',
      'serviceName': 'logd',
      'preview': true,
    });
    final rejectedService = await tool.execute({
      'action': 'restart_service',
      'serviceName': 'system_server',
      'preview': true,
    });

    expect(dns.ok, isTrue);
    expect(dns.data?['command'], 'su -c "ndc resolver flushdefaultif"');
    expect(vpn.ok, isTrue);
    expect(vpn.data?['scope'], contains('用户'));
    expect(service.ok, isTrue);
    expect(service.data?['riskClass'], 'dangerous');
    expect(service.data?['command'], 'su -c "setprop ctl.restart logd"');
    expect(rejectedService.ok, isFalse);
    expect(calls, isEmpty);
  });

  test('adjusts display settings and opens user-mediated system pages',
      () async {
    final refresh = await _executeAfterPreview(tool, {
      'action': 'set_refresh_rate',
      'value': 120,
    });
    final font = await _executeAfterPreview(tool, {
      'action': 'set_font_scale',
      'value': 1.1,
    });
    final animations = await _executeAfterPreview(tool, {
      'action': 'set_animation_scale',
      'value': 0,
    });
    final defaultApps = await _executeAfterPreview(tool, {
      'action': 'open_default_apps_settings',
    });
    final notification = await _executeAfterPreview(tool, {
      'action': 'open_notification_settings',
      'packageName': 'com.example.chat',
    });
    final invalidRate = await tool.execute({
      'action': 'set_refresh_rate',
      'value': 241,
      'preview': true,
    });

    expect(refresh.data?['refreshRate'], 120.0);
    expect(font.data?['fontScale'], 1.1);
    expect(animations.ok, isTrue);
    expect(defaultApps.data?['userActionRequired'], isTrue);
    expect(notification.data?['userActionRequired'], isTrue);
    expect(invalidRate.ok, isFalse);
  });

  test('manages app aliases and launches deep links', () async {
    final saved = await _executeAfterPreview(tool, {
      'action': 'set_app_alias',
      'alias': '工作聊天',
      'packageName': 'com.example.chat',
    });
    final aliases = await tool.execute({'action': 'list_app_aliases'});
    final launched = await _executeAfterPreview(tool, {
      'action': 'launch_deep_link',
      'packageName': 'com.example.chat',
      'deepLink': 'chat://inbox',
    });

    expect(saved.ok, isTrue);
    expect(aliases.data?['aliases'], hasLength(1));
    expect(launched.ok, isTrue);
    expect(launched.hasSideEffect, isTrue);
  });

  test('previews mutating actions without calling the Android bridge',
      () async {
    final result = await tool.execute({
      'action': 'delete_root_file',
      'path': '/data/local/tmp/report.txt',
      'preview': true,
    });

    expect(result.ok, isTrue);
    expect(result.data?['preview'], isTrue);
    expect(result.data?['requiresConfirmation'], isTrue);
    expect(result.data?['mustWaitForUser'], isTrue);
    expect(result.data?['planId'], isA<String>());
    expect(result.data?.containsKey('previewId'), isFalse);
    expect(result.data?['reversible'], isFalse);
    expect(result.data?['target'], '/data/local/tmp/report.txt');
    expect(result.data?['command'],
        'su -c "rm -f -- \'/data/local/tmp/report.txt\'"');
    expect(calls, isEmpty);
  });

  test('requires a matching one-time preview for device mutations', () async {
    final direct = await tool.execute({
      'action': 'delete_root_file',
      'path': '/data/local/tmp/report.txt',
    });
    final preview = await tool.execute({
      'action': 'delete_root_file',
      'path': '/data/local/tmp/report.txt',
      'preview': true,
    });
    final planId = preview.data?['planId'] as String;
    final mismatchedArguments = {
      'action': 'delete_root_file',
      'path': '/data/local/tmp/other.txt',
      'planId': planId,
    };
    expect(tool.approvalDetailsFor(mismatchedArguments), isNull);
    expect(
      () => tool.authorizeAfterApproval(mismatchedArguments),
      throwsA(isA<ToolApprovalAuthorizationException>()),
    );
    final authorizedArguments = tool.authorizeAfterApproval({
      'action': 'delete_root_file',
      'path': '/data/local/tmp/report.txt',
      'planId': planId,
    });
    final executed = await tool.execute(authorizedArguments);
    final replay = await tool.execute(authorizedArguments);

    expect(direct.ok, isFalse);
    expect(executed.ok, isTrue);
    expect(replay.ok, isFalse);
    expect(calls, hasLength(1));
  });

  test('rejects unsafe previews and describes file move source and target',
      () async {
    final rejected = await tool.execute({
      'action': 'delete_root_file',
      'path': '/data/system/secret',
      'preview': true,
    });
    final move = await tool.execute({
      'action': 'move_root_file',
      'source': '/data/local/tmp/from.txt',
      'destination': '/data/local/tmp/to.txt',
      'preview': true,
    });

    expect(rejected.ok, isFalse);
    expect(move.ok, isTrue);
    expect(move.data?['target'],
        '/data/local/tmp/from.txt → /data/local/tmp/to.txt');
    expect(move.data?['command'],
        'su -c "mv -n -- \'/data/local/tmp/from.txt\' \'/data/local/tmp/to.txt\'"');
    expect(calls, isEmpty);
  });

  test('reads network diagnostics without executing a command', () async {
    final result = await tool.execute({'action': 'network_info'});

    expect(result.ok, isTrue);
    expect(result.data?['connected'], isTrue);
    expect(result.data?['transports'], contains('wifi'));
    expect(result.data?['dnsServers'], contains('192.168.1.1'));
    expect(result.data?['httpProxy']?['port'], 8080);
    expect(calls.single.method, 'networkInfo');
  });

  test('matches and launches an app by the user-provided name in one call',
      () async {
    final result = await _executeAfterPreview(tool, {
      'action': 'launch_app_by_name',
      'appName': '打开微信',
    });

    expect(result.ok, isTrue);
    expect(result.hasSideEffect, isTrue);
    expect(calls.single.method, 'launchAppByName');
    expect(calls.single.arguments, {'query': '打开微信'});
  });

  test('returns candidates without launching when the app name is ambiguous',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return {
        'status': 'ambiguous',
        'candidates': [
          {'label': '微信', 'packageName': 'com.example.wechat'},
          {'label': '微信测试版', 'packageName': 'com.example.wechat.beta'},
        ],
      };
    });

    final result = await _executeAfterPreview(tool, {
      'action': 'launch_app_by_name',
      'appName': '微信',
    });

    expect(result.ok, isTrue);
    expect(result.data?['status'], 'ambiguous');
    expect(result.data?['candidates'], hasLength(2));
    expect(result.hasSideEffect, isFalse);
  });

  test('reports when first file search needs folder authorization', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return {'needsFolderPermission': true, 'files': []};
    });

    final result = await tool.execute({
      'action': 'search_files',
      'query': 'contract',
    });

    expect(result.ok, isTrue);
    expect(result.data?['needsFolderPermission'], isTrue);
  });

  test('returns files found in an authorized folder', () async {
    final result = await tool.execute({
      'action': 'search_files',
      'query': 'contract',
    });

    expect(result.ok, isTrue);
    expect(result.data?['files'], hasLength(1));
    expect(result.data?['indexUsed'], isTrue);
    expect(calls.single.arguments['query'], 'contract');
    expect(calls.single.arguments['requestId'], isNotEmpty);
  });

  test('rejects file paths outside SAF content URIs', () async {
    final result = await _executeAfterPreview(tool, {
      'action': 'open_file',
      'uri': '/storage/emulated/0/contract.pdf',
    });

    expect(result.ok, isFalse);
    expect(calls, isEmpty);
  });

  test('opens only a SAF content URI', () async {
    final result = await _executeAfterPreview(tool, {
      'action': 'open_file',
      'uri': 'content://tree/1/document/2',
    });

    expect(result.ok, isTrue);
    expect(calls.single.method, 'openFile');
  });

  test('private app data needs dangerous approval after its safe preview',
      () async {
    expect(privateDataPreviewTool.manifest.risk, ToolRisk.safe);
    expect(privateDataTool.manifest.risk, ToolRisk.dangerous);
    expect(
      privateDataTool.riskForArguments({'action': 'list'}),
      ToolRisk.dangerous,
    );
    expect(
      privateDataTool.manifest.parametersSchema['properties'],
      contains('planId'),
    );

    final listPreview = await privateDataPreviewTool.execute({
      'action': 'list',
      'packageName': 'com.example.chat',
    });
    expect(listPreview.ok, isTrue);
    expect(listPreview.data?['target'], '/data/user/0/com.example.chat');
    expect(listPreview.data?['riskClass'], 'dangerous');
    expect(listPreview.data?['mustWaitForUser'], isTrue);
    expect(listPreview.data?['planId'], isA<String>());
    expect(listPreview.data?.containsKey('previewId'), isFalse);
    expect(listPreview.data?['command'], contains('readlink -f'));
    expect(listPreview.data?['command'], contains('ls -lan'));
    expect(calls, isEmpty);

    final listArguments = {
      'action': 'list',
      'packageName': 'com.example.chat',
      'planId': listPreview.data?['planId'],
    };
    final approvalDetails = privateDataTool.approvalDetailsFor(listArguments);
    final authorizedList =
        privateDataTool.authorizeAfterApproval(listArguments);
    expect(approvalDetails?['target'], '/data/user/0/com.example.chat');
    expect(approvalDetails?['riskClass'], 'dangerous');
    expect(approvalDetails?['command'], contains('exit 25'));
    expect(approvalDetails?['command'], contains('head -n 101'));
    expect(authorizedList, contains('previewId'));
    expect(authorizedList, isNot(contains('planId')));
    final listing = await privateDataTool.execute(authorizedList);
    final replay = await privateDataTool.execute(authorizedList);
    final readPreview = await privateDataPreviewTool.execute({
      'action': 'read',
      'packageName': 'com.example.chat',
      'path': 'shared_prefs/settings.xml',
    });
    final readArguments = {
      'action': 'read',
      'packageName': 'com.example.chat',
      'path': 'shared_prefs/settings.xml',
      'planId': readPreview.data?['planId'],
    };
    final read = await privateDataTool.execute(
      privateDataTool.authorizeAfterApproval(readArguments),
    );

    expect(listing.ok, isTrue);
    expect(replay.ok, isFalse);
    expect(read.data?['content'], '<settings />');
    expect(calls.map((call) => call.method), [
      'inspectAppPrivateData',
      'inspectAppPrivateData',
    ]);
    expect(calls.last.arguments, {
      'operation': 'read',
      'packageName': 'com.example.chat',
      'relativePath': 'shared_prefs/settings.xml',
    });
  });

  test(
      'private app data rejects traversal and non-text reads before bridge access',
      () async {
    final traversal = await privateDataTool.execute({
      'action': 'read',
      'packageName': 'com.example.chat',
      'path': 'shared_prefs/../../data/system/token.xml',
    });
    final absolute = await privateDataTool.execute({
      'action': 'list',
      'packageName': 'com.example.chat',
      'path': '/data/user/0/com.example.chat',
    });
    final binary = await privateDataTool.execute({
      'action': 'read',
      'packageName': 'com.example.chat',
      'path': 'databases/accounts.db',
    });
    final badPackage = await privateDataTool.execute({
      'action': 'list',
      'packageName': 'com.example.chat;id',
    });
    final noPreview = await privateDataTool.execute({
      'action': 'list',
      'packageName': 'com.example.chat',
    });
    final planPreview = await privateDataPreviewTool.execute({
      'action': 'list',
      'packageName': 'com.example.chat',
    });
    final rejectedArguments = {
      'action': 'list',
      'packageName': 'com.example.chat',
      'planId': planPreview.data?['planId'],
    };
    privateDataTool.rejectApproval(rejectedArguments);

    expect(traversal.ok, isFalse);
    expect(absolute.ok, isFalse);
    expect(binary.ok, isFalse);
    expect(badPackage.ok, isFalse);
    expect(noPreview.ok, isFalse);
    expect(
      () => privateDataTool.authorizeAfterApproval(rejectedArguments),
      throwsA(isA<ToolApprovalAuthorizationException>()),
    );
    expect(calls, isEmpty);
  });

  test('private app data preview cannot authorize a different path', () async {
    final preview = await privateDataPreviewTool.execute({
      'action': 'read',
      'packageName': 'com.example.chat',
      'path': 'shared_prefs/settings.xml',
    });
    final mismatched = {
      'action': 'read',
      'packageName': 'com.example.chat',
      'path': 'shared_prefs/credentials.xml',
      'planId': preview.data?['planId'],
    };

    expect(privateDataTool.approvalDetailsFor(mismatched), isNull);
    expect(
      () => privateDataTool.authorizeAfterApproval(mismatched),
      throwsA(isA<ToolApprovalAuthorizationException>()),
    );
    expect(calls, isEmpty);
  });
}
