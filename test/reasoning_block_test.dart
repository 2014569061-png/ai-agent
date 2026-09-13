import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/chat/widgets/reasoning_block.dart';
import 'package:mobile_agent/presentation/markdown/math_block.dart';

void main() {
  testWidgets('does not build markdown until reasoning is expanded',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ReasoningCompactBlock(reasoning: '**reasoning**'),
      ),
    ));

    expect(find.byType(MathMarkdown), findsNothing);
    await tester.tap(find.text('已思考'));
    await tester.pumpAndSettle();
    expect(find.byType(MathMarkdown), findsOneWidget);
  });

  testWidgets('uses plain selectable text while streaming', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ReasoningCompactBlock(
          reasoning: '**reasoning**',
          streaming: true,
        ),
      ),
    ));

    await tester.tap(find.text('正在思考…'));
    await tester.pumpAndSettle();
    expect(find.byType(MathMarkdown), findsNothing);
    expect(find.byType(SelectableText), findsOneWidget);
  });
}
