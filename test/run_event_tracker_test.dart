import 'dart:convert';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/run_audit_report.dart';
import 'package:mobile_agent/application/run_event_tracker.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('persists real duration and updates status on finish', () async {
    final tracker = RunEventTracker(database: db, runId: 'run-1');
    final handle = await tracker.start(
        type: 'tool_call', name: 'slow-tool', metadata: {'token': 'secret'});
    expect(handle, isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await tracker.finish(handle, status: 'success', outputSummary: 'ok');
    await tracker.flush();

    final events = await db.eventsForRun('run-1');
    expect(events, hasLength(1));
    expect(events.single.status, 'success');
    expect(events.single.durationMs, greaterThanOrEqualTo(0));
    expect(events.single.outputSummary, 'ok');
    expect(events.single.metadataJson, contains('[REDACTED]'));
  });

  test('sequence numbers increase monotonically', () async {
    final tracker = RunEventTracker(database: db, runId: 'run-2');
    await tracker.record(type: 'model_request', name: 'one');
    await tracker.record(type: 'network', name: 'two');
    await tracker.flush();
    final events = await db.eventsForRun('run-2');
    expect(events.map((event) => event.sequenceNo), [1, 2]);
  });

  test('tool audit metadata keeps effect, code, path and evidence together',
      () async {
    final tracker = RunEventTracker(database: db, runId: 'run-audit');
    // read_file 既不属参数敏感也不属结果敏感，其审计元数据（effect/code/path/
    // evidence）应原样保留。write_file/edit_file 因参数可能含密钥已被纳入参数
    // 脱敏名单，其 path 会按策略被隐藏，不适合再作本用例的夹具。
    final handle = await tracker.start(
      type: 'file_operation',
      name: 'read_file',
      inputSummary: '{"path":"lib/main.dart"}',
    );
    await tracker.finish(
      handle,
      status: 'success',
      outputSummary: '文件内容已读取',
      metadata: {
        'effect': 'applied',
        'toolCode': 'OK',
        'path': 'lib/main.dart',
        'evidence': 'size 10→12',
      },
    );
    await tracker.flush();

    final event = (await db.eventsForRun('run-audit')).single;
    expect(event.status, 'success');
    expect(event.outputSummary, '文件内容已读取');
    expect(event.metadataJson, contains('"effect":"applied"'));
    expect(event.metadataJson, contains('"toolCode":"OK"'));
    expect(event.metadataJson, contains('"path":"lib/main.dart"'));
    expect(event.metadataJson, contains('"evidence":"size 10→12"'));
  });

  test('audit JSON keeps effect, code and unknown display evidence', () async {
    final now = DateTime(2026, 9, 6, 12);
    await db.insertRunEvent(RunEventsCompanion.insert(
      eventId: 'event-unknown',
      runId: 'run-audit-json',
      sequenceNo: 1,
      type: 'file_operation',
      status: 'failed',
      name: 'delete_file',
      startedAt: now,
      outputSummary: const Value('OUTCOME_UNKNOWN: 可能已执行，请先确认'),
      metadataJson: const Value(
          '{"effect":"unknown","toolCode":"OUTCOME_UNKNOWN","message":"可能已执行，请先确认"}'),
    ));

    final report =
        RunAuditReport.fromEvents(await db.eventsForRun('run-audit-json'));
    final encoded = jsonDecode(report.encode()) as Map<String, dynamic>;
    final entry = (encoded['entries'] as List).single as Map<String, dynamic>;
    expect(entry['effect'], 'unknown');
    expect(entry['code'], 'OUTCOME_UNKNOWN');
    expect(entry['evidence'], contains('确认'));
  });

  test('log queries filter by level, category, keyword and time range',
      () async {
    final day = DateTime(2026, 9, 6);
    await db.insertLogRecord(LogRecordsCompanion.insert(
      logId: 'log-1',
      runId: const Value('run-logs'),
      level: 'error',
      category: 'network',
      message: 'request timeout',
      createdAt: day.add(const Duration(hours: 2)),
    ));
    await db.insertLogRecord(LogRecordsCompanion.insert(
      logId: 'log-2',
      runId: const Value('run-logs'),
      level: 'info',
      category: 'tool',
      message: 'tool completed',
      createdAt: day.add(const Duration(hours: 3)),
    ));

    final filtered = await db.recentLogRecords(
      runId: 'run-logs',
      level: 'error',
      category: 'network',
      keyword: 'timeout',
      from: day,
      to: day.add(const Duration(days: 1)),
    );
    expect(filtered.map((log) => log.logId), ['log-1']);
  });

  test('prunes old completed runs but keeps active runs', () async {
    final now = DateTime(2026, 9, 6, 12);
    await db.insertRunRecord(RunRecordsCompanion.insert(
      runId: 'old',
      conversationId: 'c',
      status: const Value('success'),
      startedAt: now.subtract(const Duration(days: 31)),
    ));
    await db.insertRunRecord(RunRecordsCompanion.insert(
      runId: 'active',
      conversationId: 'c',
      status: const Value('running'),
      startedAt: now.subtract(const Duration(days: 90)),
    ));
    await db.insertRunEvent(RunEventsCompanion.insert(
      eventId: 'old-event',
      runId: 'old',
      sequenceNo: 1,
      type: 'tool_call',
      status: 'success',
      name: 'old',
      startedAt: now.subtract(const Duration(days: 31)),
    ));
    await db.pruneRunRecords(now: now);

    expect(await db.findRunRecord('old'), isNull);
    expect(await db.findRunRecord('active'), isNotNull);
    expect(await db.eventsForRun('old'), isEmpty);
  });
}
