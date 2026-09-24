import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/context_insights.dart';
import 'package:mobile_agent/presentation/chat/widgets/context_budget_bar.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SizedBox(width: 320, child: child)),
      );

  testWidgets('renders used, reserved output and remaining capacity',
      (tester) async {
    await tester.pumpWidget(wrap(ContextBudgetBar.fromParts(
      parts: const [
        ContextPart(type: ContextPartType.user, tokens: 20000),
      ],
      limit: 32000,
      reservedOutputTokens: 2048,
    )));

    expect(find.byType(ContextBudgetBar), findsOneWidget);
    expect(find.byKey(const ValueKey('context-output-reserved-segment')),
        findsOneWidget);
    expect(find.byType(Expanded), findsNWidgets(3));
  });

  testWidgets('omits the reserved segment when reservation is zero',
      (tester) async {
    await tester.pumpWidget(wrap(const ContextBudgetBar(
      segments: [
        ContextBudgetSegment(tokens: 20, color: Colors.blue),
      ],
      limit: 32,
    )));

    expect(find.byKey(const ValueKey('context-output-reserved-segment')),
        findsNothing);
    expect(find.byType(Expanded), findsNWidgets(2));
  });
}
