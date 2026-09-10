import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../infrastructure/database/app_database.dart';
import '../infrastructure/observability/unified_diff.dart';
import 'sensitive_tool_policy.dart';
import 'providers.dart';

/// 将外部名称压缩为可安全落日志的 token。日志不应携带 prompt、路径、命令
/// 或远端返回的任意长字符串；无法证明安全时统一使用 unknown。
String toSafeLogToken(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text.length > 64) return 'unknown';
  return RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(text) ? text : 'unknown';
}

/// User-facing diagnostic log service. Writes are best effort and never fail
/// the active model/tool/file operation.
class LogService {
  LogService(this._database);

  final Future<AppDatabase> _database;
  Future<void> _pending = Future<void>.value();
  static const _debugKey = 'diagnostic_debug_logging';
  static const _debugExpiryKey = 'diagnostic_debug_logging_expiry';
  static const _maxMessageLength = 2000;
  static const _maxDetailLength = 8000;
  static const _maxLogsPerRun = 2000;

  /// Waits for all queued diagnostic writes. Normal callers should not need
  /// this; a run coordinator can use it before reading/exporting the final
  /// run snapshot.
  Future<void> flush() => _pending;

  Future<bool> debugEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_debugKey) ?? false;
    final expiry = prefs.getInt(_debugExpiryKey) ?? 0;
    if (enabled &&
        expiry > 0 &&
        expiry <= DateTime.now().millisecondsSinceEpoch) {
      await prefs.setBool(_debugKey, false);
      await prefs.remove(_debugExpiryKey);
      return false;
    }
    return enabled;
  }

  Future<void> setDebugEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_debugKey, value);
    if (value) {
      await prefs.setInt(_debugExpiryKey,
          DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch);
    } else {
      await prefs.remove(_debugExpiryKey);
    }
  }

  Future<void> info(String message,
          {String? runId,
          String? eventId,
          String category = 'system',
          Map<String, dynamic>? detail}) =>
      _write(
          level: 'info',
          message: message,
          runId: runId,
          eventId: eventId,
          category: category,
          detail: detail);

  Future<void> debug(String message,
          {String? runId,
          String? eventId,
          String category = 'system',
          Map<String, dynamic>? detail}) =>
      _write(
          level: 'debug',
          message: message,
          runId: runId,
          eventId: eventId,
          category: category,
          detail: detail);

  Future<void> warning(String message,
          {String? runId,
          String? eventId,
          String category = 'system',
          Map<String, dynamic>? detail}) =>
      _write(
          level: 'warning',
          message: message,
          runId: runId,
          eventId: eventId,
          category: category,
          detail: detail);

  Future<void> error(String message,
          {Object? error,
          StackTrace? stackTrace,
          String? runId,
          String? eventId,
          String category = 'system',
          String? errorCode,
          bool retryable = false,
          Map<String, dynamic>? detail}) =>
      _write(
          level: 'error',
          message: message,
          runId: runId,
          eventId: eventId,
          category: category,
          errorCode: errorCode,
          retryable: retryable,
          stackTrace: stackTrace?.toString(),
          detail: {
            ...?detail,
            if (error != null) 'error': error.toString(),
          });

  Future<void> _write({
    required String level,
    required String message,
    required String? runId,
    required String? eventId,
    required String category,
    Map<String, dynamic>? detail,
    String? errorCode,
    String? stackTrace,
    bool retryable = false,
  }) {
    _pending = _pending.then((_) async {
      try {
        if (level == 'debug' && !await debugEnabled()) return;
        final db = await _database;
        final now = DateTime.now();
        final detailJson = detail == null || detail.isEmpty
            ? null
            : _truncate(jsonEncode(_sanitize(detail)), _maxDetailLength);
        await db.insertLogRecord(LogRecordsCompanion.insert(
          logId: 'log-${now.microsecondsSinceEpoch}',
          runId: Value(runId == null ? null : toSafeLogToken(runId)),
          eventId: Value(eventId == null ? null : toSafeLogToken(eventId)),
          level: level,
          category: toSafeLogToken(category),
          message: _truncate(redactSensitiveText(message), _maxMessageLength),
          detailJson: Value(detailJson),
          errorCode:
              Value(errorCode == null ? null : toSafeLogToken(errorCode)),
          stackTrace: Value(stackTrace == null
              ? null
              : _truncate(redactSensitiveText(stackTrace), _maxDetailLength)),
          createdAt: now,
          retryable: Value(retryable),
        ));
        await db.pruneLogRecords(now.subtract(const Duration(days: 30)));
        if (runId != null) await db.pruneRunLogs(runId, max: _maxLogsPerRun);
      } catch (_) {
        // Diagnostics must not affect the conversation or tool execution.
      }
    });
    // Deliberately return immediately; [flush] is the explicit durability
    // boundary used after a run completes.
    return Future<void>.value();
  }

  dynamic _sanitize(dynamic value) {
    if (value is String) return redactSensitiveText(value);
    if (value is Map) {
      final toolName = value['tool']?.toString();
      final sensitiveTool =
          toolName != null && SensitiveToolPolicy.isSensitive(toolName);
      return value.map((key, item) {
        final compact = '$key'.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
        final sensitive = [
          'apikey',
          'authorization',
          'cookie',
          'password',
          'secret',
          'token'
        ].contains(compact);
        final forbidden = [
          'path',
          'filepath',
          'newpath',
          'command',
          'stdout',
          'stderr',
          'arguments',
          'prompt',
        ].contains(compact);
        final sensitivePayload = [
          'result',
          'output',
          'data',
          'content',
          'text',
          'path',
          'newpath',
        ].contains(compact);
        return MapEntry(
            '$key',
            sensitiveTool && (forbidden || sensitivePayload)
                ? '[REDACTED]'
                : sensitive && item is String
                    ? '[REDACTED]'
                    : forbidden
                        ? '[OMITTED]'
                        : _sanitize(item));
      });
    }
    if (value is Iterable) return value.map(_sanitize).toList(growable: false);
    return value;
  }

  String _truncate(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max)}…';
}

final logServiceProvider = Provider<LogService>(
    (ref) => LogService(ref.watch(databaseProvider.future)));
