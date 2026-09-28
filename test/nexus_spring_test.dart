// L0 灵动动效基础：弹簧 Token、降级策略、可打断保速度的驱动器与隐式组件。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/motion/motion_tier.dart';
import 'package:mobile_agent/presentation/motion/nexus_motion.dart';
import 'package:mobile_agent/presentation/motion/nexus_spring.dart';

double _overshoot(SpringDescription s) {
  final sim = NexusMotion.spring(s);
  var peak = 0.0;
  for (var ms = 0; ms <= 1500; ms++) {
    peak = peak > sim.x(ms / 1000) ? peak : sim.x(ms / 1000);
  }
  return peak - 1;
}

void main() {
  group('弹簧 Token', () {
    test('snappy 几乎不过冲、落定 ≤ 0.23s', () {
      expect(_overshoot(NexusSprings.snappy), lessThan(0.01));
      expect(NexusSprings.settleOf(NexusSprings.snappy).inMilliseconds,
          lessThanOrEqualTo(230));
    });

    test('bouncy 过冲约 5%、落定 ≤ 0.35s（干脆利落 + 明显回弹）', () {
      expect(_overshoot(NexusSprings.bouncy), closeTo(0.05, 0.01));
      expect(NexusSprings.settleOf(NexusSprings.bouncy).inMilliseconds,
          lessThanOrEqualTo(350));
    });

    test('smooth 无明显过冲、落定 ≤ 0.32s', () {
      expect(_overshoot(NexusSprings.smooth), lessThan(0.005));
      expect(NexusSprings.settleOf(NexusSprings.smooth).inMilliseconds,
          lessThanOrEqualTo(320));
    });

    test('critical 去掉过冲且按实例缓存', () {
      final c = NexusSprings.critical(NexusSprings.bouncy);
      expect(NexusSprings.ratioOf(c), closeTo(1, 1e-9));
      expect(_overshoot(c), lessThan(0.001));
      expect(identical(c, NexusSprings.critical(NexusSprings.bouncy)), isTrue);
      expect(
          identical(NexusSprings.critical(NexusSprings.reduced),
              NexusSprings.reduced),
          isTrue);
    });

    test('curveOf 缓存，settleOf 与曲线一致', () {
      expect(
          identical(NexusSprings.curveOf(NexusSprings.smooth),
              NexusSprings.curveOf(NexusSprings.smooth)),
          isTrue);
      expect(
          NexusSprings.curveOf(NexusSprings.bouncy, allowOvershoot: true)
              .allowOvershoot,
          isTrue);
    });
  });

  test('降级策略：off → null，reduced → 临界短弹簧，low 档去过冲', () {
    final b = NexusSprings.bouncy;
    expect(NexusSpringPolicy.resolveFor(MotionLevel.off, MotionTier.high, b),
        isNull);
    expect(
        NexusSpringPolicy.resolveFor(MotionLevel.reduced, MotionTier.high, b),
        same(NexusSprings.reduced));
    expect(NexusSpringPolicy.resolveFor(MotionLevel.full, MotionTier.high, b),
        same(b));
    expect(NexusSpringPolicy.resolveFor(MotionLevel.full, MotionTier.mid, b),
        same(b));
    expect(NexusSpringPolicy.resolveFor(MotionLevel.full, MotionTier.low, b),
        same(NexusSprings.critical(b)));
  });

  testWidgets('SpringController：中途改目标保留速度，不跳变', (tester) async {
    late SpringController spring;
    await tester.pumpWidget(_Host(onCreate: (s) => spring = s));
    unawaited(spring.animateTo(1, spring: NexusSprings.smooth));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final before = spring.value;
    final v = spring.velocity;
    expect(v, greaterThan(0));
    // 反向：数值连续、速度方向仍为正（惯性），随后才折返。
    unawaited(spring.animateTo(0, spring: NexusSprings.smooth));
    await tester.pump();
    expect(spring.value, closeTo(before, 1e-6));
    await tester.pump(const Duration(milliseconds: 8));
    expect(spring.value, greaterThan(before));
    await tester.pumpAndSettle();
    expect(spring.value, closeTo(0, 0.002));
  });

  testWidgets('SpringController：spring 为 null 时直接跳到终值', (tester) async {
    late SpringController spring;
    await tester.pumpWidget(_Host(onCreate: (s) => spring = s));
    unawaited(spring.animateTo(1, spring: null));
    expect(spring.value, 1);
    expect(spring.isAnimating, isFalse);
  });

  testWidgets('SpringController：甩动初速度影响过程', (tester) async {
    late SpringController spring;
    await tester.pumpWidget(_Host(onCreate: (s) => spring = s));
    unawaited(spring.animateTo(1, spring: NexusSprings.smooth, velocity: 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // 同一时刻无初速度时约 0.3，带甩动速度应明显更远。
    expect(spring.value, greaterThan(0.6));
    await tester.pumpAndSettle();
  });

  Future<List<double>> runSpringValue(
      WidgetTester tester, MotionLevel level) async {
    final values = <double>[];
    Widget build(double target) => MaterialApp(
          home: NexusMotionScope(
            level: level,
            child: SpringValue(
              value: target,
              spring: NexusSprings.bouncy,
              builder: (context, v, _) {
                values.add(v);
                return const SizedBox();
              },
            ),
          ),
        );
    await tester.pumpWidget(build(0));
    await tester.pumpWidget(build(1));
    await tester.pumpAndSettle();
    return values;
  }

  testWidgets('SpringValue：full 下有 ≈5% 过冲并落定到目标', (tester) async {
    final values = await runSpringValue(tester, MotionLevel.full);
    final peak = values.reduce((a, b) => a > b ? a : b);
    expect(peak, greaterThan(1.02));
    expect(peak, lessThan(1.08));
    expect(values.last, closeTo(1, 0.002));
  });

  testWidgets('SpringValue：reduced 无过冲', (tester) async {
    final values = await runSpringValue(tester, MotionLevel.reduced);
    expect(values.reduce((a, b) => a > b ? a : b), lessThanOrEqualTo(1.0005));
    expect(values.last, closeTo(1, 0.002));
  });

  testWidgets('SpringValue：off 立即到位', (tester) async {
    final values = await runSpringValue(tester, MotionLevel.off);
    expect(values.last, 1);
    expect(values.where((v) => v > 0 && v < 1), isEmpty);
  });

  testWidgets('SpringAnimatedSize：full 下用弹簧时长，off 下不包 AnimatedSize',
      (tester) async {
    Widget build(MotionLevel level) => MaterialApp(
          home: NexusMotionScope(
            level: level,
            child: const SpringAnimatedSize(child: SizedBox(height: 10)),
          ),
        );
    await tester.pumpWidget(build(MotionLevel.full));
    final size = tester.widget<AnimatedSize>(find.byType(AnimatedSize));
    expect(size.duration, NexusSprings.settleOf(NexusSprings.smooth));
    await tester.pumpWidget(build(MotionLevel.off));
    expect(find.byType(AnimatedSize), findsNothing);
  });
}

class _Host extends StatefulWidget {
  const _Host({required this.onCreate});
  final ValueChanged<SpringController> onCreate;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with SingleTickerProviderStateMixin {
  late final SpringController spring = SpringController(vsync: this);

  @override
  void initState() {
    super.initState();
    widget.onCreate(spring);
  }

  @override
  void dispose() {
    spring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
