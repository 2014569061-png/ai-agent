// M8 光尘粒子：粒子系统的参数边界，以及随 AmbientGlow 按档位挂载。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/motion/motion_tier.dart';
import 'package:mobile_agent/presentation/motion/nexus_motion.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/widgets/ambient_glow.dart';
import 'package:mobile_agent/presentation/widgets/light_dust_field.dart';

Widget _app({
  MotionLevel level = MotionLevel.full,
  MotionTier? tier,
  MotionTierController? controller,
  Brightness brightness = Brightness.light,
}) {
  return MaterialApp(
    theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
    builder: (context, c) {
      Widget result = NexusMotionScope(level: level, child: c!);
      final ctrl = controller ??
          (tier != null ? MotionTierController(initial: tier) : null);
      if (ctrl != null) {
        result = MotionTierScope(controller: ctrl, child: result);
      }
      return result;
    },
    home: const Scaffold(
      body: SizedBox(width: 360, height: 640, child: AmbientGlow()),
    ),
  );
}

LightDustSystem? _dust(WidgetTester tester) =>
    (tester.state(find.byType(AmbientGlow)) as dynamic).debugDust
        as LightDustSystem?;

Finder get _dustPaint => find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is LightDustPainter);

void main() {
  const size = Size(360, 640);
  const dt = 0.05;

  test('出生点都在发射椭圆内', () {
    final s = LightDustSystem(count: 200, seed: 1)..resize(size);
    final c = LightDustSystem.emitterCenter(size);
    final r = LightDustSystem.emitterRadii(size);
    for (var i = 0; i < 200; i++) {
      final p = s.positionOf(i);
      // 纵向可能已随初始存活时间上浮，只检查横向：不超出椭圆 + 横摆幅度。
      expect((p.dx - c.dx).abs(),
          lessThanOrEqualTo(r.width + LightDustSystem.swayAmplitude + 0.01));
    }
  });

  test('长时间推进：粒子始终在区域内，α 在 [0, 0.45]，半径在 [0.8, 2.2]', () {
    final s = LightDustSystem(count: 28)..resize(size);
    for (var k = 0; k < 20 * 60; k++) {
      s.step(dt);
      for (var i = 0; i < s.count; i++) {
        final p = s.positionOf(i);
        expect(p.dy, inInclusiveRange(0, size.height));
        expect(s.alphaOf(i), inInclusiveRange(0, LightDustSystem.maxAlpha));
        expect(
            s.radiusOf(i),
            inInclusiveRange(LightDustSystem.minRadius - 1e-6,
                LightDustSystem.maxRadius + 1e-6));
      }
    }
  });

  test('接近顶边时渐隐：y < 24dp 的粒子 α 按比例衰减', () {
    final s = LightDustSystem(count: 28)..resize(size);
    for (var k = 0; k < 20 * 30; k++) {
      s.step(dt);
      for (var i = 0; i < s.count; i++) {
        final y = s.positionOf(i).dy;
        if (y < LightDustSystem.edgeFade) {
          expect(
              s.alphaOf(i),
              lessThanOrEqualTo(
                  LightDustSystem.maxAlpha * y / LightDustSystem.edgeFade +
                      1e-6));
        }
      }
    }
  });

  test('同一种子结果可复现', () {
    final a = LightDustSystem(count: 14, seed: 3)..resize(size);
    final b = LightDustSystem(count: 14, seed: 3)..resize(size);
    for (var k = 0; k < 100; k++) {
      a.step(dt);
      b.step(dt);
    }
    for (var i = 0; i < 14; i++) {
      expect(a.positionOf(i), b.positionOf(i));
    }
  });

  testWidgets('high 挂 28 颗、mid 挂 14 颗，并随时钟推进', (tester) async {
    await tester.pumpWidget(_app(tier: MotionTier.high));
    expect(_dust(tester)!.count, 28);
    expect(_dustPaint, findsOneWidget);
    await tester.pump(NexusMotion.ambientGlowTick);
    final before = _dust(tester)!.positionOf(0);
    await tester.pump(NexusMotion.ambientGlowTick * 4);
    expect(_dust(tester)!.positionOf(0), isNot(before));

    await tester.pumpWidget(_app(tier: MotionTier.mid));
    expect(_dust(tester)!.count, 14);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('low / reduced / off / 无 Scope 时不挂载粒子', (tester) async {
    for (final app in [
      _app(tier: MotionTier.low),
      _app(level: MotionLevel.reduced, tier: MotionTier.high),
      _app(level: MotionLevel.off, tier: MotionTier.high),
      _app(),
    ]) {
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      expect(_dustPaint, findsNothing);
    }
  });

  testWidgets('运行时降档到 low：粒子立即卸载，光晕保留', (tester) async {
    final controller = MotionTierController(initial: MotionTier.mid);
    await tester.pumpWidget(_app(controller: controller));
    expect(_dustPaint, findsOneWidget);
    controller.value = MotionTier.low;
    await tester.pump();
    expect(_dustPaint, findsNothing);
    expect(
        find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is AmbientGlowPainter),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('深色用 plus 叠加，浅色用 srcOver', (tester) async {
    await tester
        .pumpWidget(_app(tier: MotionTier.high, brightness: Brightness.dark));
    var painter =
        tester.widget<CustomPaint>(_dustPaint).painter! as LightDustPainter;
    expect(painter.blendMode, BlendMode.plus);
    await tester.pumpWidget(_app(tier: MotionTier.high));
    // MaterialApp 的主题切换带 200ms 过渡，等过渡结束再读。
    await tester.pump(const Duration(milliseconds: 300));
    painter =
        tester.widget<CustomPaint>(_dustPaint).painter! as LightDustPainter;
    expect(painter.blendMode, BlendMode.srcOver);
    await tester.pumpWidget(const SizedBox());
  });
}
