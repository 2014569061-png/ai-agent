import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('schemaVersion 已升至 24', () {
    final db = AppDatabase(NativeDatabase.memory());
    expect(db.schemaVersion, 24);
    db.close();
  });

  test('v16→v17 迁移重建热查询索引（B-4）', () async {
    final db = AppDatabase(NativeDatabase.memory());
    // 模拟 v16：删掉 fresh-create 时已建的全部目标索引，再跑升级路径。
    for (final name in [
      'idx_messages_conversation',
      'idx_tasks_status_updated',
      'idx_memories_enabled',
      'idx_scheduled_tasks_enabled',
      'idx_audit_logs_created',
      'idx_run_records_started',
    ]) {
      await db.customStatement('DROP INDEX IF EXISTS $name');
    }

    final m = db.createMigrator();
    await db.migration.onUpgrade(m, 16, 17);

    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name IN "
          "('idx_messages_conversation', 'idx_tasks_status_updated', "
          "'idx_memories_enabled', 'idx_scheduled_tasks_enabled', "
          "'idx_audit_logs_created', 'idx_run_records_started')",
        )
        .get();
    final names = rows.map((row) => row.data['name'] as String).toSet();
    expect(names, hasLength(6), reason: '迁移后 6 个索引都应存在');

    // 消息索引必须是 (conversation_id, created_at) 复合 —— 单列索引无法免排序。
    final msgSql = await db
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type = 'index' "
          "AND name = 'idx_messages_conversation'",
        )
        .getSingle();
    final sql = msgSql.data['sql'] as String;
    expect(sql, contains('conversation_id'));
    expect(sql, contains('created_at'));
    await db.close();
  });

  test('v17→v18 迁移新增定时任务独立执行标记', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.customStatement(
        'CREATE TABLE scheduled_tasks_v17 AS SELECT id, name, prompt, cron, '
        'agent_id, enabled, last_result, created_at, updated_at FROM scheduled_tasks');
    await db.customStatement('DROP TABLE scheduled_tasks');
    await db.customStatement(
        'ALTER TABLE scheduled_tasks_v17 RENAME TO scheduled_tasks');

    final m = db.createMigrator();
    await db.migration.onUpgrade(m, 17, 18);

    final columns =
        await db.customSelect('PRAGMA table_info(scheduled_tasks)').get();
    expect(columns.map((row) => row.data['name']), contains('last_run_at'));
    await db.close();
  });

  test('v20→v21 迁移创建独立任务控制表', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('DROP TABLE IF EXISTS run_controls');
    await db.customStatement('DROP TABLE IF EXISTS execution_leases');
    final m = db.createMigrator();
    await db.migration.onUpgrade(m, 20, 21);
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN "
          "('run_controls', 'execution_leases')",
        )
        .get();
    expect(tables.map((row) => row.data['name']).toSet(),
        {'run_controls', 'execution_leases'});
    final columns =
        await db.customSelect('PRAGMA table_info(run_records)').get();
    expect(columns.map((row) => row.data['name']),
        containsAll(['task_id', 'project_id']));
    await db.close();
  });

  test('v21→v22 迁移创建 artifacts 表', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('DROP TABLE IF EXISTS artifacts');
    final m = db.createMigrator();
    await db.migration.onUpgrade(m, 21, 22);
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'artifacts'",
        )
        .get();
    expect(tables, isNotEmpty);
    await db.saveArtifactRecord({
      'id': 'art-1',
      'projectId': 'p1',
      'taskId': 't1',
      'runId': 'r1',
      'kind': 'apk',
      'relativePath': 'build/app.apk',
      'hash': 'abc',
      'bytes': 12,
      'inspectionJson': {'exists': true},
      'createdAt': DateTime.now().toIso8601String(),
    });
    final rows = await db.artifactsForProject('p1');
    expect(rows.single['relativePath'], 'build/app.apk');
    await db.close();
  });

  test('v22→v23 迁移创建锁屏审批决策表（含索引）', () async {
    final db = AppDatabase(NativeDatabase.memory());
    // 模拟 v22：把 fresh-create 时已建的表与索引删掉，再跑升级路径。
    await db
        .customStatement('DROP INDEX IF EXISTS idx_pending_approvals_created');
    await db.customStatement('DROP TABLE IF EXISTS pending_approvals');

    final m = db.createMigrator();
    await db.migration.onUpgrade(m, 22, 23);

    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name = 'pending_approvals'",
        )
        .get();
    expect(tables, isNotEmpty, reason: '升级后必须有 pending_approvals 表');

    final indexes = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name = 'idx_pending_approvals_created'",
        )
        .get();
    expect(indexes, isNotEmpty, reason: '升级后必须有对应的清理索引');

    // 表建出来还不算完，必须真的能完成一次握手（列名/类型写错会在这里暴露）。
    await db.insertPendingApproval(
      requestId: 'appr-migrated',
      toolName: 'terminal',
      summary: 'x',
      risk: 'requiresConfirmation',
      ttl: const Duration(minutes: 1),
    );
    expect(await db.findPendingApprovalDecision('appr-migrated'), isNull);
    expect(await db.decidePendingApproval('appr-migrated', 'approve'), isTrue);
    expect(await db.findPendingApprovalDecision('appr-migrated'), 'approve');
    await db.close();
  });

  test('v23→v24 迁移创建后台数据维护任务表', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('DROP TABLE IF EXISTS data_maintenance_jobs');

    final m = db.createMigrator();
    await db.migration.onUpgrade(m, 23, 24);

    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name = 'data_maintenance_jobs'",
        )
        .get();
    expect(tables, isNotEmpty);
    await db.close();
  });

  test('v23→v24 重复迁移保持幂等', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('DROP TABLE IF EXISTS data_maintenance_jobs');

    final m = db.createMigrator();
    await db.migration.onUpgrade(m, 23, 24);
    await db.migration.onUpgrade(m, 23, 24);

    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name = 'data_maintenance_jobs'",
        )
        .get();
    expect(tables, hasLength(1));
    await db.close();
  });

  test('recentConversations 支持 limit 分页且保持置顶优先（B-2）', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final now = DateTime.now();
    for (var i = 0; i < 5; i++) {
      await db.insertConversation(ConversationsCompanion.insert(
        id: 'c$i',
        createdAt: now.subtract(Duration(minutes: 5 - i)),
        updatedAt: now.subtract(Duration(minutes: 5 - i)),
      ));
    }
    // c4 置顶但最旧 —— 置顶优先级高于时间。
    await db.customStatement(
        'UPDATE conversations SET is_pinned = 1 WHERE id = \'c4\'');

    final top3 = await db.recentConversations(limit: 3);
    expect(top3.map((c) => c.id).toList(), ['c4', 'c3', 'c2']);

    final page2 = await db.recentConversations(limit: 3, offset: 3);
    expect(page2.map((c) => c.id).toList(), ['c1', 'c0']);
    await db.close();
  });

  test('messagesFor 键集分页只取更早消息且保持升序（B-2）', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final base = DateTime(2026, 9, 12, 10);
    for (var i = 0; i < 10; i++) {
      await db.saveMessage(Message(
        id: 'm$i',
        conversationId: 'c1',
        role: 'user',
        content: 'msg$i',
        createdAt: base.add(Duration(minutes: i)),
      ));
    }

    // 键集分页语义：第一页取「最新 N 条」（升序返回），向更早翻页用 before。
    final first3 = await db.messagesFor('c1', limit: 3);
    expect(first3.map((m) => m.id).toList(), ['m7', 'm8', 'm9']);

    // 以第 3 条为键，取其之前的消息 → m2、m1、m0（升序不变）。
    final older = await db.messagesFor('c1',
        before: base.add(const Duration(minutes: 3)));
    expect(older.map((m) => m.id).toList(), ['m0', 'm1', 'm2']);
    await db.close();
  });
}
