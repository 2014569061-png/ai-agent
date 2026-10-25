import '../../domain/models.dart';
import '../../domain/tool_codes.dart';
import '../../domain/tool_result.dart';
import '../../infrastructure/tools/tool_registry.dart';
import '../agent_executor.dart' show AgentStatusEvent, ApprovalRequiredEvent;
import '../approval_policy.dart';
import 'preflight_guards.dart';
import 'tool_invocation.dart';
import 'tool_pipeline.dart';
import 'tool_run_context.dart';

/// 默认完整管线：前置守卫 → 审批 → 取消/暂停检查点 → 执行边界 → 授权，
/// 终点为 [executeWithTimeout]。
List<ToolInterceptor> defaultToolInterceptors() => [
      ...defaultToolPreflightGuards(),
      const ApprovalInterceptor(),
      const CheckpointInterceptor(),
      const ControlRevisionInterceptor(),
      const ExecutionBoundary(),
      const AuthorizationInterceptor(),
    ];

/// 按审批策略决定是否需要用户确认；拒绝时回滚动作级预览并短路。
final class ApprovalInterceptor implements ToolInterceptor {
  const ApprovalInterceptor();

  @override
  String get id => 'approval';

  @override
  Future<ToolResult> intercept(ToolInvocation invocation, ToolNext next) async {
    if (!await invocation.context.planIsCurrent()) {
      return _superseded(invocation);
    }
    final spec = invocation.resolved.spec;
    final gate = invocation.approvalGate;
    final call = invocation.call;
    final context = invocation.context;
    final risk = gate?.riskForArguments(call.arguments) ?? spec.risk;
    final decision = const ApprovalPolicy().decide(
      toolName: spec.name,
      mode: context.approvalMode,
      risk: risk,
      sensitive: spec.sensitive,
      trusted: context.isToolTrusted?.call(spec.name, risk) ?? false,
    );
    if (!decision.requiresUser) return next(invocation);

    // 预览详情只随审批请求展示，执行参数中不会出现 `_approvalDetails`。
    final details = invocation.approvalDetails;
    final approvalCall = details == null
        ? call
        : call.copyWith(
            arguments: {...call.arguments, '_approvalDetails': details},
          );
    await context.emit(ApprovalRequiredEvent(approvalCall, risk));
    final userDecision =
        await context.approveTool?.call(approvalCall, risk, spec.sensitive) ??
            ToolApproval.reject;
    if (!await context.planIsCurrent()) return _superseded(invocation);
    if (userDecision == ToolApproval.reject) {
      gate?.rejectApproval(call.arguments);
      return ToolResult.failure(
        code: ToolCodes.approvalRejected,
        message: '用户拒绝了该工具调用，请改用不需要该权限的方案继续',
      );
    }
    return next(invocation);
  }
}

/// 执行前的取消与暂停检查点。取消时抛出 [ToolRunCancelled] 结束本轮；
/// 暂停时先发出 paused 让 UI 立即切换，再等待恢复。
final class CheckpointInterceptor implements ToolInterceptor {
  const CheckpointInterceptor();

  @override
  String get id => 'checkpoint';

  @override
  Future<ToolResult> intercept(ToolInvocation invocation, ToolNext next) async {
    final context = invocation.context;
    if (context.isCancelled) throw const ToolRunCancelled();
    if (context.isPaused) {
      await context.emit(const AgentStatusEvent(RunStatus.paused));
      await context.waitForResume();
    }
    if (context.isCancelled) throw const ToolRunCancelled();
    await context.emit(const AgentStatusEvent(RunStatus.executingTool));
    return next(invocation);
  }
}

/// Final check after approval, pause/resume and event-emitter backpressure.
/// Never claims to undo a tool that has already crossed the execution boundary.
final class ControlRevisionInterceptor implements ToolInterceptor {
  const ControlRevisionInterceptor();
  @override
  String get id => 'control-revision';
  @override
  Future<ToolResult> intercept(ToolInvocation invocation, ToolNext next) async {
    if (!await invocation.context.planIsCurrent()) {
      return _superseded(invocation);
    }
    return next(invocation);
  }
}

ToolResult _superseded(ToolInvocation invocation) {
  invocation.approvalGate?.rejectApproval(invocation.call.arguments);
  return ToolResult.failure(
      code: ToolCodes.revisionConflict,
      message: '用户已修改当前目标，本轮旧工具调用和旧审批未执行；请先读取最新指令后重新规划',
      data: const {'reason': 'control_superseded'},
      effect: ToolEffect.none);
}

/// 执行边界：其下游（授权 + 实际执行）抛出的异常都在这里转成结构化失败。
///
/// 异常发生在工具边界内，无法证明副作用是否发生，因此按 effect=unknown
/// 上报，让模型先读取确认而不是盲目重试。
final class ExecutionBoundary implements ToolInterceptor {
  const ExecutionBoundary();

  @override
  String get id => 'execution-boundary';

  @override
  Future<ToolResult> intercept(ToolInvocation invocation, ToolNext next) async {
    final context = invocation.context;
    final rejected = await context.claimDispatch?.call(invocation.call.id);
    if (rejected != null) {
      invocation.approvalGate?.rejectApproval(invocation.call.arguments);
      return rejected;
    }
    if (context.isSuperseded) {
      final result = _superseded(invocation);
      return await context.settleDispatch?.call(invocation.call.id, result) ??
          result;
    }
    context.markExecutionStarted();
    ToolResult result;
    try {
      result = await next(invocation);
    } on ToolRunCancelled {
      await context.settleDispatch?.call(
          invocation.call.id,
          ToolResult.failure(
              code: ToolCodes.toolError,
              message: '执行边界后取消，副作用待核实',
              effect: ToolEffect.unknown));
      rethrow;
    } on ToolApprovalAuthorizationException catch (error) {
      result = ToolResult.failure(
          code: ToolCodes.invalidArguments, message: error.message);
    } catch (error) {
      result = ToolResult.failure(
          code: ToolCodes.toolError,
          message: '工具执行异常：$error；副作用无法确认，请先检查目标状态',
          effect: ToolEffect.unknown);
    }
    return await context.settleDispatch?.call(invocation.call.id, result) ??
        result;
  }
}

/// 审批通过后换取一次性执行授权（例如设备变更的预览凭据）。
final class AuthorizationInterceptor implements ToolInterceptor {
  const AuthorizationInterceptor();

  @override
  String get id => 'authorization';

  @override
  Future<ToolResult> intercept(ToolInvocation invocation, ToolNext next) async {
    final gate = invocation.approvalGate;
    if (gate == null) return next(invocation);
    return next(invocation.withExecutionArguments(
      gate.authorizeAfterApproval(invocation.call.arguments),
    ));
  }
}

/// 管线终点：以注册项声明的超时执行工具。
///
/// 强制超时：一个卡死的终端命令或网络工具若不设上限，会无限期挂住整个
/// Agent 回合。这里只停止“等待”，**不保证中断底层进程/连接**——现有工具
/// 没有统一的取消通道，因此结果按 effect=unknown 上报。
Future<ToolResult> executeWithTimeout(ToolInvocation invocation) {
  final registration = invocation.resolved;
  final timeout = registration.spec.timeout;
  return registration.executor.execute(invocation.arguments).timeout(
        timeout,
        onTimeout: () => ToolResult.failure(
          code: ToolCodes.timeout,
          message: '工具执行超时（${timeout.inSeconds}s），已中止等待；'
              '副作用无法确认，请先检查目标状态',
          effect: ToolEffect.unknown,
        ),
      );
}
