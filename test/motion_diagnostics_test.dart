// 动效诊断卡：结论优先级与渲染。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/motion/motion_tier.dart';
import 'package:mobile_agent/presentation/settings/motion_diagnostics.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

void main() {
  test('结论按优先级：系统关闭 > App 关闭 > 减弱 > low 档 > 正常', () {
    String v(bool sys, MotionLevel l, MotionTier? t, bool g) =>
        MotionDiagnosticsCard.verdict(
            systemDisabled: sys, level: l, tier: t, glassCapped: g);
    expect(v(true, MotionLevel.full, MotionTier.high, false), contains('系统'));
    expect(v(false, MotionLevel.off, MotionTier.high, false), contains('关闭动效'));
    expect(
        v(false, MotionLevel.reduced, MotionTier.high, false), contains('减弱'));
    expect(v(false, MotionLevel.full, MotionTier.low, true), contains('纯扁平'));
    expect(v(false, MotionLevel.full, MotionTier.low, false), contains('low'));
    expect(v(false, MotionLevel.full, MotionTier.high, false), '动效全部生效');
  });

  test('测试环境未注入构建信息时给出提示', () {
    expect(MotionDiagnosticsCard.buildStamp, contains('未注入'));
  });

  testWidgets('系统移除动画时卡片直接指出原因', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Scaffold(body: MotionDiagnosticsCard()),
      ),
    ));
    final verdict = tester
        .widget<Text>(find.byKey(const ValueKey('motion-diagnostics-verdict')));
    expect(verdict.data, contains('系统已关闭动画'));
  });
}
