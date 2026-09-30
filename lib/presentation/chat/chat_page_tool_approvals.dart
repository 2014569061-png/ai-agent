part of 'chat_page.dart';

/// 工具审批：等待用户决定、确认/拒绝/重试工具调用。
extension _ChatToolApprovals on _ChatPageState {
  Future<ToolApproval> _approveTool(
    ToolCall call,
    ToolRisk risk,
    bool sensitive,
  ) async {
    if (!mounted) return ToolApproval.reject;
    final previous = _pendingToolApprovals[call.id];
    if (previous != null && !previous.isCompleted) {
      previous.complete(ToolApproval.reject);
    }
    final approval = Completer<ToolApproval>();
    _pendingToolApprovals[call.id] = approval;
    try {
      return await approval.future;
    } finally {
      if (identical(_pendingToolApprovals[call.id], approval)) {
        _pendingToolApprovals.remove(call.id);
      }
    }
  }

  bool _resolveToolApproval(String callId, ToolApproval decision) {
    final approval = _pendingToolApprovals[callId];
    if (approval == null || approval.isCompleted) return false;
    approval.complete(decision);
    return true;
  }

  void _confirmToolActivity(ToolActivity activity) {
    if (!_resolveToolApproval(activity.call.id, ToolApproval.allowOnce)) {
      FloatingToast.show(context, '该审批已失效，请重试任务', tone: ToastTone.warning);
    }
  }

  void _rejectToolActivity(ToolActivity activity) {
    if (!_resolveToolApproval(activity.call.id, ToolApproval.reject)) {
      FloatingToast.show(context, '该审批已失效，请重试任务', tone: ToastTone.warning);
    }
  }

  void _reviewToolActivity(ToolActivity activity) {
    if (!_pendingToolApprovals.containsKey(activity.call.id)) {
      FloatingToast.show(context, '该审批已失效，请重试任务', tone: ToastTone.warning);
      return;
    }
    unawaited(_showToolApprovalDetails(activity));
  }

  Future<void> _showToolApprovalDetails(ToolActivity activity) async {
    final decision = await promptToolApproval(
      context,
      ref,
      activity.call,
      activity.risk,
      activity.sensitive,
    );
    if (!mounted) return;
    _resolveToolApproval(activity.call.id, decision);
  }

  void _retryToolActivity(ToolActivity activity) {
    final state = ref.read(chatControllerProvider);
    if (state.running) {
      FloatingToast.show(context, '当前任务仍在运行', tone: ToastTone.warning);
      return;
    }
    unawaited(_confirmToolRetry(activity));
  }

  Future<void> _confirmToolRetry(ToolActivity activity) async {
    final unknownEffect = activity.effect == ToolEffect.unknown;
    final confirmed = await showConfirmAction(
      context,
      title: '重试上一次任务？',
      message: unknownEffect
          ? '该操作的副作用无法确认。请先检查目标状态，避免重复写入后再重试。'
          : '将重新运行上一条请求和其工具步骤。',
      confirmLabel: '确认重试',
      isDanger: unknownEffect,
    );
    if (confirmed && mounted) _regenerate();
  }
}
