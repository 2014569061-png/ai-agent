import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 长会话键集分页「加载更早」（B-2 UI 接线）的护栏测试。
///
/// 初始只载最新 200 条；loadOlderMessages 按 (conversationId, createdAt)
/// 键集向前翻页并前插。此前的实现是 messagesFor 全量入内存 —— 长会话
/// （数百条）首屏内存与加载时间随历史无限增长。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  // 与 chat_resume_test 的 _Env.boot 同手法：内存 DB + mock prefs，
  // 走真实 ChatController 初始化链路（无网络依赖）。
  Future<(AppDatabase, ProviderContainer, ChatController)> boot() async {
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) async => db),
    ]);
    final controller = container.read(chatControllerProvider.notifier);
    await pumpEventQueue();
    return (db, container, controller);
  }

  Future<void> seedConversation(
    AppDatabase db, {
    required String conversationId,
    required int count,
  }) async {
    final base = DateTime(2026, 9, 12, 8);
    await db.insertConversation(ConversationsCompanion.insert(
      id: conversationId,
      createdAt: base,
      updatedAt: base.add(const Duration(minutes: 30)),
    ));
    for (var i = 0; i < count; i++) {
      await db.saveMessage(Message(
        id: 'm$i',
        conversationId: conversationId,
        role: 'user',
        content: '消息$i',
        createdAt: base.add(Duration(milliseconds: i)),
      ));
    }
  }

  test('超过一页的会话只载最新 200 条，滚顶翻页补齐更早消息', () async {
    final (db, container, controller) = await boot();
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await seedConversation(db, conversationId: 'big', count: 250);
    final conversation =
        (await db.recentConversations()).firstWhere((c) => c.id == 'big');

    await controller.switchConversation(conversation);
    final state = container.read(chatControllerProvider);
    expect(state.messages, hasLength(200), reason: '初始窗口 = 最新 200 条');
    // 领域 ChatMessage 不携带 DB id，用内容定位（m50..m249 的正文是 消息50..消息249）。
    expect(state.messages.first.text, '消息50');
    expect(state.messages.last.text, '消息249');

    expect(await controller.loadOlderMessages(), isTrue,
        reason: '还有 50 条更早消息，应翻到一页');
    final afterFirst = container.read(chatControllerProvider);
    expect(afterFirst.messages, hasLength(250));
    expect(afterFirst.messages.first.text, '消息0', reason: '前插后保持升序');
    expect(afterFirst.messages[50].text, '消息50');

    // 剩余不足一页时也应标记耗尽：再次调用是 no-op。
    expect(await controller.loadOlderMessages(), isFalse);
    expect(container.read(chatControllerProvider).messages, hasLength(250));
  });

  test('不足一页的会话直接标记耗尽，翻页是 no-op', () async {
    final (db, container, controller) = await boot();
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await seedConversation(db, conversationId: 'small', count: 10);
    final conversation =
        (await db.recentConversations()).firstWhere((c) => c.id == 'small');

    await controller.switchConversation(conversation);
    expect(container.read(chatControllerProvider).messages, hasLength(10));
    expect(await controller.loadOlderMessages(), isFalse,
        reason: '10 < 200，初始加载已覆盖全量');
    expect(container.read(chatControllerProvider).messages, hasLength(10));
  });

  test('切换会话后游标重置，按新会话的窗口翻页', () async {
    final (db, container, controller) = await boot();
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await seedConversation(db, conversationId: 'big', count: 250);
    await seedConversation(db, conversationId: 'small', count: 5);
    final conversations = await db.recentConversations();
    await controller
        .switchConversation(conversations.firstWhere((c) => c.id == 'big'));
    expect(await controller.loadOlderMessages(), isTrue);

    await controller
        .switchConversation(conversations.firstWhere((c) => c.id == 'small'));
    expect(container.read(chatControllerProvider).messages, hasLength(5));
    expect(await controller.loadOlderMessages(), isFalse,
        reason: '游标必须随会话切换重置，不能沿用上一会话的耗尽/位置状态');
  });
}
