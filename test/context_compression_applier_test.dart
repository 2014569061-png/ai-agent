import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/context_compression_applier.dart';
import 'package:mobile_agent/application/context_compression_planner.dart';
import 'package:mobile_agent/application/context_window.dart';
import 'package:mobile_agent/domain/models.dart';

void main() {
  test('compresses approved tool results without changing user messages', () {
    final originalResult = 'secret detail ' * 500;
    final messages = [
      ChatMessage(
        role: MessageRole.user,
        parts: const [MessagePart.text('请分析')],
      ),
      ChatMessage(
        role: MessageRole.tool,
        toolCallId: 'call-1',
        parts: [MessagePart.text(originalResult)],
      ),
      ChatMessage(
        role: MessageRole.user,
        parts: const [MessagePart.text('继续')],
      ),
    ];
    final plan = const ContextCompressionPlanner().plan(
      contextWindow: 1000,
      targetTokens: 0,
      messages: messages,
    );

    final result = const ContextCompressionApplier().apply(messages, plan);

    expect(result.appliedCandidates, hasLength(1));
    expect(result.savedTokens, greaterThan(0));
    expect(result.messages, hasLength(messages.length));
    expect(result.messages[0].text, '请分析');
    expect(result.messages[2].text, '继续');
    expect(result.messages[1].role, MessageRole.tool);
    expect(result.messages[1].toolCallId, 'call-1');
    expect(
      result.messages[1].text,
      contains(ContextWindow.compressedToolResultMark),
    );
    expect(result.messages[1].text, isNot(contains(originalResult)));
    expect(messages[1].text, originalResult);
  });

  test('ignores stale candidates instead of compressing a different message', () {
    final messages = [
      ChatMessage(
        role: MessageRole.user,
        parts: const [MessagePart.text('新的内容')],
      ),
    ];
    final plan = const ContextCompressionPlan(
      currentTokens: 1000,
      contextWindow: 1000,
      targetTokens: 700,
      candidateCount: 1,
      candidates: [
        ContextCompressionCandidate(
          messageIndex: 0,
          type: ContextCompressionCandidateType.toolResult,
          estimatedTokens: 500,
        ),
      ],
    );

    final result = const ContextCompressionApplier().apply(messages, plan);

    expect(result.appliedCandidates, isEmpty);
    expect(result.messages.single.text, '新的内容');
  });
}
