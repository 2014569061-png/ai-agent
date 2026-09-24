import 'dart:math' as math;

import '../domain/models.dart';
import 'context_compression_planner.dart';
import 'context_window.dart';

class ContextCompressionResult {
  const ContextCompressionResult({
    required this.messages,
    required this.appliedCandidates,
    required this.originalTokens,
    required this.compressedTokens,
  });

  final List<ChatMessage> messages;
  final List<ContextCompressionCandidate> appliedCandidates;
  final int originalTokens;
  final int compressedTokens;

  int get savedTokens => math.max(0, originalTokens - compressedTokens);
}

/// Applies only a previously approved plan. User and assistant messages are
/// never candidates, and a stale index/tool id is ignored rather than applied
/// to a different message.
class ContextCompressionApplier {
  const ContextCompressionApplier();

  ContextCompressionResult apply(
    List<ChatMessage> messages,
    ContextCompressionPlan plan,
  ) {
    final byIndex = <int, ContextCompressionCandidate>{
      for (final candidate in plan.candidates)
        candidate.messageIndex: candidate,
    };
    final applied = <ContextCompressionCandidate>[];
    final output = <ChatMessage>[];
    var originalTokens = 0;
    var compressedTokens = 0;

    for (var index = 0; index < messages.length; index++) {
      final message = messages[index];
      originalTokens += ContextWindow.estimateTokens(message);
      final candidate = byIndex[index];
      final matches = candidate != null &&
          candidate.type == ContextCompressionCandidateType.toolResult &&
          message.role == MessageRole.tool &&
          (candidate.toolCallId == null ||
              candidate.toolCallId == message.toolCallId);
      if (!matches) {
        output.add(message);
        compressedTokens += ContextWindow.estimateTokens(message);
        continue;
      }

      final compressed = message.copyWith(
        parts: [
          const MessagePart.text(
            '${ContextWindow.compressedToolResultMark}\n'
            '原始工具结果仍保留在会话历史中；需要细节时请重新读取或重新执行工具。',
          ),
        ],
      );
      final compressedMessageTokens = ContextWindow.estimateTokens(compressed);
      if (compressedMessageTokens >= ContextWindow.estimateTokens(message)) {
        output.add(message);
        compressedTokens += ContextWindow.estimateTokens(message);
        continue;
      }
      output.add(compressed);
      compressedTokens += compressedMessageTokens;
      applied.add(candidate);
    }

    return ContextCompressionResult(
      messages: List.unmodifiable(output),
      appliedCandidates: List.unmodifiable(applied),
      originalTokens: originalTokens,
      compressedTokens: compressedTokens,
    );
  }

  ContextCompressionResult applyToolCallIds(
    List<ChatMessage> messages,
    Set<String> toolCallIds,
  ) {
    final candidates = <ContextCompressionCandidate>[];
    for (var index = 0; index < messages.length; index++) {
      final message = messages[index];
      if (message.role != MessageRole.tool ||
          message.toolCallId == null ||
          !toolCallIds.contains(message.toolCallId)) {
        continue;
      }
      candidates.add(ContextCompressionCandidate(
        messageIndex: index,
        type: ContextCompressionCandidateType.toolResult,
        estimatedTokens: ContextWindow.estimateTokens(message),
        toolCallId: message.toolCallId,
      ));
    }
    final currentTokens = messages.fold<int>(
      0,
      (total, message) => total + ContextWindow.estimateTokens(message),
    );
    return apply(
      messages,
      ContextCompressionPlan(
        currentTokens: currentTokens,
        contextWindow: currentTokens,
        targetTokens: 0,
        candidateCount: candidates.length,
        candidates: candidates,
      ),
    );
  }
}
