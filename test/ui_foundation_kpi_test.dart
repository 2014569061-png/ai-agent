import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/dashboard_service.dart';
import 'package:mobile_agent/presentation/dashboard/widgets/kpi_card_grid.dart';
import 'package:mobile_agent/presentation/theme/app_appearance_controller.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/theme/desktop_theme.dart';
import 'package:mobile_agent/presentation/widgets/nexus_metric_tile.dart';

const _kpis = DashboardKpis(
  todayConversations: 987654,
  todayTokens: 10000,
  todayPromptTokens: 10000,
  todayCachedTokens: 10000,
  runningTasks: 12345,
  taskSuccessRate: 100,
  weeklyHelpfulTasks: 999999,
  taskFeedbackRate: 100,
  taskFeedbackSamples: 999999,
);

void main() {
  late double previous;
  setUp(() {
    previous = AppAppearanceController.glassIntensity.value;
    AppAppearanceController.glassIntensity.value = 0;
  });
  tearDown(() => AppAppearanceController.glassIntensity.value = previous);
  Future<void> pump(WidgetTester tester, double width, double scale, bool dark,
      {bool desktop = false, Widget? child}) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var theme = dark ? AppTheme.dark() : AppTheme.light();
    if (desktop) theme = DesktopTheme.apply(theme);
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      builder: (context, content) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: content!,
      ),
      home: Scaffold(
          body: SingleChildScrollView(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: child ?? const KpiCardGrid(kpis: _kpis)),
      )),
    ));
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    for (final width in [320.0, 360.0, 411.0]) {
      for (final scale in [1.0, 1.3, 1.6, 2.0]) {
        testWidgets('KPI fits dark=$dark width=$width scale=$scale',
            (tester) async {
          await pump(tester, width, scale, dark);
          expect(find.byType(NexusMetricGrid), findsOneWidget);
          expect(find.byType(NexusMetricTile), findsNWidgets(6));
          for (final element in find.byType(NexusMetricTile).evaluate()) {
            final rect = tester.getRect(find.byWidget(element.widget));
            expect(rect.left, greaterThanOrEqualTo(16));
            expect(rect.right, lessThanOrEqualTo(width - 16 + .01));
            if (scale >= 1.6) expect(rect.width, closeTo(width - 32, .01));
          }
          expect(find.text('100%'), findsNWidgets(3));
          expect(find.text('999999'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
    testWidgets('metric long label and unit wrap dark=$dark', (tester) async {
      await pump(tester, 320, 2, dark,
          child: const NexusMetricTile(
            label: '缓存命中率和完整用户评价样本说明',
            value: '100%',
            unit: '来自最近累计999999条用户评价样本',
            explanation: '完整指标说明，不缩字不删单位',
            icon: Icons.info_outline,
          ));
      expect(find.text('来自最近累计999999条用户评价样本'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('desktop KPI preserves two-column layout', (tester) async {
    await pump(tester, 1000, 1, false, desktop: true);
    expect(find.byType(NexusMetricGrid), findsNothing);
    final tiles = find.byType(NexusMetricTile);
    expect(
        tester.getRect(tiles.at(0)).width, closeTo((1000 - 32 - 12) / 2, .01));
    expect(tester.getRect(tiles.at(0)).top, tester.getRect(tiles.at(1)).top);
    expect(tester.takeException(), isNull);
  });
}
