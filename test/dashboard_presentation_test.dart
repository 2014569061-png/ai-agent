import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/application/dashboard_service.dart';
import 'package:mobile_agent/presentation/dashboard/dashboard_page.dart';
import 'package:mobile_agent/presentation/dashboard/dashboard_provider.dart';
import 'package:mobile_agent/presentation/dashboard/widgets/kpi_card_grid.dart';
import 'package:mobile_agent/presentation/dashboard/widgets/token_trend_card.dart';
import 'package:mobile_agent/presentation/dashboard/widgets/token_usage_hero.dart';
import 'package:mobile_agent/presentation/theme/app_appearance_controller.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/widgets/glass_scroll_edge.dart';
import 'package:mobile_agent/presentation/widgets/liquid_glass.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppAppearanceController.glassIntensity.value = 0.85;
  });

  testWidgets('dashboard defaults to a simple view and can reveal diagnostics',
      (tester) async {
    final summary = DashboardSummary(
      kpis: const DashboardKpis(
        todayConversations: 0,
        todayTokens: 0,
        todayCachedTokens: 0,
        runningTasks: 0,
        taskSuccessRate: null,
        weeklyHelpfulTasks: 0,
        taskFeedbackRate: null,
        taskFeedbackSamples: 0,
      ),
      weeklyUsage: List<UsageDaily>.generate(
        7,
        (index) => UsageDaily(
          day: '01-0${index + 1}',
          calls: 0,
          promptTokens: 0,
          completionTokens: 0,
          cachedTokens: 0,
          spendCents: 0,
          costCents: 0,
          isToday: index == 6,
        ),
      ),
      recentRuns: const [],
      todos: const [],
      recentConversations: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardSummaryProvider.overrideWith((ref) async => summary),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const DashboardPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('性能详情'), findsOneWidget);
    expect(find.byType(TokenUsageHero), findsNothing);
    expect(find.byType(LiquidGlass), findsAtLeastNWidgets(1));
    expect(find.byType(GlassScrollEdge), findsOneWidget);

    await tester.tap(find.text('性能详情'));
    await tester.pumpAndSettle();
    expect(find.byType(TokenUsageHero), findsOneWidget);
    expect(find.byType(KpiCardGrid), findsOneWidget);
    expect(find.byType(LiquidGlass), findsAtLeastNWidgets(7));
    await tester.scrollUntilVisible(
      find.byType(TokenTrendCard),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byType(TokenTrendCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
