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
}
