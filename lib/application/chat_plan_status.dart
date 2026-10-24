// 计划步骤与顶层计划状态收敛的纯函数规则。
//
// 从 ChatController 抽出，行为保持不变；ChatController 上的同名静态方法
// 保留为委托，既有测试无需修改。

import '../domain/models.dart';

List<PlanStep> planNormalizeStepsForTerminal(
    List<PlanStep> steps, String terminal) {
  final String? replacement;
  if (terminal == 'completed') {
    replacement = 'completed';
  } else if (terminal == 'failed' || terminal == 'cancelled') {
    replacement = 'failed';
  } else {
    replacement = null;
  }
  if (replacement == null) return steps;
  return [
    for (final step in steps)
      if (step.status == 'running' || step.status == 'pending')
        step.copyWith(status: replacement)
      else
        step,
  ];
}

String? planResolveTerminalStatus({
  required List<PlanStep> steps,
  required String currentStatus,
  String? runStatus,
  bool cancelled = false,
}) {
  if (steps.isEmpty) return null;
  final allCompleted = steps.every((step) => step.status == 'completed');
  final allTerminal = steps
      .every((step) => step.status == 'completed' || step.status == 'failed');
  final anyFailed = steps.any((step) => step.status == 'failed');

  // 运行尚未结束：仅在步骤全部走到终态时收敛，避免提前改态。
  if (runStatus == null) {
    if (allCompleted) return 'completed';
    if (allTerminal && anyFailed) return 'failed';
    return null;
  }

  // 运行已结束：按运行结果解析。
  if (cancelled || runStatus == 'cancelled') return 'cancelled';
  if (runStatus == 'success') return 'completed';
  if (allCompleted) return 'completed';
  if (runStatus == 'paused') return 'paused';
  return 'failed';
}
