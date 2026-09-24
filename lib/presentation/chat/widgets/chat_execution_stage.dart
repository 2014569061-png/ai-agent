import '../../../application/chat_controller.dart';
import '../../../domain/models.dart';

/// Structured execution stages shared by the chat input and top bar.
///
/// User-facing copy stays separate from the stage so a wording change cannot
/// silently break status rendering.
enum ChatExecutionStage {
  waitingForUser,
  preparing,
  running,
  succeeded,
  failed,
  cancelled,
}

({ChatExecutionStage stage, String label})? resolveChatExecutionStage({
  required List<ToolActivity> toolActivities,
  required bool running,
  required bool paused,
  required PlanState? planState,
  ChatRunProgress? runProgress,
}) {
  if (!running) {
    if (planState != null && !planState.isConfirmed) {
      return (stage: ChatExecutionStage.waitingForUser, label: '等待确认计划');
    }
    return null;
  }
  if (paused) {
    return (
      stage: ChatExecutionStage.waitingForUser,
      label: '已暂停，可继续或追加指令',
    );
  }
  final progressLabel = runProgress?.label.trim();
  if (progressLabel != null && progressLabel.isNotEmpty) {
    return (
      stage: runProgress?.stage == ChatRunStage.waitingForUser
          ? ChatExecutionStage.waitingForUser
          : ChatExecutionStage.running,
      label: progressLabel,
    );
  }
  final current = toolActivities.lastOrNull;
  if (current?.status == '等待确认') {
    return (
      stage: ChatExecutionStage.waitingForUser,
      label: '等待确认：${current!.call.name}',
    );
  }
  if (current?.status == '执行中') {
    return (
      stage: ChatExecutionStage.running,
      label: '正在执行：${current!.call.name}',
    );
  }
  return (stage: ChatExecutionStage.running, label: '生成中…');
}
