import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/application/change_set_service.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/application/session_checkpoint_service.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/presentation/navigation/desktop_checkpoint_timeline.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime(2026, 10, 15, 9);

  ChatMessage msg(String id, String text) => ChatMessage(
      id: id, role: MessageRole.user, parts: [MessagePart.text(text)]);

  Future<void> insertMessage(
      AppDatabase db, String id, String conversationId, DateTime at) async {
    await db.into(db.messages).insert(MessagesCompanion.insert(
          id: id,
          conversationId: conversationId,
          role: 'user',
          content: 'content $id',
          createdAt: at,
        ));
  }

  testWidgets('cp timeline empty state and manual create', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = _InMemoryCheckpointStore();

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) async => db),
      chatControllerProvider.overrideWith(() => _FakeChatController(
          const ChatState(conversationId: 'c-1', messages: []))),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 420,
                  height: 640,
                  child: DesktopCheckpointTimeline(store: store)))),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('暂无 checkpoint'), findsOneWidget);

    // 手动创建 checkpoint。
    await tester.tap(find.text('立即创建'));
    await tester.pump();
    await tester.pump();

    expect(find.text('第 1 轮前'), findsOneWidget);
  });

  testWidgets('rewind conversation truncates db and memory', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    for (var i = 0; i < 3; i++) {
      await insertMessage(db, 'm-$i', 'c-1', t0.add(Duration(minutes: i)));
    }

    final store = _InMemoryCheckpointStore();
    await store.append(SessionCheckpoint(
      id: 'cp-1',
      conversationId: 'c-1',
      workspacePath: '',
      messageCount: 1,
      createdAt: t0,
      turn: 1,
    ));

    final initial = ChatState(
        conversationId: 'c-1',
        messages: [msg('m-0', 'a'), msg('m-1', 'b'), msg('m-2', 'c')]);
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) async => db),
      chatControllerProvider.overrideWith(() => _FakeChatController(initial)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 420,
                  height: 640,
                  child: DesktopCheckpointTimeline(store: store)))),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('第 1 轮前'), findsOneWidget);

    final moreBtn = find.byTooltip('选择回退方式');
    expect(moreBtn, findsOneWidget);
    await tester.tap(moreBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('回会话（保留代码）'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 确认弹窗 → 执行。
    expect(find.textContaining('仅回退会话'), findsOneWidget);
    await tester.tap(find.text('确认回退'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect((await db.messagesFor('c-1')).map((m) => m.id), ['m-0']);
    final chat = container.read(chatControllerProvider);
    expect(chat.messages, hasLength(1));
  });
  testWidgets('conflicted both rewind keeps every conversation message',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    for (var i = 0; i < 3; i++) {
      await insertMessage(db, 'conflict-$i', 'conflict', t0);
    }
    final store = _InMemoryCheckpointStore();
    await store.append(SessionCheckpoint(
        id: 'cp-conflict',
        conversationId: 'conflict',
        workspacePath: 'D:/fixture',
        messageCount: 1,
        createdAt: t0,
        turn: 1));
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) async => db),
      chatControllerProvider.overrideWith(() => _FakeChatController(ChatState(
              conversationId: 'conflict',
              messages: [
                msg('conflict-0', 'a'),
                msg('conflict-1', 'b'),
                msg('conflict-2', 'c')
              ])))
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: Scaffold(
                body: SizedBox(
                    width: 600,
                    height: 700,
                    child: DesktopCheckpointTimeline(
                        store: store, service: const _ConflictService()))))));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byTooltip('选择回退方式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回代码 + 回会话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认回退'));
    await tester.pumpAndSettle();
    expect(await db.messagesFor('conflict'), hasLength(3));
    expect(container.read(chatControllerProvider).messages, hasLength(3));
    expect(find.textContaining('文件和会话均已保留'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _FakeChatController extends ChatController {
  _FakeChatController(this._initial);
  final ChatState _initial;
  @override
  ChatState build() => _initial;
}

class _InMemoryCheckpointStore extends SessionCheckpointStore {
  final Map<String, List<SessionCheckpoint>> _data = {};

  @override
  Future<List<SessionCheckpoint>> listFor(String conversationId) async {
    return List.unmodifiable(_data[conversationId] ?? const []);
  }

  @override
  Future<void> append(SessionCheckpoint checkpoint) async {
    final list = _data.putIfAbsent(checkpoint.conversationId, () => []);
    list.add(checkpoint);
  }

  @override
  Future<void> remove(String conversationId, String id) async {
    _data[conversationId]?.removeWhere((cp) => cp.id == id);
  }
}

class _ConflictService extends SessionCheckpointService {
  const _ConflictService();
  @override
  Future<CheckpointRewindSummary> preflight(SessionCheckpoint checkpoint,
          {required Future<List<CheckpointTaskRef>> Function()
              tasksAfter}) async =>
      const CheckpointRewindSummary(
          tasks: 1,
          restored: 0,
          conflicts: [RollbackConflict(path: 'changed.dart', reason: '人工修改')]);
}
