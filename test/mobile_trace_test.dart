import 'dart:convert';
import 'package:dio/dio.dart' show CancelToken;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/run_event_tracker.dart';
import 'package:mobile_agent/application/traced_model_provider.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/providers/llm_provider.dart';

class TraceFixture implements LlmProvider {
  TraceFixture(this.events, {this.throwAfter = false, this.onDispatch});
  final List<UnifiedEvent> events;
  final bool throwAfter;
  final void Function()? onDispatch;
  int calls = 0;
  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    calls++;
    onDispatch?.call();
    yield* Stream.fromIterable(events);
    if (throwAfter) throw StateError('SECRET-error-body');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late RunEventTracker tracker;
  var closed = false;
  setUp(() {
    closed = false;
    db = AppDatabase(NativeDatabase.memory());
    tracker = RunEventTracker(
        database: db, runId: 'trace-fixture', environment: 'fixture');
  });
  tearDown(() async {
    if (!closed) await db.close();
  });
  final request = UnifiedRequest(
      model: 'fixture',
      costRequestId: 'logical-request',
      messages: [
        ChatMessage(
            role: MessageRole.user,
            parts: const [MessagePart.text('SECRET-prompt')])
      ]);
  Future<List<RunEvent>> rows() async {
    await tracker.flush();
    return db.eventsForRun('trace-fixture');
  }

  test(
      'model attempt links cost identity; no prompt, text or errors are captured',
      () async {
    final raw = TraceFixture([
      const TextDeltaEvent('SECRET-answer'),
      const UsageEvent(promptTokens: 7, completionTokens: 3),
      const CompletedEvent()
    ]);
    await TracedModelProvider(raw, tracker).stream(request).toList();
    final row = (await rows()).single;
    final meta = jsonDecode(row.metadataJson) as Map;
    expect(row.type, 'model_attempt');
    expect(row.status, 'success');
    expect(meta['traceId'], 'trace-fixture');
    expect(meta['spanId'], row.eventId);
    expect(meta['logicalRequestId'], 'logical-request');
    expect(meta['parentSpanId'], null);
    expect(meta['environment'], 'fixture');
    expect(meta['firstTokenMs'], greaterThanOrEqualTo(0));
    expect(meta['reportedPromptTokens'], 7);
    expect(meta['reportedCompletionTokens'], 3);
    expect('${row.inputSummary}${row.outputSummary}${row.metadataJson}',
        isNot(contains('SECRET')));
  });
  test('tool start/finish retains model parent and immutable correlation',
      () async {
    await TracedModelProvider(TraceFixture([const CompletedEvent()]), tracker)
        .stream(request)
        .toList();
    final parent = tracker.currentModelSpanId;
    final h = await tracker.start(
        type: 'tool_call', name: 'fixture_tool', metadata: {'safe': true});
    await tracker.finish(h, metadata: {
      'traceId': 'wrong',
      'spanId': 'wrong',
      'logicalRequestId': 'wrong',
      'toolCode': 'ok'
    });
    final row = (await rows()).singleWhere((r) => r.type == 'tool_call');
    final meta = jsonDecode(row.metadataJson) as Map;
    expect(meta['traceId'], 'trace-fixture');
    expect(meta['spanId'], row.eventId);
    expect(meta['parentSpanId'], parent);
    expect(meta['logicalRequestId'], 'logical-request');
    expect(meta['safe'], true);
    expect(meta['toolCode'], 'ok');
  });
  test('repeated subscriptions have distinct spans and one logical request',
      () async {
    final p =
        TracedModelProvider(TraceFixture([const CompletedEvent()]), tracker);
    await p.stream(request).toList();
    await p.stream(request).toList();
    final result = await rows();
    expect(result.length, 2);
    expect(result.map((r) => r.eventId).toSet().length, 2);
    expect(
        result.every((r) =>
            (jsonDecode(r.metadataJson) as Map)['logicalRequestId'] ==
            'logical-request'),
        true);
  });
  test('a stream without completion is unknown, not successful zero latency',
      () async {
    await TracedModelProvider(TraceFixture([]), tracker)
        .stream(request)
        .toList();
    final row = (await rows()).single;
    final meta = jsonDecode(row.metadataJson) as Map;
    expect(row.status, 'unknown');
    expect(meta['failureCategory'], 'stream_incomplete');
    expect(meta['firstTokenMs'], null);
    expect(meta['firstTextMs'], null);
    expect(meta['reportedPromptTokens'], null);
    expect(meta['usageReported'], false);
  });
  test('consumer interruption stays unknown', () async {
    await TracedModelProvider(
            TraceFixture([const TextDeltaEvent('x'), const CompletedEvent()]),
            tracker)
        .stream(request)
        .take(1)
        .toList();
    expect((await rows()).single.status, 'unknown');
  });
  test('known cancellation is distinct from provider failure', () async {
    final cancel = CancelToken();
    await TracedModelProvider(
            TraceFixture([const CompletedEvent()],
                onDispatch: () => cancel.cancel()),
            tracker)
        .stream(request, cancelToken: cancel)
        .toList();
    expect((await rows()).single.status, 'cancelled');
  });
  test('provider errors are classified without raw bodies', () async {
    await TracedModelProvider(
            TraceFixture([
              const ProviderErrorEvent('SECRET-http-body', statusCode: 401)
            ]),
            tracker)
        .stream(request)
        .toList();
    final row = (await rows()).single;
    expect(row.status, 'failed');
    expect((jsonDecode(row.metadataJson) as Map)['failureCategory'],
        'authentication');
    expect(row.metadataJson, isNot(contains('SECRET')));
  });
  test('thrown failures propagate while telemetry keeps only a category',
      () async {
    await expectLater(
        TracedModelProvider(TraceFixture([], throwAfter: true), tracker)
            .stream(request)
            .toList(),
        throwsStateError);
    final row = (await rows()).single;
    expect(row.status, 'failed');
    expect(row.metadataJson, isNot(contains('SECRET')));
  });
  test('wall clock jumps do not inflate measured duration', () async {
    var at = DateTime.utc(2026, 10, 20);
    tracker = RunEventTracker(
        database: db,
        runId: 'trace-fixture',
        environment: 'fixture',
        now: () => at);
    final h = await tracker.start(type: 'tool_call', name: 'fixture');
    at = DateTime.utc(2036, 10, 20);
    await tracker.finish(h);
    final row = (await rows()).single;
    expect(row.durationMs, lessThan(1000));
    expect((jsonDecode(row.metadataJson) as Map)['timingSource'], 'stopwatch');
  });
  test('bounded queue exposes dropped writes instead of silently hiding gaps',
      () async {
    tracker = RunEventTracker(
        database: db,
        runId: 'trace-fixture',
        environment: 'fixture',
        maxQueuedWrites: 1);
    await Future.wait(List.generate(
        20, (_) => tracker.record(type: 'tool_call', name: 'fixture')));
    await tracker.flush();
    expect(tracker.droppedWrites, greaterThan(0));
    expect(tracker.pendingWrites, 0);
    expect((await rows()).where((r) => r.type == 'telemetry_health').length, 1);
  });
  test(
      'database failure never changes provider output and becomes visible in counters',
      () async {
    await db.customStatement(
        "CREATE TRIGGER fixture_reject_trace BEFORE INSERT ON run_events BEGIN SELECT RAISE(FAIL, 'fixture'); END");
    final result = await TracedModelProvider(
            TraceFixture([const CompletedEvent()]), tracker)
        .stream(request)
        .toList();
    await tracker.flush();
    expect(result.single, isA<CompletedEvent>());
    expect(tracker.writeFailures, greaterThan(0));
    expect(RunEventTracker.processHealthFor('fixture')['writeFailures'],
        greaterThan(0));
  });
  test('unencodable metadata degrades safely and keeps trace identity',
      () async {
    final h = await tracker.start(
        type: 'tool_call',
        name: 'fixture',
        metadata: {'unsupported': Object()});
    await tracker.finish(h);
    final row = (await rows()).singleWhere((r) => r.type == 'tool_call');
    expect((jsonDecode(row.metadataJson) as Map)['traceId'], 'trace-fixture');
    expect(tracker.metadataDrops, greaterThan(0));
  });
  test(
      'started spans remain distinguishable from zero-duration completed spans',
      () async {
    await tracker.start(type: 'tool_call', name: 'fixture');
    final row = (await rows()).single;
    expect(row.status, 'started');
    expect(row.durationMs, null);
    expect(row.endedAt, null);
  });
}
