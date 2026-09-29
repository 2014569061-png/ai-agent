// 阶段 3a：ModuleHost / RunProfile / SessionLogModule。
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/agent_executor.dart';
import 'package:mobile_agent/application/agent_loop/agent_loop_hooks.dart';
import 'package:mobile_agent/application/modules/agent_module.dart';
import 'package:mobile_agent/application/modules/module_host.dart';
import 'package:mobile_agent/application/modules/run_profile.dart';
import 'package:mobile_agent/application/modules/session_log_module.dart';
import 'package:mobile_agent/application/session_log/session_event.dart';
import 'package:mobile_agent/application/session_log/session_event_store.dart';
import 'package:mobile_agent/application/session_log/session_log_reader.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/providers/llm_provider.dart';
import 'package:mobile_agent/infrastructure/tools/tool_registry.dart';

RunScope _scope({
  RunProfile profile = RunProfile.background,
  String? sessionId = 'task:t1',
}) =>
    RunScope(
      profile: profile,
      runId: 'r1',
      model: 'm',
      sessionId: sessionId,
      taskId: 't1',
    );

class _Recording implements AgentModule {
  _Recording(this.id, this.log, {this.applies = true, this.failOn});

  @override
  final String id;
  final List<String> log;
  final bool applies;
  final String? failOn;

  @override
  bool appliesTo(RunScope scope) => applies;

  @override
  ModuleAttachment attach(RunScope scope) {
    if (failOn == 'attach') throw StateError('attach');
    log.add('$id:attach');
    return ModuleAttachment(
      hooks: AgentLoopHooks(requestObservers: [(step, _) => log.add('$id:req$step')]),
      onEvent: (event) {
        if (failOn == 'event') throw StateError('event');
        log.add('$id:${event.runtimeType}');
      },
      onFinish: (outcome) {
        if (failOn == 'finish') throw StateError('finish');
        log.add('$id:finish:${outcome.abortReason ?? 'ok'}');
      },
    );
  }
}

class _TextProvider implements LlmProvider {
  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    yield const TextDeltaEvent('hello');
    yield const CompletedEvent(stopReason: StopReason.endOfTurn);
  }
}

void main() {
  test('profiles encode who is present and what is recorded', () {
    expect(RunProfile.chat.interactive, isTrue);
    for (final p in [
      RunProfile.background,
      RunProfile.scheduled,
      RunProfile.subagent,
      RunProfile.collaboration,
    ]) {
      expect(p.interactive, isFalse, reason: '$p');
    }
    expect(RunProfile.background.recordSession, isTrue);
    expect(RunProfile.subagent.recordSession, isFalse);
    expect(RunScope.taskSessionId('abc'), 'task:abc');
  });

  test('host attaches applicable modules in order and finishes in reverse',
      () async {
    final log = <String>[];
    final session = await ModuleHost([
      _Recording('a', log),
      _Recording('skip', log, applies: false),
      _Recording('b', log),
    ]).open(_scope());

    expect(session.moduleIds, ['a', 'b']);
    for (final observer in session.hooks.requestObservers) {
      observer(1, const UnifiedRequest(model: 'm', messages: []));
    }
    session.observe(const TextEvent('x'));
    await session.finish(const RunOutcome.aborted('boom'));
    await session.finish(const RunOutcome.finished());

    expect(log, [
      'a:attach',
      'b:attach',
      'a:req1',
      'b:req1',
      'a:TextEvent',
      'b:TextEvent',
      'b:finish:boom',
      'a:finish:boom',
    ]);
    expect(session.finished, isTrue);
  });

  test('a failing module is isolated and reported', () async {
    final log = <String>[];
    final errors = <String>[];
    final host = ModuleHost(
      [
        _Recording('bad-attach', log, failOn: 'attach'),
        _Recording('bad-event', log, failOn: 'event'),
        _Recording('bad-finish', log, failOn: 'finish'),
        _Recording('good', log),
      ],
      onError: (id, error, _) => errors.add(id),
    );
    final session = await host.open(_scope());
    session.observe(const TextEvent('x'));
    await session.finish(const RunOutcome.finished());

    expect(session.moduleIds, ['bad-event', 'bad-finish', 'good']);
    expect(errors, ['bad-attach', 'bad-event', 'bad-finish']);
    expect(log, contains('good:TextEvent'));
    expect(log, contains('good:finish:ok'));
    expect(log, contains('bad-event:finish:ok'));
  });

  group('SessionLogModule', () {
    SessionLogModule module(InMemorySessionEventStore store,
            {bool enabled = true}) =>
        SessionLogModule(store: () => store, enabled: enabled);

    test('only attaches when enabled, recordable and scoped', () {
      final store = InMemorySessionEventStore();
      expect(module(store).appliesTo(_scope()), isTrue);
      expect(module(store, enabled: false).appliesTo(_scope()), isFalse);
      expect(module(store).appliesTo(_scope(sessionId: null)), isFalse);
      expect(
          module(store).appliesTo(_scope(profile: RunProfile.subagent)), isFalse);
    });

    test('records a full run through executor hooks', () async {
      final store = InMemorySessionEventStore();
      final session = await ModuleHost([module(store)]).open(_scope());
      await for (final event in AgentExecutor(
        provider: _TextProvider(),
        tools: ToolRegistry(),
        hooks: session.hooks,
      ).run(history: [
        ChatMessage(
            role: MessageRole.user, parts: [const MessagePart.text('hi')]),
      ], model: 'm')) {
        session.observe(event);
      }
      await session.finish(const RunOutcome.finished());

      final events = await store.events('task:t1');
      expect(events.first.type, SessionEventType.turnStart);
      expect(events.last.type, SessionEventType.turnEnd);
      expect(events.last.payload['status'], 'completed');
      final reader = SessionLogReader(events);
      expect(reader.requestsFor('r1'), hasLength(1));
      final derived = reader.deriveMessages()!
          .where((m) => m.role != MessageRole.system)
          .map((m) => '${m.role.name}:${m.text}')
          .toList();
      expect(derived, ['user:hi', 'assistant:hello']);
    });

    test('seals the run as interrupted when the stream ends without status',
        () async {
      final store = InMemorySessionEventStore();
      final session = await ModuleHost([module(store)]).open(_scope());
      await session.finish(const RunOutcome.aborted('unexpected_error'));

      final end = (await store.events('task:t1')).last;
      expect(end.type, SessionEventType.turnEnd);
      expect(end.payload['status'], 'interrupted');
      expect(end.payload['reason'], 'unexpected_error');
    });
  });
}
