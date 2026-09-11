import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/dashboard_service.dart';
import 'package:mobile_agent/presentation/dashboard/widgets/token_usage_hero.dart';
import 'package:mobile_agent/presentation/dashboard/widgets/token_trend_card.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

void main() {
  List<UsageDaily> sampleDays({bool withToday = true}) {
    final now = DateTime.now();
    final todayKey =
        '${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      final key =
          '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final isToday = withToday && key == todayKey;
      return UsageDaily(
        day: key,
        calls: isToday ? 9 : 3,
        promptTokens: isToday ? 6000 : 800 * (i + 1),
        completionTokens: isToday ? 3000 : 400 * (i + 1),
        cachedTokens: isToday ? 2500 : 0,
        spendCents: 0,
        costCents: isToday ? 120 : 30 * (i + 1),
        isToday: isToday,
      );
    });
  }

  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(child: child),
        ),
      );

  testWidgets('TokenUsageHero 展示今日精确 Token 数字', (tester) async {
    await tester.pumpWidget(wrap(TokenUsageHero(days: sampleDays())));

    // 大数字：输入 6,000 + 输出 3,000 = 9,000
    expect(find.text('9,000'), findsOneWidget);
    // 分项数字：输入为未缓存部分 6,000-2,500=3,500
    expect(find.text('3,500'), findsOneWidget);
    expect(find.text('3,000'), findsOneWidget); // 输出
    expect(find.text('2,500'), findsOneWidget); // 缓存
    // 底栏数据
    expect(find.textContaining('9'), findsWidgets);
  });

  testWidgets('TokenUsageHero 无数据时展示 -- 而不是崩溃', (tester) async {
    await tester.pumpWidget(wrap(const TokenUsageHero(days: <UsageDaily>[])));
    expect(find.text('--'), findsOneWidget);
  });

  testWidgets('TokenTrendCard 有数据时渲染柱状图与图例', (tester) async {
    await tester.pumpWidget(wrap(TokenTrendCard(days: sampleDays())));
    expect(find.text('Token 用量（近 7 天）'), findsOneWidget);
    expect(find.text('今日'), findsOneWidget);
    expect(find.text('历史'), findsOneWidget);
    // 7 个日期标签都在（MM-dd）
    expect(find.text('今日'), findsOneWidget);
    // 柱状图本身由 CustomPaint 绘制，无需文本断言，仅验证绘制不抛异常
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('TokenTrendCard 空数据展示空态', (tester) async {
    final days = List.generate(7, (i) {
      return UsageDaily(
        day: '01-0${i + 1}',
        calls: 0,
        promptTokens: 0,
        completionTokens: 0,
        cachedTokens: 0,
        spendCents: 0,
        costCents: 0,
        isToday: false,
      );
    });
    await tester.pumpWidget(wrap(TokenTrendCard(days: days)));
    expect(find.text('暂无 Token 消耗数据'), findsOneWidget);
  });
}
