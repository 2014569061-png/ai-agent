import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../infrastructure/database/app_database.dart';
import '../infrastructure/observability/unified_diff.dart';
import 'sensitive_tool_policy.dart';

/// Persists a run event as a started row and later completes it with the
/// measured duration. Database failures are intentionally swallowed so
/// observability never changes the user's task result.
class RunEventTracker {
  RunEventTracker(
      {required this.database, required this.runId, this.nextSequence = 0});

  final AppDatabase database;
  final String runId;
  int nextSequence;
  Future<void> _pending = Future<void>.value();

  /// Serializes writes without making the streaming loop wait for SQLite.
  /// Callers can await [flush] at the end of a run when a durable snapshot is
  /// required (for example before uploading events).
  void _enqueue(Future<void> Function() operation) {
    _pending = _pending.then((_) async {
      try {
        await operation();
      } catch (_) {
        // Observability is best effort and must never fail the run.
      }
    });
  }

  Future<void> flush() => _pending;

  Future<RunEventHandle?> start({
    required String type,
    required String name,
    String? inputSummary,
    Map<String, dynamic>? metadata,
  }) async {
    final startedAt = DateTime.now();
    final handle = RunEventHandle(
      eventId: 'event-${startedAt.microsecondsSinceEpoch}-${nextSequence + 1}',
      sequenceNo: ++nextSequence,
      startedAt: startedAt,
      sensitive: SensitiveToolPolicy.isSensitive(name),
    );
    _enqueue(() => database.insertRunEvent(RunEventsCompanion.insert(
          eventId: handle.eventId,
          runId: runId,
          sequenceNo: handle.sequenceNo,
          type: type,
          status: 'started',
          name: name,
          startedAt: startedAt,
          inputSummary: Value(_summary(inputSummary, handle.sensitive)),
          metadataJson:
              Value(_encodeMetadata(metadata, sensitive: handle.sensitive)),
        )));
    return handle;
  }

  Future<void> finish(
    RunEventHandle? handle, {
    String status = 'success',
    String? outputSummary,
    Map<String, dynamic>? metadata,
  }) async {
    if (handle == null) return;
    final endedAt = DateTime.now();
    final duration = endedAt.difference(handle.startedAt).inMilliseconds;
    _enqueue(() => database.updateRunEvent(
          handle.eventId,
          RunEventsCompanion(
            status: Value(status),
            endedAt: Value(endedAt),
            durationMs: Value(duration < 0 ? 0 : duration),
            outputSummary: Value(_summary(outputSummary, handle.sensitive)),
            metadataJson: metadata == null
                ? const Value.absent()
                : Value(_encodeMetadata(metadata, sensitive: handle.sensitive)),
          ),
        ));
  }

  Future<RunEventHandle?> record({
    required String type,
    required String name,
    String status = 'success',
    String? inputSummary,
    String? outputSummary,
    Map<String, dynamic>? metadata,
  }) async {
    final handle = await start(
      type: type,
      name: name,
      inputSummary: inputSummary,
      metadata: metadata,
    );
    await finish(handle,
        status: status, outputSummary: outputSummary, metadata: metadata);
    return handle;
  }

  static String? _limit(String? value) {
    if (value == null) return null;
    if (value.length <= 2000) return value;
    return '${value.substring(0, 2000)}…';
  }

  static String? _summary(String? value, bool sensitive) {
    if (value == null) return null;
    if (sensitive) return '[敏感工具内容已脱敏]';
    return _limit(redactSensitiveText(value));
  }

  static String _encodeMetadata(Map<String, dynamic>? metadata,
      {bool sensitive = false}) {
    if (metadata == null || metadata.isEmpty) return '{}';
    final sanitized = _sanitize(metadata, sensitive: sensitive);
    final encoded = jsonEncode(sanitized);
    if (encoded.length <= 8000) return encoded;
    return jsonEncode({
      'truncated': true,
      'summary': redactSensitiveText(encoded.substring(0, 7800)),
    });
  }

  static dynamic _sanitize(dynamic value, {bool sensitive = false}) {
    if (value is String) {
      return sensitive
          ? '[REDACTED]'
          : redactSensitiveText(_limit(value) ?? '');
    }
    if (value is Map) {
      return value.map((key, item) {
        final normalizedKey = '$key'.toLowerCase();
        final compactKey = normalizedKey.replaceAll(RegExp(r'[^a-z]'), '');
        final keySensitive = compactKey.contains('apikey') ||
            compactKey.contains('authorization') ||
            compactKey == 'cookie' ||
            compactKey == 'password' ||
            compactKey == 'secret' ||
            compactKey == 'token';
        final sensitiveValue = sensitive &&
            const {
              'argument',
              'arguments',
              'input',
              'output',
              'result',
              'data',
              'content',
              'path',
              'text',
              'command',
              'stdout',
              'stderr',
            }.contains(compactKey);
        return MapEntry(
            '$key',
            (keySensitive && item is String)
                ? '[REDACTED]'
                : sensitiveValue
                    ? '[REDACTED]'
                    : _sanitize(item));
      });
    }
    if (value is Iterable) {
      return value
          .map((item) => _sanitize(item, sensitive: sensitive))
          .toList(growable: false);
    }
    return value;
  }
}

class RunEventHandle {
  const RunEventHandle({
    required this.eventId,
    required this.sequenceNo,
    required this.startedAt,
    this.sensitive = false,
  });

  final String eventId;
  final int sequenceNo;
  final DateTime startedAt;
  final bool sensitive;
}
