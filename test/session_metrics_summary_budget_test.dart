import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/context_insights.dart';
import 'package:mobile_agent/domain/session_metrics.dart';
import 'package:mobile_agent/presentation/chat/widgets/context_budget_bar.dart';
import 'package:mobile_agent/presentation/chat/widgets/session_metrics_summary.dart';

void main() {
  testWidgets('summary preserves input, output reserve and free capacity',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 320,
                child: SessionMetricsSummary(
                    metrics: SessionMetrics.empty,
                    used: 343,
                    limit: 256000,
                    reserved: 2048,
                    timing: TimingSnapshot.empty)))));
    final bar = tester.widget<ContextBudgetBar>(find.byType(ContextBudgetBar));
    expect(bar.segments.single.tokens, 343);
    expect(bar.reservedOutputTokens, 2048);
    expect(bar.limit, 256000);
    expect(find.text('≈1%'), findsOneWidget);
    final segments = tester
        .widgetList<Expanded>(find.descendant(
            of: find.byType(ContextBudgetBar), matching: find.byType(Expanded)))
        .toList();
    expect(segments.map((e) => e.flex), [343, 2048, 253609]);
    final reserveWidth = tester
        .getSize(find.byKey(const ValueKey('context-output-reserved-segment')))
        .width;
    expect(reserveWidth, closeTo(320 * 2048 / 256000, 0.01));
  });

  testWidgets('empty-input fallback has an explicit neutral track',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: ContextBudgetBar(
                segments: [],
                limit: 256000,
                reservedOutputTokens: 2048,
                fallbackRatio: 0.008))));
    final progress = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(progress.value, 0.008);
    expect(progress.backgroundColor, isNotNull);
    expect(progress.backgroundColor, isNot(progress.valueColor!.value));
  });

  testWidgets('unreported metrics are not displayed as measured zero',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SessionMetricsSummary(
                metrics: SessionMetrics.empty,
                used: 0,
                limit: 0,
                reserved: 0,
                timing: TimingSnapshot.empty))));
    expect(find.text('未知'), findsOneWidget);
    expect(find.text('未记录'), findsNWidgets(3));
    expect(find.byType(ContextBudgetBar), findsNothing);
  });
}
