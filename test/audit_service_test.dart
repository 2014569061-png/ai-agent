import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/audit_service.dart';
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
}
