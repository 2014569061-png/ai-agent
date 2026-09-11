import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('schemaVersion 已升至 17', () {
    final db = AppDatabase(NativeDatabase.memory());
    expect(db.schemaVersion, 17);
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

    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND name IN "
      "('idx_messages_conversation', 'idx_tasks_status_updated', "
      "'idx_memories_enabled', 'idx_scheduled_tasks_enabled', "
      "'idx_audit_logs_created', 'idx_run_records_started')",
    ).get();
    final names = rows.map((row) => row.data['name'] as String).toSet();
    expect(names, hasLength(6), reason: '迁移后 6 个索引都应存在');

    // 消息索引必须是 (conversation_id, created_at) 复合 —— 单列索引无法免排序。
    final msgSql = await db.customSelect(
      "SELECT sql FROM sqlite_master WHERE type = 'index' "
      "AND name = 'idx_messages_conversation'",
    ).getSingle();
    final sql = msgSql.data['sql'] as String;
    expect(sql, contains('conversation_id'));
    expect(sql, contains('created_at'));
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
    final older = await db.messagesFor('c1', before: base.add(const Duration(minutes: 3)));
    expect(older.map((m) => m.id).toList(), ['m0', 'm1', 'm2']);
    await db.close();
  });
}
