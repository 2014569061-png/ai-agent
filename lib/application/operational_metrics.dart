import 'dart:convert';
import 'package:drift/drift.dart';
import '../infrastructure/database/app_database.dart';
import 'run_event_tracker.dart';

class ReferenceSlo {
  ReferenceSlo(
      {required this.p95Ms, required this.successRate, this.minSamples = 20}) {
    if (p95Ms < 1 ||
        !successRate.isFinite ||
        successRate < 0 ||
        successRate > 1 ||
        minSamples < 20) {
      throw ArgumentError('Invalid reference target');
    }
  }
  final int p95Ms, minSamples;
  final double successRate;
  Map<String, Object> toJson() =>
      {'p95Ms': p95Ms, 'successRate': successRate, 'minSamples': minSamples};
}

/// Numeric/identifier-only report. This is NOT an APK/device attestation.
class OperationalMetrics {
  static const observedTypes = [
    'model_attempt',
    'tool_call',
    'file_operation',
    'telemetry_health',
    'model_request'
  ];
  static int? percentile(Iterable<int> values, double percentile) {
    final sorted = values.toList()..sort();
    if (sorted.isEmpty) return null;
    if (!percentile.isFinite || percentile <= 0 || percentile > 1) {
      throw ArgumentError.value(percentile);
    }
    return sorted[(sorted.length * percentile).ceil() - 1];
  }

  static Future<Map<String, dynamic>> load(
    AppDatabase database, {
    required String environment,
    required DateTime since,
    DateTime? until,
    ReferenceSlo? target,
    int limit = 5000,
  }) async {
    if (limit < 1 || limit > 5000) throw ArgumentError.value(limit);
    final end = until ?? DateTime.now();
    final rows = await (database.select(database.runEvents)
          ..where((r) =>
              r.startedAt.isBiggerOrEqualValue(since) &
              r.startedAt.isSmallerOrEqualValue(end) &
              r.type.isIn(observedTypes))
          ..orderBy([
            (r) => OrderingTerm.desc(r.startedAt),
            (r) => OrderingTerm.desc(r.sequenceNo)
          ])
          ..limit(limit + 1))
        .get();
    return summarize(rows.take(limit),
        environment: environment,
        since: since,
        until: end,
        target: target,
        truncated: rows.length > limit,
        processHealth: RunEventTracker.processHealthFor(environment));
  }

  static Map<String, dynamic> summarize(
    Iterable<RunEvent> events, {
    required String environment,
    required DateTime since,
    required DateTime until,
    ReferenceSlo? target,
    bool truncated = false,
    Map<String, int> processHealth = const {},
  }) {
    if (!{'debug', 'profile', 'release', 'fixture'}.contains(environment) ||
        until.isBefore(since)) {
      throw ArgumentError('Invalid metrics scope');
    }
    final groups = {
      for (final name in [
        'model_inference',
        'model_summary',
        'model_other',
        'tool_end_to_end'
      ])
        name: _Group()
    };
    final storedHealth = <String, Map<String, int>>{};
    final spans = <Map<String, dynamic>>[];
    var unclassified = 0,
        otherEnvironment = 0,
        malformed = 0,
        missingParents = 0,
        missingRequests = 0,
        legacySummaries = 0;
    final selected = <({RunEvent row, Map<String, dynamic> meta})>[];
    for (final row in events) {
      if (!observedTypes.contains(row.type) ||
          row.startedAt.isBefore(since) ||
          row.startedAt.isAfter(until)) {
        continue;
      }
      Map<String, dynamic> meta;
      try {
        meta = Map<String, dynamic>.from(jsonDecode(row.metadataJson) as Map);
      } catch (_) {
        malformed++;
        continue;
      }
      if (meta['traceSchema'] != 1 ||
          !{'debug', 'profile', 'release', 'fixture'}
              .contains(meta['environment'])) {
        unclassified++;
        continue;
      }
      if (meta['environment'] != environment) {
        otherEnvironment++;
        continue;
      }
      selected.add((row: row, meta: meta));
    }
    final modelIds = {
      for (final entry in selected.where((e) => e.row.type == 'model_attempt'))
        entry.row.eventId: entry.row.runId
    };
    for (final entry in selected) {
      final row = entry.row, meta = entry.meta;
      if (row.type == 'model_request') {
        legacySummaries++;
        continue;
      }
      if (row.type == 'telemetry_health') {
        final stats = storedHealth.putIfAbsent(row.runId, () => {});
        for (final key in ['writeFailures', 'droppedWrites', 'metadataDrops']) {
          final n = meta[key];
          if (n is int && n >= 0) {
            if (n > (stats[key] ?? 0)) stats[key] = n;
          } else {
            malformed++;
          }
        }
        continue;
      }
      if (meta['traceId'] != row.runId || meta['spanId'] != row.eventId) {
        malformed++;
        continue;
      }
      final tool = row.type != 'model_attempt';
      if (tool &&
          (meta['parentSpanId'] is! String ||
              modelIds[meta['parentSpanId']] != row.runId)) {
        missingParents++;
      }
      if (meta['logicalRequestId'] is! String ||
          (meta['logicalRequestId'] as String).isEmpty) {
        missingRequests++;
      }
      final purpose = meta['purpose'];
      final group = groups[tool
          ? 'tool_end_to_end'
          : purpose == 'summary'
              ? 'model_summary'
              : purpose == 'inference'
                  ? 'model_inference'
                  : 'model_other']!;
      final status =
          group.add(row, meta, tool: tool, synthetic: environment == 'fixture');
      if (spans.length < 100) {
        spans.add({
          'runId': row.runId,
          'spanId': row.eventId,
          'parentSpanId': _id(meta['parentSpanId']),
          'logicalRequestId': _id(meta['logicalRequestId']),
          'type': row.type,
          'status': status,
          'startedAt': row.startedAt.toUtc().toIso8601String(),
          'durationMs': row.durationMs,
        });
      }
    }
    final persisted = {
      for (final key in ['writeFailures', 'droppedWrites', 'metadataDrops'])
        key: storedHealth.values.fold<int>(0, (sum, m) => sum + (m[key] ?? 0))
    };
    final degraded = truncated ||
        malformed > 0 ||
        unclassified > 0 ||
        missingParents > 0 ||
        missingRequests > 0 ||
        groups.values.any((g) => g.unknown > 0 || g.invalidTiming > 0) ||
        persisted.values.any((n) => n > 0) ||
        processHealth.values.any((n) => n > 0);
    return {
      'schemaVersion': 1,
      'notReleaseSignOff': true,
      'deviceEvidence': 'unverified',
      'environment': environment,
      'fixtureOnly': environment == 'fixture',
      'since': since.toUtc().toIso8601String(),
      'until': until.toUtc().toIso8601String(),
      'scope':
          'observed_persisted_runs_only_excludes_unpersisted_headless_and_drafts',
      'target': target?.toJson(),
      'truncated': truncated,
      'unclassifiedEvents': unclassified,
      'otherEnvironmentExcluded': otherEnvironment,
      'malformedEvents': malformed,
      'legacySummaryRowsExcluded': legacySummaries,
      'missingLogicalRequestIds': missingRequests,
      'missingModelParents': missingParents,
      'dataQualityDegraded': degraded,
      'persistedHealth': persisted,
      'processHealth': Map<String, int>.from(processHealth),
      'processHealthScope':
          'current_process_not_time_windowed_not_additive_with_persisted',
      'groups': {
        for (final entry in groups.entries)
          entry.key: entry.value.toJson(
              target: target,
              degraded: degraded,
              fixture: environment == 'fixture')
      },
      'spans': spans,
      'spanPreviewLimit': 100,
      'definitions': {
        'duration':
            'subscription_to_stream_end_including_backpressure_or_tool_end_to_end_including_approval',
        'firstToken':
            'first_nonempty_text_or_reasoning_event_not_network_first_byte',
        'successRate':
            'successful_attempts_over_all_observed_attempts_including_cancellation_and_unknown_not_business_success',
        'coverage':
            'observed_only_storage_loss_across_restart_cannot_be_proven_complete',
        'percentile': 'nearest_rank_missing_values_excluded_not_zero',
        'timeWindow': 'span_start_time_cohort',
      },
    };
  }

  static String? _id(dynamic value) => value is String ? value : null;
}

class _Group {
  int total = 0,
      success = 0,
      failed = 0,
      cancelled = 0,
      unknown = 0,
      invalidTiming = 0;
  final durations = <int>[], firstTokens = <int>[], firstTexts = <int>[];
  final failures = <String, int>{};
  String add(RunEvent row, Map<String, dynamic> meta,
      {required bool tool, required bool synthetic}) {
    total++;
    var status = row.status;
    if (row.endedAt == null ||
        !{'success', 'failed', 'cancelled'}.contains(status) ||
        meta['effect'] == 'unknown' ||
        meta['businessCompleted'] == false) {
      status = 'unknown';
    }
    switch (status) {
      case 'success':
        success++;
      case 'failed':
        failed++;
      case 'cancelled':
        cancelled++;
      default:
        unknown++;
    }
    final duration = row.durationMs;
    if (row.endedAt != null &&
        duration != null &&
        duration >= 0 &&
        (meta['timingSource'] == 'stopwatch' ||
            synthetic && meta['timingSource'] == 'synthetic')) {
      durations.add(duration);
      for (final (key, list) in [
        ('firstTokenMs', firstTokens),
        ('firstTextMs', firstTexts)
      ]) {
        final value = meta[key];
        if (value is int && value >= 0 && value <= duration) {
          list.add(value);
        } else if (value != null) {
          invalidTiming++;
        }
      }
    } else {
      invalidTiming++;
    }
    if (status != 'success') {
      final raw = meta['failureCategory'];
      const allowed = {
        'authentication',
        'billing',
        'COST_BUDGET_EXHAUSTED',
        'COST_PRICING_UNAVAILABLE',
        'quota',
        'permanent',
        'transient',
        'cancelled',
        'timeout',
        'provider_exception',
        'stream_incomplete',
        'protocol',
        'context_length',
        'unknown'
      };
      final category = raw is String && allowed.contains(raw)
          ? raw
          : status == 'cancelled'
              ? 'cancelled'
              : tool
                  ? 'tool_failed_or_unverified'
                  : 'unknown';
      failures[category] = (failures[category] ?? 0) + 1;
    }
    return status;
  }

  Map<String, dynamic> toJson(
      {required ReferenceSlo? target,
      required bool degraded,
      required bool fixture}) {
    final p95 = OperationalMetrics.percentile(durations, .95);
    final rate = total == 0 ? null : success / total;
    final assessment = fixture
        ? 'fixture_only'
        : target == null
            ? 'target_not_configured'
            : degraded || unknown > 0 || invalidTiming > 0
                ? 'data_quality_degraded'
                : total < target.minSamples ||
                        durations.length < target.minSamples
                    ? 'insufficient_samples'
                    : rate! >= target.successRate && p95! <= target.p95Ms
                        ? 'meets_reference_target'
                        : 'breach';
    return {
      'total': total,
      'success': success,
      'failed': failed,
      'cancelled': cancelled,
      'unknown': unknown,
      'successRate': rate,
      'durationSamples': durations.length,
      'invalidOrMissingTiming': invalidTiming,
      'p50Ms': OperationalMetrics.percentile(durations, .5),
      'p95Ms': p95,
      'firstTokenSamples': firstTokens.length,
      'firstTokenP95Ms': OperationalMetrics.percentile(firstTokens, .95),
      'firstTextSamples': firstTexts.length,
      'firstTextP95Ms': OperationalMetrics.percentile(firstTexts, .95),
      'failureCategories': failures,
      'assessment': assessment
    };
  }
}
