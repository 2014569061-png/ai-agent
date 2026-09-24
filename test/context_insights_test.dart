import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/context_insights.dart';

void main() {
  group('ContextBudget', () {
    test('uses the documented budget thresholds', () {
      expect(
        ContextBudget.levelFor(usedTokens: 6999, contextWindow: 10000),
        ContextBudgetLevel.normal,
      );
      expect(
        ContextBudget.levelFor(usedTokens: 7000, contextWindow: 10000),
        ContextBudgetLevel.attention,
      );
      expect(
        ContextBudget.levelFor(usedTokens: 8500, contextWindow: 10000),
        ContextBudgetLevel.warning,
      );
      expect(
        ContextBudget.levelFor(usedTokens: 9500, contextWindow: 10000),
        ContextBudgetLevel.warning,
      );
      expect(
        ContextBudget.levelFor(usedTokens: 9501, contextWindow: 10000),
        ContextBudgetLevel.critical,
      );
    });

    test('treats an invalid window as unknown instead of warning', () {
      expect(
        ContextBudget.levelFor(usedTokens: 100, contextWindow: 0),
        ContextBudgetLevel.normal,
      );
      expect(
        ContextBudget.ratioFor(usedTokens: 100, contextWindow: 0),
        0,
      );
    });
  });

  test('reserves completion capacity in the input budget and ratio', () {
    expect(
      ContextBudget.inputBudgetFor(
        contextWindow: 10000,
        reservedOutputTokens: 2048,
      ),
      7952,
    );
    expect(
      ContextBudget.ratioFor(
        usedTokens: 7000,
        contextWindow: 10000,
        reservedOutputTokens: 2048,
      ),
      closeTo(0.9048, 0.0001),
    );
    expect(
      ContextBudget.levelFor(
        usedTokens: 7000,
        contextWindow: 10000,
        reservedOutputTokens: 2048,
      ),
      ContextBudgetLevel.warning,
    );
  });

  test('describes the dominant estimated context part and remaining budget',
      () {
    final snapshot = ContextSnapshot(
      parts: const [
        ContextPart(type: ContextPartType.system, tokens: 100),
        ContextPart(type: ContextPartType.tools, tokens: 200),
        ContextPart(type: ContextPartType.toolResult, tokens: 600),
      ],
      usedTokens: 900,
      contextWindow: 1000,
      reservedOutputTokens: 100,
      updatedAt: DateTime(2026),
    );

    expect(snapshot.budgetLevel, ContextBudgetLevel.critical);
    expect(snapshot.remainingTokens, 0);
    expect(snapshot.dominantPart?.type, ContextPartType.toolResult);
    expect(snapshot.dominantPart?.tokens, 600);
    expect(snapshot.hasEstimatedComposition, isTrue);
  });
}
