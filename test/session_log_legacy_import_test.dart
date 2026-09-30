// 阶段 4b：旧会话导入会话日志 + 影子比对。
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/session_log/legacy_import.dart';
import 'package:mobile_agent/application/session_log/session_event.dart';
import 'package:mobile_agent/application/session_log/session_event_store.dart';
import 'package:mobile_agent/application/session_log/session_log_maintenance.dart';
import 'package:mobile_agent/application/session_log/session_log_reader.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';

void main() {
  late AppDatabase db;
  late DriftSessionEventStore store;
  var clock = DateTime(2026, 1, 1, 8);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftSessionEventStore(db);
  });
  tearDown(() => db.close());

  Future<void> conversation(String id) => db.saveConversation(Conversation(
        id: id,
        title: id,
        agentId: null,
        projectId: null,
        mode: 'chat',
        providerProfileId: null,
        isPinned: false,
        isFavorite: false,
        tagsJson: '[]',
        createdAt: clock,
        updatedAt: clock,
      ));

  Future<void> row(String conversationId, String role, String content,
      {String? toolCallId, List<Map<String, dynamic>>? toolCalls}) {
    clock = clock.add(const Duration(seconds: 1));
    return db.insertMessage(MessagesCompanion.insert(
      id: 'm${clock.millisecondsSinceEpoch}',
      conversationId: conversationId,
      role: role,
      content: content,
      createdAt: clock,
      toolCallId: Value(toolCallId),
      toolCallsJson: Value(toolCalls == null ? null : jsonEncode(toolCalls)),
    ));
  }

  Future<void> legacyConversation(String id) async {
    await conversation(id);
    await row(id, 'user', '读一下 README');
    await row(id, 'assistant', '好的', toolCalls: [
      {
        'id': 'call-1',
        'name': 'read_file',
        'arguments': {'path': 'README.md'},
        'risk': 'safe',
      },
    ]);
    await row(id, 'tool', '{"ok":true}', toolCallId: 'call-1');
    await row(id, 'assistant', '内容如下');
    await row(id, 'user', '继续');
    await row(id, 'assistant', '完成');
    await row(id, 'user', '继续');
  }

  test('imports a legacy conversation as one synthetic run', () async {
    await legacyConversation('c1');

    expect(await LegacySessionImporter(db, store).importConversation('c1'),
        isTrue);

    final events = await store.events('c1');
    final reader = SessionLogReader(events);
    expect(events.first.type, SessionEventType.turnStart);
    expect(events.first.payload['imported'], isTrue);
    expect(reader.lastTurnStatus, 'imported');
    expect(reader.unsealedRuns, isEmpty);
    // 重复的“继续”只写一次消息事件，但在 refs 中出现两次。
    final userEvents = events.where((e) =>
        e.type == SessionEventType.message && e.payload['role'] == 'user');
    expect(userEvents, hasLength(2));
    final derived = reader.deriveMessages()!;
    expect(derived.map((m) => m.text).toList(),
        ['读一下 README', '好的', '{"ok":true}', '内容如下', '继续', '完成', '继续']);
    expect(derived[1].toolCalls.single.name, 'read_file');
    expect(derived[1].toolCalls.single.arguments, {'path': 'README.md'});
    expect(derived[2].toolCallId, 'call-1');

    final shadow = await SessionLogShadowCheck.compare(db, store, 'c1');
    expect(shadow!.matches, isTrue);
    expect(shadow.loggedCount, 7);
  });

  test('import is idempotent and never touches logged conversations',
      () async {
    await legacyConversation('c1');
    final importer = LegacySessionImporter(db, store);
    expect(await importer.importConversation('c1'), isTrue);
    final before = (await store.events('c1')).length;

    expect(await importer.importConversation('c1'), isFalse);
    expect(await importer.importConversation('empty'), isFalse);
    expect((await store.events('c1')).length, before);
  });

  test('importPending only picks conversations without a log', () async {
    await legacyConversation('old');
    await legacyConversation('logged');
    await store.append(
        conversationId: 'logged',
        type: SessionEventType.turnStart,
        payload: const {'runId': 'r'},
        runId: 'r');

    expect(await LegacySessionImporter(db, store).importPending(), 1);
    expect(await store.events('old'), isNotEmpty);
    expect(await store.events('logged'), hasLength(1));
  });

  test('appendAllIfEmpty refuses a conversation that already has events',
      () async {
    await store.append(
        conversationId: 'c', type: SessionEventType.turnStart, payload: const {});
    final wrote = await store.appendAllIfEmpty('c', [
      (type: SessionEventType.turnStart, payload: const {}, runId: null,
          contentKey: null),
    ]);
    expect(wrote, isFalse);
    expect(await store.events('c'), hasLength(1));
  });

  test('shadow check reports the first divergence without message text',
      () async {
    await legacyConversation('c1');
    await LegacySessionImporter(db, store).importConversation('c1');
    await row('c1', 'assistant', '只在 Messages 表里的秘密回复');

    final shadow = await SessionLogShadowCheck.compare(db, store, 'c1');
    expect(shadow!.matches, isFalse);
    expect(shadow.firstMismatch, 7);
    expect(shadow.storedCount, 8);
    expect(shadow.logged, isNull);
    expect(shadow.stored, startsWith('assistant||len='));
    expect(jsonEncode(shadow.toJson()), isNot(contains('秘密')));

    final recent = await SessionLogShadowCheck.compareRecent(db, store);
    expect(recent.map((r) => r.conversationId), ['c1']);
  });

  test('conversations without a finished run are not compared', () async {
    await conversation('c2');
    await row('c2', 'user', 'hi');
    expect(await SessionLogShadowCheck.compare(db, store, 'c2'), isNull);
  });

  test('startup steps run in order and a failing step does not stop the rest',
      () async {
    final ran = <String>[];
    var errors = 0;
    await SessionLogMaintenance.runOnStartup(
      InMemorySessionEventStore(),
      extraSteps: [
        () async => throw StateError('import failed'),
        () async => ran.add('shadow'),
      ],
      onError: (_, __) => errors++,
    );
    expect(errors, 1);
    expect(ran, ['shadow']);
  });

  test('rows convert to the same message the chat history restores', () async {
    await conversation('c3');
    await row('c3', 'assistant', 'plain');
    final message = chatMessageFromRow((await db.messagesFor('c3')).single);
    expect(message.role, MessageRole.assistant);
    expect(message.toolCalls, isEmpty);
    expect(message.text, 'plain');
  });
}
