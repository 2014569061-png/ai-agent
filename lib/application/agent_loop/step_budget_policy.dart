import 'dart:convert';

import '../../domain/models.dart';
import '../../domain/tool_result.dart';
import 'loop_messages.dart';

/// 步数预算的判定结果。
sealed class BudgetDecision {
  const BudgetDecision();
}

/// 还有预算，继续本步。
final class BudgetProceed extends BudgetDecision {
  const BudgetProceed();
}

/// 预算用完但最近仍有进展：自动追加一轮预算后继续。
final class BudgetExtended extends BudgetDecision {
  const BudgetExtended({
    required this.round,
    required this.limit,
    required this.addedSteps,
  });
  final int round;
  final int limit;
  final int addedSteps;
}

/// 预算耗尽：可恢复的暂停。
final class BudgetExhausted extends BudgetDecision {
  const BudgetExhausted(this.budget);
  final int budget;
}

/// 步数预算、自动续跑与连续失败熔断（原先内联在 AgentExecutor.run 中）。
///
/// 只统计真正进入执行边界的工具结果；守卫短路与审批拒绝不计入。
/// 阶段 3 起作为 `agent/pre-step` 与 `tools/post-execute` 的监听模块挂载。
class StepBudgetPolicy {
  StepBudgetPolicy({
    required this.maxSteps,
    this.autoContinueLimit = 0,
    this.failurePauseThreshold = 4,
  }) : _budget = maxSteps;

  final int maxSteps;
  final int autoContinueLimit;
  final int failurePauseThreshold;

  int _budget;
  int _autoContinued = 0;
  final _recentOutcomes = <bool>[];
  final _failuresByCall = <String, int>{};
  final _hintedCalls = <String>{};
  final _failureHints = <String>[];
  int _consecutiveFailures = 0;

  /// 当前总预算（含自动续跑追加的部分）。
  int get budget => _budget;
  int get consecutiveFailures => _consecutiveFailures;

  /// 每步开始前调用（step 从 0 开始）。
  BudgetDecision beforeStep(int step) {
    if (step < _budget) return const BudgetProceed();
    if (_autoContinued >= autoContinueLimit || !hasRecentProgress()) {
      return BudgetExhausted(_budget);
    }
    _autoContinued++;
    _budget += maxSteps;
    return BudgetExtended(
      round: _autoContinued,
      limit: autoContinueLimit,
      addedSteps: maxSteps,
    );
  }

  /// 记录一次已执行的工具结果。
  void recordToolOutcome(ToolCall call, ToolResult result) {
    _recentOutcomes.add(result.ok);
    if (_recentOutcomes.length > 12) _recentOutcomes.removeAt(0);
    final signature = _callSignature(call);
    if (result.ok) {
      _consecutiveFailures = 0;
      _failuresByCall.remove(signature);
      return;
    }
    _consecutiveFailures++;
    final count = (_failuresByCall[signature] ?? 0) + 1;
    _failuresByCall[signature] = count;
    if (count >= 2 && _hintedCalls.add(signature)) {
      _failureHints.add(LoopMessages.repeatedFailureHint(call.name, count));
    }
  }

  /// 取出本步累计的失败提示（同一调用只提示一次）。
  List<String> drainFailureHints() {
    if (_failureHints.isEmpty) return const [];
    final hints = List<String>.of(_failureHints);
    _failureHints.clear();
    return hints;
  }

  /// 连续失败达到阈值（且中间没有成功），应提前暂停。
  bool get shouldPauseForFailures =>
      failurePauseThreshold > 0 &&
      _consecutiveFailures >= failurePauseThreshold;

  /// 进展判断：最近有工具成功，且最后 4 次不全是失败。
  bool hasRecentProgress() {
    if (!_recentOutcomes.contains(true)) return false;
    final tail = _recentOutcomes.length > 4
        ? _recentOutcomes.sublist(_recentOutcomes.length - 4)
        : _recentOutcomes;
    return tail.contains(true);
  }

  static String _callSignature(ToolCall call) {
    try {
      return '${call.name} ${jsonEncode(call.arguments)}';
    } catch (_) {
      return '${call.name} ${call.arguments}';
    }
  }
}
