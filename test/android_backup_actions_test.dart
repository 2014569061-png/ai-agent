import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/infrastructure/tools/android_device_tool.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('nexus/device_backup');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  PlatformException? nextError;
  const backupId = 'app-20260924-101500-ab12';

  setUp(() {
    calls.clear();
    nextError = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (nextError != null && call.method != 'inspectBackup') {
        throw nextError!;
      }
      switch (call.method) {
        case 'listBackups':
          return {
            'backups': [
              {'backupId': backupId, 'kind': 'app_data'},
            ],
            'total': 1,
          };
        case 'inspectBackup':
          return {
            'backupId': backupId,
            'kind': 'app_data',
            'packageName': 'com.example.notes',
            'entries': [
              for (var i = 0; i < 25; i++)
                {'path': 'databases/db$i.sqlite', 'bytes': 1000 + i},
            ],
            'entryCount': 25,
            'remainingEntries': 5,
            'uncompressedBytes': 4096,
            'totalBytes': 2048,
            'restoreCoverage': ['shared_prefs', 'databases'],
            'restoreCompatibility': 'same_version',
          };
        case 'backupAppData':
          return {'backupId': backupId, 'totalBytes': 2048};
        case 'restoreAppData':
          return {
            'packageName': 'com.example.notes',
            'undoBackupId': 'prerestore-20260924-101600-cd34',
          };
      }
      return <String, dynamic>{};
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('backup risk tiers: list is safe, personal export needs confirmation, '
      'root backup and delete are dangerous', () {
    final tool = AndroidDeviceTool();
    expect(tool.riskForArguments({'action': 'backup_list'}), ToolRisk.safe);
    expect(
      tool.riskForArguments(
          {'action': 'backup_personal_data', 'category': 'sms'}),
      ToolRisk.requiresConfirmation,
    );
    expect(
      tool.riskForArguments(
          {'action': 'backup_app_data', 'packageName': 'com.example.notes'}),
      ToolRisk.dangerous,
    );
    expect(
      tool.riskForArguments({'action': 'backup_delete', 'backupId': backupId}),
      ToolRisk.dangerous,
    );
    expect(tool.requiresPreviewPlan({'action': 'backup_list'}), isFalse);
    expect(
      tool.requiresPreviewPlan(
          {'action': 'restore_app_data', 'backupId': backupId}),
      isTrue,
    );
  });

  test('read-only backup listing executes without a plan', () async {
    final result = await AndroidDeviceTool().execute({'action': 'backup_list'});
    expect(result.ok, isTrue);
    expect(result.data?['total'], 1);
  });

  test('restore preview lists first 20 files, sizes and overwrite scope',
      () async {
    final tool = AndroidDeviceTool();
    final preview = await tool.preview({
      'action': 'restore_app_data',
      'backupId': backupId,
    });
    expect(preview.ok, isTrue);
    final data = preview.data!;
    expect(data['planId'], isA<String>());
    expect(data['files'], hasLength(20));
    expect(data['fileCount'], 25);
    expect(data['remainingFiles'], 5);
    expect(data['overwriteScope'], ['shared_prefs', 'databases']);
    expect(data['compatibility'], 'same_version');
    expect(data['rollback'], contains('undoBackupId'));
    expect(calls.map((c) => c.method), isNot(contains('restoreAppData')));

    final authorized = tool.authorizeAfterApproval({
      'action': 'restore_app_data',
      'backupId': backupId,
      'planId': data['planId'],
    });
    final result = await tool.execute(authorized);
    expect(result.ok, isTrue);
    expect(result.data?['undoBackupId'], startsWith('prerestore-'));
  });

  test('mutating backup actions without an approved plan are refused',
      () async {
    final result = await AndroidDeviceTool().execute({
      'action': 'backup_app_data',
      'packageName': 'com.example.notes',
    });
    expect(result.ok, isFalse);
    expect(calls.map((c) => c.method), isNot(contains('backupAppData')));
  });

  test('native SELinux and root failures map to explicit tool codes', () async {
    Future<String> runWith(String code) async {
      nextError = PlatformException(code: code, message: code);
      final tool = AndroidDeviceTool();
      final arguments = {
        'action': 'backup_app_data',
        'packageName': 'com.example.notes',
      };
      final preview = await tool.preview(arguments);
      final authorized = tool.authorizeAfterApproval({
        ...arguments,
        'planId': preview.data!['planId'],
      });
      return (await tool.execute(authorized)).code;
    }

    expect(await runWith('SELINUX_DENIED'), ToolCodes.permissionRequired);
    expect(await runWith('ROOT_UNAVAILABLE'), ToolCodes.rootRequired);
    expect(await runWith('TIMEOUT'), ToolCodes.timeout);
  });

  test('invalid backup arguments are rejected before any native call',
      () async {
    final tool = AndroidDeviceTool();
    final preview = await tool.preview({
      'action': 'backup_directory',
      'path': '/sdcard',
    });
    expect(preview.ok, isFalse);
    expect(preview.code, ToolCodes.invalidArguments);
    final badId = await tool.preview({
      'action': 'backup_delete',
      'backupId': '../../etc',
    });
    expect(badId.ok, isFalse);
  });
}
