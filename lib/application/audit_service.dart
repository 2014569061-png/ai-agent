import 'package:drift/drift.dart' show Value;
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/unique_id.dart';
import '../infrastructure/database/app_database.dart';
import 'log_service.dart';

/// 审计日志服务（G2）。普通诊断审计默认关闭（隐私优先），安全事件始终留痕。
class AuditService {
  static const _prefsKeyEnabled = 'audit_enabled';
  static const _retentionDays = 90;

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyEnabled) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyEnabled, enabled);
  }

  Future<void> log(
    AppDatabase db, {
    required String type,
    required String detail,
    String? decision,
    String? risk,
    String? conversationId,
    bool force = false,
  }) async {
    if (!force && !await isEnabled()) return;
    try {
      final now = DateTime.now();
      await db.insertAuditLog(AuditLogsCompanion.insert(
        id: UniqueId.generate('audit', now: now),
        conversationId: Value(conversationId),
        type: toSafeLogToken(type),
        detail: _redactDetail(detail),
        decision: Value(decision == null ? null : toSafeLogToken(decision)),
        risk: Value(risk == null ? null : toSafeLogToken(risk)),
        createdAt: now,
      ));
    } catch (_) {
      // 审计写入失败不阻断主流程。
    }
  }

  /// 安全事件（例如审批授予/拒绝）不依赖用户的诊断日志开关。
  Future<void> logSecurityEvent(
    AppDatabase db, {
    required String type,
    required String detail,
    String? decision,
    String? risk,
    String? conversationId,
  }) =>
      log(
        db,
        type: type,
        detail: detail,
        decision: decision,
        risk: risk,
        conversationId: conversationId,
        force: true,
      );

  String _redactDetail(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        final safe = <String, dynamic>{};
        for (final entry in decoded.entries) {
          final key = entry.key.toString();
          safe[key] = _safeAuditFields.contains(key.toLowerCase())
              ? _safeAuditValue(entry.value)
              : '[REDACTED]';
        }
        return jsonEncode(safe);
      }
      if (decoded is List) return '[REDACTED]';
    } catch (_) {
      // 普通文本不是 JSON，继续走通用凭证脱敏。
    }
    final token = toSafeLogToken(value);
    return token == 'unknown' ? '[REDACTED]' : token;
  }

  static const _safeAuditFields = {
    'tool',
    'operation',
    'effect',
    'code',
    'toolcode',
    'decision',
    'risk',
  };

  Object _safeAuditValue(Object? value) {
    if (value is bool) return value;
    if (value is num) return value;
    final token = toSafeLogToken(value);
    return token == 'unknown' ? '[REDACTED]' : token;
  }

  /// 清理超过保留期的日志（90 天）。
  Future<void> prune(AppDatabase db) async {
    await db.pruneAuditLogs(
        DateTime.now().subtract(const Duration(days: _retentionDays)));
  }
}

final auditServiceProvider = Provider<AuditService>((ref) => AuditService());
