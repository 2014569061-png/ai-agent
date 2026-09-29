import 'dart:async';

import '../agent_executor.dart' show AgentEvent;
import '../agent_loop/agent_loop_hooks.dart';
import 'run_profile.dart';

/// 一次运行的结束方式。
class RunOutcome {
  /// 事件流正常结束（终态事件由模块自己从事件流中识别）。
  const RunOutcome.finished() : abortReason = null;

  /// 事件流以异常结束或被外部中止。
  const RunOutcome.aborted(String this.abortReason);

  final String? abortReason;
  bool get aborted => abortReason != null;
}

/// 模块挂到一次运行上的全部效果。[onFinish] 负责撤销/收尾：宿主保证每个
/// 成功挂载的模块恰好收到一次，按挂载的逆序调用。
class ModuleAttachment {
  const ModuleAttachment({
    this.hooks = AgentLoopHooks.empty,
    this.onEvent,
    this.onFinish,
  });

  final AgentLoopHooks hooks;
  final void Function(AgentEvent event)? onEvent;
  final FutureOr<void> Function(RunOutcome outcome)? onFinish;
}

/// 第一方运行模块（不支持第三方插件）：按运行形态决定是否挂载，
/// 挂载后通过阶段钩子与事件观察参与运行。
abstract interface class AgentModule {
  /// 稳定标识，用于错误上报与排查，例如 `builtin.session-log`。
  String get id;

  bool appliesTo(RunScope scope);

  /// 返回 null 表示本次不挂载。
  FutureOr<ModuleAttachment?> attach(RunScope scope);
}
