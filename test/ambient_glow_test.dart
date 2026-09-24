// M7 环境光晕：分档、生命周期、测试兼容（无 Scope 静态）与对比度护栏。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/chat/widgets/chat_empty_state.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/motion/motion_tier.dart';
import 'package:mobile_agent/presentation/motion/nexus_motion.dart';
import 'package:mobile_agent/presentation/theme/app_palette.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/widgets/ambient_glow.dart';

Widget _app(
  Widget child, {
  MotionLevel level = MotionLevel.full,
  MotionTier? tier,
  bool tickerEnabled = true,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    builder: (context, c) {
      Widget result = NexusMotionScope(level: level, child: c!);
      if (tier != null) {
        result = MotionTierScope(
          controller: MotionTierController(initial: tier),
          child: result,
        );
      }
      return result;
    },
    home: Scaffold(
      body: TickerMode(
        enabled: tickerEnabled,
        child: SizedBox(width: 360, height: 640, child: child),
      ),
    ),
  );
}

AmbientGlowPainter _painter(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(find.descendant(
    of: find.byType(AmbientGlow),
    matching: find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is AmbientGlowPainter),
  ));
  return paint.painter! as AmbientGlowPainter;
}

bool _looping(WidgetTester tester) =>
    (tester.state(find.byType(AmbientGlow)) as dynamic).isLooping as bool;

double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

void main() {
  testWidgets('high：漂移 + 呼吸，按 50ms 步进，卸载后不残留 Timer', (tester) async {
    await tester.pumpWidget(_app(const AmbientGlow(), tier: MotionTier.high));
    final painter = _painter(tester);
    expect(painter.drift, isTrue);
    expect(painter.breathing, isTrue);
    expect(painter.singleLayer, isFalse);
    expect(_looping(tester), isTrue);

    final t0 = painter.time.value;
    await tester.pump(NexusMotion.ambientGlowTick * 3);
    expect(painter.time.value, greaterThan(t0));

    await tester.pumpWidget(const SizedBox());
    // 测试框架会在结束时检查是否仍有挂起的 Timer。
  });

  testWidgets('mid：只呼吸不漂移', (tester) async {
    await tester.pumpWidget(_app(const AmbientGlow(), tier: MotionTier.mid));
    final painter = _painter(tester);
    expect(painter.drift, isFalse);
    expect(painter.breathing, isTrue);
    expect(_looping(tester), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('low：静态双层，不创建 Timer，pumpAndSettle 可结束', (tester) async {
    await tester.pumpWidget(_app(const AmbientGlow(), tier: MotionTier.low));
    await tester.pumpAndSettle();
    final painter = _painter(tester);
    expect(painter.drift, isFalse);
    expect(painter.breathing, isFalse);
    expect(painter.singleLayer, isFalse);
    expect(_looping(tester), isFalse);
  });

  testWidgets('reduced：静态单层', (tester) async {
    await tester.pumpWidget(_app(const AmbientGlow(),
        level: MotionLevel.reduced, tier: MotionTier.high));
    await tester.pumpAndSettle();
    final painter = _painter(tester);
    expect(painter.singleLayer, isTrue);
    expect(painter.drift || painter.breathing, isFalse);
    expect(_looping(tester), isFalse);
  });

  testWidgets('off：不绘制', (tester) async {
    await tester.pumpWidget(_app(const AmbientGlow(),
        level: MotionLevel.off, tier: MotionTier.high));
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is AmbientGlowPainter),
        findsNothing);
  });

  testWidgets('未挂 MotionTierScope（独立 widget 测试）时静态，pumpAndSettle 可结束',
      (tester) async {
    await tester.pumpWidget(_app(const AmbientGlow()));
    await tester.pumpAndSettle();
    expect(_looping(tester), isFalse);
    expect(_painter(tester).breathing, isFalse);
  });

  testWidgets('页面被遮挡（TickerMode 关闭）时停止，恢复后重新循环', (tester) async {
    await tester.pumpWidget(_app(const AmbientGlow(), tier: MotionTier.high));
    expect(_looping(tester), isTrue);
    await tester.pumpWidget(
        _app(const AmbientGlow(), tier: MotionTier.high, tickerEnabled: false));
    expect(_looping(tester), isFalse);
    await tester.pumpWidget(_app(const AmbientGlow(), tier: MotionTier.high));
    expect(_looping(tester), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('进入后台时停止，回到前台恢复', (tester) async {
    await tester.pumpWidget(_app(const AmbientGlow(), tier: MotionTier.high));
    expect(_looping(tester), isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(_looping(tester), isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(_looping(tester), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  test('任一时刻每层 α ≤ 0.12，漂移模长 ≤ 24dp', () {
    final period = NexusMotion.ambientGlowPeriod.inMilliseconds / 1000;
    for (var i = 0; i <= 240; i++) {
      final t = period * i / 240;
      for (final a in AmbientGlowPainter.layerAlphas(t, breathing: true)) {
        expect(a, lessThanOrEqualTo(AmbientGlowPainter.maxAlpha));
      }
      expect(AmbientGlowPainter.driftOffset(t, drift: true).distance,
          lessThanOrEqualTo(NexusMotion.ambientGlowDrift));
    }
  });

  test('两层光晕在最亮处叠加后，次级文字对比度仍 ≥ 4.5（浅色 / 深色）', () {
    // 取呼吸峰值时两层的真实 α，并假设两团光的中心完全重叠（最坏情况）。
    final period = NexusMotion.ambientGlowPeriod.inMilliseconds / 1000;
    final peak = AmbientGlowPainter.layerAlphas(period / 4, breathing: true);
    Color worst(Color canvas) {
      var c = canvas;
      c = Color.alphaBlend(
          AmbientGlowPainter.secondaryColor.withValues(alpha: peak[1]), c);
      c = Color.alphaBlend(
          AmbientGlowPainter.primaryColor.withValues(alpha: peak[0]), c);
      return c;
    }

    expect(_contrast(AppPalette.lightTextMuted, worst(AppPalette.lightCanvas)),
        greaterThanOrEqualTo(4.5));
    expect(_contrast(AppPalette.darkTextMuted, worst(AppPalette.darkCanvas)),
        greaterThanOrEqualTo(4.5));
  });

  testWidgets('空状态页挂载了光晕，且在内容之下', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: ChatEmptyState()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(AmbientGlow), findsOneWidget);
    final stack = tester.widget<Stack>(find
        .ancestor(of: find.byType(AmbientGlow), matching: find.byType(Stack))
        .first);
    final first = stack.children.first;
    expect(first, isA<Positioned>());
    expect((first as Positioned).child, isA<AmbientGlow>());
  });
}
