// 阶段 1：会话日志（与 Messages 双写）。
//
// 核心不变式：“模型可见 = 已记录”。对每一次模型请求，从日志解析出的消息
// 必须与 Provider 在发送时刻收到的消息逐字节一致（规范化 JSON 比较）。
import 'package:dio/dio.dart' show CancelToken;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/agent_executor.dart';
import 'package:mobile_agent/application/run_controller.dart';
import 'package:mobile_agent/application/session_log/chat_message_codec.dart';
import 'package:mobile_agent/application/session_log/session_event.dart';
import 'package:mobile_agent/application/session_log/session_event_store.dart';
import 'package:mobile_agent/application/session_log/session_log_reader.dart';
import 'package:mobile_agent/application/session_log/session_recorder.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/providers/llm_provider.dart';
import 'package:mobile_agent/infrastructure/tools/tool_registry.dart';

ChatMessage _user(String text) =>
    ChatMessage(role: MessageRole.user, parts: [MessagePart.text(text)]);

List<String> _canon(List<ChatMessage> messages) =>
    messages.map(ChatMessageCodec.canonicalJson).toList();

class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.steps);

  final List<List<UnifiedEvent>> steps;

  /// 发送时刻的消息快照。
  final sent = <List<ChatMessage>>[];

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    sent.add(List<ChatMessage>.of(request.messages));
    final index = sent.length - 1;
    final script = index < steps.length ? steps[index] : _text('fallback');
    for (final event in script) {
      yield event;
    }
  }
}

List<UnifiedEvent> _text(String text) => [
      TextDeltaEvent(text),
      const CompletedEvent(stopReason: StopReason.endOfTurn),
    ];

List<UnifiedEvent> _tool(String id) => [
      const TextDeltaEvent('computing'),
      const ReasoningDeltaEvent('need calc'),
      ToolCallEvent(
          ToolCall(id: id, name: 'calculator', arguments: const {'a': 1, 'b': 2})),
      const CompletedEvent(stopReason: StopReason.toolUse),
    ];

class _Harness {
  _Harness(List<List<UnifiedEvent>> steps, {SessionEventStore? store})
      : provider = _ScriptedProvider(steps),
        store = store ?? InMemorySessionEventStore();

  final _ScriptedProvider provider;
  final SessionEventStore store;
  final events = <AgentEvent>[];
  late SessionRecorder recorder;

  Future<SessionLogReader> run(
    List<ChatMessage> history, {
    String runId = 'run-1',
    String? systemPrompt,
    int maxSteps = 8,
    AgentRunController? controller,
    AgentCancellationToken? cancellationToken,
  }) async {
    recorder = SessionRecorder(
      store: store,
      conversationId: 'conv',
      runId: runId,
      model: 'm',
    )..start();
    final executor = AgentExecutor(
      provider: provider,
      tools: ToolRegistry()..register(CalculatorTool()),
    );
    await for (final event in executor.run(
      history: history,
      model: 'm',
      systemPrompt: systemPrompt,
      maxSteps: maxSteps,
      runController: controller,
      cancellationToken: cancellationToken,
      onRequest: recorder.onRequest,
    )) {
      events.add(event);
      recorder.observe(event);
    }
    await recorder.flush();
    return SessionLogReader(await store.events('conv'));
  }
}

void main() {
  group('ChatMessageCodec', () {
    test('round-trips every model-visible field', () {
      final message = ChatMessage(
        id: 'm1',
        role: MessageRole.assistant,
        parts: const [
          MessagePart.text('hello'),
          MessagePart.image('data:image/png;base64,AAAA', mimeType: 'image/png'),
          MessagePart.file('/tmp/a.txt', mimeType: 'text/plain'),
        ],
        toolCalls: const [
          ToolCall(
            id: 't1',
            name: 'calculator',
            arguments: {
              'a': 1,
              'nested': {'z': 1, 'y': [1, 2]}
            },
            providerMetadata: {'thoughtSignature': 'sig'},
          ),
        ],
        reasoning: 'because',
      );
      final decoded =
          ChatMessageCodec.decode(ChatMessageCodec.encode(message));
      expect(ChatMessageCodec.canonicalJson(decoded),
          ChatMessageCodec.canonicalJson(message));
      expect(decoded.toolCalls.single.thoughtSignature, 'sig');
      expect(decoded.parts[1].mimeType, 'image/png');
    });

    test('content key ignores display metadata but not content', () {
      final a = ChatMessage(
          id: 'x', role: MessageRole.user, parts: const [MessagePart.text('hi')]);
      final b = ChatMessage(
        id: 'y',
        role: MessageRole.user,
        parts: const [MessagePart.text('hi')],
        usage: const Usage(promptTokens: 9),
        elapsed: const Duration(seconds: 3),
      );
      final c = _user('hi!');
      final d = ChatMessage(
          role: MessageRole.assistant, parts: const [MessagePart.text('hi')]);
      expect(ChatMessageCodec.contentKey(a), ChatMessageCodec.contentKey(b));
      expect(ChatMessageCodec.contentKey(a),
          isNot(ChatMessageCodec.contentKey(c)));
      expect(ChatMessageCodec.contentKey(a),
          isNot(ChatMessageCodec.contentKey(d)));
    });

    test('argument key order does not change the content key', () {
      ChatMessage withArgs(Map<String, dynamic> args) => ChatMessage(
            role: MessageRole.assistant,
            parts: const [MessagePart.text('')],
            toolCalls: [ToolCall(id: '1', name: 'n', arguments: args)],
          );
      expect(ChatMessageCodec.contentKey(withArgs({'a': 1, 'b': 2})),
          ChatMessageCodec.contentKey(withArgs({'b': 2, 'a': 1})));
    });
  });

  group('model-visible means logged', () {
    test('every request of a tool run is reconstructable from the log',
        () async {
      final h = _Harness([_tool('c1'), _tool('c2'), _text('done')]);
      final log = await h.run([_user('1+2')], systemPrompt: 'be exact');

      expect(h.provider.sent, hasLength(3));
      final derived = log.requestsFor('run-1');
      expect(derived.map(_canon).toList(), h.provider.sent.map(_canon).toList());
      expect(log.lastTurnStatus, 'completed');
      expect(log.unsealedRuns, isEmpty);

      // 完成时的历史 = 最后一次请求 + 最终 assistant 回复。
      final history = log.deriveMessages()!;
      expect(_canon(history.sublist(0, history.length - 1)),
          _canon(h.provider.sent.last));
      expect(history.last.role, MessageRole.assistant);
      expect(history.last.text, 'done');
    });

    test('steering and executor-injected messages are captured', () async {
      final controller = AgentRunController()..steer('prefer integers');
      final h = _Harness([_text('first'), _tool('c1'), _text('done')]);
      final log = await h.run([_user('go')], controller: controller);
      expect(log.requestsFor('run-1').map(_canon).toList(),
          h.provider.sent.map(_canon).toList());
      final second = log.requestsFor('run-1')[1];
      expect(second.last.text, contains('用户补充指令：prefer integers'));
    });

    test('a budget pause logs the resumable context', () async {
      final h = _Harness([_tool('c1'), _tool('c2')]);
      final log = await h.run([_user('loop')], maxSteps: 1);
      final paused = h.events.whereType<AgentBudgetExhaustedEvent>().single;
      expect(log.lastTurnStatus, 'paused');
      expect(_canon(log.deriveMessages()!), _canon(paused.context));
    });

    test('cancellation and failures seal the turn', () async {
      final cancelled = _Harness([_text('never')]);
      final log1 = await cancelled.run([_user('x')],
          cancellationToken: AgentCancellationToken()..cancel());
      expect(log1.lastTurnStatus, 'cancelled');
      expect(log1.unsealedRuns, isEmpty);

      final failed = _Harness([
        [const ProviderErrorEvent('invalid api key', statusCode: 401)],
      ]);
      final log2 = await failed.run([_user('x')]);
      expect(log2.lastTurnStatus, 'failed');
      final end = log2.events.last;
      expect(end.type, SessionEventType.turnEnd);
      expect(end.payload['failureKind'], 'authentication');
    });

    test('a run that never ends is reported as unsealed', () async {
      final store = InMemorySessionEventStore();
      final recorder = SessionRecorder(
          store: store, conversationId: 'conv', runId: 'dead', model: 'm')
        ..start();
      recorder.onRequest(1, UnifiedRequest(model: 'm', messages: [_user('x')]));
      await recorder.flush();
      final log = SessionLogReader(await store.events('conv'));
      expect(log.unsealedRuns, ['dead']);
      expect(log.deriveMessages(), isNull);
    });
  });

  group('storage efficiency', () {
    test('each distinct message is stored once across steps and runs',
        () async {
      final store = InMemorySessionEventStore();
      final first = _Harness([_tool('c1'), _text('done')], store: store);
      final log1 = await first.run([_user('1+2')]);
      final messagesAfterRun1 = log1.events
          .where((e) => e.type == SessionEventType.message)
          .length;
      // user, assistant(tool call), tool result, final assistant
      expect(messagesAfterRun1, 4);

      // 第二次运行以日志推导的历史 + 新问题继续：旧消息不再重复写入。
      final second = _Harness([_text('again')], store: store);
      final log2 = await second.run([...log1.deriveMessages()!, _user('more')],
          runId: 'run-2');
      final newMessages = log2.events
          .where((e) => e.type == SessionEventType.message && e.runId == 'run-2')
          .length;
      expect(newMessages, 2, reason: '只有新问题和新回复');
      expect(log2.requestsFor('run-2').map(_canon).toList(),
          second.provider.sent.map(_canon).toList());
    });

    test('the request snapshot handed to observers never grows', () async {
      final snapshots = <UnifiedRequest>[];
      final provider = _ScriptedProvider([_tool('c1'), _text('done')]);
      await AgentExecutor(
        provider: provider,
        tools: ToolRegistry()..register(CalculatorTool()),
      )
          .run(
            history: [_user('1+2')],
            model: 'm',
            onRequest: (step, request) => snapshots.add(request),
          )
          .drain<void>();
      expect(snapshots.map((r) => r.messages.length).toList(), [1, 3]);
      expect(() => snapshots.first.messages.add(_user('x')),
          throwsUnsupportedError);
    });
  });

  group('recorder isolation', () {
    test('storage failures never break the run', () async {
      final errors = <Object>[];
      final provider = _ScriptedProvider([_tool('c1'), _text('done')]);
      final recorder = SessionRecorder(
        store: _FailingStore(),
        conversationId: 'conv',
        runId: 'r',
        model: 'm',
        onError: (e, _) => errors.add(e),
      )..start();
      final events = <AgentEvent>[];
      await for (final event in AgentExecutor(
        provider: provider,
        tools: ToolRegistry()..register(CalculatorTool()),
      ).run(history: [_user('1+2')], model: 'm', onRequest: recorder.onRequest)) {
        events.add(event);
        recorder.observe(event);
      }
      await recorder.flush();
      expect(events.whereType<AgentStatusEvent>().last.status,
          RunStatus.completed);
      expect(recorder.failures, greaterThan(0));
      expect(errors, isNotEmpty);
    });

    test('a throwing observer does not affect the executor', () async {
      final provider = _ScriptedProvider([_text('ok')]);
      final events = await AgentExecutor(
        provider: provider,
        tools: ToolRegistry(),
      )
          .run(
            history: [_user('hi')],
            model: 'm',
            onRequest: (_, __) => throw StateError('observer bug'),
          )
          .toList();
      expect(events.whereType<AgentStatusEvent>().last.status,
          RunStatus.completed);
    });
  });

  group('DriftSessionEventStore', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('sequences are per conversation and payloads round-trip', () async {
      final store = DriftSessionEventStore(db);
      final a1 = await store.append(
          conversationId: 'a', type: 'message', payload: {'x': 1}, contentKey: 'k1');
      final b1 = await store.append(
          conversationId: 'b', type: 'message', payload: {'y': 2});
      final a2 = await store.append(
          conversationId: 'a',
          type: SessionEventType.requestSent,
          payload: {
            'refs': [1]
          },
          runId: 'r');
      expect([a1.seq, b1.seq, a2.seq], [1, 1, 2]);
      final events = await store.events('a');
      expect(events.map((e) => e.seq), [1, 2]);
      expect(events.first.payload, {'x': 1});
      expect(events.last.refs, [1]);
      expect(events.last.runId, 'r');
      expect(await store.messageKeys('a'), {'k1': 1});
    });

    test('the full recorder pipeline works against SQLite', () async {
      final h = _Harness([_tool('c1'), _text('done')],
          store: DriftSessionEventStore(db));
      final log = await h.run([_user('1+2')]);
      expect(log.requestsFor('run-1').map(_canon).toList(),
          h.provider.sent.map(_canon).toList());
      expect(log.lastTurnStatus, 'completed');
    });

    test('deleting a conversation removes its session log', () async {
      final store = DriftSessionEventStore(db);
      await store.append(conversationId: 'gone', type: 'message', payload: {});
      await store.append(conversationId: 'kept', type: 'message', payload: {});
      await db.deleteConversation('gone');
      expect(await store.events('gone'), isEmpty);
      expect(await store.events('kept'), hasLength(1));
    });

    test('v25 to v26 migration creates the session_events table', () async {
      await db.customStatement('DROP TABLE IF EXISTS session_events');
      await db.migration.onUpgrade(db.createMigrator(), 25, 26);
      final rows = await db
          .customSelect("SELECT name FROM sqlite_master WHERE name IN "
              "('session_events', 'idx_session_events_content_key', "
              "'idx_session_events_run')")
          .get();
      expect(rows, hasLength(3));
    });
  });
}

class _FailingStore implements SessionEventStore {
  @override
  Future<SessionEvent> append({
    required String conversationId,
    required String type,
    required Map<String, dynamic> payload,
    String? runId,
    String? contentKey,
  }) async =>
      throw StateError('disk full');

  @override
  Future<List<SessionEvent>> events(String conversationId) async => const [];

  @override
  Future<Map<String, int>> messageKeys(String conversationId) async => {};

  @override
  Future<List<UnsealedRun>> unsealedRuns() async => const [];

  @override
  Future<bool> appendAllIfEmpty(
          String conversationId, List<NewSessionEvent> events) async =>
      throw StateError('disk full');

  @override
  Future<void> putBlobs(
          String conversationId, Map<String, SessionBlobData> blobs) async =>
      throw StateError('disk full');

  @override
  Future<Map<String, String>> blobs(Iterable<String> hashes) async => const {};

  @override
  Future<int> pruneBlobs({required DateTime unusedSince}) async => 0;
}
