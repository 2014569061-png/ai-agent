import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/audit_service.dart';
import 'package:mobile_agent/application/nexus_guard.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('security events are retained when the audit preference is disabled',
      () async {
    final service = AuditService();

    await service.log(
      db,
      type: 'tool_grant',
      detail: 'terminal',
      decision: 'allowOnce',
      risk: 'dangerous',
    );
    expect(await db.recentAuditLogs(), isEmpty);

    await service.logSecurityEvent(
      db,
      type: 'tool_grant',
      detail: 'terminal',
      decision: 'allowOnce',
      risk: 'dangerous',
    );

    final rows = await db.recentAuditLogs();
    expect(rows, hasLength(1));
    expect(rows.single.type, 'tool_grant');
    expect(rows.single.detail, 'terminal');
    expect(rows.single.decision, 'allowOnce');
  });

  test('Android operation audit stores bounded request, target, and outcome',
      () async {
    final service = AuditService();

    await service.logAndroidDeviceOperation(
      db,
      userRequest: '删除临时文件；备用 token=SECRET-123',
      arguments: {
        'action': 'delete_root_file',
        'path': '/data/local/tmp/report.txt',
        'content': 'must-not-be-persisted',
        'preview': true,
      },
      resultOk: true,
      resultCode: 'OK',
      resultEffect: 'none',
      conversationId: 'conversation-1',
    );

    final row = (await db.recentAuditLogs()).single;
    final detail = jsonDecode(row.detail) as Map<String, dynamic>;
    expect(row.type, 'android_device_operation');
    expect(row.decision, 'preview');
    expect(row.conversationId, 'conversation-1');
    expect(row.createdAt, isA<DateTime>());
    expect(detail['userRequest'], contains('删除临时文件'));
    expect(detail['userRequest'], isNot(contains('SECRET-123')));
    expect(
      (detail['target'] as Map<String, dynamic>)['path'],
      '/data/local/tmp/report.txt',
    );
    expect(detail['preview'], isTrue);
    expect((detail['result'] as Map<String, dynamic>)['status'], 'preview');
    expect(row.detail, isNot(contains('must-not-be-persisted')));
  });

  test('Android operation audit write failures are reported and swallowed',
      () async {
    NexusGuard.resetReportedKeys();
    final messages = <String>[];
    final service = AuditService(
      logger: (message, {Map<String, dynamic>? detail}) =>
          messages.add(message),
    );
    await db.recentAuditLogs();
    await db.close();

    await expectLater(
      service.logAndroidDeviceOperation(
        db,
        userRequest: '清理缓存',
        arguments: const {
          'action': 'clear_app_cache',
          'packageName': 'com.example.app',
        },
        resultOk: true,
        resultCode: 'OK',
        resultEffect: 'applied',
      ),
      completes,
    );

    expect(messages, hasLength(1));
    expect(messages.single, contains('audit.androidDeviceOperation.write'));
  });

  test('Android operation audit marks approval rejection explicitly', () async {
    await AuditService().logAndroidDeviceOperation(
      db,
      userRequest: '删除临时目录文件',
      arguments: const {
        'action': 'delete_root_file',
        'path': '/data/local/tmp/report.txt',
        'preview': true,
      },
      resultOk: false,
      resultCode: 'APPROVAL_REJECTED',
      resultEffect: 'none',
    );

    final row = (await db.recentAuditLogs()).single;
    final detail = jsonDecode(row.detail) as Map<String, dynamic>;
    expect(row.decision, 'approval_rejected');
    expect(detail['preview'], isTrue);
    expect(
      (detail['result'] as Map<String, dynamic>)['status'],
      'approval_rejected',
    );
  });

  test('private app data audit stores the exact target but never file contents',
      () async {
    await AuditService().logAndroidDeviceOperation(
      db,
      userRequest: '读取聊天应用设置文件',
      arguments: const {
        'action': 'read',
        'packageName': 'com.example.chat',
        'path': 'shared_prefs/settings.xml',
        'content': 'refresh_token=must-not-be-persisted',
      },
      resultOk: true,
      resultCode: 'OK',
      resultEffect: 'none',
      risk: 'dangerous',
    );

    final row = (await db.recentAuditLogs()).single;
    final detail = jsonDecode(row.detail) as Map<String, dynamic>;
    expect(row.risk, 'dangerous');
    expect(detail['operation'], 'read');
    expect((detail['target'] as Map<String, dynamic>)['packageName'],
        'com.example.chat');
    expect((detail['target'] as Map<String, dynamic>)['path'],
        'shared_prefs/settings.xml');
    expect(row.detail, isNot(contains('refresh_token')));
  });

  test(
      'private app data previews are audited as previews without device access',
      () async {
    await AuditService().logAndroidDeviceOperation(
      db,
      userRequest: '预览读取应用设置文件',
      arguments: const {
        'action': 'read',
        'packageName': 'com.example.chat',
        'path': 'shared_prefs/settings.xml',
      },
      resultOk: true,
      resultCode: 'OK',
      resultEffect: 'none',
      risk: 'safe',
      previewOnly: true,
    );

    final row = (await db.recentAuditLogs()).single;
    expect(row.decision, 'preview');
    expect(row.risk, 'safe');
  });

  test('structured audit details keep only an explicit safe-field allowlist',
      () async {
    final service = AuditService();
    await service.logSecurityEvent(
      db,
      type: 'tool_grant',
      detail: jsonEncode({
        'tool': 'terminal',
        'operation': 'execute',
        'effect': 'applied',
        'decision': 'allowOnce',
        'path': '/private/project/secret.txt',
        'arguments': {'token': 'SECRET-123'},
        'unknownField': 'SECRET-456',
      }),
    );

    final detail = (await db.recentAuditLogs()).single.detail;
    expect(detail, contains('"tool":"terminal"'));
    expect(detail, contains('"operation":"execute"'));
    expect(detail, contains('"decision":"allowOnce"'));
    expect(detail, isNot(contains('/private/project/secret.txt')));
    expect(detail, isNot(contains('SECRET-123')));
    expect(detail, isNot(contains('SECRET-456')));
    expect(detail, contains('[REDACTED]'));
  });

  test('审计写入失败不再无声：记录 warning 且不向调用方抛出', () async {
    NexusGuard.resetReportedKeys();
    final messages = <String>[];
    final service = AuditService(
      logger: (message, {Map<String, dynamic>? detail}) =>
          messages.add(message),
    );

    // 复用 setUp 里的库并在用过后关掉：Drift 是懒打开，一次都没用过就 close()
    // 等于没关，之后的写入会重新打开并成功，于是测不到失败路径。
    await db.recentAuditLogs();
    await db.close();

    // 1) 失败不得变成调用方的异常——「审计失败不阻断主流程」的既定语义不变。
    await expectLater(
      service.logSecurityEvent(
        db,
        type: 'tool_grant',
        detail: 'terminal',
        decision: 'allowOnce',
        risk: 'dangerous',
      ),
      completes,
    );

    // 2) 但失败必须留下痕迹：审计页读的就是这张表，静默少报已授予的权限
    // 是审计日志最不能有的失效方式。
    expect(messages, hasLength(1));
    expect(messages.single, contains('audit.write'));
  });
}
