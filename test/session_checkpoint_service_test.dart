import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mobile_agent/application/change_review.dart';
import 'package:mobile_agent/application/change_set_service.dart';
import 'package:mobile_agent/application/session_checkpoint_service.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';

void main() {
  late Directory root;
  late Directory workspace;
  const store = SessionCheckpointStore();
  const service = SessionCheckpointService();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nexus-cp-test');
    workspace = Directory(p.join(root.path, 'ws'))..createSync(recursive: true);
    PathProviderPlatform.instance = _TempPathProvider(p.join(root.path, 'docs'));
  });
  tearDown(() => root.delete(recursive: true));

  test('recordTurn 逐轮打点、同位置去重、remove 生效', () async {
    final t0 = DateTime(2026, 10, 15, 9);
    final first = await service.recordTurn(
        store: store,
        conversationId: 'c-1',
        workspacePath: '/ws',
        messageCount: 0,
        now: t0);
    expect(first, isNotNull);
    expect(first!.turn, 1);

    // 同位置重复打点应被跳过（自动 + 手动不会翻倍）。
    final dupe = await service.recordTurn(
        store: store,
        conversationId: 'c-1',
        workspacePath: '/ws',
        messageCount: 0,
        now: t0.add(const Duration(seconds: 1)));
    expect(dupe, isNull);

    final second = await service.recordTurn(
        store: store,
        conversationId: 'c-1',
        workspacePath: '/ws',
        messageCount: 2,
        now: t0.add(const Duration(minutes: 1)));
    expect(second!.turn, 2);

    var list = await store.listFor('c-1');
    expect(list, hasLength(2));
    await store.remove('c-1', first.id);
    list = await store.listFor('c-1');
    expect(list.single.id, second.id);
  });

  test('rewindCode 把 checkpoint 之后任务的变更集逐个回滚', () async {
    // 工作区里已有被任务修改过的文件。
    final target = File(p.join(workspace.path, 'lib', 'x.txt'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('after\n');
    const before = 'before\n';

    const changeSets = ChangeSetService();
    const reviews = ChangeReviewService();
    await changeSets.capture(
      projectId: 'p1',
      taskId: 'task-a',
      workspacePath: workspace.path,
      review: ChangeReview(files: [
        reviews.summarizeEdit(path: 'lib/x.txt', before: 'before\n', after: 'after\n')
      ], mark: ChangeVerificationMark.passed),
    );

    final checkpoint = SessionCheckpoint(
      id: 'cp-1',
      conversationId: 'c-1',
      workspacePath: workspace.path,
      messageCount: 0,
      createdAt: DateTime(2026, 10, 15, 9),
      turn: 1,
    );
    final summary = await service.rewindCode(checkpoint,
        tasksAfter: () async => [
              CheckpointTaskRef(id: 'task-a', createdAt: DateTime(2026, 10, 15, 10)),
            ]);
    expect(summary.tasks, 1);
    expect(summary.restored, 1);
    expect(summary.conflicts, isEmpty);
    expect(target.readAsStringSync(), before);
  });

  test('无工作区时 rewindCode 返回零汇总（合法的无代码改动场景）', () async {
    final checkpoint = SessionCheckpoint(
      id: 'cp-x',
      conversationId: 'c-1',
      workspacePath: '',
      messageCount: 0,
      createdAt: DateTime(2026),
      turn: 1,
    );
    final summary =
        await service.rewindCode(checkpoint, tasksAfter: () async => const []);
    expect(summary.tasks, 0);
    expect(summary.restored, 0);
    expect(summary.conflicts, isEmpty);
  });

  test('db：tasksForConversation(since) 与 deleteMessagesByIds 支撑回退', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final t0 = DateTime(2026, 10, 15, 9);
    for (var i = 0; i < 4; i++) {
      await db.into(db.messages).insert(MessagesCompanion.insert(
            id: 'm-$i',
            conversationId: 'c-1',
            role: 'user',
            content: 'msg $i',
            createdAt: t0.add(Duration(minutes: i)),
          ));
    }
    // 另一个会话的消息不应受影响。
    await db.into(db.messages).insert(MessagesCompanion.insert(
          id: 'm-other',
          conversationId: 'c-2',
          role: 'user',
          content: 'other',
          createdAt: t0,
        ));
    await db.into(db.tasks).insert(TasksCompanion.insert(
          id: 't-old',
          conversationId: 'c-1',
          requestJson: '{}',
          createdAt: t0,
          updatedAt: t0,
        ));
    await db.into(db.tasks).insert(TasksCompanion.insert(
          id: 't-new',
          conversationId: 'c-1',
          requestJson: '{}',
          createdAt: t0.add(const Duration(minutes: 10)),
          updatedAt: t0.add(const Duration(minutes: 10)),
        ));

    final removed = await db.deleteMessagesByIds(const ['m-2', 'm-3']);
    expect(removed, 2);
    final remaining = await db.messagesFor('c-1');
    expect(remaining.map((m) => m.id), ['m-0', 'm-1']);
    expect((await db.messagesFor('c-2')).single.id, 'm-other');

    final after = await db.tasksForConversation('c-1',
        since: t0.add(const Duration(minutes: 5)));
    expect(after.map((t) => t.id), ['t-new']);
    expect(await db.tasksForConversation('c-1'), hasLength(2));
    expect(await db.tasksForConversation('c-2'), isEmpty);
  });
}

class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}
