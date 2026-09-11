import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/task_service.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  final taskService = TaskService();

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('creates a running task and lists it', () async {
    final task = await taskService.create(
      db: db,
      conversationId: 'c1',
      requestJson: '{"query":"算一下 1+2"}',
    );

    expect(task.status, 'running');
    expect(task.resumeCount, 0);

    final running = await taskService.runningTasks(db);
    expect(running.map((t) => t.id), contains(task.id));
  });

  test('rapid creates never collide on id (Windows clock granularity)', () async {
    final ids = <String>{};
    for (var i = 0; i < 200; i++) {
      final task = await taskService.create(
          db: db, conversationId: 'c$i', requestJson: '{}');
      expect(ids.add(task.id), isTrue,
          reason: 'create 的 id 在时钟同刻度下发生碰撞: ${task.id}');
    }
  });

  test('resumableTasks lists running and paused, excludes terminal', () async {
    final a = await taskService.create(
        db: db, conversationId: 'c1', requestJson: '{}');
    final b = await taskService.create(
        db: db, conversationId: 'c1', requestJson: '{}');
    final c = await taskService.create(
        db: db, conversationId: 'c1', requestJson: '{}');

    await taskService.updateStatus(db, b.id, 'paused');
    await taskService.updateStatus(db, c.id, 'completed');

    final ids = (await taskService.resumableTasks(db)).map((t) => t.id);
    expect(ids, contains(a.id), reason: 'running 应可恢复');
    expect(ids, contains(b.id), reason: 'paused 应可恢复（resumeTask 本就支持）');
    expect(ids, isNot(contains(c.id)), reason: 'completed 不应出现在恢复入口');
  });

  test('updateStatus completes a task and removes it from running', () async {
    final task = await taskService.create(
        db: db, conversationId: 'c1', requestJson: '{}');

    await taskService.updateStatus(db, task.id, 'completed');

    final saved = await db.findTask(task.id);
    expect(saved?.status, 'completed');
    expect(await taskService.runningTasks(db), isEmpty);
  });

  test('markResumed increments resumeCount', () async {
    final task = await taskService.create(
        db: db, conversationId: 'c1', requestJson: '{}');
    expect(task.resumeCount, 0);

    await taskService.markResumed(db, task.id);
    final saved = await db.findTask(task.id);
    expect(saved?.resumeCount, 1);

    await taskService.markResumed(db, task.id);
    final saved2 = await db.findTask(task.id);
    expect(saved2?.resumeCount, 2);
  });

  test('stores development metadata and a bounded result summary', () async {
    final task = await taskService.create(
      db: db,
      conversationId: 'c1',
      type: 'development:bug_fix',
      requestJson: '{"prompt":"定位崩溃"}',
      metadata: {
        'taskType': 'bug_fix',
        'sourceType': 'share',
        'workspacePath': '/workspace/demo',
        'title': '问题修复：定位崩溃',
      },
    );

    final info = taskService.describe(task);
    expect(info.type, 'bug_fix');
    expect(info.sourceType, 'share');
    expect(info.workspacePath, '/workspace/demo');

    await taskService.complete(
      db,
      task.id,
      status: 'completed',
      summary: '已定位根因',
      runId: 'run-1',
    );
    final saved = await db.findTask(task.id);
    expect(saved?.status, 'completed');
    final completed = taskService.describe(saved!);
    expect(completed.summary, '已定位根因');
    expect(completed.runId, 'run-1');
  });

  test('records applied run ids explicitly and keeps the list bounded',
      () async {
    final task = await taskService.create(
      db: db,
      conversationId: 'c1',
      requestJson: '{}',
    );

    await taskService.complete(
      db,
      task.id,
      status: 'completed',
      summary: '完成',
      runId: 'run-1',
    );
    final completed = await db.findTask(task.id);
    final progress =
        jsonDecode(completed!.progressJson) as Map<String, dynamic>;
    expect(progress['appliedRunIds'], ['run-1']);
    expect(taskService.isRunApplied(progress, 'run-1'), isTrue);

    expect(await taskService.markRunApplied(db, task.id, 'run-1'), isFalse);
    expect(await taskService.markRunApplied(db, task.id, 'run-2'), isTrue);
    final updated = await db.findTask(task.id);
    final updatedProgress =
        jsonDecode(updated!.progressJson) as Map<String, dynamic>;
    expect(updatedProgress['appliedRunIds'], ['run-1', 'run-2']);
  });
}
