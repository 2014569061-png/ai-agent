import 'dart:math' as math;

import '../domain/context_insights.dart';
import '../domain/models.dart';
import 'context_window.dart';

enum ContextCompressionCandidateType { toolResult }

extension ContextCompressionCandidateTypeX on ContextCompressionCandidateType {
  String get label => switch (this) {
        ContextCompressionCandidateType.toolResult => '工具结果',
      };
}

/// One safe-to-review target. The planner never mutates the associated message.
class ContextCompressionCandidate {
  const ContextCompressionCandidate({
    required this.messageIndex,
    required this.type,
    required this.estimatedTokens,
    this.toolCallId,
  });

  final int messageIndex;
  final ContextCompressionCandidateType type;
  final int estimatedTokens;
  final String? toolCallId;
}

/// A tool result that only exists as a live tool activity and has not been
/// persisted as a tool message yet.
///
/// Callers translate their own activity model into this neutral shape so the
/// planner stays independent of the chat layer.
class ToolResultRef {
  const ToolResultRef({required this.toolCallId, required this.result});

  final String toolCallId;
  final String result;
}

/// A user-reviewable compression proposal. It is deliberately data-only so a
/// later approval flow can apply it and record an audit event separately.
class ContextCompressionPlan {
  const ContextCompressionPlan({
    required this.currentTokens,
    required this.contextWindow,
    required this.targetTokens,
    required this.candidateCount,
    required this.candidates,
    this.reservedOutputTokens = 0,
  });

  /// Current input estimate, including any fixed prompt/tool tokens supplied
  /// by the caller. It does not include the reserved completion budget.
  final int currentTokens;
  final int contextWindow;
  final int targetTokens;
  final int candidateCount;
  final List<ContextCompressionCandidate> candidates;
  final int reservedOutputTokens;

  ContextBudgetLevel get budgetLevel => ContextBudget.levelFor(
        usedTokens: currentTokens,
        contextWindow: contextWindow,
        reservedOutputTokens: reservedOutputTokens,
      );

  bool get shouldSuggest =>
      candidates.isNotEmpty &&
      (budgetLevel == ContextBudgetLevel.warning ||
          budgetLevel == ContextBudgetLevel.critical);

  int get estimatedSavings => candidates.fold(
        0,
        (total, candidate) => total + candidate.estimatedTokens,
      );

  int get projectedTokens => math.max(0, currentTokens - estimatedSavings);
}

/// Finds reversible, user-reviewable compression targets without changing the
/// conversation. Tool results are the first target because they can usually be
/// re-read from the workspace or fetched again when needed.
class ContextCompressionPlanner {
  const ContextCompressionPlanner({this.minCandidateTokens = 64});

  final int minCandidateTokens;

  /// Plans against the live conversation, folding in tool results that are only
  /// present as running tool activities.
  ///
  /// The metrics sheet and the HUD shortcut both go through here so the user
  /// always reviews an identical candidate set regardless of entry point.
  ContextCompressionPlan planForConversation({
    required List<ChatMessage> messages,
    required Iterable<ToolResultRef> liveToolResults,
    required int contextWindow,
    int fixedTokens = 0,
    int reservedOutputTokens = 0,
    int? targetTokens,
  }) {
    final persistedToolIds = messages
        .where((message) => message.role == MessageRole.tool)
        .map((message) => message.toolCallId)
        .whereType<String>()
        .toSet();
    final merged = <ChatMessage>[
      ...messages,
      for (final toolResult in liveToolResults)
        if (toolResult.result.trim().isNotEmpty &&
            !persistedToolIds.contains(toolResult.toolCallId))
          ChatMessage(
            role: MessageRole.tool,
            toolCallId: toolResult.toolCallId,
            parts: [MessagePart.text(toolResult.result)],
          ),
    ];
    return plan(
      messages: merged,
      contextWindow: contextWindow,
      fixedTokens: fixedTokens,
      reservedOutputTokens: reservedOutputTokens,
      targetTokens: targetTokens,
    );
  }

  ContextCompressionPlan plan({
    required List<ChatMessage> messages,
    required int contextWindow,
    int fixedTokens = 0,
    int reservedOutputTokens = 0,
    int? targetTokens,
  }) {
    final currentTokens = fixedTokens +
        messages.fold<int>(
          0,
          (total, message) => total + ContextWindow.estimateTokens(message),
        );
    final inputBudget = ContextBudget.inputBudgetFor(
      contextWindow: contextWindow,
      reservedOutputTokens: reservedOutputTokens,
    );
    final target = math.max(
      0,
      targetTokens ?? (inputBudget * ContextBudget.attentionThreshold).floor(),
    );
    final allCandidates = <ContextCompressionCandidate>[];
    for (var index = 0; index < messages.length; index++) {
      final message = messages[index];
      if (message.role != MessageRole.tool ||
          message.toolCallId?.trim().isNotEmpty != true) {
        continue;
      }
      final tokens = ContextWindow.estimateTokens(message);
      if (tokens < minCandidateTokens) continue;
      allCandidates.add(ContextCompressionCandidate(
        messageIndex: index,
        type: ContextCompressionCandidateType.toolResult,
        estimatedTokens: tokens,
        toolCallId: message.toolCallId,
      ));
    }
    allCandidates.sort(
      (a, b) => b.estimatedTokens.compareTo(a.estimatedTokens),
    );

    final level = ContextBudget.levelFor(
      usedTokens: currentTokens,
      contextWindow: contextWindow,
      reservedOutputTokens: reservedOutputTokens,
    );
    final canSuggest = level == ContextBudgetLevel.warning ||
        level == ContextBudgetLevel.critical;
    if (!canSuggest || currentTokens <= target) {
      return ContextCompressionPlan(
        currentTokens: currentTokens,
        contextWindow: contextWindow,
        targetTokens: target,
        candidateCount: allCandidates.length,
        candidates: const [],
        reservedOutputTokens: reservedOutputTokens,
      );
    }

    final selected = <ContextCompressionCandidate>[];
    var projected = currentTokens;
    for (final candidate in allCandidates) {
      selected.add(candidate);
      projected = math.max(0, projected - candidate.estimatedTokens);
      if (projected <= target) break;
    }
    return ContextCompressionPlan(
      currentTokens: currentTokens,
      contextWindow: contextWindow,
      targetTokens: target,
      candidateCount: allCandidates.length,
      candidates: List.unmodifiable(selected),
      reservedOutputTokens: reservedOutputTokens,
    );
  }
}
