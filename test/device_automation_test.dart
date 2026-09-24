import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/audit_service.dart';
import 'package:mobile_agent/application/device_action_runner.dart';
import 'package:mobile_agent/application/device_automation_service.dart';
import 'package:mobile_agent/domain/device_automation.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/application/android_automation_tool.dart';
import 'package:mobile_agent/infrastructure/tools/android_device_tool.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const deviceChannel = MethodChannel('nexus/device_control');
  const automationChannel = MethodChannel('nexus/device_automation');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late AppDatabase db;
  late List<MethodCall> deviceCalls;
  late List<MethodCall> automationCalls;
  late Map<String, dynamic> settings;
  late List<Map<String, dynamic>> folderFiles;

  DeviceAutomationService buildService() {
    final audit = AuditService();
    Future<AppDatabase> database() async => db;
    return DeviceAutomationService(
      runner: DeviceActionRunner(
        tool: AndroidDeviceTool(),
        audit: audit,
        database: database,
      ),
      audit: audit,
      database: database,
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    deviceCalls = [];
    automationCalls = [];
    settings = {
      'brightness': 0.8,
      'doNotDisturbEnabled': false,
      'bluetoothEnabled': true,
      'musicVolume': 0.5,
    };
    folderFiles = [];
    messenger.setMockMethodCallHandler(deviceChannel, (call) async {
      deviceCalls.add(call);
      switch (call.method) {
        case 'systemSettings':
          return settings;
        case 'setBrightness':
          settings['brightness'] = (call.arguments as Map)['value'];
          return {'brightness': settings['brightness']};
        case 'setDoNotDisturb':
          settings['doNotDisturbEnabled'] = (call.arguments as Map)['enabled'];
          return {'enabled': settings['doNotDisturbEnabled']};
        case 'rootStatus':
          return {'rootGranted': true, 'suPresent': true};
        case 'fileOperationBatch':
          return {
            'status': 'completed',
            'succeeded': (call.arguments as Map)['uris'],
            'failed': const [],
          };
      }
      return <String, dynamic>{};
    });
    messenger.setMockMethodCallHandler(automationChannel, (call) async {
      automationCalls.add(call);
      switch (call.method) {
        case 'syncRules':
          return {'synced': true};
        case 'pendingFires':
          return jsonEncode([]);
        case 'resolveFire':
          return {'resolved': true};
        case 'listFolderFiles':
          final total = folderFiles.fold<int>(
            0,
            (sum, file) => sum + (file['size'] as int),
          );
          return {
            'files': folderFiles,
            'matchedCount': folderFiles.length,
            'totalBytes': total,
            'remaining': 0,
          };
      }
      return null;
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(deviceChannel, null);
    messenger.setMockMethodCallHandler(automationChannel, null);
    await db.close();
  });

  group('domain', () {
    test('rule JSON round trip keeps trigger and actions', () {
      const rule = AutomationRule(
        id: 'auto_1',
        name: '夜间勿扰',
        enabled: true,
        trigger: AutomationTrigger.time(hour: 23, minute: 5, days: [1, 5]),
        actions: [
          AutomationAction('set_do_not_disturb', {'enabled': true}),
        ],
        createdAtMs: 1,
        updatedAtMs: 2,
      );
      final decoded = AutomationRule.fromJson(
        jsonDecode(jsonEncode(rule.toJson())),
      )!;
      expect(decoded.name, '夜间勿扰');
      expect(decoded.trigger.describe(), '每周一、五 23:05');
      expect(decoded.actions.single.arguments['enabled'], isTrue);
      expect(decoded.requiresRoot, isTrue);
      expect(decoded.hasIrreversibleAction, isFalse);
    });

    test('validation rejects non-whitelisted actions and bad triggers', () {
      AutomationRule rule(AutomationTrigger trigger, List<AutomationAction> a) =>
          AutomationRule(
            id: 'x',
            name: 'n',
            enabled: true,
            trigger: trigger,
            actions: a,
            createdAtMs: 0,
            updatedAtMs: 0,
          );
      const ok = [AutomationAction('set_brightness', {'value': 0.3})];
      expect(rule(const AutomationTrigger.batteryBelow(20), ok).validate(),
          isNull);
      expect(rule(const AutomationTrigger.batteryBelow(2), ok).validate(),
          contains('5%–95%'));
      expect(rule(const AutomationTrigger.wifiConnected(' '), ok).validate(),
          contains('SSID'));
      expect(
        rule(const AutomationTrigger.batteryBelow(20), const [
          AutomationAction('write_root_file', {'path': '/sdcard/a'}),
        ]).validate(),
        contains('不支持'),
      );
      expect(
        rule(
          const AutomationTrigger.batteryBelow(20),
          List.filled(6, ok.single),
        ).validate(),
        contains('最多'),
      );
      expect(
        rule(const AutomationTrigger.batteryBelow(20), const [
          AutomationAction('clean_folder', {'treeUri': '/sdcard', 'olderThanDays': 3}),
        ]).validate(),
        contains('treeUri'),
      );
    });

    test('undo uses the state captured before execution', () {
      final dnd = automationUndoFor(
        {'action': 'set_do_not_disturb', 'enabled': true},
        {'doNotDisturbEnabled': false},
      );
      expect(dnd?.arguments, {'action': 'set_do_not_disturb', 'enabled': false});
      // 已是目标状态时没有可撤销的变化。
      expect(
        automationUndoFor(
          {'action': 'set_wifi', 'enabled': true},
          {'wifiEnabled': true},
        ),
        isNull,
      );
      // 执行前状态未知：明确不可自动撤销。
      expect(
        automationUndoFor({'action': 'set_brightness', 'value': 0.2}, {}),
        isNull,
      );
      expect(
        automationUndoFor(
          {'action': 'set_volume', 'stream': 'music', 'value': 0.1},
          {'musicVolume': 0.5},
        )?.arguments['value'],
        0.5,
      );
      expect(
        automationUndoFor({'action': 'clear_app_cache', 'packageName': 'a.b'}, {}),
        isNull,
      );
    });
  });

  group('android_automation tool', () {
    final tool = AndroidAutomationTool(service: DeviceAutomationService());

    test('risk tiers follow rule contents', () {
      expect(tool.riskForArguments({'action': 'list_rules'}), ToolRisk.safe);
      expect(
        tool.riskForArguments({
          'action': 'create_rule',
          'name': '亮度',
          'trigger': {'type': 'battery_below', 'threshold': 20},
          'actions': [
            {'action': 'set_brightness', 'value': 0.2},
          ],
        }),
        ToolRisk.requiresConfirmation,
      );
      expect(
        tool.riskForArguments({
          'action': 'create_rule',
          'name': '蓝牙',
          'trigger': {'type': 'battery_below', 'threshold': 20},
          'actions': [
            {'action': 'set_bluetooth', 'enabled': false},
          ],
        }),
        ToolRisk.dangerous,
      );
      expect(
        tool.riskForArguments({
          'action': 'create_rule',
          'name': '清理',
          'trigger': {'type': 'time', 'hour': 3, 'minute': 0},
          'actions': [
            {
              'action': 'clean_folder',
              'treeUri': 'content://x/tree/1',
              'olderThanDays': 30,
            },
          ],
        }),
        ToolRisk.dangerous,
      );
      expect(
        tool.riskForArguments(
            {'action': 'set_rule_enabled', 'ruleId': 'a', 'enabled': true}),
        ToolRisk.dangerous,
      );
      expect(tool.requiresPreviewPlan({'action': 'create_rule'}), isFalse);
    });

    test('approval details describe trigger, actions and irreversibility', () {
      final details = tool.approvalDetailsFor({
        'action': 'create_rule',
        'name': '清理下载',
        'trigger': {'type': 'time', 'hour': 3, 'minute': 0},
        'actions': [
          {
            'action': 'clean_folder',
            'treeUri': 'content://x/tree/1',
            'olderThanDays': 30,
            'extension': 'apk',
          },
        ],
      })!;
      expect(details['scope'], contains('每天 03:00'));
      expect(details['reversible'], isFalse);
      expect(details['rollback'], contains('不可撤销'));
      expect(details['impact'], contains('确认'));
    });

    test('create_rule rejects actions outside the whitelist', () async {
      final result = await tool.execute({
        'action': 'create_rule',
        'name': '飞行',
        'trigger': {'type': 'battery_below', 'threshold': 10},
        'actions': [
          {'action': 'set_airplane_mode', 'enabled': true},
        ],
      });
      expect(result.ok, isFalse);
      expect(result.code, ToolCodes.invalidArguments);
    });
  });

  group('service', () {
    test('rule lifecycle is persisted, synced and audited', () async {
      final service = buildService();
      final rule = await service.createRule(
        name: '低电量省电',
        trigger: const AutomationTrigger.batteryBelow(20),
        actions: const [AutomationAction('set_brightness', {'value': 0.2})],
        userRequest: '电量低于20%就把亮度调低',
      );
      expect((await service.rules()).single.id, rule.id);
      expect(automationCalls.where((c) => c.method == 'syncRules'), isNotEmpty);
      final synced = jsonDecode(
        (automationCalls.last.arguments as Map)['rules'] as String,
      ) as List;
      expect(synced.single['trigger'], {'type': 'battery_below', 'threshold': 20});

      await service.setEnabled(rule.id, false);
      expect((await service.rules()).single.enabled, isFalse);
      await service.deleteRule(rule.id);
      expect(await service.rules(), isEmpty);

      final logs = (await db.recentAuditLogs())
          .where((log) => log.type == 'device_automation')
          .toList();
      expect(logs, hasLength(3));
      final events = logs
          .map((log) => (jsonDecode(log.detail) as Map)['event'])
          .toSet();
      expect(events, {'created', 'paused', 'deleted'});
      final created = logs.firstWhere(
        (log) => (jsonDecode(log.detail) as Map)['event'] == 'created',
      );
      expect(jsonDecode(created.detail)['userRequest'], '电量低于20%就把亮度调低');
    });

    test('confirmed fire executes via one-time tickets, audits and supports undo',
        () async {
      final service = buildService();
      final rule = await service.createRule(
        name: '夜间',
        trigger: const AutomationTrigger.time(hour: 23, minute: 0),
        actions: const [
          AutomationAction('set_brightness', {'value': 0.3}),
          AutomationAction('set_do_not_disturb', {'enabled': true}),
        ],
      );
      const fire = AutomationFire(
        fireId: 'fire_0123456789abcdef',
        ruleId: 'x',
        ruleName: '夜间',
        trigger: '每天 23:00',
        firedAtMs: 0,
      );
      final prepared = await service.prepare(rule, fire: fire);
      expect(prepared.actions.every((a) => a.executable), isTrue);
      expect(prepared.actions[1].riskClass, 'dangerous');
      // 预览阶段不得触碰设备。
      expect(
        deviceCalls.where((c) =>
            c.method == 'setBrightness' || c.method == 'setDoNotDisturb'),
        isEmpty,
      );

      final run = await service.executePrepared(prepared);
      expect(run.status, 'executed');
      expect(settings['brightness'], 0.3);
      expect(settings['doNotDisturbEnabled'], isTrue);
      expect(run.steps[0].undoArguments, {'action': 'set_brightness', 'value': 0.8});
      expect(run.steps[1].undoArguments,
          {'action': 'set_do_not_disturb', 'enabled': false});
      expect(
        automationCalls.where((c) => c.method == 'resolveFire').single.arguments,
        {'fireId': 'fire_0123456789abcdef'},
      );

      final deviceLogs = (await db.recentAuditLogs())
          .where((log) => log.type == 'android_device_operation')
          .map((log) => jsonDecode(log.detail) as Map)
          .toList();
      expect(deviceLogs, hasLength(2));
      expect(
        deviceLogs.every((d) =>
            (d['intent'] as Map)['tool'] == 'android_automation' &&
            (d['intent'] as Map)['source'] == 'automation_rule'),
        isTrue,
      );
      expect(
        deviceLogs.every((d) => (d['timing'] as Map)['durationMs'] is int),
        isTrue,
      );
      expect(deviceLogs.first['userRequest'], contains('夜间'));

      // 重放同一计划必须失败（一次性票据）。
      final replay = await service.runner.executeConfirmed(
        [prepared.actions.first],
        userRequest: 'replay',
      );
      expect(replay.single.result.ok, isFalse);

      final undo = await service.prepareUndo(run.id, 0);
      final outcome = await service.executeUndo(run.id, 0, undo);
      expect(outcome.result.ok, isTrue);
      expect(settings['brightness'], 0.8);
      final stored = (await service.runs()).first;
      expect(stored.steps[0].undoneAtMs, isNotNull);
      expect(stored.steps[0].canUndo, isFalse);
      expect(() => service.prepareUndo(run.id, 0), throwsStateError);
    });

    test('dismissing a fire rejects plans and records the decision', () async {
      final service = buildService();
      final rule = await service.createRule(
        name: '亮度',
        trigger: const AutomationTrigger.batteryBelow(30),
        actions: const [AutomationAction('set_brightness', {'value': 0.1})],
      );
      const fire = AutomationFire(
        fireId: 'fire_aaaaaaaaaaaaaaaa',
        ruleId: 'x',
        ruleName: '亮度',
        trigger: '电量低于 30%',
        firedAtMs: 0,
      );
      final prepared = await service.prepare(rule, fire: fire);
      final run = await service.dismiss(prepared);
      expect(run.status, 'dismissed');
      expect(settings['brightness'], 0.8);
      expect(automationCalls.where((c) => c.method == 'resolveFire'), isNotEmpty);
      final outcome = await service.runner.executeConfirmed(
        prepared.actions,
        userRequest: 'late',
      );
      expect(outcome.single.result.ok, isFalse);
    });

    test('clean_folder lists matching files and becomes a batch delete preview',
        () async {
      final service = buildService();
      const rule = AutomationRule(
        id: 'r',
        name: '清理',
        enabled: true,
        trigger: AutomationTrigger.time(hour: 3, minute: 0),
        actions: [
          AutomationAction('clean_folder', {
            'treeUri': 'content://com.android.externalstorage.documents/tree/primary%3ADownload',
            'olderThanDays': 30,
            'extension': 'apk',
          }),
        ],
        createdAtMs: 0,
        updatedAtMs: 0,
      );

      final empty = await service.prepare(rule);
      expect(empty.actions.single.executable, isFalse);
      expect(empty.actions.single.error, contains('没有符合条件'));

      folderFiles = [
        {
          'uri': 'content://com.android.externalstorage.documents/tree/primary%3ADownload/document/primary%3ADownload%2Fa.apk',
          'name': 'a.apk',
          'size': 1024,
          'modifiedMs': 1,
        },
        {
          'uri': 'content://com.android.externalstorage.documents/tree/primary%3ADownload/document/primary%3ADownload%2Fb.apk',
          'name': 'b.apk',
          'size': 2048,
          'modifiedMs': 1,
        },
      ];
      final prepared = await service.prepare(rule);
      final action = prepared.actions.single;
      final listCall =
          automationCalls.lastWhere((c) => c.method == 'listFolderFiles');
      expect((listCall.arguments as Map)['extension'], 'apk');
      expect(action.arguments['action'], 'file_operation');
      expect(action.arguments['operation'], 'delete');
      expect(action.arguments['uris'], hasLength(2));
      expect(action.extra['fileCount'], 2);
      expect(action.extra['totalBytes'], 3072);
      expect(action.extra['sample'], ['a.apk', 'b.apk']);
      if (action.executable) {
        expect(action.reversible, isFalse);
      }
    });
  });
}
