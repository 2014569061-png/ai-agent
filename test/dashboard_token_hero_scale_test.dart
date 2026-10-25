import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/dashboard_service.dart';
import 'package:mobile_agent/presentation/dashboard/widgets/token_usage_hero.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

/// 仪表盘「实时用量」环形座舱在窄屏 + 大字号下不得溢出。
///
/// 背景（2026-10-17 模拟器实测）：环形座舱是固定 `SizedBox(130,130)`，而环内
/// 四行文字随 `MediaQuery.textScalerOf` 放大。系统字号的放大倍数会被应用内
/// 「字体大小」偏好再乘一次（`app_presentation_preferences.dart`），所以在
/// 「应用特大 + 系统最大」≈2.05× 的窄屏组合下，环内内容高于 130dp，出现
/// `BOTTOM OVERFLOWED BY 51 PIXELS`（证据
/// `local/temp/mobile-acceptance-2026-10-17/section3-5/screenshots/zoom-ring-font20.png`），
/// 同时 `¥0.00` 胶囊与「7 日峰值」文字互相压盖。
///
/// 本用例把座舱放进 360dp 宽的卡片里、字号放大到 2.3×（覆盖外推路径），
/// 断言不抛出 RenderFlex overflow。
List<UsageDaily> _week() => List<UsageDaily>.generate(
      7,
      (index) => UsageDaily(
        day: '01-0${index + 1}',
        calls: index == 6 ? 3 : 0,
        promptTokens: index == 6 ? 5200 : 0,
        completionTokens: index == 6 ? 2381 : 0,
        cachedTokens: index == 6 ? 1200 : 0,
        spendCents: 0,
        costCents: 0,
        isToday: index == 6,
      ),
    );

Future<void> _pumpHero(WidgetTester tester, double scale) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(360, 800),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: 360, child: TokenUsageHero(days: _week())),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 32));
}

void main() {
  testWidgets('环形座舱在 360dp 窄屏与 2.3 倍字号下不溢出', (tester) async {
    await _pumpHero(tester, 2.3);
    expect(tester.takeException(), isNull);
    expect(find.text('实时用量'), findsOneWidget);
    expect(find.textContaining('7日峰值'), findsOneWidget);
  });

  testWidgets('环形座舱在默认字号下保持稳定', (tester) async {
    await _pumpHero(tester, 1.0);
    expect(tester.takeException(), isNull);
    expect(find.text('实时用量'), findsOneWidget);
  });
}
