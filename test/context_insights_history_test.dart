import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/context_insights_history.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';

void main() {
  RunEvent event({
    required int sequence,
    required String type,
    required Map<String, dynamic> metadata,
  }) =>
      RunEvent(
        eventId: 'event-$sequence',
        runId: 'run-1',
        sequenceNo: sequence,
        type: type,
        status: 'recorded',
        name: type,
        startedAt: DateTime(2026, 1, 1, 12, sequence),
        metadataJson: jsonEncode(metadata),
      );

  test('rebuilds step records from snapshot and usage events', () {
    final records = ContextInsightsHistory.fromEvents([
      event(
        sequence: 1,
        type: 'context_snapshot',
        metadata: {
          'step': 1,
          'startedAt': '2026-01-01T12:00:00.000',
          'snapshot': {
            'usedTokens': 1800,
            'contextWindow': 32000,
            'reservedOutputTokens': 2048,
            'updatedAt': '2026-01-01T12:00:00.000',
            'omittedParts': ['较早对话历史'],
            'truncatedParts': ['工具结果'],
            'parts': [
              {'type': 'system', 'tokens': 300, 'estimated': true},
              {'type': 'user', 'tokens': 1500, 'estimated': true},
            ],
          },
        },
      ),
      event(
        sequence: 2,
        type: 'context_usage',
        metadata: {
          'step': 1,
          'promptTokens': 1900,
          'completionTokens': 120,
          'cachedTokens': 800,
          'cacheWriteTokens': 0,
          'reasoningTokens': 10,
          'usageReported': true,
          'cacheStatsReported': true,
        },
      ),
      event(
        sequence: 3,
        type: 'context_usage',
        metadata: {'step': 99},
      ),
    ]);

    expect(records, hasLength(1));
    expect(records.single.step, 1);
    expect(records.single.snapshot.usedTokens, 1800);
    expect(records.single.snapshot.parts, hasLength(2));
    expect(records.single.snapshot.omittedParts, ['较早对话历史']);
    expect(records.single.snapshot.truncatedParts, ['工具结果']);
    expect(records.single.usage?.promptTokens, 1900);
    expect(records.single.usage?.cacheStatsReported, isTrue);
    expect(records.single.anchorMessageId, isNull);
  });

  test('restores an optional message anchor', () {
    final records = ContextInsightsHistory.fromEvents([
      event(
        sequence: 1,
        type: 'context_snapshot',
        metadata: {
          'step': 1,
          'anchorMessageId': 'message-42',
          'startedAt': '2026-01-01T12:00:00.000',
          'snapshot': {
            'usedTokens': 10,
            'contextWindow': 100,
            'updatedAt': '2026-01-01T12:00:00.000',
            'parts': [
              {'type': 'user', 'tokens': 10, 'estimated': true},
            ],
          },
        },
      ),
    ]);

    expect(records.single.anchorMessageId, 'message-42');
  });

  test('ignores malformed telemetry events', () {
    final malformed = RunEvent(
      eventId: 'bad',
      runId: 'run-1',
      sequenceNo: 1,
      type: 'context_snapshot',
      status: 'recorded',
      name: 'bad',
      startedAt: DateTime(2026),
      metadataJson: '{bad-json',
    );
    expect(ContextInsightsHistory.fromEvents([malformed]), isEmpty);
  });

  test('applies usage when it arrives before the matching snapshot', () {
    final records = ContextInsightsHistory.fromEvents([
      event(
        sequence: 1,
        type: 'context_usage',
        metadata: {
          'step': 1,
          'promptTokens': 1900,
          'completionTokens': 120,
          'usageReported': true,
        },
      ),
      event(
        sequence: 2,
        type: 'context_snapshot',
        metadata: {
          'step': 1,
          'startedAt': '2026-01-01T12:00:00.000',
          'snapshot': {
            'usedTokens': 1800,
            'contextWindow': 32000,
            'reservedOutputTokens': 2048,
            'updatedAt': '2026-01-01T12:00:00.000',
            'parts': [
              {'type': 'user', 'tokens': 1800, 'estimated': true},
            ],
          },
        },
      ),
    ]);

    expect(records, hasLength(1));
    expect(records.single.usage?.promptTokens, 1900);
    expect(records.single.usage?.completionTokens, 120);
  });

  test('falls back to the newest older run that has a snapshot', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final older = DateTime(2026, 1, 1, 12);
    final newer = older.add(const Duration(minutes: 1));

    await db.insertRunRecord(RunRecordsCompanion.insert(
      runId: 'run-new',
      conversationId: 'conversation-1',
      status: const Value('success'),
      startedAt: newer,
    ));
    await db.insertRunRecord(RunRecordsCompanion.insert(
      runId: 'run-old-with-snapshot',
      conversationId: 'conversation-1',
      status: const Value('success'),
      startedAt: older,
    ));
    await db.insertRunEvent(RunEventsCompanion.insert(
      eventId: 'snapshot-old',
      runId: 'run-old-with-snapshot',
      sequenceNo: 1,
      type: 'context_snapshot',
      status: 'recorded',
      name: '上下文快照',
      startedAt: older,
      metadataJson: Value(jsonEncode({
        'step': 1,
        'startedAt': older.toIso8601String(),
        'snapshot': {
          'usedTokens': 1800,
          'contextWindow': 32000,
          'reservedOutputTokens': 2048,
          'updatedAt': older.toIso8601String(),
          'parts': [
            {'type': 'user', 'tokens': 1800, 'estimated': true},
          ],
        },
      })),
    ));

    final records = await ContextInsightsHistory.latestForConversation(
      db,
      'conversation-1',
    );

    expect(records, hasLength(1));
    expect(records.single.snapshot.usedTokens, 1800);
  });

  test('keeps budget warnings in history without a snapshot', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final startedAt = DateTime(2026, 1, 1, 12);

    await db.insertRunRecord(RunRecordsCompanion.insert(
      runId: 'run-budget',
      conversationId: 'conversation-budget',
      status: const Value('success'),
      startedAt: startedAt,
    ));
    await db.insertRunEvent(RunEventsCompanion.insert(
      eventId: 'budget-event',
      runId: 'run-budget',
      sequenceNo: 1,
      type: 'context_budget',
      status: 'critical',
      name: '上下文预算需要处理',
      startedAt: startedAt,
      metadataJson: Value(jsonEncode({
        'level': 'critical',
        'usedTokens': 980,
        'contextWindow': 1000,
        'remainingTokens': 20,
      })),
    ));

    final histories = await ContextInsightsHistory.recentForConversation(
      db,
      'conversation-budget',
    );

    expect(histories, hasLength(1));
    expect(histories.single.steps, isEmpty);
    expect(histories.single.events.single.type, 'context_budget');
    expect(histories.single.events.single.metadata['level'], 'critical');
  });
}
