import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/task_feedback_service.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('反馈可 upsert、统计并恢复选中态', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final service = const TaskFeedbackService();
    final now = DateTime.now();
    for (final id in ['task-1', 'task-2']) {
      await db.into(db.tasks).insert(Task(
            id: id,
            conversationId: 'conversation-1',
            type: 'development:bug_fix',
            status: 'completed',
            requestJson: '{}',
            progressJson: '{}',
            resumeCount: 0,
            createdAt: now,
            updatedAt: now,
          ));
    }

    await service.save(db: db, taskId: 'task-1', runId: 'run-1', helpful: true);
    await service.save(db: db, taskId: 'task-2', helpful: false);
    expect((await service.feedbackForTask(db, 'task-1'))?.helpful, isTrue);
    expect((await service.metrics(db)).samples, 2);
    expect((await service.metrics(db)).helpfulRate, 50);

    await service.save(db: db, taskId: 'task-1', helpful: false);
    final metrics = await service.metrics(db);
    expect(metrics.samples, 2);
    expect(metrics.helpfulRate, 0);
  });

  test('删除任务与清理全部用户数据会删除反馈', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime(2026, 9, 13);
    await db.saveTaskFeedback(taskId: 'orphan', helpful: true, now: now);
    await db.clearTaskFeedback();
    expect(await db.taskFeedbackCount(), 0);
  });

  test('v18 到 v19 创建 task_feedback 表并保留既有数据', () async {
    final rawDb = sqlite.sqlite3.openInMemory()
      ..execute(
        'CREATE TABLE migration_sentinel (id TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)',
      )
      ..execute(
        "INSERT INTO migration_sentinel (id, value) VALUES ('existing', 'kept')",
      )
      ..userVersion = 18;
    final db = AppDatabase(NativeDatabase.opened(rawDb));
    addTearDown(db.close);

    await db.customSelect('SELECT 1').get();

    final feedbackTable = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'task_feedback'",
        )
        .get();
    final sentinel = await db
        .customSelect(
          "SELECT value FROM migration_sentinel WHERE id = 'existing'",
        )
        .getSingle();
    expect(feedbackTable, isNotEmpty);
    expect(sentinel.data['value'], 'kept');
    expect(rawDb.userVersion, 19);
  });
}
