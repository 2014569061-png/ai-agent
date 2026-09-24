import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';

import '../../application/approval_bridge.dart';
import '../../application/approval_notification_text.dart';
import '../../application/audit_service.dart';
import '../../application/chat_controller.dart';
import '../../application/nexus_guard.dart';
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

  // 会话级授权：非敏感、非危险级工具可在本次 App 会话内免于重复审批。授权只写
  // 内存（ToolTrustStore._session），退出应用即失效，仍会写入审计。
  final allowSessionTrust = !sensitive && risk != ToolRisk.dangerous;

  // 持久级授权：会写入全局信任清单，此后所有会话静默放行，因此比会话级严格得多。
  // 当前策略下 requiresConfirmation（终端、写文件等）不开放持久信任——那会绕过
  // README 里「终端默认逐次确认」的承诺；需要长期免打扰的用户应显式切换到
  // 「完全访问」模式，那是一个可随时撤回的全局开关。
  // 注意：此前这里的条件把 requiresConfirmation 一并排除，导致 UI 上「本会话允许
  // / 始终允许」两个按钮永远不显示（safe 才会通过，而 safe 从不弹窗），是一处
  // 不可达的假 UI。现在会话级与持久级分开判断。
  final allowPersistentTrust =
      allowSessionTrust && risk != ToolRisk.requiresConfirmation;
  var expired = false;
  var backgrounded = false;
  final decision = await showNexusSheet<ToolApproval>(
    context: context,
    builder: (context) => ToolApprovalSheet(
      call: call,
      risk: risk,
      allowSessionTrust: allowSessionTrust,
      allowPersistentTrust: allowPersistentTrust,
      timeout: const Duration(minutes: 5),
      onExpired: () => expired = true,
      // 弹窗显示期间被切到后台：弹窗已经看不见，后台又冻结倒计时，若继续等下去
      // 整个运行会卡在后台。这里改走通知通道等待裁决，语义与开头那次判断一致
      // （仍是「超时即拒绝」），只是把裁决面从不可见的弹窗换到锁屏/通知栏。
      onBackgrounded: () => backgrounded = true,
    ),
  );

  var resolvedDecision = decision ?? ToolApproval.reject;
  if (backgrounded) {
    final approved = await const ApprovalBridge().requestDecision(
      toolName: call.name,
      summary: approvalNotificationSummary(call, risk),
      risk: risk.name,
      database: await ref.read(databaseProvider.future),
    );
    resolvedDecision =
        approved == true ? ToolApproval.allowOnce : ToolApproval.reject;
  }

  if (expired && context.mounted) {
    FloatingToast.show(context, '审批已超时，已自动拒绝', tone: ToastTone.warning);
  }
  _recordToolDecision(ref, call, risk, resolvedDecision);
  if (allowSessionTrust && resolvedDecision == ToolApproval.allowSession) {
    trust.allowSession(call.name);
  } else if (allowPersistentTrust &&
      resolvedDecision == ToolApproval.allowAlways) {
    await trust.allowAlways(call.name);
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
  // 「谁能批什么」的审计留痕失败绝不能无声：串里的 finally 写成
  // catchError((_) {}) 时，数据库打不开或写入失败都不会留下任何痕迹，
  // 审计页于是少报已授予的权限。保持 fire-and-forget，但让失败可观测。
  unawaited(
    NexusGuard.silentlyAsync<bool>('approval.audit', () async {
      final database = await db;
      await audit.logSecurityEvent(
        database,
        type: 'tool_grant',
        detail: call.name,
        decision: decision.name,
        risk: risk.name,
        conversationId: ref.read(chatControllerProvider).conversationId,
      );
      return true;
    }),
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
