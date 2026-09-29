import '../../domain/context_insights.dart';
import '../../domain/models.dart';
import '../context_snapshot_builder.dart';
import '../context_window.dart';

/// 一次运行中每步请求共享的固定形状：工具目录、输出预留与历史裁剪窗口。
class RequestShape {
  RequestShape._(this.tools, this.reservedOutputTokens, this.contextWindow);

  /// 工具定义也占模型输入窗口；历史裁剪必须先扣除这部分固定成本，
  /// 并为本次模型输出预留 [requestedOutputTokens]，避免输入与输出合计超过窗口。
  ///
  /// 工具定义数组是 Provider 前缀缓存的一部分（Anthropic 还显式在 tools
  /// 段打缓存断点）。目录按装配顺序生成（内置/MCP/插件/工作区），装配顺序
  /// 受运行环境影响；这里按名称稳定排序，保证同一份工具目录在整个运行期
  /// 的每一步请求中字节级一致，不因装配差异打爆前缀缓存。
  factory RequestShape.resolve({
    required Iterable<UnifiedTool> manifests,
    required bool toolsEnabled,
    required int contextBudgetTokens,
    required int requestedOutputTokens,
  }) {
    final tools = toolsEnabled
        ? (manifests.toList()..sort((a, b) => a.name.compareTo(b.name)))
        : const <UnifiedTool>[];
    final reserved = ContextBudget.outputReservationFor(
      contextWindow: contextBudgetTokens,
      requestedOutputTokens: requestedOutputTokens,
    );
    final window = ContextWindow(
      maxTokens: ContextBudget.inputBudgetFor(
        contextWindow: contextBudgetTokens,
        reservedOutputTokens: reserved,
      ),
      fixedTokens: ContextSnapshotBuilder.estimateToolTokens(tools),
    );
    return RequestShape._(tools, reserved, window);
  }

  final List<UnifiedTool> tools;
  final int reservedOutputTokens;

  /// 每步请求前裁剪一次，同时约束初始历史与多步工具循环中持续追加的工具结果。
  final ContextWindow contextWindow;
}
