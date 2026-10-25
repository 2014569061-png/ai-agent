import '../../application/run_approval_scope.dart';
import '../../application/approval_decision_scope.dart';
import '../../application/result_action_approval_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';

import '../../application/approval_bridge.dart';
import '../../application/app_lock_service.dart';
import '../../application/foreground_approval_guard.dart';
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
Future<ToolApproval> promptToolApproval(BuildContext context, WidgetRef ref,
    ToolCall call, ToolRisk risk, bool sensitive,
    {RunApprovalScope? approvalScope}) async {
  final scope = approvalScope ?? RunApprovalScope.current;
  if (scope != null && !await scope.isCurrent()) return ToolApproval.reject;
  // 页面未挂载时无法弹窗，保守拒绝，让执行层暂停等待。
  if (!context.mounted) return ToolApproval.reject;

  // 后台通知只能拒绝或引导回前台；不把通知点击当作批准身份凭证。
  // 超时保守拒绝，前台待审批入口仍负责查看和身份验证。
  if (!_appIsInteractive()) {
    final approved = await const ApprovalBridge().requestDecision(
      toolName: call.name,
      summary: approvalNotificationSummary(call, risk),
      risk: risk.name,
      database: await ref.read(databaseProvider.future),
      approvalScope: scope,
    );
    final decision =
        approved == true ? ToolApproval.allowOnce : ToolApproval.reject;
    _recordToolDecision(ref, call, risk, decision, scope: scope);
    return decision;
  }

  final trust = await ref.read(toolTrustStoreProvider.future);
  if (!context.mounted) return ToolApproval.reject;

  // 会话级授权：非敏感、非危险级工具可在本次 App 会话内免于重复审批。授权只写
  // 内存（ToolTrustStore._session），退出应用即失效，仍会写入审计。
  final allowSessionTrust =
      !requiresFreshToolAuthentication(risk, sensitive, call.name);

  // 持久级授权：会写入全局信任清单，此后所有会话静默放行，因此比会话级严格得多。
  // 当前策略下 requiresConfirmation（终端、写文件等）不开放持久信任——那会绕过
  // README 里「终端默认逐次确认」的承诺；需要长期免打扰的用户应显式切换到
  // 「完全访问」模式，那是一个可随时撤回的全局开关。
  // 注意：此前这里的条件把 requiresConfirmation 一并排除，导致 UI 上「本会话允许
  // / 始终允许」两个按钮永远不显示（safe 才会通过，而 safe 从不弹窗），是一处
  // 不可达的假 UI。现在会话级与持久级分开判断。
  final allowPersistentTrust = scope == null &&
      allowSessionTrust &&
      risk != ToolRisk.requiresConfirmation;
  var expired = false;
  var backgrounded = false;
  final decision = await showNexusSheet<ToolApproval>(
    context: context,
    builder: (context) => _ScopedApprovalHost(
        scope: scope,
        child: ToolApprovalSheet(
          call: call,
          risk: risk,
          allowSessionTrust: allowSessionTrust,
          sessionTrustLabel: scope == null ? '本会话允许' : '本计划允许',
          allowPersistentTrust: allowPersistentTrust,
          timeout: const Duration(minutes: 5),
          onExpired: () => expired = true,
          // 弹窗显示期间被切到后台：弹窗已经看不见，后台又冻结倒计时，若继续等下去
          // 整个运行会卡在后台。这里改走通知通道等待裁决，语义与开头那次判断一致
          // （仍是「超时即拒绝」），只是把裁决面从不可见的弹窗换到锁屏/通知栏。
          onBackgrounded: () => backgrounded = true,
        )),
  );

  var resolvedDecision = decision ?? ToolApproval.reject;
  if (backgrounded) {
    final approved = await const ApprovalBridge().requestDecision(
      toolName: call.name,
      summary: approvalNotificationSummary(call, risk),
      risk: risk.name,
      database: await ref.read(databaseProvider.future),
      approvalScope: scope,
    );
    resolvedDecision =
        approved == true ? ToolApproval.allowOnce : ToolApproval.reject;
  }

  resolvedDecision = await validateForegroundToolApproval(
    decision: resolvedDecision,
    risk: risk,
    sensitive: sensitive,
    toolName: call.name,
    authenticate: ref.read(appLockServiceProvider).authenticate,
    isForeground: () => context.mounted &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    isCurrent: scope?.isCurrent,
  );
  if (scope != null && !await scope.isCurrent()) return ToolApproval.reject;
  if (expired && context.mounted) {
    FloatingToast.show(context, '审批已超时，已自动拒绝', tone: ToastTone.warning);
  }
  _recordToolDecision(ref, call, risk, resolvedDecision, scope: scope);
  if (scope == null &&
      allowSessionTrust &&
      resolvedDecision == ToolApproval.allowSession) {
    trust.allowSession(call.name);
  } else if (allowPersistentTrust &&
      resolvedDecision == ToolApproval.allowAlways) {
    await trust.allowAlways(call.name);
  }
  return resolvedDecision;
}

void _recordToolDecision(
    WidgetRef ref, ToolCall call, ToolRisk risk, ToolApproval decision,
    {RunApprovalScope? scope}) {
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
        conversationId: scope == null
            ? ref.read(chatControllerProvider).conversationId
            : (await database.findTask(scope.token.taskId))?.conversationId,
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

/// Same foreground sheet and background bridge as tool approvals, but only an
/// explicitly scoped one-time decision. No trust-store reads or grants.
Future<ToolApproval> promptResultActionApproval(
        BuildContext context, ResultActionApprovalScope scope) =>
    scope.invoke(() async {
      if (!context.mounted || !await scope.isCurrent()) {
        return ToolApproval.reject;
      }
      Future<ToolApproval> notify() async {
        final approved = await scope.bridge.requestDecision(
            toolName: scope.ticket.callType,
            // Notification/lock-screen text must not expose file names or targets.
            summary: '结果卡操作需要批准（仅本次）',
            risk: scope.risk.name,
            database: scope.db,
            approvalScope: scope,
            timeout:
                scope.remaining.isNegative ? Duration.zero : scope.remaining);
        return approved == true ? ToolApproval.allowOnce : ToolApproval.reject;
      }

      if (!_appIsInteractive()) return notify();
      var backgrounded = false;
      if (!context.mounted) return ToolApproval.reject;
      final decision = await showNexusSheet<ToolApproval>(
          context: context,
          builder: (_) => _ScopedApprovalHost(
              scope: scope,
              child: ToolApprovalSheet(
                call: scope.call,
                risk: scope.risk,
                allowSessionTrust: false,
                allowPersistentTrust: false,
                timeout: scope.remaining,
                onBackgrounded: () => backgrounded = true,
              )));
      if (!await scope.isCurrent()) return ToolApproval.reject;
      if (backgrounded) return notify();
      if (!context.mounted) return ToolApproval.reject;
      return validateForegroundToolApproval(
        decision: decision ?? ToolApproval.reject,
        risk: scope.risk,
        sensitive: false,
        toolName: scope.call.name,
        authenticate: ProviderScope.containerOf(context)
            .read(appLockServiceProvider).authenticate,
        isForeground: () => context.mounted &&
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
        isCurrent: scope.isCurrent,
      );
    });

class _ScopedApprovalHost extends StatefulWidget {
  const _ScopedApprovalHost({required this.scope, required this.child});
  final ApprovalDecisionScope? scope;
  final Widget child;
  @override
  State<_ScopedApprovalHost> createState() => _ScopedApprovalHostState();
}

class _ScopedApprovalHostState extends State<_ScopedApprovalHost> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.scope?.invalidated.then((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route, ToolApproval.reject);
      }
    }));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
