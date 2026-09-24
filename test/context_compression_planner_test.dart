import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/context_compression_planner.dart';
import 'package:mobile_agent/domain/context_insights.dart';
import 'package:mobile_agent/domain/models.dart';

void main() {
  test('suggests the largest tool results when context is over budget', () {
    final plan = const ContextCompressionPlanner().plan(
      contextWindow: 1000,
      targetTokens: 0,
      messages: [
        ChatMessage(
          role: MessageRole.user,
          parts: [const MessagePart.text('请分析结果')],
        ),
        ChatMessage(
          role: MessageRole.tool,
          toolCallId: 'large-result',
          parts: [MessagePart.text('x' * 4000)],
        ),
        ChatMessage(
          role: MessageRole.tool,
          toolCallId: 'small-result',
          parts: [MessagePart.text('y' * 800)],
        ),
        ChatMessage(
          role: MessageRole.user,
          parts: [const MessagePart.text('继续')],
        ),
      ],
    );

    expect(plan.budgetLevel, ContextBudgetLevel.critical);
    expect(plan.shouldSuggest, isTrue);
    expect(plan.candidateCount, 2);
    expect(
        plan.candidates.first.type, ContextCompressionCandidateType.toolResult);
    expect(
      plan.candidates.first.estimatedTokens,
      greaterThan(plan.candidates.last.estimatedTokens),
    );
    expect(plan.estimatedSavings, greaterThan(900));
    expect(plan.projectedTokens, lessThan(plan.currentTokens));
  });

  test('reserved output capacity participates in planner severity', () {
    final plan = const ContextCompressionPlanner().plan(
      contextWindow: 1000,
      reservedOutputTokens: 200,
      messages: [
        ChatMessage(
          role: MessageRole.tool,
          toolCallId: 'stable-id',
          parts: [MessagePart.text('x' * 2700)],
        ),
      ],
    );

    expect(plan.currentTokens, greaterThan(150));
    expect(plan.budgetLevel, ContextBudgetLevel.warning);
    expect(plan.shouldSuggest, isTrue);
  });

  test('does not select tool results without a stable call id', () {
    final plan = const ContextCompressionPlanner().plan(
      contextWindow: 100,
      targetTokens: 0,
      messages: [
        ChatMessage(
          role: MessageRole.tool,
          parts: [MessagePart.text('x' * 1000)],
        ),
      ],
    );

    expect(plan.candidateCount, 0);
    expect(plan.candidates, isEmpty);
  });
  test('does not suggest compression for normal or user-only history', () {
    final normal = const ContextCompressionPlanner().plan(
      contextWindow: 10000,
      messages: [
        ChatMessage(
          role: MessageRole.tool,
          toolCallId: 'small',
          parts: [const MessagePart.text('short result')],
        ),
      ],
    );
    final userOnly = const ContextCompressionPlanner().plan(
      contextWindow: 1000,
      messages: [
        ChatMessage(
          role: MessageRole.user,
          parts: [MessagePart.text('x' * 4000)],
        ),
      ],
    );

    expect(normal.shouldSuggest, isFalse);
    expect(userOnly.budgetLevel, ContextBudgetLevel.critical);
    expect(userOnly.candidates, isEmpty);
    expect(userOnly.shouldSuggest, isFalse);
  });

  group('planForConversation', () {
    test('folds in live tool results that are not persisted yet', () {
      final plan = const ContextCompressionPlanner().planForConversation(
        contextWindow: 1000,
        messages: [
          ChatMessage(
            role: MessageRole.user,
            parts: [const MessagePart.text('请分析结果')],
          ),
        ],
        liveToolResults: [
          ToolResultRef(toolCallId: 'live-result', result: 'x' * 4000),
        ],
      );

      expect(plan.shouldSuggest, isTrue);
      expect(plan.candidateCount, 1);
      expect(plan.candidates.single.toolCallId, 'live-result');
    });

    test('does not double count a result already persisted as a message', () {
      final plan = const ContextCompressionPlanner().planForConversation(
        contextWindow: 1000,
        messages: [
          ChatMessage(
            role: MessageRole.tool,
            toolCallId: 'persisted',
            parts: [MessagePart.text('x' * 4000)],
          ),
        ],
        liveToolResults: [
          ToolResultRef(toolCallId: 'persisted', result: 'y' * 4000),
        ],
      );

      expect(plan.candidateCount, 1, reason: '同一 toolCallId 的运行时结果不应生成第二个候选');
      expect(plan.candidates.single.toolCallId, 'persisted');
    });

    test('ignores blank live tool results', () {
      final plan = const ContextCompressionPlanner().planForConversation(
        contextWindow: 1000,
        messages: [
          ChatMessage(
            role: MessageRole.tool,
            toolCallId: 'big',
            parts: [MessagePart.text('x' * 4000)],
          ),
        ],
        liveToolResults: const [
          ToolResultRef(toolCallId: 'blank', result: '   '),
        ],
      );

      expect(plan.candidateCount, 1);
      expect(plan.candidates.single.toolCallId, 'big');
    });
  });
}
