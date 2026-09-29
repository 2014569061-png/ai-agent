import '../../domain/tool_codes.dart';
import '../../domain/tool_result.dart';
import '../../infrastructure/tools/schema_validator.dart';
import '../context_window.dart';
import 'tool_invocation.dart';
import 'tool_pipeline.dart';

/// 默认前置守卫，顺序即短路优先级：未注册 → 参数截断 → schema → 预览计划。
List<ToolInterceptor> defaultToolPreflightGuards() => const [
      UnknownToolGuard(),
      TruncatedArgumentsGuard(),
      SchemaValidationGuard(),
      PreviewPlanGuard(),
    ];

/// 工具不在当前能力目录中时短路。必须位于管线首位。
final class UnknownToolGuard implements ToolInterceptor {
  const UnknownToolGuard();

  @override
  String get id => 'unknown-tool';

  @override
  Future<ToolResult> intercept(ToolInvocation invocation, ToolNext next) {
    if (invocation.registration == null) {
      return Future.value(ToolResult.failure(
        code: ToolCodes.unknownTool,
        message: '工具未注册：${invocation.call.name}，请改用当前能力目录中的工具',
      ));
    }
    return next(invocation);
  }
}

/// 参数未能解析或被上下文裁剪截断时短路，避免用残缺参数产生副作用。
final class TruncatedArgumentsGuard implements ToolInterceptor {
  const TruncatedArgumentsGuard();

  @override
  String get id => 'truncated-arguments';

  @override
  Future<ToolResult> intercept(ToolInvocation invocation, ToolNext next) {
    final arguments = invocation.arguments;
    if (arguments.containsKey('_unparsed') ||
        arguments.containsKey(ContextWindow.truncatedArgumentMark)) {
      return Future.value(ToolResult.failure(
        code: ToolCodes.truncatedToolCall,
        message: '工具参数不完整或超过上下文上限，本次未执行，请重新生成完整参数',
      ));
    }
    return next(invocation);
  }
}

/// 按注册项的 JSON Schema 校验参数。
final class SchemaValidationGuard implements ToolInterceptor {
  const SchemaValidationGuard();

  static const _validator = SchemaValidator();

  @override
  String get id => 'schema-validation';

  @override
  Future<ToolResult> intercept(ToolInvocation invocation, ToolNext next) {
    final validation = _validator.validate(
      invocation.arguments,
      invocation.resolved.spec.parametersSchema,
    );
    if (!validation.isValid) {
      return Future.value(ToolResult.failure(
        code: ToolCodes.invalidArguments,
        message: '工具参数校验失败：${validation.error}',
      ));
    }
    return next(invocation);
  }
}

/// 设备变更类工具必须引用有效预览；通过时把预览详情放进调用上下文，
/// 供审批展示使用（不会进入执行参数）。
final class PreviewPlanGuard implements ToolInterceptor {
  const PreviewPlanGuard();

  @override
  String get id => 'preview-plan';

  @override
  Future<ToolResult> intercept(ToolInvocation invocation, ToolNext next) {
    final gate = invocation.approvalGate;
    if (gate == null) return next(invocation);
    final arguments = invocation.arguments;
    final details = gate.approvalDetailsFor(arguments);
    if (gate.requiresPreviewPlan(arguments) && details == null) {
      return Future.value(ToolResult.failure(
        code: ToolCodes.invalidArguments,
        message: '该设备变更没有匹配的有效预览，请先生成预览再请求执行',
      ));
    }
    return next(invocation.withApprovalDetails(details));
  }
}
