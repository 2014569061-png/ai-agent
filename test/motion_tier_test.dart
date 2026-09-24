import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/motion/motion_tier.dart';
import 'package:mobile_agent/presentation/motion/nexus_motion.dart';

const _fast = Duration(milliseconds: 4);
const _slow = Duration(milliseconds: 30);

void main() {
  tearDown(() => MotionTierController.debugOverride = null);

  group('MotionTierController', () {
    test('初始档位按刷新率判定', () {
      expect(MotionTierController(refreshRate: 120).value, MotionTier.high);
      expect(MotionTierController(refreshRate: 90).value, MotionTier.high);
      expect(MotionTierController(refreshRate: 60).value, MotionTier.mid);
      // 非法刷新率回退到 60Hz。
      expect(
          MotionTierController(refreshRate: double.nan).value, MotionTier.mid);
    });

    test('帧预算随刷新率变化', () {
      expect(MotionTierController(refreshRate: 60).frameBudgetMicros, 16667);
      expect(MotionTierController(refreshRate: 120).frameBudgetMicros, 8333);
    });

    test('预热期内的卡顿帧不计入', () {
      final c = MotionTierController(
          refreshRate: 60, sampleSize: 10, warmupFrames: 20);
      for (var i = 0; i < 20; i++) {
        c.recordFrame(_slow, _slow);
      }
      expect(c.value, MotionTier.mid);
    });

    test('窗口内掉帧率超过阈值时降一档，且只降不升', () {
      final c = MotionTierController(
          refreshRate: 120, sampleSize: 10, warmupFrames: 0);
      // 10 帧中 2 帧超预算 = 20% > 8%。
      for (var i = 0; i < 10; i++) {
        c.recordFrame(i < 2 ? _slow : _fast, _fast);
      }
      expect(c.value, MotionTier.mid);
      // 之后全部流畅也不会回升。
      for (var i = 0; i < 50; i++) {
        c.recordFrame(_fast, _fast);
      }
      expect(c.value, MotionTier.mid);
      for (var i = 0; i < 10; i++) {
        c.recordFrame(_fast, _slow);
      }
      expect(c.value, MotionTier.low);
    });

    test('掉帧率未超阈值时保持档位', () {
      final c = MotionTierController(
          refreshRate: 60, sampleSize: 100, warmupFrames: 0);
      for (var i = 0; i < 100; i++) {
        c.recordFrame(i < 5 ? _slow : _fast, _fast);
      }
      expect(c.value, MotionTier.mid);
    });

    test('debugOverride 生效且屏蔽运行时降档', () {
      MotionTierController.debugOverride = MotionTier.high;
      final c =
          MotionTierController(refreshRate: 60, sampleSize: 5, warmupFrames: 0);
      expect(c.value, MotionTier.high);
      for (var i = 0; i < 20; i++) {
        c.recordFrame(_slow, _slow);
      }
      expect(c.value, MotionTier.high);
    });
  });

  group('MotionBudget', () {
    test('降级顺序：先关粒子，再简化光晕，最后关闭流光与光感', () {
      final high = MotionBudget.resolve(MotionLevel.full, MotionTier.high);
      final mid = MotionBudget.resolve(MotionLevel.full, MotionTier.mid);
      final low = MotionBudget.resolve(MotionLevel.full, MotionTier.low);
      expect([high.particleCount, mid.particleCount, low.particleCount],
          [28, 14, 0]);
      expect([high.ambientDrift, mid.ambientDrift, low.ambientDrift],
          [true, false, false]);
      expect(mid.ambientBreathing, isTrue);
      expect(low.ambientBreathing, isFalse);
      expect(low.ambientGlow, isTrue, reason: '低端机保留静态光晕');
      expect(low.shimmer || low.touchLight || low.sendRipple, isFalse);
      expect(mid.shimmerPeriodScale, greaterThan(1));
    });

    test('reduced 只保留静态光晕，off 全部关闭', () {
      for (final tier in MotionTier.values) {
        final reduced = MotionBudget.resolve(MotionLevel.reduced, tier);
        expect(reduced.particleCount, 0);
        expect(reduced.hasContinuousDecoration, isFalse);
        expect(reduced.ambientGlow, isTrue);
        final off = MotionBudget.resolve(MotionLevel.off, tier);
        expect(off.ambientGlow, isFalse);
        expect(off.hasContinuousDecoration, isFalse);
        expect(off.routeParallax, isFalse);
      }
    });

    testWidgets('Scope 注入、cap 上限与系统「移除动画」', (tester) async {
      final controller = MotionTierController(refreshRate: 120);
      late MotionBudget budget;
      Widget host({MotionTier? cap, bool disableAnimations = false}) =>
          MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: MotionTierScope(
              controller: controller,
              cap: cap,
              child: Builder(builder: (context) {
                budget = MotionBudget.of(context);
                return const SizedBox();
              }),
            ),
          );

      await tester.pumpWidget(host());
      expect(budget.tier, MotionTier.high);
      expect(budget.particleCount, 28);

      await tester.pumpWidget(host(cap: MotionTier.low));
      expect(budget.tier, MotionTier.low);
      expect(budget.particleCount, 0);

      await tester.pumpWidget(host(disableAnimations: true));
      expect(budget.level, MotionLevel.off);
      expect(budget.hasContinuousDecoration, isFalse);

      // 运行时降档会通知依赖方重建。
      await tester.pumpWidget(host());
      controller.value = MotionTier.mid;
      await tester.pump();
      expect(budget.particleCount, 14);
    });

    testWidgets('未挂载 Scope 时使用保守默认档', (tester) async {
      late MotionBudget budget;
      await tester.pumpWidget(Builder(builder: (context) {
        budget = MotionBudget.of(context);
        return const SizedBox();
      }));
      expect(budget.tier, MotionTierScope.fallback);
    });
  });

  group('弹簧 Token', () {
    double ratio(SpringDescription s) =>
        s.damping / (2 * math.sqrt(s.mass * s.stiffness));
    double response(SpringDescription s) =>
        2 * math.pi / math.sqrt(s.stiffness / s.mass);

    test('跟手 / 离手 / 轻弹与 HarmonyOS 参数换算一致', () {
      expect(response(NexusMotion.springFollow), closeTo(0.15, 0.005));
      expect(ratio(NexusMotion.springFollow), closeTo(0.86, 0.005));
      expect(response(NexusMotion.springRelease), closeTo(0.55, 0.005));
      expect(ratio(NexusMotion.springRelease), closeTo(0.825, 0.005));
      expect(NexusMotion.springLively.stiffness, 128);
      expect(NexusMotion.springLively.damping, 12);
      expect(ratio(NexusMotion.springLively), closeTo(0.53, 0.005));
    });

    test('spring() 在有限时间内收敛到目标值', () {
      final sim = NexusMotion.spring(NexusMotion.springRelease);
      expect(sim.isDone(2.0), isTrue);
      expect(sim.x(2.0), closeTo(1.0, 0.01));
    });
  });
}
