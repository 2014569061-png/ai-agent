import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/development_execution_service.dart';
import 'package:mobile_agent/application/draft_service.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('draft attachments missing on disk are marked invalid', () async {
    const service = DraftService();
    await service.save(
      db,
      draftKey: 'conversation:c1',
      conversationId: 'c1',
      text: 'hello',
      attachments: const [
        DraftAttachment(
          id: 'a1',
          name: 'shot.png',
          mime: 'image/png',
          path: '/not/there/shot.png',
        ),
      ],
    );
    final loaded = await service.load(db, 'conversation:c1');
    expect(loaded, isNotNull);
    expect(loaded!.text, 'hello');
    expect(loaded.attachments.single.status, 'missing');
  });

  test('enqueue with the same clientRequestId is idempotent', () async {
    final service = DevelopmentExecutionService(db: db);
    const request = DevelopmentTaskRequest(
      prompt: 'fix login',
      conversationId: 'c1',
      requestId: 'req-dup',
    );
    final first = await service.enqueue(request);
    final second = await service.enqueue(request);
    expect(second.taskId, first.taskId);
    final tasks = await db.allTasks(limit: 20);
    expect(tasks.where((task) => task.requestJson.contains('req-dup')), hasLength(1));
  });
}
