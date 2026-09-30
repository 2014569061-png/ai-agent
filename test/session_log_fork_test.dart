// 阶段 4c：会话分叉时在 turn 边界复制会话日志。
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/agent_executor.dart';
import 'package:mobile_agent/application/conversation_fork_service.dart';
import 'package:mobile_agent/application/session_log/chat_message_codec.dart';
import 'package:mobile_agent/application/session_log/legacy_import.dart';
import 'package:mobile_agent/application/session_log/session_event.dart';
import 'package:mobile_agent/application/session_log/session_event_store.dart';
import 'package:mobile_agent/application/session_log/session_log_fork.dart';
import 'package:mobile_agent/application/session_log/session_log_reader.dart';
import 'package:mobile_agent/application/session_log/session_recorder.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';

final _bigImage = 'data:image/png;base64,${'B' * 3000}';

ChatMessage _msg(MessageRole role, String text, {bool image = false}) =>
    ChatMessage(role: role, parts: [
      MessagePart.text(text),
      if (image) MessagePart.image(_bigImage, mimeType: 'image/png'),
    ]);

final _system = _msg(MessageRole.system, '你是助手');

String? _lastStatus(SessionLogReader reader) => reader.events.reversed
    .firstWhere((e) => e.type == SessionEventType.turnEnd)
    .payload['status'] as String?;

void main() {
  late AppDatabase db;
  late DriftSessionEventStore store;
  var clock = DateTime(2026, 3, 1, 9);
  const service = ConversationForkService();

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftSessionEventStore(db);
    await db.saveConversation(Conversation(
      id: 'src',
      title: '原会话',
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
  });
  tearDown(() => db.close());

  Future<void> row(String id, String role, String content) {
    clock = clock.add(const Duration(seconds: 1));
    return db.insertMessage(MessagesCompanion.insert(
      id: id,
      conversationId: 'src',
      role: role,
      content: content,
      createdAt: clock,
      toolCallId: const Value(null),
    ));
  }

  /// 一次聊天运行：日志记录模型请求与完成，同时像聊天路径一样写 Messages 行。
  Future<void> run(String runId, List<ChatMessage> history, String userRowId,
      String answerRowId, String answer) async {
    final recorder = SessionRecorder(
        store: store, conversationId: 'src', runId: runId, model: 'm')
      ..start()
      ..onRequest(1, UnifiedRequest(model: 'm', messages: history))
      ..observe(TextEvent(answer))
      ..observe(const AgentStatusEvent(RunStatus.completed));
    await recorder.flush();
    // 与 _contentForPersist 一致：附件在 Messages 行里只是占位标记。
    await row(userRowId, 'user',
        history.last.text.replaceAll('[图片]', '[图片附件]'));
    await row(answerRowId, 'assistant', answer);
  }

  Future<void> twoRuns() async {
    final q1 = _msg(MessageRole.user, '第一问', image: true);
    await run('r1', [_system, q1], 'u1', 'a1', '第一答');
    await run('r2', [
      _system,
      q1,
      _msg(MessageRole.assistant, '第一答'),
      _msg(MessageRole.user, '第二问'),
    ], 'u2', 'a2', '第二答');
  }

  Future<Conversation> fork(String anchor) => service.fork(
        db: db,
        sourceConversationId: 'src',
        forkMessageId: anchor,
        sessionLog: store,
      );

  test('forking at a finished turn copies that turn\'s exact history',
      () async {
    await twoRuns();
    final branch = await fork('a1');

    final reader = await SessionLogReader.load(store, branch.id);
    final start = reader.events.first;
    expect(start.payload['forked'], isTrue);
    expect(start.payload['parentConversationId'], 'src');
    expect(start.payload['parentRunId'], 'r1');
    expect(_lastStatus(reader), 'forked');

    final history = reader.deriveMessages()!;
    expect(history.first.text, '你是助手', reason: 'system 随边界一起复制');
    expect(history.map((m) => m.text).skip(1), ['第一问[图片]', '第一答']);
    expect(history[1].parts[1].value, _bigImage, reason: '附件随分支保留');
    expect((await SessionLogShadowCheck.compare(db, store, branch.id))!.matches,
        isTrue);
  });

  test('forking at the latest turn picks the latest boundary', () async {
    await twoRuns();
    final branch = await fork('a2');
    final reader = await SessionLogReader.load(store, branch.id);
    expect(reader.events.first.payload['parentRunId'], 'r2');
    expect(reader.deriveMessages()!.last.text, '第二答');
  });

  test('forking mid-turn falls back to importing the copied rows', () async {
    await twoRuns();
    final branch = await fork('u2');
    final reader = await SessionLogReader.load(store, branch.id);
    expect(_lastStatus(reader), 'imported');
    expect(reader.deriveMessages()!.map((m) => m.text),
        ['第一问[图片附件]', '第一答', '第二问'],
        reason: '导入只能拿到 Messages 行里的占位标记');
  });

  test('a source without a log also falls back to import', () async {
    await row('u1', 'user', 'hi');
    await row('a1', 'assistant', 'hello');
    final branch = await fork('a1');
    expect(_lastStatus(await SessionLogReader.load(store, branch.id)),
        'imported');
  });

  test('without a store the fork writes no session log', () async {
    await twoRuns();
    final branch = await service.fork(
        db: db, sourceConversationId: 'src', forkMessageId: 'a1');
    expect(await store.events(branch.id), isEmpty);
    expect(await db.messagesFor(branch.id), hasLength(2));
  });

  test('the branch keeps attachments after the source is deleted', () async {
    await twoRuns();
    final branch = await fork('a1');
    await db.deleteConversation('src');

    final monthAgo = DateTime.now().subtract(const Duration(days: 30));
    expect(await store.pruneBlobs(unusedSince: monthAgo), 0);
    final history = (await SessionLogReader.load(store, branch.id))
        .deriveMessages()!;
    expect(history[1].parts[1].value, _bigImage);
    expect(ChatMessageCodec.blobRefs(
            (await store.events(branch.id))
                .firstWhere((e) =>
                    e.type == SessionEventType.message &&
                    ChatMessageCodec.blobRefs(e.payload).isNotEmpty)
                .payload),
        hasLength(1));
  });

  test('shadow check tolerates attachment placeholders and redaction', () {
    final logged = [
      _msg(MessageRole.user, '看图', image: true),
      ChatMessage(
          role: MessageRole.tool, toolCallId: 'c1', parts: const [
        MessagePart.text('{"secret":1}')
      ]),
    ];
    final stored = [
      _msg(MessageRole.user, '看图[图片附件]'),
      ChatMessage(
          role: MessageRole.tool, toolCallId: 'c1', parts: const [
        MessagePart.text('[敏感工具结果已脱敏]')
      ]),
    ];
    expect(SessionLogShadowCheck.firstMismatch(logged, stored), isNull);
    expect(
        SessionLogShadowCheck.firstMismatch(
            [_msg(MessageRole.assistant, 'a')], [_msg(MessageRole.assistant, 'b')]),
        0);
    expect(
        SessionLogShadowCheck.firstMismatch(logged, stored.take(1).toList()),
        1);
  });

  test('log failures never break the fork itself', () async {
    await twoRuns();
    Object? reported;
    final branch = await service.fork(
      db: db,
      sourceConversationId: 'src',
      forkMessageId: 'a1',
      sessionLog: _BrokenStore(),
      onSessionLogError: (error, _) => reported = error,
    );
    expect(await db.messagesFor(branch.id), hasLength(2));
    expect(reported, isA<StateError>());
  });

  test('forking an already logged branch is a no-op', () async {
    await twoRuns();
    final branch = await fork('a1');
    final before = (await store.events(branch.id)).length;
    expect(
      await SessionLogForker(db, store).fork(
          sourceConversationId: 'src', branchConversationId: branch.id),
      SessionLogForkKind.skipped,
    );
    expect((await store.events(branch.id)).length, before);
  });
}

class _BrokenStore extends InMemorySessionEventStore {
  @override
  Future<List<SessionEvent>> events(String conversationId) async =>
      throw StateError('disk');
}
