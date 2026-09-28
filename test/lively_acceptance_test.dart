// L8：灵动动效验收——节奏（~0.3s 干脆利落）、回弹幅度（~5%）、减弱/关闭动效下无回弹无循环。
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/motion/micro_interactions.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/motion/motion_tier.dart';
import 'package:mobile_agent/presentation/motion/nexus_spring.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/widgets/nexus_switch.dart';

double _peak(SpringDescription s) {
  final sim = SpringSimulation(s, 0, 1, 0);
  var peak = 0.0;
  for (var t = 0.0; t < 1.5; t += 0.002) {
    final x = sim.x(t);
    if (x > peak) peak = x;
  }
  return peak;
}

Widget _host(MotionLevel level, Widget child) => MaterialApp(
      theme: AppTheme.light(),
      builder: (context, c) => MotionTierScope(
        controller: MotionTierController(initial: MotionTier.high),
        child: NexusMotionScope(level: level, child: c!),
      ),
      home: Scaffold(body: Center(child: child)),
    );

class _SwitchHarness extends StatefulWidget {
  const _SwitchHarness();
  @override
  State<_SwitchHarness> createState() => _SwitchHarnessState();
}

class _SwitchHarnessState extends State<_SwitchHarness> {
  bool on = false;
  @override
  Widget build(BuildContext context) =>
      NexusSwitch(value: on, onChanged: (v) => setState(() => on = v));
}

double _thumbX(WidgetTester t) =>
    t.getCenter(find.byKey(const ValueKey('nexus_switch_thumb'))).dx;

/// 点开开关并逐帧记录滑块位置；返回 (最大值, 终值, 到位帧数)。
Future<(double, double, int)> _trackSwitch(
    WidgetTester tester, MotionLevel level) async {
  await tester.pumpWidget(_host(level, const _SwitchHarness()));
  await tester.tap(find.byType(NexusSwitch));
  await tester.pump();
  var peak = _thumbX(tester), frames = 0;
  final xs = <double>[];
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    xs.add(_thumbX(tester));
    if (xs.last > peak) peak = xs.last;
  }
  final end = xs.last;
  frames = xs.indexWhere((x) => (x - end).abs() < 0.25) + 1;
  return (peak, end, frames);
}

void main() {
  group('节奏与回弹（令牌）', () {
    test('snappy / bouncy / smooth 约 0.3s 内收敛，release ≤ 0.5s', () {
      for (final s in [
        NexusSprings.snappy,
        NexusSprings.bouncy,
        NexusSprings.smooth
      ]) {
        expect(NexusSprings.settleOf(s).inMilliseconds, lessThanOrEqualTo(350));
      }
      expect(NexusSprings.settleOf(NexusSprings.release).inMilliseconds,
          lessThanOrEqualTo(500));
    });

    test('bouncy 回弹约 5%，smooth/reduced 基本无回弹', () {
      expect(_peak(NexusSprings.bouncy), inInclusiveRange(1.03, 1.07));
      expect(_peak(NexusSprings.smooth), lessThan(1.005));
      expect(_peak(NexusSprings.reduced), lessThanOrEqualTo(1.0001));
    });
  });

  group('开关：三档动效', () {
    testWidgets('full：越过终点后回弹，约 0.4s 内到位', (tester) async {
      final (peak, end, frames) = await _trackSwitch(tester, MotionLevel.full);
      expect(peak, greaterThan(end + 0.3));
      expect(frames * 16, lessThanOrEqualTo(420));
    });

    testWidgets('reduced：无越界回弹', (tester) async {
      final (peak, end, _) = await _trackSwitch(tester, MotionLevel.reduced);
      expect(peak, lessThanOrEqualTo(end + 0.05));
    });

    testWidgets('off：下一帧即到位', (tester) async {
      final (peak, end, frames) = await _trackSwitch(tester, MotionLevel.off);
      expect(peak, lessThanOrEqualTo(end + 0.05));
      expect(frames, lessThanOrEqualTo(1));
    });
  });

  group('微交互：关闭动效时直接换值', () {
    testWidgets('RollingText off：不滚动', (tester) async {
      await tester.pumpWidget(_host(MotionLevel.off, const RollingText('12')));
      await tester.pumpWidget(_host(MotionLevel.off, const RollingText('13')));
      await tester.pump();
      expect(find.text('13'), findsOneWidget);
      expect(find.text('2'), findsNothing);
    });

    testWidgets('PopOnChange off：不弹', (tester) async {
      Widget pop(Object t) => _host(
          MotionLevel.off, PopOnChange(trigger: t, child: const Text('就绪')));
      await tester.pumpWidget(pop(1));
      await tester.pumpWidget(pop(2));
      await tester.pump();
      expect(
          find.descendant(
              of: find.byType(PopOnChange), matching: find.byType(Transform)),
          findsNothing);
    });
  });
}
