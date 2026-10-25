import '../../domain/models.dart';
import '../../domain/tool_result.dart';
import '../agent_executor.dart' show AgentEvent;

/// 把事件交给执行器输出。
///
/// 返回的 Future 在执行器 `yield` 该事件、且消费方处理完毕并恢复执行器之后
/// 才完成，从而保持原 `async*` 循环的背压时序：例如消费方先把任务状态落库为
/// 「等待确认」，拦截器随后才调用 `approveTool`。
typedef ToolEventEmitter = Future<void> Function(AgentEvent event);

/// 管线在取消检查点发现运行已取消时抛出；执行器据此结束本轮。
final class ToolRunCancelled implements Exception {
  const ToolRunCancelled();

  @override
  String toString() => 'ToolRunCancelled';
}

/// 单次工具调用的运行上下文：审批配置，以及与执行器事件流、取消、暂停的桥接。
///
/// 每个调用新建一份；[executionStarted] 记录该调用是否已进入执行边界，
/// 执行器据此决定是否附带执行元数据、是否计入失败熔断统计。
final class ToolRunContext {
  ToolRunContext({
    required this.approvalMode,
    required ToolEventEmitter emit,
    this.approveTool,
    this.isToolTrusted,
    this.verifyPlan,
    this.claimDispatch,
    this.settleDispatch,
    this.whenSuperseded,
    bool Function()? isCancelled,
    bool Function()? isPaused,
    bool Function()? isSuperseded,
    Future<void> Function()? waitForResume,
  })  : _emit = emit,
        _isCancelled = isCancelled ?? _never,
        _isPaused = isPaused ?? _never,
        _isSuperseded = isSuperseded ?? _never,
        _waitForResume = waitForResume ?? _resumeImmediately;

  /// 不接入执行器的上下文：事件被丢弃，永不取消或暂停。用于测试与离线调用。
  factory ToolRunContext.detached({
    ApprovalMode approvalMode = ApprovalMode.ask,
    ToolApprovalCallback? approveTool,
  }) =>
      ToolRunContext(
        approvalMode: approvalMode,
        approveTool: approveTool,
        emit: _discard,
      );

  final Future<bool> Function()? verifyPlan;
  final Future<ToolResult?> Function(String callId)? claimDispatch;
  final Future<ToolResult> Function(String callId, ToolResult result)?
      settleDispatch;
  final Future<void>? whenSuperseded;
  Future<bool> planIsCurrent() async =>
      !isSuperseded && (await verifyPlan?.call() ?? true);
  final ApprovalMode approvalMode;
  final ToolApprovalCallback? approveTool;
  final bool Function(String toolName, ToolRisk risk)? isToolTrusted;

  final ToolEventEmitter _emit;
  final bool Function() _isCancelled;
  final bool Function() _isPaused;
  final bool Function() _isSuperseded;
  final Future<void> Function() _waitForResume;
  var _executionStarted = false;

  Future<void> emit(AgentEvent event) => _emit(event);

  bool get isCancelled => _isCancelled();

  bool get isPaused => _isPaused();

  bool get isSuperseded => _isSuperseded();

  /// 已暂停时等待恢复或取消；未暂停时立即完成。
  Future<void> waitForResume() => _waitForResume();

  bool get executionStarted => _executionStarted;

  void markExecutionStarted() => _executionStarted = true;
}

bool _never() => false;

Future<void> _resumeImmediately() async {}

Future<void> _discard(AgentEvent _) async {}
