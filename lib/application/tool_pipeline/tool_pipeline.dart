import '../../domain/tool_result.dart';
import 'tool_invocation.dart';

/// 把调用交给下游（下一个拦截器或终点）。
typedef ToolNext = Future<ToolResult> Function(ToolInvocation invocation);

/// 工具执行管线中的一环（中间件）。
///
/// 可以：直接返回失败结果短路下游；改写调用上下文后调用 [ToolNext]；
/// 或包裹 `next` 对结果做后处理。借鉴 DeepSeek Harness 的
/// `tools/pre-execute → execute → post-execute` 瀑布事件：需要放行时
/// 必须显式调用 `next`。
abstract interface class ToolInterceptor {
  /// 稳定标识，用于装配校验与诊断。
  String get id;

  Future<ToolResult> intercept(ToolInvocation invocation, ToolNext next);
}

/// 按装配顺序串联 [ToolInterceptor]，最终交给终点执行。
final class ToolPipeline {
  ToolPipeline(Iterable<ToolInterceptor> interceptors)
      : interceptors = List.unmodifiable(interceptors) {
    final seen = <String>{};
    for (final interceptor in this.interceptors) {
      if (!seen.add(interceptor.id)) {
        throw ArgumentError.value(
          interceptor.id,
          'interceptors',
          '拦截器 id 重复',
        );
      }
    }
  }

  final List<ToolInterceptor> interceptors;

  /// 依次经过全部拦截器，最终交给 [terminal] 执行。
  Future<ToolResult> run(ToolInvocation invocation, ToolNext terminal) {
    var next = terminal;
    for (final interceptor in interceptors.reversed) {
      final downstream = next;
      next = (current) => interceptor.intercept(current, downstream);
    }
    return next(invocation);
  }
}
