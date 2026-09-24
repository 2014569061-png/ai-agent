import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../domain/tool_codes.dart';
import '../domain/tool_result.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/tools/android_device_tool.dart';
import '../infrastructure/tools/tool_registry.dart';
import 'audit_service.dart';
import 'providers.dart';

/// 一项已生成预览、等待用户确认的设备动作。
class PreparedDeviceAction {
  PreparedDeviceAction({
    required this.description,
    required this.arguments,
    this.planId,
    this.preview,
    this.error,
    this.extra = const {},
  }) : preparedAt = DateTime.now();

  final String description;

  /// 交给 android_device 的参数（不含 planId/previewId）。
  final Map<String, dynamic> arguments;
  final String? planId;
  final Map<String, dynamic>? preview;

  /// 预览失败原因（参数无效、目录为空等）；有值时该项不会执行。
  final String? error;

  /// 附加展示信息，例如批量删除的文件清单摘要。
  final Map<String, dynamic> extra;
  final DateTime preparedAt;

  bool get executable => planId != null && error == null;

  /// android_device 的执行计划两分钟过期；留 10 秒余量。
  bool get expired =>
      DateTime.now().difference(preparedAt) > const Duration(seconds: 110);

  String get riskClass => preview?['riskClass']?.toString() ?? 'unknown';
  bool get reversible => preview?['reversible'] != false;
}

class DeviceActionOutcome {
  const DeviceActionOutcome({
    required this.prepared,
    required this.result,
    required this.startedAt,
    required this.completedAt,
  });

  final PreparedDeviceAction prepared;
  final ToolResult result;
  final DateTime startedAt;
  final DateTime completedAt;
}

/// 前台“预览 → 用户确认 → 一次性票据 → 执行 → 审计”的统一入口。
///
/// 自动化确认、撤销和备份页面都走这里，保证与 Agent 调用 android_device
/// 时相同的白名单、预览账本和审计格式，不另开旁路。
class DeviceActionRunner {
  DeviceActionRunner({
    AndroidDeviceTool? tool,
    AuditService? audit,
    Future<AppDatabase> Function()? database,
  })  : _tool = tool ?? AndroidDeviceTool(),
        _audit = audit ?? AuditService(),
        _database = database;

  final AndroidDeviceTool _tool;
  final AuditService _audit;
  final Future<AppDatabase> Function()? _database;

  AndroidDeviceTool get tool => _tool;

  Future<PreparedDeviceAction> prepare(
    String description,
    Map<String, dynamic> arguments, {
    Map<String, dynamic> extra = const {},
  }) async {
    final clean = Map<String, dynamic>.from(arguments)
      ..remove('preview')
      ..remove('planId')
      ..remove('previewId');
    if (!_tool.requiresPreviewPlan(clean)) {
      return PreparedDeviceAction(
        description: description,
        arguments: clean,
        error: '该动作不是设备变更，无需确认执行',
        extra: extra,
      );
    }
    final result = await _tool.preview(clean);
    final data = result.data;
    if (!result.ok || data == null || data['planId'] is! String) {
      return PreparedDeviceAction(
        description: description,
        arguments: clean,
        error: result.message,
        extra: extra,
      );
    }
    return PreparedDeviceAction(
      description: description,
      arguments: clean,
      planId: data['planId'] as String,
      preview: Map<String, dynamic>.from(data)..remove('planId'),
      extra: extra,
    );
  }

  /// 用户确认后执行。每项单独签发票据、单独审计；前一项失败不影响后续项。
  Future<List<DeviceActionOutcome>> executeConfirmed(
    List<PreparedDeviceAction> actions, {
    required String userRequest,
    String toolName = 'android_device',
    String intentSource = 'user_confirmed_ui',
    Future<void> Function(PreparedDeviceAction action)? beforeEach,
  }) async {
    final outcomes = <DeviceActionOutcome>[];
    for (final action in actions) {
      final startedAt = DateTime.now();
      ToolResult result;
      if (!action.executable) {
        result = ToolResult.failure(
          code: ToolCodes.invalidArguments,
          message: action.error ?? '该项没有有效预览，未执行',
        );
      } else if (action.expired) {
        _tool.rejectApproval({...action.arguments, 'planId': action.planId});
        result = ToolResult.failure(
          code: ToolCodes.sessionExpired,
          message: '预览已超过 2 分钟有效期，未执行；请重新生成预览',
        );
      } else {
        try {
          await beforeEach?.call(action);
          final authorized = _tool.authorizeAfterApproval({
            ...action.arguments,
            'planId': action.planId,
          });
          result = await _tool.execute(authorized);
        } on ToolApprovalAuthorizationException catch (error) {
          result = ToolResult.failure(
            code: ToolCodes.invalidArguments,
            message: error.message,
          );
        } catch (error) {
          result = ToolResult.failure(
            code: ToolCodes.toolError,
            message: '执行异常：$error；副作用无法确认，请检查设备状态',
            effect: ToolEffect.unknown,
          );
        }
      }
      final completedAt = DateTime.now();
      outcomes.add(DeviceActionOutcome(
        prepared: action,
        result: result,
        startedAt: startedAt,
        completedAt: completedAt,
      ));
      await _auditOutcome(
        action.arguments,
        result,
        userRequest: userRequest,
        toolName: toolName,
        intentSource: intentSource,
        startedAt: startedAt,
        completedAt: completedAt,
      );
    }
    return outcomes;
  }

  /// 用户放弃执行：作废预览计划并留下审计记录。
  Future<void> reject(
    List<PreparedDeviceAction> actions, {
    required String userRequest,
    String toolName = 'android_device',
    String intentSource = 'user_confirmed_ui',
  }) async {
    for (final action in actions) {
      if (action.planId != null) {
        _tool.rejectApproval({...action.arguments, 'planId': action.planId});
      }
      await _auditOutcome(
        action.arguments,
        ToolResult.failure(
          code: ToolCodes.approvalRejected,
          message: '用户未确认执行',
        ),
        userRequest: userRequest,
        toolName: toolName,
        intentSource: intentSource,
      );
    }
  }

  Future<void> _auditOutcome(
    Map<String, dynamic> arguments,
    ToolResult result, {
    required String userRequest,
    required String toolName,
    required String intentSource,
    DateTime? startedAt,
    DateTime? completedAt,
  }) async {
    final database = _database;
    if (database == null) return;
    try {
      final db = await database();
      await _audit.logAndroidDeviceOperation(
        db,
        userRequest: userRequest,
        arguments: arguments,
        resultOk: result.ok,
        resultCode: result.code,
        resultEffect: result.effect.name,
        risk: _tool.riskForArguments(arguments).name,
        toolName: toolName,
        execution: AndroidDeviceTool.auditExecutionFor(arguments),
        startedAt: startedAt,
        completedAt: completedAt,
        intentSource: intentSource,
      );
    } catch (_) {
      // 审计服务内部已通过 NexusGuard 记录写入失败；这里不阻断执行结果返回。
    }
  }

  ToolRisk riskFor(Map<String, dynamic> arguments) =>
      _tool.riskForArguments(arguments);
}

final deviceActionRunnerProvider = Provider<DeviceActionRunner>((ref) {
  return DeviceActionRunner(
    audit: ref.watch(auditServiceProvider),
    database: () => ref.read(databaseProvider.future),
  );
});
