import 'package:flutter/services.dart';

import '../domain/device_automation.dart';
import '../domain/models.dart';
import '../domain/tool_codes.dart';
import '../domain/tool_result.dart';
import '../infrastructure/tools/tool_registry.dart';
import 'device_automation_service.dart';

/// 让 Agent 创建/管理“条件触发 → 通知 → 用户确认 → 执行”的设备自动化规则。
///
/// 本工具只管理规则，本身不执行任何设备动作：规则触发后只发通知，动作必须
/// 由用户在前台逐项查看预览并确认后，才经 android_device 的一次性票据执行。
class AndroidAutomationTool implements AgentTool, ToolApprovalGate {
  AndroidAutomationTool({DeviceAutomationService? service})
      : _service = service ?? DeviceAutomationService();

  final DeviceAutomationService _service;

  static const _readActions = {
    'list_rules',
    'rule_history',
    'trigger_status',
    'pending_fires',
  };

  @override
  final manifest = const UnifiedTool(
    name: 'android_automation',
    description: '管理设备自动化规则：定时、连上指定 Wi-Fi、电量低于阈值时触发。'
        '触发后只发送通知，用户点击后逐项预览并确认才执行，永不在后台静默执行。'
        '动作仅限白名单（打开/停止应用、深链、清缓存、Wi-Fi/蓝牙/勿扰/亮度/音量/旋转、'
        '清理已授权目录中的旧文件）；Root 动作与不可撤销动作在创建规则时按危险操作审批。'
        '创建或启用规则前先调用 trigger_status：它同时检查定位/通知权限（识别 Wi-Fi 名称需要定位权限）和 Root/Shizuku 执行通道，'
        '返回的 fallbackPreview 说明哪些动作在当前设备上只能打开系统设置页；把这些限制告诉用户，审批卡片也会列出，只需审批一次。'
        '未先调用 trigger_status 时，缺少执行通道的 create_rule / 启用会返回 requiresAcknowledgement，用户同意后带 acknowledgeFallback=true 重新调用。',
    risk: ToolRisk.requiresConfirmation,
    parametersSchema: {
      'type': 'object',
      'properties': {
        'action': {
          'type': 'string',
          'enum': [
            'list_rules',
            'rule_history',
            'trigger_status',
            'pending_fires',
            'create_rule',
            'set_rule_enabled',
            'delete_rule',
          ],
        },
        'ruleId': {'type': 'string'},
        'enabled': {'type': 'boolean'},
        'acknowledgeFallback': {
          'type': 'boolean',
          'description': '用户已知悉：无 Root/Shizuku 时部分动作触发后只能打开系统设置页由用户手动完成',
        },
        'name': {'type': 'string', 'description': '规则名，1–40 个字符'},
        'trigger': {
          'type': 'object',
          'description': '{"type":"time","hour":23,"minute":0,"days":[1,2,3,4,5]}'
              ' | {"type":"wifi_connected","ssid":"Office"}'
              ' | {"type":"battery_below","threshold":20}；days 为 ISO 星期 1–7，空表示每天',
        },
        'actions': {
          'type': 'array',
          'description': '最多 5 个动作，参数与 android_device 相同，例如 '
              '{"action":"set_do_not_disturb","enabled":true}、'
              '{"action":"launch_app","packageName":"com.example"}、'
              '{"action":"set_brightness","value":0.3}、'
              '{"action":"clean_folder","treeUri":"content://...","olderThanDays":30,"extension":"apk"}',
          'items': {'type': 'object'},
        },
      },
      'required': ['action'],
    },
  );

  // -------------------------------------------------------------------------
  // 审批
  // -------------------------------------------------------------------------

  @override
  ToolRisk riskForArguments(Map<String, dynamic> arguments) {
    final action = arguments['action'];
    if (_readActions.contains(action)) return ToolRisk.safe;
    final rule = _ruleFromArguments(arguments);
    if (action == 'create_rule' &&
        rule != null &&
        (rule.requiresRoot || rule.hasIrreversibleAction)) {
      return ToolRisk.dangerous;
    }
    if (action == 'set_rule_enabled' && arguments['enabled'] == true) {
      // 启用可能包含 Root 动作的规则：无法同步读取规则内容，按危险审批。
      return ToolRisk.dangerous;
    }
    // 会降级为“打开设置页”的规则按危险审批：危险级在任何模式下都会弹出审批，
    // 保证用户一定看到审批卡片里的降级说明（批准即视为知悉）。
    if (action == 'create_rule' &&
        rule != null &&
        (arguments['acknowledgeFallback'] == true ||
            (_service.cachedFallbackWarnings(rule)?.isNotEmpty ?? false))) {
      return ToolRisk.dangerous;
    }
    return ToolRisk.requiresConfirmation;
  }

  /// 审批时可见的降级说明（基于最近的执行通道快照）；null = 尚未读取通道。
  List<String>? _approvalWarnings(Map<String, dynamic> arguments) {
    final action = arguments['action'];
    final rule = action == 'create_rule'
        ? _ruleFromArguments(arguments)
        : action == 'set_rule_enabled' &&
                arguments['enabled'] == true &&
                arguments['ruleId'] is String
            ? _service.cachedRule(arguments['ruleId'] as String)
            : null;
    return rule == null ? null : _service.cachedFallbackWarnings(rule);
  }

  Map<String, dynamic> _fallbackApprovalFields(
    Map<String, dynamic> arguments,
  ) {
    final warnings = _approvalWarnings(arguments);
    if (warnings == null) {
      return {
        'privilegeCheck': '尚未读取 Root/Shizuku 执行通道；如果缺少通道，执行时会先拦下并说明',
      };
    }
    if (warnings.isEmpty) {
      return {'privilegeCheck': '当前设备上所有动作都能直接执行'};
    }
    return {
      'fallbackActions': warnings,
      'fallbackNotice': '当前没有 Root/Shizuku（或缺少对应系统权限）：以上动作触发时只能打开系统设置页，'
          '需要你手动完成。批准即表示知悉；也可以先在“设备能力”页连接 Shizuku 或授予权限。',
    };
  }

  @override
  bool requiresPreviewPlan(Map<String, dynamic> arguments) => false;

  @override
  Map<String, dynamic>? approvalDetailsFor(Map<String, dynamic> arguments) {
    final action = arguments['action'];
    if (action == 'create_rule') {
      final rule = _ruleFromArguments(arguments);
      if (rule == null) return null;
      return {
        'target': '新自动化规则「${rule.name}」',
        'scope': '触发：${rule.trigger.describe()}；动作：'
            '${rule.actions.map((a) => a.describe()).join('；')}',
        'impact': '触发时只发送通知；每次都需你点开通知、查看预览并确认后才执行',
        'riskClass': rule.requiresRoot ? 'root' : 'normal',
        'reversible': !rule.hasIrreversibleAction,
        'rollback': '可随时在“设置 → 设备自动化”暂停或删除规则'
            '${rule.hasIrreversibleAction ? '；其中清缓存/删除文件动作执行后不可撤销' : ''}',
        ..._fallbackApprovalFields(arguments),
        // 智能体先把限制告诉用户、用户同意后才会带 acknowledgeFallback 重新调用：
        // 此时审批卡片应写明「用户已知悉」，而不是「批准即表示知悉」。有通道快照
        // 时仍保留上面列出的具体降级动作（fallbackActions）。
        if (arguments['acknowledgeFallback'] == true)
          'fallbackNotice': '用户已知悉：没有 Root/Shizuku 时，部分动作触发后只能打开系统设置页由用户手动完成',
      };
    }
    if (action == 'set_rule_enabled' || action == 'delete_rule') {
      return {
        'target': '自动化规则 ${arguments['ruleId']}',
        'impact': action == 'delete_rule'
            ? '删除规则，已记录的执行历史保留'
            : arguments['enabled'] == true
                ? '启用后满足条件会发送确认通知（不会自动执行）'
                : '暂停后不再触发',
        'reversible': action != 'delete_rule',
        if (action == 'set_rule_enabled' && arguments['enabled'] == true)
          ..._fallbackApprovalFields(arguments),
      };
    }
    return null;
  }

  @override
  Map<String, dynamic> authorizeAfterApproval(Map<String, dynamic> arguments) {
    final authorized = Map<String, dynamic>.from(arguments);
    // 审批卡片已列出降级动作且审批为危险级（必定由用户亲自批准）：视为已知悉。
    final warnings = _approvalWarnings(arguments);
    if (warnings != null &&
        warnings.isNotEmpty &&
        riskForArguments(arguments) == ToolRisk.dangerous) {
      authorized
        ..['acknowledgeFallback'] = true
        ..['acknowledgedFallbackActions'] = warnings;
    }
    return authorized;
  }

  @override
  void rejectApproval(Map<String, dynamic> arguments) {}

  // -------------------------------------------------------------------------
  // 执行
  // -------------------------------------------------------------------------

  AutomationRule? _ruleFromArguments(Map<String, dynamic> arguments) {
    final trigger = AutomationTrigger.fromJson(arguments['trigger']);
    final rawActions = arguments['actions'];
    final name = arguments['name'];
    if (trigger == null || rawActions is! List || name is! String) return null;
    final actions = <AutomationAction>[];
    for (final raw in rawActions) {
      final action = AutomationAction.fromJson(raw);
      if (action == null) return null;
      actions.add(action);
    }
    return AutomationRule(
      id: 'pending',
      name: name.trim(),
      enabled: true,
      trigger: trigger,
      actions: actions,
      createdAtMs: 0,
      updatedAtMs: 0,
    );
  }

  /// 没有特权通道时先让用户知情：返回无副作用的失败结果，列出只能降级的动作。
  Future<ToolResult?> _fallbackGate(
    AutomationRule rule,
    Map<String, dynamic> arguments,
  ) async {
    final warnings = await _service.privilegeFallbackWarnings(rule);
    if (warnings == null || warnings.isEmpty) return null;
    if (arguments['acknowledgeFallback'] == true) {
      final acknowledged = arguments['acknowledgedFallbackActions'];
      // 用户在对话中同意（模型转述）时没有清单，按已知悉处理；
      // 审批时看到的清单与执行时实测不一致（通道状态变了）则重新确认新增项。
      if (acknowledged is! List) return null;
      final unseen =
          warnings.where((warning) => !acknowledged.contains(warning)).toList();
      if (unseen.isEmpty) return null;
      return _fallbackBlocked(rule, arguments, unseen);
    }
    return _fallbackBlocked(rule, arguments, warnings);
  }

  /// trigger_status 用的动作级摘要（去掉依赖具体参数的动作描述前缀）。
  static String _fallbackSummary(
    String action,
    AutomationPrivilegeContext context,
  ) {
    final note = automationFallbackFor(
      AutomationAction(action, const {'enabled': true}),
      context,
    );
    if (note == null) return '可直接执行';
    final split = note.indexOf('：');
    return split < 0 ? note : note.substring(split + 1);
  }

  ToolResult _fallbackBlocked(
    AutomationRule rule,
    Map<String, dynamic> arguments,
    List<String> warnings,
  ) {
    return ToolResult.failure(
      code: ToolCodes.capabilityUnavailable,
      message:
          '规则「${rule.name}」未${arguments['action'] == 'create_rule' ? '创建' : '启用'}：'
          '当前没有 Root/Shizuku（或缺少对应系统权限），以下动作触发时无法自动完成——'
          '${warnings.join('；')}。请先告诉用户这些限制；用户同意后带 acknowledgeFallback=true 重新调用，'
          '或先连接 Shizuku / 在“设备能力”页授予权限。',
      data: {
        'requiresAcknowledgement': true,
        'fallbackActions': warnings,
        'ruleName': rule.name,
      },
    );
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final action = arguments['action'];
    try {
      switch (action) {
        case 'list_rules':
          final rules = await _service.rules();
          return ToolResult.success(
            message: rules.isEmpty ? '还没有自动化规则' : '共 ${rules.length} 条自动化规则',
            data: {
              'rules': [
                for (final rule in rules)
                  {
                    'id': rule.id,
                    'name': rule.name,
                    'enabled': rule.enabled,
                    'trigger': rule.trigger.describe(),
                    'actions': rule.actions.map((a) => a.describe()).toList(),
                    'requiresRoot': rule.requiresRoot,
                    'irreversible': rule.hasIrreversibleAction,
                  },
              ],
            },
          );
        case 'rule_history':
          final ruleId = arguments['ruleId'] as String?;
          final runs = (await _service.runs(ruleId: ruleId)).take(20).toList();
          return ToolResult.success(
            message: runs.isEmpty ? '暂无执行记录' : '最近 ${runs.length} 条执行记录',
            data: {'runs': runs.map((run) => run.toJson()).toList()},
          );
        case 'trigger_status':
          final status = await _service.bridge.triggerStatus();
          final privilege = await _service.refreshPrivilegeStatus();
          final routes = privilege?['routes'];
          final context = privilege == null
              ? null
              : AutomationPrivilegeContext.fromStatus(privilege);
          return ToolResult.success(
            message: '已读取触发器状态与执行通道',
            data: {
              ...status,
              if (routes is Map) 'privilegeRoutes': routes,
              if (context != null)
                'fallbackPreview': {
                  for (final action in automationFallbackCandidates)
                    action: _fallbackSummary(action, context),
                },
            },
          );
        case 'pending_fires':
          final fires = await _service.pendingFires();
          return ToolResult.success(
            message: fires.isEmpty ? '没有待确认的触发' : '${fires.length} 个触发等待用户确认',
            data: {
              'fires': [
                for (final fire in fires)
                  {
                    'fireId': fire.fireId,
                    'ruleName': fire.ruleName,
                    'trigger': fire.trigger,
                    'firedAtMs': fire.firedAtMs,
                  },
              ],
              'note': '待确认的触发只能由用户在通知或“设备自动化”页面中确认执行',
            },
          );
        case 'create_rule':
          final draft = _ruleFromArguments(arguments);
          if (draft == null) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: 'create_rule 需要 name、trigger 与 actions 数组',
            );
          }
          final error = draft.validate();
          if (error != null) {
            return ToolResult.failure(
                code: ToolCodes.invalidArguments, message: error);
          }
          final blocked = await _fallbackGate(draft, arguments);
          if (blocked != null) return blocked;
          final rule = await _service.createRule(
            name: draft.name,
            trigger: draft.trigger,
            actions: draft.actions,
          );
          return ToolResult.success(
            message: '已创建自动化规则「${rule.name}」；触发时会发送通知，用户确认后才执行',
            data: {'ruleId': rule.id, 'trigger': rule.trigger.describe()},
            effect: ToolEffect.applied,
          );
        case 'set_rule_enabled':
          final ruleId = arguments['ruleId'];
          final enabled = arguments['enabled'];
          if (ruleId is! String || enabled is! bool) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: 'set_rule_enabled 需要 ruleId 和 enabled',
            );
          }
          if (enabled) {
            final existing = await _service.findRule(ruleId);
            if (existing == null) throw StateError('规则不存在');
            final blocked = await _fallbackGate(existing, arguments);
            if (blocked != null) return blocked;
          }
          final rule = await _service.setEnabled(ruleId, enabled);
          return ToolResult.success(
            message: enabled ? '已启用「${rule.name}」' : '已暂停「${rule.name}」',
            effect: ToolEffect.applied,
          );
        case 'delete_rule':
          final ruleId = arguments['ruleId'];
          if (ruleId is! String) {
            return ToolResult.failure(
                code: ToolCodes.invalidArguments,
                message: 'delete_rule 需要 ruleId');
          }
          await _service.deleteRule(ruleId);
          return ToolResult.success(
              message: '已删除自动化规则', effect: ToolEffect.applied);
        default:
          return ToolResult.failure(
            code: ToolCodes.invalidArguments,
            message: '未知 action：$action',
          );
      }
    } on ArgumentError catch (error) {
      return ToolResult.failure(
          code: ToolCodes.invalidArguments, message: '${error.message}');
    } on StateError catch (error) {
      return ToolResult.failure(
          code: ToolCodes.notFound, message: error.message);
    } on MissingPluginException {
      return ToolResult.failure(
        code: ToolCodes.platformUnsupported,
        message: '设备自动化仅支持 Android',
      );
    } on PlatformException catch (error) {
      return ToolResult.failure(
        code: error.code == 'PERMISSION_DENIED'
            ? ToolCodes.permissionRequired
            : ToolCodes.toolError,
        message: error.message ?? error.code,
      );
    }
  }
}
