import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_picker/file_picker.dart';

import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config_store.dart';

void main() {
  test('ChatController streams a demo response into state', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        providerConfigStoreProvider.overrideWith((ref) => _FakeConfigStore()),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    final controller = container.read(chatControllerProvider.notifier);
    // 等待异步初始化完成（加载会话与默认 Agent）。
    await pumpEventQueue();
    expect(container.read(chatControllerProvider).loading, isFalse);

    await controller.send(
      text: '你好',
      attachments: const [],
      approveTool: (call, risk) async => ToolApproval.allowOnce,
    );

    final state = container.read(chatControllerProvider);
    expect(state.running, isFalse);
    expect(state.messages.length, 2);
    expect(state.messages.last.text, contains('演示响应'));
    expect(state.messages.last.elapsed, isNotNull);

    final runs = await db.recentRuns();
    expect(runs, hasLength(1));
    expect(runs.single.status, 'success');
    expect(runs.single.totalDurationMs, greaterThanOrEqualTo(0));
    expect(runs.single.firstTokenDurationMs, isNotNull);
    final events = await db.eventsForRun(runs.single.runId);
    expect(events, isNotEmpty);
    expect(events.any((event) => event.type == 'model_request'), isTrue);
    expect(events.any((event) => event.type == 'network'), isTrue);
  });

  test('sends an attachment without text', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        providerConfigStoreProvider.overrideWith((ref) => _FakeConfigStore()),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    final controller = container.read(chatControllerProvider.notifier);
    await pumpEventQueue();
    await controller.send(
      text: '',
      attachments: [
        PlatformFile(
          name: 'note.txt',
          size: 5,
          bytes: Uint8List.fromList([104, 101, 108, 108, 111]),
        ),
      ],
      approveTool: _allowOnce,
    );

    final state = container.read(chatControllerProvider);
    expect(state.messages.length, 2);
    expect(
        state.messages.first.parts.any((part) => part.value.contains('hello')),
        isTrue);
  });

  test('restores tool call cards from persisted history', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final now = DateTime.now();
    await db.saveConversation(Conversation(
      id: 'c1',
      title: '测试会话',
      agentId: null,
      isPinned: false,
      isFavorite: false,
      tagsJson: '[]',
      createdAt: now,
      updatedAt: now,
    ));
    await db.insertMessage(MessagesCompanion.insert(
        id: 'm1',
        conversationId: 'c1',
        role: 'user',
        content: '算一下 1+2',
        createdAt: now));
    await db.insertMessage(MessagesCompanion.insert(
      id: 'm2',
      conversationId: 'c1',
      role: 'assistant',
      content: '',
      toolCallsJson: const Value(
          '[{"id":"call-1","name":"calculator","arguments":{"a":1,"b":2},"risk":"safe"}]'),
      createdAt: now,
    ));
    await db.insertMessage(MessagesCompanion.insert(
      id: 'm3',
      conversationId: 'c1',
      role: 'tool',
      content: '3',
      toolCallId: const Value('call-1'),
      createdAt: now,
    ));
    await db.insertMessage(MessagesCompanion.insert(
        id: 'm4',
        conversationId: 'c1',
        role: 'assistant',
        content: '结果是 3',
        createdAt: now));

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        providerConfigStoreProvider.overrideWith((ref) => _FakeConfigStore()),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    container.read(chatControllerProvider.notifier);
    await pumpEventQueue();

    final state = container.read(chatControllerProvider);
    expect(state.toolActivities.length, 1);
    expect(state.toolActivities.first.call.name, 'calculator');
    expect(state.toolActivities.first.risk, ToolRisk.safe);
    expect(state.toolActivities.first.status, '已完成');
    expect(state.toolActivities.first.result, '3');
    // 工具调用与工具结果消息转为卡片，不进入气泡列表
    expect(state.messages.length, 2);
    expect(state.messages.last.text, '结果是 3');
  });

  test('recovers to idle state with error text when provider request fails',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        // apiKey 非空 → isConfigured=true → 走真实 OpenAI 兼容 provider。
        // baseUrl 指向不可达端口 → 请求失败 → 必须恢复 running=false 并给出错误提示。
        providerConfigStoreProvider
            .overrideWith((ref) => _FailingConfigStore()),
        agentRetrySettingsProvider.overrideWith(
          (ref) => const AgentRetrySettings(
            maxRetries: 0,
            retryBackoff: Duration.zero,
          ),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    final controller = container.read(chatControllerProvider.notifier);
    await pumpEventQueue();
    expect(container.read(chatControllerProvider).loading, isFalse);

    await controller.send(
        text: '你好',
        attachments: const [],
        approveTool: (call, risk) async => ToolApproval.allowOnce);

    final state = container.read(chatControllerProvider);
    expect(state.running, isFalse);
    expect(state.messages.length, 2);
    final failedRuns = await db.recentRuns();
    expect(failedRuns, hasLength(1));
    expect(failedRuns.single.status, 'failed');
    expect(state.messages.last.text, contains('错误'));
    // 兜底后仍可继续发送（running 已复位）。
    await controller.send(
        text: '再试一次',
        attachments: const [],
        approveTool: (call, risk) async => ToolApproval.allowOnce);
    expect(container.read(chatControllerProvider).messages.length, 4);
  });

  test('stop cancels an in-flight run and resets running state', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        providerConfigStoreProvider.overrideWith((ref) => _FakeConfigStore()),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    final controller = container.read(chatControllerProvider.notifier);
    await pumpEventQueue();

    final future = controller.send(
        text: '长文本',
        attachments: const [],
        approveTool: (call, risk) async => ToolApproval.allowOnce);
    // 等流真正开始（DemoProvider 每字符延迟 12ms）。
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(container.read(chatControllerProvider).running, isTrue);
    expect(container.read(chatControllerProvider).liveContextTokens,
        greaterThan(0));

    controller.stop();
    await future;

    final state = container.read(chatControllerProvider);
    expect(state.running, isFalse);
    // 停止后消息仍保留（部分或全部文本），且可再次发送。
    expect(state.messages.length, 2);
  });

  test('regenerate replaces the trailing assistant message in place', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        providerConfigStoreProvider.overrideWith((ref) => _FakeConfigStore()),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    final controller = container.read(chatControllerProvider.notifier);
    await pumpEventQueue();

    await controller.send(
        text: '你好',
        attachments: const [],
        approveTool: (call, risk) async => ToolApproval.allowOnce);
    expect(container.read(chatControllerProvider).messages.length, 2);

    await controller.regenerate(
        approveTool: (call, risk) async => ToolApproval.allowOnce);

    final state = container.read(chatControllerProvider);
    expect(state.running, isFalse);
    expect(state.messages.length, 2);
    expect(state.messages.last.text, contains('演示响应'));
  });

  test('editAndResend replaces an earlier user message and regenerates',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        providerConfigStoreProvider.overrideWith((ref) => _FakeConfigStore()),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    final controller = container.read(chatControllerProvider.notifier);
    await pumpEventQueue();

    const approve = _allowOnce;
    await controller.send(
        text: '第一问', attachments: const [], approveTool: approve);
    await controller.send(
        text: '第二问', attachments: const [], approveTool: approve);
    expect(container.read(chatControllerProvider).messages.length, 4);

    await controller.editAndResend(
        messageIndex: 0, newText: '  第一问修改版  ', approveTool: approve);

    final state = container.read(chatControllerProvider);
    expect(state.running, isFalse);
    expect(state.messages.length, 2);
    expect(state.messages.first.text, '第一问修改版');
    expect(state.messages.last.text, contains('演示响应'));

    // 库中只留下编辑后的用户消息与新生成的回复，第二轮被截断。
    final rows = await db.messagesFor(state.conversationId!);
    final userRows = rows.where((m) => m.role == 'user').toList();
    expect(userRows, hasLength(1));
    expect(userRows.single.content, '第一问修改版');
    expect(rows.last.role, 'assistant');
  });

  test('switchConversation loads the target conversation messages', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final now = DateTime.now();
    await db.saveConversation(Conversation(
        id: 'c1',
        title: '会话一',
        agentId: null,
        isPinned: false,
        isFavorite: false,
        tagsJson: '[]',
        createdAt: now,
        updatedAt: now));
    await db.saveConversation(Conversation(
        id: 'c2',
        title: '会话二',
        agentId: null,
        isPinned: false,
        isFavorite: false,
        tagsJson: '[]',
        createdAt: now,
        updatedAt: now));
    await db.insertMessage(MessagesCompanion.insert(
        id: 'm1',
        conversationId: 'c1',
        role: 'user',
        content: '一的内容',
        createdAt: now));
    await db.insertMessage(MessagesCompanion.insert(
        id: 'm2',
        conversationId: 'c2',
        role: 'user',
        content: '二的内容',
        createdAt: now));

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        providerConfigStoreProvider.overrideWith((ref) => _FakeConfigStore()),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    final controller = container.read(chatControllerProvider.notifier);
    await pumpEventQueue();
    // 默认加载最近会话（c2，updatedAt 相同取 lastInserted 排序，这里显式切换验证）。
    await controller.switchConversation((await db.findConversation('c2'))!);
    var state = container.read(chatControllerProvider);
    expect(state.conversationId, 'c2');
    expect(state.messages.single.text, '二的内容');

    await controller.switchConversation((await db.findConversation('c1'))!);
    state = container.read(chatControllerProvider);
    expect(state.conversationId, 'c1');
    expect(state.messages.single.text, '一的内容');
  });

  test('deleteTrailingAssistantAndTool removes only the last round', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final now = DateTime.now();
    await db.saveConversation(Conversation(
        id: 'c1',
        title: 't',
        agentId: null,
        isPinned: false,
        isFavorite: false,
        tagsJson: '[]',
        createdAt: now,
        updatedAt: now));
    await db.insertMessage(MessagesCompanion.insert(
        id: 'm1',
        conversationId: 'c1',
        role: 'user',
        content: '第一轮',
        createdAt: now.add(const Duration(minutes: 1))));
    await db.insertMessage(MessagesCompanion.insert(
        id: 'm2',
        conversationId: 'c1',
        role: 'assistant',
        content: '第一轮回答',
        createdAt: now.add(const Duration(minutes: 2))));
    await db.insertMessage(MessagesCompanion.insert(
        id: 'm3',
        conversationId: 'c1',
        role: 'tool',
        content: 'r',
        toolCallId: const Value('t1'),
        createdAt: now.add(const Duration(minutes: 3))));
    await db.insertMessage(MessagesCompanion.insert(
        id: 'm4',
        conversationId: 'c1',
        role: 'user',
        content: '第二轮',
        createdAt: now.add(const Duration(minutes: 4))));
    await db.insertMessage(MessagesCompanion.insert(
        id: 'm5',
        conversationId: 'c1',
        role: 'assistant',
        content: '第二轮回答',
        createdAt: now.add(const Duration(minutes: 5))));

    await db.deleteTrailingAssistantAndTool('c1');

    final remaining = await db.messagesFor('c1');
    expect(remaining.map((m) => m.id), ['m1', 'm2', 'm3', 'm4']);
    expect(remaining.map((m) => m.role), ['user', 'assistant', 'tool', 'user']);
  });
}

class _FailingConfigStore extends _FakeConfigStore {
  @override
  Future<ProviderConfig> load() async => const ProviderConfig(
        id: 'fail',
        name: 'Unreachable',
        baseUrl: 'http://127.0.0.1:1/v1',
        model: 'test-model',
        apiKey: 'test-key',
      );
}

Future<ToolApproval> _allowOnce(ToolCall call, ToolRisk risk) async =>
    ToolApproval.allowOnce;

class _FakeConfigStore extends ProviderConfigStore {
  @override
  Future<ProviderConfig> load() async => const ProviderConfig(
      baseUrl: 'https://api.openai.com/v1', model: 'gpt-4o-mini', apiKey: '');

  @override
  Future<String> readToolKey(String name) async => '';
}
