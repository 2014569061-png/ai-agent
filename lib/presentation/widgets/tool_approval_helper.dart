import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';

import '../../application/approval_bridge.dart';
import '../../application/approval_notification_text.dart';
import '../../application/audit_service.dart';
import '../../application/chat_controller.dart';
import '../../application/providers.dart';
import '../../domain/models.dart';
import '../chat/widgets/tool_approval_sheet.dart';
import 'floating_toast.dart';
import 'nexus_sheet.dart';

/// 共享工具审批入口：审批弹窗 → 记录允许范围与审计。
///
/// 聊天页与仪表盘（恢复任务）共用此入口，保证"危险操作必须确认"
/// 的安全语义在任意入口一致。
///
/// 返回 [ToolApproval] 决策；context 已卸载时保守地返回 reject。
Future<ToolApproval> promptToolApproval(
  BuildContext context,
  WidgetRef ref,
  ToolCall call,
  ToolRisk risk,
  bool sensitive,
) async {
  // 页面未挂载时无法弹窗，保守拒绝，让执行层暂停等待。
  if (!context.mounted) return ToolApproval.reject;

  // 应用不在前台（锁屏 / 已切走）时，弹窗用户根本看不见，需审批的工具会一直等
  // 下去——这不是体验问题而是死锁。这种情况改走通知裁决通道：带「批准/拒绝」
  // 动作的通知可在锁屏或通知栏直接处理。超时即拒绝，因此不比原路径宽松。
  if (!_appIsInteractive()) {
    final approved = await const ApprovalBridge().requestDecision(
      toolName: call.name,
      summary: approvalNotificationSummary(call, risk),
      risk: risk.name,
      database: await ref.read(databaseProvider.future),
    );
    final decision =
        approved == true ? ToolApproval.allowOnce : ToolApproval.reject;
    _recordToolDecision(ref, call, risk, decision);
    return decision;
  }

  final trust = await ref.read(toolTrustStoreProvider.future);
  if (!context.mounted) return ToolApproval.reject;

  final allowPersistentTrust = !sensitive &&
      risk != ToolRisk.dangerous &&
      risk != ToolRisk.requiresConfirmation;
  var expired = false;
  final decision = await showNexusSheet<ToolApproval>(
    context: context,
    builder: (context) => ToolApprovalSheet(
      call: call,
      risk: risk,
      allowPersistentTrust: allowPersistentTrust,
      timeout: const Duration(minutes: 5),
      onExpired: () => expired = true,
    ),
  );

  final resolvedDecision = decision ?? ToolApproval.reject;
  if (expired && context.mounted) {
    FloatingToast.show(context, '瀹℃壒宸茶秴鏃讹紝宸茶嚜鍔ㄦ嫆缁?', tone: ToastTone.warning);
  }
  _recordToolDecision(ref, call, risk, resolvedDecision);
  if (allowPersistentTrust &&
      (resolvedDecision == ToolApproval.allowAlways ||
          resolvedDecision == ToolApproval.allowSession)) {
    if (resolvedDecision == ToolApproval.allowAlways) {
      await trust.allowAlways(call.name);
    } else {
      trust.allowSession(call.name);
    }
  }
  return resolvedDecision;
}

void _recordToolDecision(
  WidgetRef ref,
  ToolCall call,
  ToolRisk risk,
  ToolApproval decision,
) {
  final audit = ref.read(auditServiceProvider);
  final db = ref.read(databaseProvider.future);
  unawaited(
    db
        .then((database) => audit.logSecurityEvent(
              database,
              type: 'tool_grant',
              detail: call.name,
              decision: decision.name,
              risk: risk.name,
              conversationId: ref.read(chatControllerProvider).conversationId,
            ))
        .catchError((_) {}),
  );
}

/// 应用是否处于用户可见的前台状态。
///
/// 取不到生命周期状态（启动早期、测试环境）时按前台处理，保持既有弹窗行为不变——
/// 锁屏通道只应在「确定用户看不到弹窗」时才接管。
bool _appIsInteractive() {
  final state = WidgetsBinding.instance.lifecycleState;
  return state == null || state == AppLifecycleState.resumed;
}
