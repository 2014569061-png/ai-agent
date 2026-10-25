import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/operational_metrics.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';

final at = DateTime.utc(2026, 10, 20, 12);
RunEvent sample(int i,
    {String type = 'model_attempt',
    String status = 'success',
    String environment = 'debug',
    int? duration = 100,
    int sequence = 1,
    Map<String, dynamic> extra = const {}}) {
  final id = '$type-$i-$sequence';
  return RunEvent(
      eventId: id,
      runId: 'run-$i',
      sequenceNo: sequence,
      type: type,
      status: status,
      name: 'fixture',
      startedAt: at,
      endedAt: status == 'started'
          ? null
          : at.add(Duration(milliseconds: duration ?? 1)),
      durationMs: duration,
      inputSummary: 'SECRET-input',
      outputSummary: 'SECRET-output',
      metadataJson: jsonEncode({
        'traceSchema': 1,
        'traceId': 'run-$i',
        'spanId': id,
        'environment': environment,
        'logicalRequestId': 'request-$i',
        'parentSpanId': type == 'tool_call' || type == 'file_operation'
            ? 'model_attempt-$i-1'
            : null,
        'purpose': 'inference',
        'timingSource': 'stopwatch',
        'firstTokenMs': duration != null && duration >= 5 ? 5 : null,
        'firstTextMs': duration != null && duration >= 10 ? 10 : null,
        ...extra,
      }));
}

Map<String, dynamic> report(Iterable<RunEvent> events,
        {String environment = 'debug',
        bool target = true,
        bool truncated = false,
        Map<String, int> processHealth = const {}}) =>
    OperationalMetrics.summarize(events,
        environment: environment,
        since: at.subtract(const Duration(hours: 1)),
        until: at.add(const Duration(hours: 1)),
        target: target ? ReferenceSlo(p95Ms: 1000, successRate: .99) : null,
        truncated: truncated,
        processHealth: processHealth);
Map<String, dynamic> group(Map<String, dynamic> report,
        [String name = 'model_inference']) =>
    (report['groups'] as Map)[name] as Map<String, dynamic>;
void main() {
  test('nearest-rank P50/P95; absent is null not zero', () {
    expect(OperationalMetrics.percentile([], .95), null);
    expect(
        OperationalMetrics.percentile(List.generate(20, (i) => i + 1), .5), 10);
    expect(OperationalMetrics.percentile(List.generate(20, (i) => i + 1), .95),
        19);
    expect(() => OperationalMetrics.percentile([1], 0), throwsArgumentError);
  });
  test('no samples cannot pass or show zero latency/rate', () {
    final g = group(report([]));
    expect(g['assessment'], 'insufficient_samples');
    expect(g['p95Ms'], null);
    expect(g['successRate'], null);
  });
  test('reference targets must be explicit', () {
    expect(
        group(report(List.generate(20, (i) => sample(i)), target: false))[
            'assessment'],
        'target_not_configured');
  });
  test('20 complete observed samples may meet only a local reference', () {
    final r = report(List.generate(20, (i) => sample(i, duration: i + 1)));
    expect(group(r)['assessment'], 'meets_reference_target');
    expect(group(r)['p95Ms'], 19);
    expect(r['notReleaseSignOff'], true);
    expect(r['deviceEvidence'], 'unverified');
  });
  test('19 samples are not enough', () {
    expect(group(report(List.generate(19, (i) => sample(i))))['assessment'],
        'insufficient_samples');
  });
  test('measured zero remains different from absent timings', () {
    final g = group(report(List.generate(20, (i) => sample(i, duration: 0))));
    expect(g['p95Ms'], 0);
    expect(g['durationSamples'], 20);
    expect(g['firstTokenP95Ms'], null);
    expect(g['firstTokenSamples'], 0);
  });
  test('missing duration is excluded and cannot pass', () {
    final g = group(report(
        List.generate(20, (i) => sample(i, duration: i == 0 ? null : 100))));
    expect(g['durationSamples'], 19);
    expect(g['invalidOrMissingTiming'], 1);
    expect(g['assessment'], 'data_quality_degraded');
  });
  test('started/incomplete span stays unknown and in the denominator', () {
    final r = report([
      ...List.generate(19, (i) => sample(i)),
      sample(20, status: 'started', duration: null)
    ]);
    expect(group(r)['unknown'], 1);
    expect(group(r)['successRate'], .95);
    expect(r['dataQualityDegraded'], true);
    expect(group(r)['assessment'], 'data_quality_degraded');
  });
  test('cancellation is separate but included in attempt denominator', () {
    final g = group(report([
      ...List.generate(19, (i) => sample(i)),
      sample(20, status: 'cancelled')
    ]));
    expect(g['cancelled'], 1);
    expect(g['successRate'], .95);
    expect(g['assessment'], 'breach');
  });
  test('inference and summary latency do not mix', () {
    final r = report([
      sample(0, duration: 40),
      sample(1, duration: 900, extra: {'purpose': 'summary'})
    ]);
    expect(group(r)['total'], 1);
    expect(group(r)['p95Ms'], 40);
    expect(group(r, 'model_summary')['total'], 1);
    expect(group(r, 'model_summary')['p95Ms'], 900);
  });
  test('environment data cannot leak into the selected sample', () {
    final r = report([
      sample(0),
      sample(1, environment: 'release'),
      sample(2, environment: 'fixture')
    ]);
    expect(group(r)['total'], 1);
    expect(r['otherEnvironmentExcluded'], 2);
  });
  test('fixtures never receive a performance pass', () {
    final r = report(
        List.generate(
            20,
            (i) => sample(i,
                environment: 'fixture', extra: {'timingSource': 'synthetic'})),
        environment: 'fixture');
    expect(group(r)['assessment'], 'fixture_only');
    expect(r['fixtureOnly'], true);
  });
  test('synthetic timing cannot masquerade as debug runtime timing', () {
    expect(
        group(report(List.generate(
                20, (i) => sample(i, extra: {'timingSource': 'synthetic'}))))[
            'assessment'],
        'data_quality_degraded');
  });
  test('legacy model summary rows are excluded, never double counted', () {
    final r = report([
      ...List.generate(20, (i) => sample(i)),
      sample(30, type: 'model_request')
    ]);
    expect(group(r)['total'], 20);
    expect(r['legacySummaryRowsExcluded'], 1);
  });
  test('unclassified legacy records block a confident assessment', () {
    final r = report([
      ...List.generate(20, (i) => sample(i)),
      sample(30, type: 'model_request', extra: {'traceSchema': null})
    ]);
    expect(r['unclassifiedEvents'], 1);
    expect(group(r)['assessment'], 'data_quality_degraded');
  });
  test('missing logical request correlation cannot pass', () {
    final r = report(
        List.generate(20, (i) => sample(i, extra: {'logicalRequestId': null})));
    expect(r['missingLogicalRequestIds'], 20);
    expect(group(r)['assessment'], 'data_quality_degraded');
  });
  test('tool end-to-end measurements require visible same-run model parents',
      () {
    final r =
        report([sample(0), sample(0, type: 'file_operation', duration: 200)]);
    expect(r['missingModelParents'], 0);
    expect(group(r, 'tool_end_to_end')['p95Ms'], 200);
    final missing =
        report(List.generate(20, (i) => sample(i, type: 'tool_call')));
    expect(missing['missingModelParents'], 20);
    expect(group(missing, 'tool_end_to_end')['assessment'],
        'data_quality_degraded');
  });
  test('handoff or unknown tool effect is not counted as business completion',
      () {
    final r = report([
      sample(0),
      sample(0, type: 'tool_call', extra: {'businessCompleted': false})
    ]);
    expect(group(r, 'tool_end_to_end')['unknown'], 1);
  });
  test('persisted health snapshots use per-run maximum, not additive snapshots',
      () {
    final r = report([
      ...List.generate(20, (i) => sample(i)),
      sample(0,
          type: 'telemetry_health',
          sequence: 2,
          extra: {'writeFailures': 0, 'droppedWrites': 1, 'metadataDrops': 0}),
      sample(0,
          type: 'telemetry_health',
          sequence: 3,
          extra: {'writeFailures': 0, 'droppedWrites': 2, 'metadataDrops': 0})
    ]);
    expect((r['persistedHealth'] as Map)['droppedWrites'], 2);
    expect(group(r)['assessment'], 'data_quality_degraded');
  });
  test('unpersisted process loss and truncated query both block passing', () {
    final events = List.generate(20, (i) => sample(i));
    expect(
        group(
            report(events, processHealth: {'writeFailures': 1}))['assessment'],
        'data_quality_degraded');
    expect(group(report(events, truncated: true))['assessment'],
        'data_quality_degraded');
  });
  test('export whitelists categories and omits body, metadata and prompts', () {
    final r = report([
      sample(0, status: 'failed', extra: {
        'failureCategory': 'SECRET-raw-error',
        'arguments': 'SECRET-args',
        'url': 'SECRET-url'
      })
    ]);
    expect(jsonEncode(r), isNot(contains('SECRET')));
    expect((group(r)['failureCategories'] as Map)['unknown'], 1);
  });
  test('span preview is bounded independently of numeric aggregation', () {
    final r = report(List.generate(101, (i) => sample(i)));
    expect((r['spans'] as List).length, 100);
    expect(group(r)['total'], 101);
  });
  test('a reference target cannot bypass the 20 sample floor', () {
    expect(() => ReferenceSlo(p95Ms: 100, successRate: 1, minSamples: 1),
        throwsArgumentError);
    expect(() => ReferenceSlo(p95Ms: 0, successRate: 1), throwsArgumentError);
  });
  test('database query enforces limit+1 and reports truncation', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    for (var i = 0; i < 3; i++) {
      final r = sample(i);
      await db.insertRunEvent(RunEventsCompanion.insert(
          eventId: r.eventId,
          runId: r.runId,
          sequenceNo: r.sequenceNo,
          type: r.type,
          status: r.status,
          name: r.name,
          startedAt: r.startedAt,
          endedAt: Value(r.endedAt),
          durationMs: Value(r.durationMs),
          metadataJson: Value(r.metadataJson)));
    }
    final r = await OperationalMetrics.load(db,
        environment: 'debug',
        since: at.subtract(const Duration(hours: 1)),
        until: at.add(const Duration(hours: 1)),
        limit: 2);
    expect(r['truncated'], true);
    expect(group(r)['total'], 2);
  });
}
