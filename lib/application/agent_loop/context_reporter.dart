import '../../domain/context_insights.dart';
import '../../domain/models.dart';
import '../agent_executor.dart'
    show
        AgentContextChangeEvent,
        AgentEvent,
        ContextBudgetWarningEvent,
        ContextSnapshotEvent;
import '../context_snapshot_builder.dart';
import '../context_window.dart';
import '../history_compactor.dart';

/// 每步请求前的上下文观测：快照、预算告警、与上一步相比的变化。
///
/// 只读消息列表，不参与模型输入；跨步保存上一份快照与压缩状态。
class ContextReporter {
  ContextReporter({
    required this.tools,
    required this.contextWindow,
    required this.reservedOutputTokens,
  });

  final List<UnifiedTool> tools;
  final int contextWindow;
  final int reservedOutputTokens;

  ContextSnapshot? _previous;
  var _wasCompressed = false;

  List<AgentEvent> report(int step, List<ChatMessage> messages) {
    final snapshot = ContextSnapshotBuilder.build(
      messages: messages,
      tools: tools,
      contextWindow: contextWindow,
      reservedOutputTokens: reservedOutputTokens,
    );
    final anchorMessageId = messages.reversed
        .where((message) => message.role != MessageRole.system)
        .map((message) => message.id)
        .whereType<String>()
        .firstOrNull;
    final compressed = messages.any((message) =>
        message.text.contains(ContextWindow.compactionNotice) ||
        message.text.startsWith(HistoryCompactor.summaryMark));
    final events = <AgentEvent>[
      ContextSnapshotEvent(
        step: step,
        snapshot: snapshot,
        anchorMessageId: anchorMessageId,
      ),
      if (snapshot.budgetLevel != ContextBudgetLevel.normal)
        ContextBudgetWarningEvent(
          level: snapshot.budgetLevel,
          usedTokens: snapshot.usedTokens,
          contextWindow: snapshot.contextWindow,
          remainingTokens: snapshot.remainingTokens,
          dominantPart: snapshot.dominantPart?.type.name,
        ),
      ...contextChanges(
        step: step,
        previous: _previous,
        current: snapshot,
        compressed: compressed,
        wasCompressed: _wasCompressed,
      ),
    ];
    _wasCompressed = compressed;
    _previous = snapshot;
    return events;
  }

  static List<AgentContextChangeEvent> contextChanges({
    required int step,
    required ContextSnapshot? previous,
    required ContextSnapshot current,
    required bool compressed,
    required bool wasCompressed,
  }) {
    if (previous == null) {
      return compressed
          ? [
              AgentContextChangeEvent(
                step: step,
                kind: 'context_compress',
                category: 'history',
                deltaTokens: 0,
              ),
            ]
          : const [];
    }
    final events = <AgentContextChangeEvent>[];
    for (final type in ContextPartType.values) {
      final before = previous.tokensFor(type);
      final after = current.tokensFor(type);
      final delta = after - before;
      if (delta == 0) continue;
      events.add(AgentContextChangeEvent(
        step: step,
        kind: delta > 0 ? 'context_inject' : 'context_prune',
        category: type.name,
        deltaTokens: delta,
      ));
    }
    if (compressed && !wasCompressed) {
      events.add(AgentContextChangeEvent(
        step: step,
        kind: 'context_compress',
        category: 'history',
        deltaTokens: current.usedTokens - previous.usedTokens,
      ));
    }
    return events;
  }
}
