import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/audit_service.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/tools/android_device_tool.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('device audit separates model intent from the executed whitelist flow',
      () async {
    final arguments = {
      'action': 'clear_app_cache',
      'packageName': 'com.example.chat',
      // 模型可能夹带命令文本；审计中的实际命令必须来自白名单重建。
      'command': 'rm -rf /data',
    };
    final startedAt = DateTime(2026, 9, 24, 10, 0, 0);
    final completedAt = startedAt.add(const Duration(milliseconds: 1500));
    await AuditService().logAndroidDeviceOperation(
      db,
      userRequest: '帮我清一下聊天应用的缓存',
      arguments: arguments,
      resultOk: true,
      resultCode: 'OK',
      resultEffect: 'applied',
      risk: 'dangerous',
      execution: AndroidDeviceTool.auditExecutionFor(arguments),
      startedAt: startedAt,
      completedAt: completedAt,
    );

    final row = (await db.recentAuditLogs()).single;
    final detail = jsonDecode(row.detail) as Map<String, dynamic>;
    expect(detail['userRequest'], '帮我清一下聊天应用的缓存');
    final intent = detail['intent'] as Map<String, dynamic>;
    expect(intent['source'], 'model_tool_call');
    expect(intent['operation'], 'clear_app_cache');
    final execution = detail['execution'] as Map<String, dynamic>;
    expect(execution['executed'], isTrue);
    expect(execution.toString(), isNot(contains('rm -rf /data')));
    expect((detail['timing'] as Map)['durationMs'], 1500);
    expect((detail['result'] as Map)['status'], 'succeeded');
    expect(row.risk, 'dangerous');
  });

  test('automation-originated operations record their intent source', () async {
    await AuditService().logAndroidDeviceOperation(
      db,
      userRequest: '自动化规则「夜间」· 每天 23:00',
      arguments: const {'action': 'set_brightness', 'value': 0.3},
      resultOk: true,
      resultCode: 'OK',
      resultEffect: 'applied',
      toolName: 'android_automation',
      intentSource: 'automation_rule',
    );
    final detail =
        jsonDecode((await db.recentAuditLogs()).single.detail) as Map;
    expect((detail['intent'] as Map)['source'], 'automation_rule');
    expect((detail['intent'] as Map)['tool'], 'android_automation');
  });

  test('device automation events are always retained with root marking',
      () async {
    await AuditService().logDeviceAutomationEvent(
      db,
      event: 'created',
      ruleId: 'auto_1',
      ruleName: '夜间勿扰',
      trigger: '每天 23:00',
      actions: const ['开启勿扰模式（Root）'],
      requiresRoot: true,
      userRequest: '每天晚上11点开勿扰',
    );
    final row = (await db.recentAuditLogs()).single;
    expect(row.type, 'device_automation');
    expect(row.risk, 'dangerous');
    expect(row.decision, 'created');
    final detail = jsonDecode(row.detail) as Map;
    expect(detail['actions'], ['开启勿扰模式（Root）']);
    expect(detail['userRequest'], '每天晚上11点开勿扰');
  });
}
