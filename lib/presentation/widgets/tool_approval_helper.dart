import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/audit_service.dart';
import '../../application/chat_controller.dart';
import '../../application/providers.dart';
import '../../domain/models.dart';
import '../chat/widgets/tool_approval_sheet.dart';
import 'immersive_sheet.dart';

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
  final trust = await ref.read(toolTrustStoreProvider.future);
  if (!context.mounted) return ToolApproval.reject;

  final allowPersistentTrust = !sensitive &&
      risk != ToolRisk.dangerous &&
      risk != ToolRisk.requiresConfirmation;
  final decision = await showImmersiveSheet<ToolApproval>(
    context: context,
    builder: (context) => ToolApprovalSheet(
      call: call,
      risk: risk,
      allowPersistentTrust: allowPersistentTrust,
    ),
  );

  if (allowPersistentTrust &&
      (decision == ToolApproval.allowAlways ||
          decision == ToolApproval.allowSession)) {
    if (decision == ToolApproval.allowAlways) {
      await trust.allowAlways(call.name);
    } else {
      trust.allowSession(call.name);
    }
    _recordToolGrant(ref, call, risk, decision!);
  }
  return decision ?? ToolApproval.reject;
}

void _recordToolGrant(
  WidgetRef ref,
  ToolCall call,
  ToolRisk risk,
  ToolApproval decision,
) {
  final audit = ref.read(auditServiceProvider);
  final db = ref.read(databaseProvider.future);
  db.then((database) {
    audit.log(
      database,
      type: 'tool_grant',
      detail: call.name,
      decision: decision.name,
      risk: risk.name,
      conversationId: ref.read(chatControllerProvider).conversationId,
    );
  });
}
