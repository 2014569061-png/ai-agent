import '../../domain/models.dart';
import '../../infrastructure/tools/tool_registry.dart';
import 'tool_run_context.dart';

/// 一次工具调用在执行管线中的上下文。
///
/// 不可变：拦截器通过 `with*` 方法产出新实例再交给下游，便于测试断言
/// 每一环看到的输入，也避免多个拦截器共享可变状态。
final class ToolInvocation {
  const ToolInvocation({
    required this.call,
    required this.registration,
    required this.context,
    this.approvalDetails,
    this.executionArguments,
  });

  /// 模型发出的原始调用；[ToolCall.arguments] 是模型给出的参数，
  /// 审批、风险评估与回滚都基于它。
  final ToolCall call;

  /// 当前能力目录中的注册项；未注册时为 null。
  ///
  /// 默认管线由 `UnknownToolGuard` 位于链首负责短路，其后的拦截器通过
  /// [resolved] 读取非空注册项。
  final ToolRegistration? registration;

  /// 审批配置与执行器桥接（事件、取消、暂停）。
  final ToolRunContext context;

  /// 设备变更类工具的预览详情，仅用于审批展示，不进入执行参数。
  final Map<String, dynamic>? approvalDetails;

  /// 授权后实际交给执行器的参数；未改写时为 null，使用模型原始参数。
  final Map<String, dynamic>? executionArguments;

  /// 交给执行器的参数。
  Map<String, dynamic> get arguments => executionArguments ?? call.arguments;

  /// 已确认存在的注册项。在 `UnknownToolGuard` 之前调用属于管线装配错误。
  ToolRegistration get resolved {
    final value = registration;
    if (value == null) {
      throw StateError(
        '工具 ${call.name} 未注册：UnknownToolGuard 必须位于管线首位',
      );
    }
    return value;
  }

  /// 执行器声明的动作级审批能力；普通工具返回 null。
  ///
  /// [ToolApprovalGate] 与 [ToolExecutor] 没有子类型关系，`is` 无法提升类型，
  /// 这里用模式绑定取得带类型的引用。
  ToolApprovalGate? get approvalGate => switch (registration?.executor) {
        final ToolApprovalGate gate => gate,
        _ => null,
      };

  ToolInvocation withApprovalDetails(Map<String, dynamic>? details) =>
      ToolInvocation(
        call: call,
        registration: registration,
        context: context,
        approvalDetails: details,
        executionArguments: executionArguments,
      );

  ToolInvocation withExecutionArguments(Map<String, dynamic> arguments) =>
      ToolInvocation(
        call: call,
        registration: registration,
        context: context,
        approvalDetails: approvalDetails,
        executionArguments: arguments,
      );
}
