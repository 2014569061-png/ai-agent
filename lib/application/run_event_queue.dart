import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'billing_api.dart';

class RunEventQueue {
  static const _key = 'pending_run_event_uploads';
  static const maxItems = 20;
  static const maxAttempts = 8;
  Future<void>? _flushInFlight;

  /// Exponential backoff capped at one hour. Kept pure for deterministic tests.
  static Duration backoffForAttempt(int attempt,
      {Duration base = const Duration(seconds: 5),
      Duration max = const Duration(hours: 1)}) {
    final safeAttempt = attempt.clamp(1, 30);
    final multiplier = 1 << (safeAttempt - 1);
    final millis = base.inMilliseconds * multiplier;
    return Duration(
        milliseconds:
            millis > max.inMilliseconds ? max.inMilliseconds : millis);
  }

  Future<RunEventEnqueueResult> enqueue({
    required String runId,
    String? conversationId,
    required List<Map<String, dynamic>> events,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final current = _read(prefs);
    final existing = current.indexWhere((item) => item['runId'] == runId);
    final item = {
      'id': '$runId-${DateTime.now().microsecondsSinceEpoch}',
      'runId': runId,
      'conversationId': conversationId,
      'events': events,
      'attempts': 0,
      'nextAttemptAt': 0,
    };
    if (existing >= 0) {
      current[existing] = item;
    } else {
      current.add(item);
    }
    final droppedRunId =
        current.length > maxItems ? current.first['runId']?.toString() : null;
    final bounded = current.length <= maxItems
        ? current
        : current.sublist(current.length - maxItems);
    await prefs.setStringList(
        _key, bounded.map(jsonEncode).toList(growable: false));
    return RunEventEnqueueResult(
      accepted: true,
      droppedOldest: droppedRunId != null,
      droppedRunId: droppedRunId,
    );
  }

  Future<int> pendingCount() async {
    final prefs = await SharedPreferences.getInstance();
    return _read(prefs).length;
  }

  Future<void> flush({
    required BillingApi api,
    required String access,
    DateTime Function()? clock,
    bool force = false,
  }) {
    final inFlight = _flushInFlight;
    if (inFlight != null) return inFlight;
    final future = _flush(
      api: api,
      access: access,
      clock: clock,
      force: force,
    );
    _flushInFlight = future.whenComplete(() => _flushInFlight = null);
    return _flushInFlight!;
  }

  Future<void> _flush({
    required BillingApi api,
    required String access,
    DateTime Function()? clock,
    bool force = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = (clock ?? DateTime.now)();
    final current = _read(prefs);
    final pending = <Map<String, dynamic>>[];
    for (final item in current) {
      final nextAttemptAt = (item['nextAttemptAt'] as num?)?.toInt() ?? 0;
      if (!force && nextAttemptAt > now.millisecondsSinceEpoch) {
        pending.add(item);
        continue;
      }
      try {
        await api.uploadRunEvents(
          access: access,
          runId: item['runId'] as String,
          conversationId: item['conversationId'] as String?,
          events: List<Map<String, dynamic>>.from(item['events'] as List),
        );
      } catch (_) {
        final attempts = ((item['attempts'] as num?)?.toInt() ?? 0) + 1;
        item['attempts'] = attempts > maxAttempts ? maxAttempts : attempts;
        item['nextAttemptAt'] =
            now.add(backoffForAttempt(attempts)).millisecondsSinceEpoch;
        pending.add(item);
      }
    }
    final bounded = pending.length <= maxItems
        ? pending
        : pending.sublist(pending.length - maxItems);
    await prefs.setStringList(
        _key, bounded.map(jsonEncode).toList(growable: false));
  }

  /// Startup recovery entry point. It is safe to call repeatedly; backoff
  /// prevents a failed server from causing a request storm.
  Future<void> recover({required BillingApi api, required String access}) =>
      flush(api: api, access: access);

  List<Map<String, dynamic>> _read(SharedPreferences prefs) {
    final result = <Map<String, dynamic>>[];
    for (final item in prefs.getStringList(_key) ?? const <String>[]) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map) {
          result.add(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {
        // Drop malformed queue entries instead of blocking future recovery.
      }
    }
    return result;
  }
}

class RunEventEnqueueResult {
  const RunEventEnqueueResult({
    required this.accepted,
    required this.droppedOldest,
    this.droppedRunId,
  });

  final bool accepted;
  final bool droppedOldest;
  final String? droppedRunId;
}
