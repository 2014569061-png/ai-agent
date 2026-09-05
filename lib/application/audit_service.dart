import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../infrastructure/database/app_database.dart';

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
        type: type,
        detail: detail,
        decision: Value(decision),
        risk: Value(risk),
        createdAt: DateTime.now(),
      ));
    } catch (_) {
      // 审计写入失败不阻断主流程。
    }
  }

  /// 清理超过保留期的日志（90 天）。
  Future<void> prune(AppDatabase db) async {
    await db.pruneAuditLogs(
        DateTime.now().subtract(const Duration(days: _retentionDays)));
  }
}

final auditServiceProvider = Provider<AuditService>((ref) => AuditService());
