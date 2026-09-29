// 阶段 4a：启动时给中断的运行封口。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/agent_executor.dart';
import 'package:mobile_agent/application/session_log/session_event.dart';
import 'package:mobile_agent/application/session_log/session_event_store.dart';
import 'package:mobile_agent/application/session_log/session_log_maintenance.dart';
import 'package:mobile_agent/application/session_log/session_log_reader.dart';
import 'package:mobile_agent/application/session_log/session_recorder.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';

ChatMessage _user(String text) =>
    ChatMessage(role: MessageRole.user, parts: [MessagePart.text(text)]);

/// 模拟一次在请求发出后进程被杀的运行：有 turn/start 与 request/sent，没有 turn/end。
Future<void> _killedRun(SessionEventStore store, String conversation,
    String runId) async {
  final recorder = SessionRecorder(
      store: store, conversationId: conversation, runId: runId, model: 'm')
    ..start()
    ..onRequest(1, UnifiedRequest(model: 'm', messages: [_user('hi $runId')]));
  await recorder.flush();
}

Future<void> _completedRun(SessionEventStore store, String conversation,
    String runId) async {
  final recorder = SessionRecorder(
      store: store, conversationId: conversation, runId: runId, model: 'm')
    ..start()
    ..onRequest(1, UnifiedRequest(model: 'm', messages: [_user('ok')]))
    ..observe(const TextEvent('done'))
    ..observe(const AgentStatusEvent(RunStatus.completed));
  await recorder.flush();
}

void main() {
  final later = DateTime.now().add(const Duration(minutes: 20));

  for (final (name, create) in [
    ('in-memory', () async => (InMemorySessionEventStore(), () async {})),
    (
      'drift',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        return (DriftSessionEventStore(db), db.close);
      }
    ),
  ]) {
    group(name, () {
      late SessionEventStore store;
      late Future<void> Function() close;
      setUp(() async => (store, close) = await create());
      tearDown(() => close());

      test('lists only runs without turn/end', () async {
        await _killedRun(store, 'c1', 'r-killed');
        await _completedRun(store, 'c1', 'r-done');
        await _killedRun(store, 'c2', 'r-other');

        final unsealed = await store.unsealedRuns();
        expect(
          unsealed.map((r) => '${r.conversationId}/${r.runId}').toSet(),
          {'c1/r-killed', 'c2/r-other'},
        );
        expect(unsealed.first.lastActivity.isAfter(DateTime(2020)), isTrue);
      });

      test('seals stale runs with the last request as their history',
          () async {
        await _killedRun(store, 'c1', 'r-killed');

        expect(await SessionLogMaintenance.sealStaleRuns(store, now: later), 1);

        final events = await store.events('c1');
        final reader = SessionLogReader(events);
        expect(reader.unsealedRuns, isEmpty);
        expect(reader.lastTurnStatus, 'interrupted');
        expect(events.last.runId, 'r-killed');
        expect(events.last.payload['reason'], 'process_ended');
        expect(reader.deriveMessages()!.map((m) => m.text), ['hi r-killed']);
        expect(await store.unsealedRuns(), isEmpty);
      });

      test('leaves recently active runs alone', () async {
        await _killedRun(store, 'c1', 'r-live');
        expect(await SessionLogMaintenance.sealStaleRuns(store), 0);
        expect(await store.unsealedRuns(), hasLength(1));
      });

      test('seals a run that never reached a request with empty refs',
          () async {
        final recorder = SessionRecorder(
            store: store, conversationId: 'c3', runId: 'r0', model: 'm')
          ..start();
        await recorder.flush();

        await SessionLogMaintenance.sealStaleRuns(store, now: later);

        final end = (await store.events('c3')).last;
        expect(end.type, SessionEventType.turnEnd);
        expect(end.refs, isEmpty);
      });
    });
  }

  test('startup maintenance runs once per process and never throws', () async {
    final store = _ThrowingStore();
    var errors = 0;
    await SessionLogMaintenance.runOnStartup(store, onError: (_, __) => errors++);
    await SessionLogMaintenance.runOnStartup(store, onError: (_, __) => errors++);
    expect(errors, 1);
    expect(store.calls, 1);
  });
}

class _ThrowingStore extends InMemorySessionEventStore {
  var calls = 0;

  @override
  Future<List<UnsealedRun>> unsealedRuns() async {
    calls++;
    throw StateError('disk');
  }
}
