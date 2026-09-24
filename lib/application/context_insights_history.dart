import 'dart:convert';

import '../domain/context_insights.dart';
import '../domain/models.dart';
import '../infrastructure/database/app_database.dart';

/// Restores context telemetry from RunEvents without requiring a schema change.
///
/// Older runs simply return an empty list because they do not contain the two
/// telemetry event types introduced for the context workspace.
class ContextInsightsHistory {
  const ContextInsightsHistory._();

  static Future<List<ContextStepRecord>> latestForConversation(
    AppDatabase database,
    String conversationId,
  ) async {
    // 最新运行可能来自旧版本，没有上下文遥测；向前查找最近仍有快照的
    // 运行，而不是让一次升级后切会话永远显示空上下文。
    final runs = await database.runsForConversation(conversationId, limit: 20);
    for (final run in runs) {
      final events = await database.contextEventsForRun(run.runId);
      final steps = fromEvents(events);
      if (steps.isNotEmpty) return steps;
    }
    return const [];
  }

  static Future<List<ContextRunHistory>> recentForConversation(
    AppDatabase database,
    String conversationId, {
    int limit = 12,
  }) async {
    final runs =
        await database.runsForConversation(conversationId, limit: limit);
    final histories = <ContextRunHistory>[];
    for (final run in runs) {
      // 历史面板还需要工具/文件/网络审计事件；过滤查询只用于切会话时
      // 恢复最新上下文快照。
      final events = await database.eventsForRun(run.runId, limit: 2000);
      final steps = fromEvents(events);
      if (steps.isEmpty && !_hasRelevantEvents(events)) continue;
      histories.add(ContextRunHistory(
        runId: run.runId,
        startedAt: run.startedAt,
        status: run.status,
        steps: steps,
        events: _auditEvents(events),
      ));
    }
    return List.unmodifiable(histories);
  }

  static List<ContextStepRecord> fromEvents(List<RunEvent> events) {
    final records = <int, ContextStepRecord>{};
    final pendingUsage = <int, Usage>{};
    for (final event in events) {
      final metadata = _decode(event.metadataJson);
      if (metadata == null) continue;
      if (event.type == 'context_snapshot') {
        final record = _snapshotRecord(metadata);
        if (record != null) {
          final usage = pendingUsage.remove(record.step);
          records[record.step] =
              usage == null ? record : record.withUsage(usage);
        }
      } else if (event.type == 'context_usage') {
        final step = _asInt(metadata['step']);
        if (step <= 0) continue;
        final usage = _usage(metadata);
        final current = records[step];
        if (current == null) {
          pendingUsage[step] = usage;
        } else {
          records[step] = current.withUsage(usage);
        }
      }
    }
    final output = records.values.toList()
      ..sort((a, b) => a.step.compareTo(b.step));
    return List.unmodifiable(output);
  }

  static bool _hasRelevantEvents(List<RunEvent> events) => events.any((event) =>
      event.type == 'tool_call' ||
      event.type == 'file_operation' ||
      event.type == 'model_request' ||
      event.type == 'context_inject' ||
      event.type == 'context_prune' ||
      event.type == 'context_compress' ||
      event.type == 'context_budget');

  static List<ContextRunEvent> _auditEvents(List<RunEvent> events) =>
      List.unmodifiable(
        events
            .where((event) =>
                event.type == 'tool_call' ||
                event.type == 'file_operation' ||
                event.type == 'model_request' ||
                event.type == 'context_snapshot' ||
                event.type == 'context_usage' ||
                event.type == 'context_inject' ||
                event.type == 'context_prune' ||
                event.type == 'context_compress' ||
                event.type == 'context_budget')
            .map((event) => ContextRunEvent(
                  type: event.type,
                  name: event.name,
                  status: event.status,
                  createdAt: event.startedAt,
                  metadata: _decode(event.metadataJson) ?? const {},
                ))
            .toList(growable: false),
      );

  static ContextStepRecord? _snapshotRecord(Map<String, dynamic> data) {
    final step = _asInt(data['step']);
    final snapshotData = _map(data['snapshot']);
    if (step <= 0 || snapshotData == null) return null;
    final partValues = snapshotData['parts'];
    if (partValues is! List) return null;
    final parts = <ContextPart>[];
    for (final item in partValues) {
      final part = _map(item);
      if (part == null) continue;
      final type = ContextPartType.values
          .where((value) => value.name == part['type'])
          .firstOrNull;
      if (type == null) continue;
      parts.add(ContextPart(
        type: type,
        tokens: _asInt(part['tokens']),
        estimated: part['estimated'] is! bool || part['estimated'] as bool,
      ));
    }
    final startedAt = DateTime.tryParse(data['startedAt']?.toString() ?? '') ??
        DateTime.now();
    return ContextStepRecord(
      step: step,
      startedAt: startedAt,
      anchorMessageId: data['anchorMessageId']?.toString(),
      snapshot: ContextSnapshot(
        parts: List.unmodifiable(parts),
        usedTokens: _asInt(snapshotData['usedTokens']),
        contextWindow: _asInt(snapshotData['contextWindow']),
        reservedOutputTokens: _asInt(snapshotData['reservedOutputTokens']),
        updatedAt:
            DateTime.tryParse(snapshotData['updatedAt']?.toString() ?? '') ??
                startedAt,
        omittedParts: _asStrings(snapshotData['omittedParts']),
        truncatedParts: _asStrings(snapshotData['truncatedParts']),
      ),
    );
  }

  static Usage _usage(Map<String, dynamic> data) => Usage(
        promptTokens: _asInt(data['promptTokens']),
        completionTokens: _asInt(data['completionTokens']),
        cachedTokens: _asInt(data['cachedTokens']),
        cacheWriteTokens: _asInt(data['cacheWriteTokens']),
        reasoningTokens: _asInt(data['reasoningTokens']),
        usageReported: data['usageReported'] == true,
        cacheStatsReported: data['cacheStatsReported'] == true,
      );

  static Map<String, dynamic>? _decode(String value) {
    try {
      return _map(jsonDecode(value));
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _map(Object? value) => value is Map
      ? value.map((key, item) => MapEntry(key.toString(), item))
      : null;

  static int _asInt(Object? value) => switch (value) {
        int value => value,
        num value => value.round(),
        String value => int.tryParse(value) ?? 0,
        _ => 0,
      };

  static List<String> _asStrings(Object? value) => value is List
      ? List.unmodifiable(
          value.whereType<String>().where((item) => item.trim().isNotEmpty))
      : const [];
}
