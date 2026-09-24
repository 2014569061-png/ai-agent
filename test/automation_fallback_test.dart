import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/android_automation_tool.dart';
import 'package:mobile_agent/application/audit_service.dart';
import 'package:mobile_agent/application/device_action_runner.dart';
import 'package:mobile_agent/application/device_automation_service.dart';
import 'package:mobile_agent/domain/device_automation.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/tools/android_device_tool.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const automationChannel = MethodChannel('nexus/device_automation');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('automationFallbackFor', () {
    const wifiOff = AutomationAction('set_wifi', {'enabled': false});
    const dnd = AutomationAction('set_do_not_disturb', {'enabled': true});
    const cache =
        AutomationAction('clear_app_cache', {'packageName': 'com.example.a'});
    const volume =
        AutomationAction('set_volume', {'stream': 'music', 'value': 0.2});

    AutomationPrivilegeContext context({
      bool shell = false,
      bool rootUid = false,
      int sdk = 35,
      Map<String, bool> permissions = const {},
    }) =>
        AutomationPrivilegeContext(
          shellAvailable: shell,
          rootUidAvailable: rootUid,
          sdkInt: sdk,
          permissions: permissions,
        );

    test('no privilege channel degrades settings actions', () {
      expect(automationFallbackFor(wifiOff, context()), contains('Wi-Fi 面板'));
      expect(automationFallbackFor(dnd, context()), contains('勿扰授权页'));
      expect(automationFallbackFor(cache, context()), contains('应用详情页'));
      expect(automationFallbackFor(volume, context()), isNull);
    });

    test('Shizuku, permissions and old Android versions avoid fallbacks', () {
      expect(automationFallbackFor(wifiOff, context(shell: true)), isNull);
      expect(automationFallbackFor(wifiOff, context(sdk: 28)), isNull);
      expect(
        automationFallbackFor(
          dnd,
          context(permissions: {'notificationPolicy': true}),
        ),
        isNull,
      );
      // ADB 模式 Shizuku：Android 14+ 才能用 pm clear --cache-only。
      expect(automationFallbackFor(cache, context(shell: true)), isNull);
      expect(
        automationFallbackFor(cache, context(shell: true, sdk: 33)),
        isNotNull,
      );
      expect(automationFallbackFor(cache, context(rootUid: true)), isNull);
    });

    test('context is parsed from privilegeStatus', () {
      final parsed = AutomationPrivilegeContext.fromStatus({
        'routes': {'shell': 'shizuku', 'rootUid': null},
        'permissions': {'writeSettings': true, 'readLogs': false},
        'sdkInt': 34,
      });
      expect(parsed.shellAvailable, isTrue);
      expect(parsed.rootUidAvailable, isFalse);
      expect(parsed.sdkInt, 34);
      expect(parsed.allowed('writeSettings'), isTrue);
      expect(parsed.allowed('readLogs'), isFalse);
    });
  });

  group('create/enable gate', () {
    late AppDatabase db;
    late List<bool> probes;
    late Map<String, dynamic> status;

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
        privilegeStatus: ({bool probeRoot = true}) async {
          probes.add(probeRoot);
          return status;
        },
      );
    }

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase(NativeDatabase.memory());
      probes = [];
      status = {
        'root': {'rootGranted': false, 'probed': true, 'suPresent': false},
        'routes': {'shell': null, 'rootUid': null},
        'permissions': <String, dynamic>{},
        'sdkInt': 35,
      };
      messenger.setMockMethodCallHandler(automationChannel, (call) async {
        return null;
      });
    });

    tearDown(() async {
      messenger.setMockMethodCallHandler(automationChannel, null);
      await db.close();
    });

    final createArguments = {
      'action': 'create_rule',
      'name': '夜间勿扰',
      'trigger': {'type': 'time', 'hour': 23, 'minute': 0},
      'actions': [
        {'action': 'set_do_not_disturb', 'enabled': true},
        {'action': 'set_volume', 'stream': 'ring', 'value': 0.1},
      ],
    };

    test('create_rule asks for acknowledgement before saving', () async {
      final service = buildService();
      final tool = AndroidAutomationTool(service: service);

      final blocked = await tool.execute(createArguments);
      expect(blocked.ok, isFalse);
      expect(blocked.code, ToolCodes.capabilityUnavailable);
      expect(blocked.effect, ToolEffect.none);
      expect(blocked.data?['requiresAcknowledgement'], isTrue);
      expect(
        (blocked.data?['fallbackActions'] as List).single,
        contains('勿扰授权页'),
      );
      expect(await service.rules(), isEmpty);
      expect(probes, [false]);

      final created = await tool.execute({
        ...createArguments,
        'acknowledgeFallback': true,
      });
      expect(created.ok, isTrue);
      expect((await service.rules()).single.name, '夜间勿扰');
      expect(
        tool.approvalDetailsFor({
          ...createArguments,
          'acknowledgeFallback': true,
        })?['fallbackNotice'],
        contains('用户已知悉'),
      );
    });

    test('trigger_status snapshot puts the fallback into a single approval',
        () async {
      final service = buildService();
      final tool = AndroidAutomationTool(service: service);

      // 没有快照：按原风险审批，审批详情提示尚未读取通道。
      expect(
        tool.approvalDetailsFor(createArguments)?['privilegeCheck'],
        contains('尚未读取'),
      );

      final status = await tool.execute({'action': 'trigger_status'});
      expect(status.ok, isTrue);
      final preview = status.data?['fallbackPreview'] as Map;
      expect(preview['set_do_not_disturb'], contains('勿扰授权页'));
      expect(preview['set_volume'], isNull);
      expect(preview['stop_app'], isNot(contains('null')));

      expect(tool.riskForArguments(createArguments), ToolRisk.dangerous);
      final details = tool.approvalDetailsFor(createArguments)!;
      expect((details['fallbackActions'] as List).single, contains('勿扰'));
      expect(details['fallbackNotice'], contains('批准即表示知悉'));

      final authorized = tool.authorizeAfterApproval(createArguments);
      expect(authorized['acknowledgeFallback'], isTrue);
      final created = await tool.execute(authorized);
      expect(created.ok, isTrue);
      expect((await service.rules()).single.name, '夜间勿扰');
    });

    test('channel changes after approval require a new acknowledgement',
        () async {
      final service = buildService();
      final tool = AndroidAutomationTool(service: service);
      await tool.execute({'action': 'trigger_status'});
      final authorized = tool.authorizeAfterApproval({
        ...createArguments,
        'actions': [
          {'action': 'set_do_not_disturb', 'enabled': true},
        ],
      });
      // 审批后又多了一个会降级的动作（参数被改写的极端情况）。
      final blocked = await tool.execute({
        ...authorized,
        'actions': [
          {'action': 'set_do_not_disturb', 'enabled': true},
          {'action': 'set_wifi', 'enabled': false},
        ],
      });
      expect(blocked.ok, isFalse);
      expect(
        (blocked.data?['fallbackActions'] as List).single,
        contains('Wi-Fi'),
      );
      expect(await service.rules(), isEmpty);
    });

    test('rules that run directly are created without a prompt', () async {
      status = {
        ...status,
        'permissions': {'notificationPolicy': true},
      };
      final service = buildService();
      final tool = AndroidAutomationTool(service: service);

      final created = await tool.execute(createArguments);
      expect(created.ok, isTrue);
      expect(await service.rules(), hasLength(1));
    });

    test('su present but unchecked triggers one root probe', () async {
      status = {
        ...status,
        'root': {'rootGranted': false, 'probed': false, 'suPresent': true},
      };
      final service = buildService();
      await service.privilegeFallbackWarnings(
        const AutomationRule(
          id: 'r',
          name: 'n',
          enabled: true,
          trigger: AutomationTrigger.batteryBelow(20),
          actions: [
            AutomationAction('set_wifi', {'enabled': false})
          ],
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      );
      expect(probes, [false, true]);
    });

    test('enabling a paused rule is gated the same way', () async {
      final service = buildService();
      final tool = AndroidAutomationTool(service: service);
      final rule = await service.createRule(
        name: '关 Wi-Fi',
        trigger: const AutomationTrigger.batteryBelow(15),
        actions: const [
          AutomationAction('set_wifi', {'enabled': false})
        ],
      );
      await service.setEnabled(rule.id, false);

      final blocked = await tool.execute({
        'action': 'set_rule_enabled',
        'ruleId': rule.id,
        'enabled': true,
      });
      expect(blocked.ok, isFalse);
      expect(blocked.data?['requiresAcknowledgement'], isTrue);
      expect((await service.rules()).single.enabled, isFalse);

      final paused = await tool.execute({
        'action': 'set_rule_enabled',
        'ruleId': rule.id,
        'enabled': false,
      });
      expect(paused.ok, isTrue);

      final enabled = await tool.execute({
        'action': 'set_rule_enabled',
        'ruleId': rule.id,
        'enabled': true,
        'acknowledgeFallback': true,
      });
      expect(enabled.ok, isTrue);
      expect((await service.rules()).single.enabled, isTrue);
    });
  });
}
