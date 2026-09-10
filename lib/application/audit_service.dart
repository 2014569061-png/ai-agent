import 'package:drift/drift.dart' show Value;
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../infrastructure/database/app_database.dart';
import '../infrastructure/observability/unified_diff.dart';
import 'log_service.dart';
import 'sensitive_tool_policy.dart';

/// 审计日志服务（G2）。默认关闭（隐私优先），开启后记录工具调用/审批/导出/同步等决策链路。
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
  }) async {
    if (!await isEnabled()) return;
    try {
      await db.insertAuditLog(AuditLogsCompanion.insert(
        id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
        conversationId: Value(conversationId),
        type: toSafeLogToken(type),
        detail: _redactDetail(detail),
        decision: Value(decision == null ? null : toSafeLogToken(decision)),
        risk: Value(risk == null ? null : toSafeLogToken(risk)),
        createdAt: DateTime.now(),
      ));
    } catch (_) {
      // 审计写入失败不阻断主流程。
    }
  }

  String _redactDetail(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        final tool = map['tool']?.toString();
        if (tool != null && SensitiveToolPolicy.isSensitive(tool)) {
          for (final key in const [
            'arguments',
            'argument',
            'result',
            'output',
            'data',
            'content',
            'text',
            'path',
          ]) {
            if (map.containsKey(key)) map[key] = '[REDACTED]';
          }
          return jsonEncode(map);
        }
      }
    } catch (_) {
      // 普通文本不是 JSON，继续走通用凭证脱敏。
    }
    return redactSensitiveText(value);
  }

  /// 清理超过保留期的日志（90 天）。
  Future<void> prune(AppDatabase db) async {
    await db.pruneAuditLogs(
        DateTime.now().subtract(const Duration(days: _retentionDays)));
  }
}

final auditServiceProvider = Provider<AuditService>((ref) => AuditService());
