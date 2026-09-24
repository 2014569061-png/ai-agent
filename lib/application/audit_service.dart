import 'package:drift/drift.dart' show Value;
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/tool_codes.dart';
import '../domain/unique_id.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/observability/unified_diff.dart';
import 'log_service.dart';
import 'nexus_guard.dart';

/// 审计告警的落点。签名与 [NexusGuard.degrade] 的 logger 契约一致，
/// 既可以直接传 `LogService.warning`，也便于测试注入探针。
typedef AuditLogger = void Function(
  String message, {
  Map<String, dynamic>? detail,
});

/// 审计日志服务（G2）。普通诊断审计默认关闭（隐私优先），安全事件始终留痕。
class AuditService {
  AuditService({AuditLogger? logger}) : _logger = logger;

  /// 可选注入的诊断日志。审计写入失败必须留下痕迹，但本应用隐私优先、崩溃上报
  /// 是用户可选开关，只往 Sentry 报可能对所有人不可见；有本地诊断日志才能让
  /// 「审计没写成」这件事真的被看见。测试与一次性构造可以传 null。
  final AuditLogger? _logger;

  static const _prefsKeyEnabled = 'audit_enabled';
  static const _retentionDays = 90;

  /// [NexusGuard.degrade] 要求必须提供 logger；未注入时退化为只上报。
  static void _noopLogger(String message, {Map<String, dynamic>? detail}) {}

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
    // 审计写入失败仍然不阻断主流程（既定语义不变），但不再被无声吞掉：
    // 审计页读的就是这张表，静默丢记录会让它少报已经授予过的权限，而
    // 「审计日志少记」恰恰是审计日志最不能有的失效方式——表面上一切正常。
    // 经 NexusGuard 记一条结构化 warning 并上报，控制流保持原样。
    await NexusGuard.degradeAsync<bool>(
      'audit.write',
      () async {
        if (!force && !await isEnabled()) return false;
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
        return true;
      },
      logger: _logger ?? _noopLogger,
    );
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

  /// Android 设备调用需要保留原始请求和实际目标供本机审计页复查。
  ///
  /// 这里故意不走通用 JSON 脱敏器，但只接受明确定义的字段；文件写入内容、
  /// 任意工具参数以及完整设备返回数据都不会进入审计记录。
  ///
  /// 记录分为三段，便于复查“模型想做什么”和“设备实际执行了什么”：
  /// * `intent`：模型发起的工具调用（工具名、action、目标、参数）；
  /// * `execution`：原生侧按白名单实际执行的命令/API 流程、风险等级、
  ///   是否可撤销与恢复方案；预览、拒绝或校验失败时 `executed=false`；
  /// * `timing`：开始、结束时间与耗时。
  /// 顶层 `operation`/`target`/`parameters` 保留以兼容旧记录与导出格式。
  Future<void> logAndroidDeviceOperation(
    AppDatabase db, {
    required String userRequest,
    required Map<String, dynamic> arguments,
    required bool resultOk,
    required String resultCode,
    required String resultEffect,
    String risk = 'requiresConfirmation',
    bool previewOnly = false,
    String? conversationId,
    String toolName = 'android_device',
    Map<String, dynamic>? execution,
    DateTime? startedAt,
    DateTime? completedAt,
    String intentSource = 'model_tool_call',
  }) async {
    final action = arguments['action'];
    final preview = previewOnly || arguments['preview'] == true;
    final status = resultCode == ToolCodes.approvalRejected
        ? 'approval_rejected'
        : preview
            ? (resultOk ? 'preview' : 'preview_failed')
            : resultOk
                ? 'succeeded'
                : 'failed';
    final operation =
        action is String ? _boundedAuditText(action, 100) : 'unknown';
    final target = _deviceAuditArguments(arguments, _deviceAuditTargetKeys);
    final parameters =
        _deviceAuditArguments(arguments, _deviceAuditParameterKeys);
    final finishedAt = completedAt ?? DateTime.now();
    final executed = status == 'succeeded' || status == 'failed';
    final detail = jsonEncode({
      'userRequest': _boundedAuditText(userRequest, 2000),
      'operation': operation,
      'target': target,
      'parameters': parameters,
      'preview': preview,
      'intent': {
        'source': _boundedAuditText(intentSource, 60),
        'tool': _boundedAuditText(toolName, 100),
        'operation': operation,
        'target': target,
        'parameters': parameters,
      },
      'execution': {
        'executed': executed,
        ..._deviceAuditExecution(execution),
      },
      'timing': {
        if (startedAt != null) 'startedAt': startedAt.toIso8601String(),
        'completedAt': finishedAt.toIso8601String(),
        if (startedAt != null)
          'durationMs': finishedAt.difference(startedAt).inMilliseconds,
      },
      'result': {
        'status': status,
        'ok': resultOk,
        'code': _boundedAuditText(resultCode, 100),
        'effect': _boundedAuditText(resultEffect, 40),
      },
    });

    await NexusGuard.degradeAsync<bool>(
      'audit.androidDeviceOperation.write',
      () async {
        final now = DateTime.now();
        await db.insertAuditLog(AuditLogsCompanion.insert(
          id: UniqueId.generate('audit', now: now),
          conversationId: Value(conversationId),
          type: 'android_device_operation',
          detail: detail,
          decision: Value(status),
          risk: Value(risk),
          createdAt: now,
        ));
        return true;
      },
      logger: _logger ?? _noopLogger,
    );
  }

  /// 设备自动化规则生命周期（创建、启用/暂停、删除、触发后执行/放弃）。
  ///
  /// 与诊断审计开关无关，始终记录；规则里含 Root 动作时风险记为 dangerous，
  /// 便于在审计页筛出“Root 定时任务”的全部变更与执行。
  Future<void> logDeviceAutomationEvent(
    AppDatabase db, {
    required String event,
    required String ruleId,
    required String ruleName,
    required String trigger,
    required List<String> actions,
    required bool requiresRoot,
    bool irreversible = false,
    String? userRequest,
  }) async {
    final detail = jsonEncode({
      'event': _boundedAuditText(event, 60),
      'ruleId': _boundedAuditText(ruleId, 100),
      'ruleName': _boundedAuditText(ruleName, 100),
      'trigger': _boundedAuditText(trigger, 200),
      'actions': actions
          .take(10)
          .map((action) => _boundedAuditText(action, 200))
          .toList(),
      'requiresRoot': requiresRoot,
      'irreversible': irreversible,
      if (userRequest != null)
        'userRequest': _boundedAuditText(userRequest, 2000),
    });
    await NexusGuard.degradeAsync<bool>(
      'audit.deviceAutomation.write',
      () async {
        final now = DateTime.now();
        await db.insertAuditLog(AuditLogsCompanion.insert(
          id: UniqueId.generate('audit', now: now),
          type: 'device_automation',
          detail: detail,
          decision: Value(toSafeLogToken(event)),
          risk: Value(requiresRoot ? 'dangerous' : 'requiresConfirmation'),
          createdAt: now,
        ));
        return true;
      },
      logger: _logger ?? _noopLogger,
    );
  }

  static const _deviceAuditTargetKeys = <String>{
    'query',
    'packageName',
    'appName',
    'uri',
    'uris',
    'destinationUri',
    'newName',
    'deepLink',
    'path',
    'source',
    'sources',
    'destination',
    'archive',
    'host',
    'port',
    'protocol',
    'domain',
    'pid',
    'processName',
    'serviceName',
    'category',
    'scope',
    'backupId',
    'ruleId',
    'extension',
    'modifiedAfterMs',
    'modifiedBeforeMs',
  };

  static const _deviceAuditParameterKeys = <String>{
    'value',
    'stream',
    'enabled',
    'alias',
    'lines',
    'operation',
  };

  static const _deviceAuditExecutionKeys = <String>{
    'mode',
    'bridgeMethod',
    'command',
    'executionPlan',
    'riskClass',
    'reversible',
    'rollback',
    'reason',
  };

  /// 只保留执行描述里的白名单字段；命令文本来自原生白名单模板，
  /// 写入内容在进入这里之前已被替换为长度占位符。
  Map<String, Object?> _deviceAuditExecution(Map<String, dynamic>? execution) {
    if (execution == null) return const {'mode': 'unrecorded'};
    final selected = <String, Object?>{};
    for (final key in _deviceAuditExecutionKeys) {
      final value = execution[key];
      if (value is String) {
        selected[key] = _boundedAuditText(value, 1000);
      } else if (value is bool || value is num) {
        selected[key] = value;
      }
    }
    return selected;
  }

  Map<String, Object?> _deviceAuditArguments(
    Map<String, dynamic> arguments,
    Set<String> allowedKeys,
  ) {
    final selected = <String, Object?>{};
    for (final key in allowedKeys) {
      if (!arguments.containsKey(key)) continue;
      final value = _boundedDeviceAuditValue(arguments[key]);
      if (value != null) selected[key] = value;
    }
    return selected;
  }

  Object? _boundedDeviceAuditValue(Object? value) {
    if (value is String) return _boundedAuditText(value, 512);
    if (value is num || value is bool) return value;
    if (value is List) {
      return value
          .take(25)
          .map(_boundedDeviceAuditValue)
          .where((item) => item != null)
          .toList(growable: false);
    }
    return null;
  }

  String _boundedAuditText(String value, int maxLength) {
    final redacted = redactSensitiveText(value);
    return redacted.length <= maxLength
        ? redacted
        : '${redacted.substring(0, maxLength)}…';
  }

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

final auditServiceProvider = Provider<AuditService>(
    (ref) => AuditService(logger: ref.watch(logServiceProvider).warning));
