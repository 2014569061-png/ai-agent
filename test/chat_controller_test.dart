import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/application/context_window.dart';
import 'package:mobile_agent/application/log_service.dart';
import 'package:mobile_agent/application/nexus_guard.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/domain/attachment_file.dart';
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
      approveTool: (call, risk, sensitive) async => ToolApproval.allowOnce,
    );

    final state = container.read(chatControllerProvider);
    expect(state.running, isFalse);
    expect(state.successfulRunCount, 1);
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

  test(
      'reply display metadata survives session switch and controller recreation',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    ProviderContainer makeContainer() => ProviderContainer(overrides: [
          databaseProvider.overrideWith((ref) async => db),
          providerConfigStoreProvider.overrideWith((ref) => _FakeConfigStore()),
        ]);
    var container = makeContainer();
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    var controller = container.read(chatControllerProvider.notifier);
    await pumpEventQueue();
    // Demo provider only: no network or paid inference.
    await controller.send(
        text: 'metadata round trip',
        attachments: const [],
        approveTool: _allowOnce);
    final before = container.read(chatControllerProvider);
    final reply = before.messages.last;
    final conversation = (await db.findConversation(before.conversationId!))!;
    expect(reply.modelName, isNotNull);
    expect(reply.elapsed, isNotNull);
    final stored = (await db.messagesFor(conversation.id)).last;
    expect(stored.displayMetadataJson, isNotNull);

    void checkRestored() {
      final restored = container.read(chatControllerProvider).messages.last;
      expect(restored.id, reply.id);
      expect(restored.text, reply.text);
      expect(restored.modelName, reply.modelName);
      expect(restored.elapsed, reply.elapsed);
      expect(restored.ttft, reply.ttft);
      expect(restored.usage?.promptTokens, reply.usage?.promptTokens);
      expect(restored.usage?.completionTokens, reply.usage?.completionTokens);
    }

    await controller.newConversation();
    await controller.switchConversation(conversation);
    checkRestored();
    // Make this the startup conversation without relying on wall-clock ties.
    await db.saveConversation(conversation.copyWith(
        updatedAt: DateTime.now().add(const Duration(minutes: 1))));
    container.dispose();
    container = makeContainer();
    controller = container.read(chatControllerProvider.notifier);
    await pumpEventQueue();
    expect(container.read(chatControllerProvider).loading, isFalse);
    expect(
        container.read(chatControllerProvider).conversationId, conversation.id);
    checkRestored();
  });

  test('surfaces an error when the provider completes without output',
      () async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8');
      request.response
          .write('data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n');
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });

    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        providerConfigStoreProvider.overrideWith(
          (ref) => _EmptyResponseConfigStore(server.port),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    final controller = container.read(chatControllerProvider.notifier);
    await pumpEventQueue();
    await controller.send(
      text: '空响应测试',
      attachments: const [],
      approveTool: _allowOnce,
    );

    final state = container.read(chatControllerProvider);
    expect(state.running, isFalse);
    expect(state.successfulRunCount, 0);
    expect(state.messages.last.text, contains('模型未返回可显示内容'));
    expect((await db.recentRuns()).single.status, 'failed');
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
        AttachmentFile(
          name: 'note.txt',
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
      mode: 'chat',
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
      content: '${ContextWindow.compressedToolResultMark}\n3',
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
    expect(state.toolActivities.first.compressed, isTrue);
    expect(state.toolActivities.first.originalResult, '3');
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
        approveTool: (call, risk, sensitive) async => ToolApproval.allowOnce);

    final state = container.read(chatControllerProvider);
    expect(state.running, isFalse);
    expect(state.successfulRunCount, 0);
    expect(state.messages.length, 2);
    final failedRuns = await db.recentRuns();
    expect(failedRuns, hasLength(1));
    expect(failedRuns.single.status, 'failed');
    expect(state.messages.last.text, contains('错误'));
    // 兜底后仍可继续发送（running 已复位）。
    await controller.send(
        text: '再试一次',
        attachments: const [],
        approveTool: (call, risk, sensitive) async => ToolApproval.allowOnce);
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
        approveTool: (call, risk, sensitive) async => ToolApproval.allowOnce);
    // 等流真正开始（DemoProvider 每字符延迟 12ms）。
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(container.read(chatControllerProvider).running, isTrue);
    expect(container.read(chatControllerProvider).liveContextTokens,
        greaterThan(0));

    controller.stop();
    await future;

    final state = container.read(chatControllerProvider);
    expect(state.running, isFalse);
    expect(state.successfulRunCount, 0);
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
        approveTool: (call, risk, sensitive) async => ToolApproval.allowOnce);
    expect(container.read(chatControllerProvider).messages.length, 2);

    await controller.regenerate(
        approveTool: (call, risk, sensitive) async => ToolApproval.allowOnce);

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

  test('editAndResend stops when the edit cannot be persisted', () async {
    final db = _FailingEditDatabase();
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
      text: '第一问',
      attachments: const [],
      approveTool: _allowOnce,
    );

    await controller.editAndResend(
      messageIndex: 0,
      newText: '改过的问题',
      approveTool: _allowOnce,
    );

    final state = container.read(chatControllerProvider);
    expect(state.running, isFalse);
    expect(state.messages.first.text, '第一问');
    expect(state.activityLog, contains('编辑未能保存，已取消重发'));
  });

  test('initialization restores the latest context snapshot', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final now = DateTime(2026, 1, 1);
    await db.saveConversation(Conversation(
      id: 'c1',
      title: '带上下文的会话',
      agentId: null,
      mode: 'agent',
      isPinned: false,
      isFavorite: false,
      tagsJson: '[]',
      createdAt: now,
      updatedAt: now,
    ));
    await db.insertRunRecord(RunRecordsCompanion.insert(
      runId: 'run-c1-context',
      conversationId: 'c1',
      status: const Value('success'),
      startedAt: now,
    ));
    await db.insertRunEvent(RunEventsCompanion.insert(
      eventId: 'event-c1-context',
      runId: 'run-c1-context',
      sequenceNo: 1,
      type: 'context_snapshot',
      status: 'recorded',
      name: '上下文快照',
      startedAt: now,
      metadataJson: const Value(
        '{"step":1,"startedAt":"2026-01-01T00:00:00.000",'
        '"snapshot":{"usedTokens":1200,"contextWindow":32000,'
        '"reservedOutputTokens":2048,"updatedAt":"2026-01-01T00:00:00.000",'
        '"parts":[{"type":"user","tokens":1200,"estimated":true}]}}',
      ),
    ));

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
    expect(state.loading, isFalse);
    expect(state.conversationId, 'c1');
    expect(state.running, isFalse);
    expect(state.contextSteps, hasLength(1));
    expect(state.contextSteps.single.snapshot.usedTokens, 1200);
    expect(state.contextSnapshot?.usedTokens, 1200);
  });

  test('invalidates empty context history after a new run', () async {
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
    expect(await controller.loadContextRuns(), isEmpty);

    await controller.send(
      text: '建立上下文历史',
      attachments: const [],
      approveTool: _allowOnce,
    );

    final histories = await controller.loadContextRuns();
    expect(histories, hasLength(1));
    expect(histories.single.steps, isNotEmpty);
  });

  test('switchConversation loads the target conversation messages', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final now = DateTime.now();
    await db.saveConversation(Conversation(
        id: 'c1',
        title: '会话一',
        agentId: null,
        mode: 'chat',
        isPinned: false,
        isFavorite: false,
        tagsJson: '[]',
        createdAt: now,
        updatedAt: now));
    await db.saveConversation(Conversation(
        id: 'c2',
        title: '会话二',
        agentId: null,
        mode: 'chat',
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
    await db.insertRunRecord(RunRecordsCompanion.insert(
      runId: 'run-c1-context',
      conversationId: 'c1',
      status: const Value('success'),
      startedAt: now.add(const Duration(minutes: 6)),
    ));
    await db.insertRunEvent(RunEventsCompanion.insert(
      eventId: 'event-c1-context',
      runId: 'run-c1-context',
      sequenceNo: 1,
      type: 'context_snapshot',
      status: 'recorded',
      name: '上下文快照',
      startedAt: now.add(const Duration(minutes: 6)),
      metadataJson: const Value(
        '{"step":1,"startedAt":"2026-01-01T00:00:00.000",'
        '"snapshot":{"usedTokens":1200,"contextWindow":32000,'
        '"reservedOutputTokens":2048,"updatedAt":"2026-01-01T00:00:00.000",'
        '"parts":[{"type":"user","tokens":1200,"estimated":true}]}}',
      ),
    ));
    await db.insertRunEvent(RunEventsCompanion.insert(
      eventId: 'event-c1-tool',
      runId: 'run-c1-context',
      sequenceNo: 2,
      type: 'tool_call',
      status: 'success',
      name: 'read_file',
      startedAt: now.add(const Duration(minutes: 6, seconds: 1)),
    ));

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
    expect(state.contextSteps, hasLength(1));
    expect(state.contextSteps.single.snapshot.usedTokens, 1200);
    expect(state.liveContextTokens, 1200);
    // 会话切换只恢复最新快照；完整运行历史由指标面板按需加载。
    expect(state.contextRuns, isEmpty);
    final histories = await controller.loadContextRuns();
    expect(histories, hasLength(1));
    expect(
      histories.single.events.map((event) => event.type),
      ['context_snapshot', 'tool_call'],
    );
    expect(container.read(chatControllerProvider).contextRuns, hasLength(1));
  });

  test('latest conversation selection wins when an older switch is delayed',
      () async {
    final db = _DelayedMessagesPageDatabase();
    final now = DateTime(2026, 1, 1);
    for (final id in ['c1', 'c2']) {
      await db.saveConversation(Conversation(
        id: id,
        title: id,
        agentId: null,
        mode: 'chat',
        isPinned: false,
        isFavorite: false,
        tagsJson: '[]',
        createdAt: now,
        updatedAt: now,
      ));
    }

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
    db.delayNextPage = true;

    final olderSwitch = controller.switchConversation(
      (await db.findConversation('c1'))!,
    );
    await db.firstPageStarted.future;
    expect(
        container.read(chatControllerProvider).restoringConversation, isTrue);
    final latestSwitch = controller.switchConversation(
      (await db.findConversation('c2'))!,
    );
    await latestSwitch;
    expect(
        container.read(chatControllerProvider).restoringConversation, isFalse);
    db.releaseFirstPage.complete();
    await olderSwitch;

    expect(container.read(chatControllerProvider).conversationId, 'c2');
  });

  test('history loading does not write an old conversation into the new one',
      () async {
    final db = _DelayedMessagesPageDatabase();
    final now = DateTime(2026, 1, 1);
    for (final id in ['c1', 'c2']) {
      await db.saveConversation(Conversation(
        id: id,
        title: id,
        agentId: null,
        mode: 'chat',
        isPinned: false,
        isFavorite: false,
        tagsJson: '[]',
        createdAt: now,
        updatedAt: now,
      ));
    }
    await db.insertRunRecord(RunRecordsCompanion.insert(
      runId: 'run-c1-history',
      conversationId: 'c1',
      status: const Value('success'),
      startedAt: now,
    ));
    await db.insertRunEvent(RunEventsCompanion.insert(
      eventId: 'event-c1-history',
      runId: 'run-c1-history',
      sequenceNo: 1,
      type: 'tool_call',
      status: 'success',
      name: 'read_file',
      startedAt: now,
    ));

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
    await controller.switchConversation((await db.findConversation('c1'))!);

    db.delayEvents = true;
    final loading = controller.loadContextRuns();
    await db.eventsStarted.future;
    await controller.switchConversation((await db.findConversation('c2'))!);
    db.releaseEvents.complete();

    expect(await loading, isEmpty);
    expect(container.read(chatControllerProvider).conversationId, 'c2');
    expect(container.read(chatControllerProvider).contextRuns, isEmpty);
  });

  test('deleteTrailingAssistantAndTool removes only the last round', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final now = DateTime.now();
    await db.saveConversation(Conversation(
        id: 'c1',
        title: 't',
        agentId: null,
        mode: 'chat',
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

  test('deleteTrailingAssistantAndTool removes same-second trailing replies',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.now();
    final sameSecond = DateTime.fromMillisecondsSinceEpoch(
      now.millisecondsSinceEpoch ~/ 1000 * 1000,
    );
    await db.saveConversation(Conversation(
        id: 'c1',
        title: 't',
        agentId: null,
        mode: 'chat',
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
        createdAt: sameSecond.subtract(const Duration(minutes: 3))));
    await db.insertMessage(MessagesCompanion.insert(
        id: 'm2',
        conversationId: 'c1',
        role: 'assistant',
        content: '第一轮回答',
        createdAt: sameSecond.subtract(const Duration(minutes: 2))));
    await db.insertMessage(MessagesCompanion.insert(
        id: 'm3',
        conversationId: 'c1',
        role: 'tool',
        content: '上一轮工具结果',
        toolCallId: const Value('t1'),
        createdAt: sameSecond.subtract(const Duration(minutes: 1))));
    await db.insertMessage(MessagesCompanion.insert(
        id: 'm4',
        conversationId: 'c1',
        role: 'user',
        content: '第二轮',
        createdAt: sameSecond));
    await db.insertMessage(MessagesCompanion.insert(
        id: 'm5',
        conversationId: 'c1',
        role: 'assistant',
        content: '同一秒回答',
        createdAt: sameSecond));
    await db.insertMessage(MessagesCompanion.insert(
        id: 'm6',
        conversationId: 'c1',
        role: 'tool',
        content: '同一秒工具结果',
        toolCallId: const Value('t2'),
        createdAt: sameSecond));

    await db.deleteTrailingAssistantAndTool('c1');

    final remaining = await db.messagesFor('c1');
    expect(remaining.map((m) => m.id).toSet(), {'m1', 'm2', 'm3', 'm4'});
    expect(remaining.map((m) => m.id), isNot(contains('m5')));
    expect(remaining.map((m) => m.id), isNot(contains('m6')));
  });

  test('editMessageAndTruncate keeps earlier same-second messages', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.now();
    final sameSecond = DateTime.fromMillisecondsSinceEpoch(
      now.millisecondsSinceEpoch ~/ 1000 * 1000,
    );
    await db.saveConversation(Conversation(
      id: 'c1',
      title: 't',
      agentId: null,
      mode: 'chat',
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
      content: '第一问',
      createdAt: sameSecond,
    ));
    await db.insertMessage(MessagesCompanion.insert(
      id: 'm2',
      conversationId: 'c1',
      role: 'assistant',
      content: '第一答',
      createdAt: sameSecond,
    ));
    await db.insertMessage(MessagesCompanion.insert(
      id: 'm3',
      conversationId: 'c1',
      role: 'user',
      content: '第二问',
      createdAt: sameSecond,
    ));

    final anchor = await db.userMessageIdByOrdinal('c1', 2);
    expect(anchor, 'm3');
    await db.editMessageAndTruncate('c1', anchor!, '第二问已改');

    final remaining = await db.messagesFor('c1');
    expect(remaining.map((m) => m.id).toList(), ['m1', 'm2', 'm3']);
    expect(remaining.last.content, '第二问已改');
  });

  group('workspaceToolRules 系统提示注入', () {
    test('未选工作区时引导用户选择，而不是声称设备无能力', () {
      final rules = ChatController.workspaceToolRules(
        workspacePath: null,
        fileToolsAvailable: false,
        terminalAvailable: false,
      );
      expect(rules, contains('未选择工作区'));
      expect(rules, contains('不是设备能力缺失'));
      expect(rules, contains('工作区入口'));
    });

    test('文件工具关闭时提示真实设置入口', () {
      final rules = ChatController.workspaceToolRules(
        workspacePath: '/data/project',
        fileToolsAvailable: false,
        terminalAvailable: false,
      );
      expect(rules, contains('/data/project'));
      expect(rules, contains('设置 → 扩展与环境 → 工具列表'));
      expect(rules, contains('允许 Agent 读写当前工作区文件'));
    });

    test('聊天模式引导切换 Agent，而不是错误指向工具设置', () {
      final rules = ChatController.workspaceToolRules(
        workspacePath: '/data/project',
        fileToolsAvailable: false,
        terminalAvailable: false,
        mode: ChatMode.chat,
      );
      expect(rules, contains('聊天”模式'));
      expect(rules, contains('切换到 Agent 模式'));
      expect(rules, isNot(contains('设置 → 扩展与环境')));
    });

    test('终端不可用不阻止静态文件任务', () {
      final rules = ChatController.workspaceToolRules(
        workspacePath: '/data/project',
        fileToolsAvailable: true,
        terminalAvailable: false,
      );
      expect(rules, contains('文件工具可用'));
      expect(rules, contains('静态 HTML/CSS/JS'));
      expect(rules, contains('仍应直接完成'));
    });

    test('工具可用时列出工具与运行时边界', () {
      final rules = ChatController.workspaceToolRules(
        workspacePath: '/data/project',
        fileToolsAvailable: true,
        terminalAvailable: true,
      );
      expect(rules, contains('terminal'));
      expect(rules, contains('write_file'));
      expect(rules, contains('Alpine PRoot'));
      expect(rules, contains('不是完整文件系统沙箱'));
      expect(rules, contains('禁止伪造成功'));
    });

    test('空白路径视为未选择工作区', () {
      final rules = ChatController.workspaceToolRules(
        workspacePath: '  ',
        fileToolsAvailable: false,
        terminalAvailable: false,
      );
      expect(rules, contains('未选择工作区'));
    });
  });

  // 回归保护：会话消息写库失败此前被 `catch (_) {}` 完全吞掉 —— 用户的消息或
  // 助手回复会从历史里静默消失，而日志、遥测、界面上都看不出发生过。现在它必须
  // 留下一条可导出的降级警告，同时**不改变控制流**（对话照常继续）。
  test('消息落库失败时记录降级警告，而不是静默吞掉', () async {
    NexusGuard.resetReportedKeys();
    final db = _FailingPersistDatabase();
    final logs = _RecordingLogService(Future.value(db));
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        providerConfigStoreProvider.overrideWith((ref) => _FakeConfigStore()),
        logServiceProvider.overrideWithValue(logs),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    final controller = container.read(chatControllerProvider.notifier);
    await pumpEventQueue();
    expect(container.read(chatControllerProvider).loading, isFalse);

    // 只让消息写入失败：run/event 记录仍然正常，归因才不会被混淆。
    db.failInserts = true;

    await controller.send(
      text: '持久化失败注入',
      attachments: const [],
      approveTool: _allowOnce,
    );

    // 1) 控制流不变：对话没有中断，回复照常显示。
    final state = container.read(chatControllerProvider);
    expect(state.running, isFalse);
    expect(state.messages.last.text, contains('演示响应'));

    // 2) 但失败不再无声。注意助手回复本身在 _runAgent 的收尾里另有 error 级日志
    //    （category: run_persistence），这里断言的是新接入的用户消息那一处。
    expect(logs.warnings, contains('已降级：chat.persistUserMessage'));
  });
}

/// 只让消息写入失败，其余表读写照常。
class _FailingPersistDatabase extends AppDatabase {
  _FailingPersistDatabase() : super(NativeDatabase.memory());

  bool failInserts = false;

  @override
  Future<void> insertMessage(MessagesCompanion message) {
    if (failInserts) {
      throw StateError('磁盘写入失败（测试注入）');
    }
    return super.insertMessage(message);
  }
}

/// 记录降级警告。真实 LogService 会写进同一个库，而这里库恰好是坏的，所以必须
/// 用一个只做记录的实现来观察「失败是否留痕」。
class _RecordingLogService extends LogService {
  _RecordingLogService(super.database);

  final List<String> warnings = <String>[];

  @override
  Future<void> warning(String message,
      {String? runId,
      String? eventId,
      String category = 'system',
      Map<String, dynamic>? detail}) async {
    warnings.add(message);
  }
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

class _EmptyResponseConfigStore extends _FakeConfigStore {
  _EmptyResponseConfigStore(this.port);

  final int port;

  @override
  Future<ProviderConfig> load() async => ProviderConfig(
        baseUrl: 'http://127.0.0.1:$port/v1',
        model: 'test-model',
        apiKey: 'test-key',
      );
}

class _DelayedMessagesPageDatabase extends AppDatabase {
  _DelayedMessagesPageDatabase() : super(NativeDatabase.memory());

  final firstPageStarted = Completer<void>();
  final releaseFirstPage = Completer<void>();
  final eventsStarted = Completer<void>();
  final releaseEvents = Completer<void>();
  bool delayNextPage = false;
  bool delayEvents = false;

  @override
  Future<List<(Message, int)>> messagesPage(
    String conversationId, {
    DateTime? before,
    int? beforeRowId,
    int? limit,
  }) async {
    if (delayNextPage) {
      delayNextPage = false;
      firstPageStarted.complete();
      await releaseFirstPage.future;
    }
    return super.messagesPage(
      conversationId,
      before: before,
      beforeRowId: beforeRowId,
      limit: limit,
    );
  }

  @override
  Future<List<RunEvent>> eventsForRun(
    String runId, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (delayEvents) {
      delayEvents = false;
      eventsStarted.complete();
      await releaseEvents.future;
    }
    return super.eventsForRun(runId, limit: limit, offset: offset);
  }
}

Future<ToolApproval> _allowOnce(
  ToolCall call,
  ToolRisk risk,
  bool sensitive,
) async =>
    ToolApproval.allowOnce;

class _FakeConfigStore extends ProviderConfigStore {
  @override
  Future<ProviderConfig> load() async => const ProviderConfig(
      baseUrl: 'https://api.openai.com/v1', model: 'gpt-4o-mini', apiKey: '');

  @override
  Future<String> readToolKey(String name) async => '';
}

class _FailingEditDatabase extends AppDatabase {
  _FailingEditDatabase() : super(NativeDatabase.memory());

  @override
  Future<void> editMessageAndTruncate(
    String conversationId,
    String messageId,
    String newContent,
  ) async {
    throw StateError('disk full');
  }
}
