// M9 思考中 / 执行中：文字流光分档、执行状态外发光环与完成收拢。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/chat/widgets/reasoning_block.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/motion/motion_tier.dart';
import 'package:mobile_agent/presentation/motion/nexus_motion.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/theme/desktop_theme.dart';
import 'package:mobile_agent/presentation/widgets/nexus_execution_status.dart';
import 'package:mobile_agent/presentation/widgets/shimmer_text.dart';

Widget _app(
  Widget child, {
  MotionLevel level = MotionLevel.full,
  MotionTier? tier,
  bool tickerEnabled = true,
  bool desktop = false,
}) {
  return MaterialApp(
    theme: AppTheme.light().copyWith(
      extensions: [
        ...AppTheme.light().extensions.values,
        if (desktop) DesktopTheme.light,
      ],
    ),
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
        child: Center(child: SizedBox(width: 360, child: child)),
      ),
    ),
  );
}

const _text = ShimmerText(child: Text('正在思考…'));

bool _shimmering(WidgetTester tester) =>
    (tester.state(find.byType(ShimmerText)) as dynamic).isShimmering as bool;

Duration? _cycle(WidgetTester tester) =>
    (tester.state(find.byType(ShimmerText)) as dynamic).cycle as Duration?;

Finder get _mask => find.descendant(
    of: find.byType(ShimmerText), matching: find.byType(ShaderMask));

ExecutionGlowRingPainter? _ring(WidgetTester tester) {
  final paints = tester.widgetList<CustomPaint>(find.descendant(
    of: find.byType(NexusExecutionStatus),
    matching: find.byType(CustomPaint),
  ));
  for (final p in paints) {
    if (p.painter is ExecutionGlowRingPainter) {
      return p.painter! as ExecutionGlowRingPainter;
    }
  }
  return null;
}

Widget _status(NexusExecutionState state) =>
    NexusExecutionStatus(state: state, label: '执行中');

void main() {
  group('ShimmerText', () {
    testWidgets('high：流光循环，周期 2000ms', (tester) async {
      await tester.pumpWidget(_app(_text, tier: MotionTier.high));
      expect(_shimmering(tester), isTrue);
      expect(_mask, findsOneWidget);
      expect(_cycle(tester), NexusMotion.shimmerSweep + NexusMotion.shimmerGap);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('mid：周期放慢 1.5 倍', (tester) async {
      await tester.pumpWidget(_app(_text, tier: MotionTier.mid));
      expect(_shimmering(tester), isTrue);
      expect(_cycle(tester),
          (NexusMotion.shimmerSweep + NexusMotion.shimmerGap) * 1.5);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('low / reduced / off / 无 Scope：静态，pumpAndSettle 可结束',
        (tester) async {
      for (final app in [
        _app(_text, tier: MotionTier.low),
        _app(_text, level: MotionLevel.reduced, tier: MotionTier.high),
        _app(_text, level: MotionLevel.off, tier: MotionTier.high),
        _app(_text),
      ]) {
        await tester.pumpWidget(app);
        await tester.pumpAndSettle();
        expect(_shimmering(tester), isFalse);
        expect(_mask, findsNothing);
        expect(find.text('正在思考…'), findsOneWidget);
      }
    });

    testWidgets('enabled=false 或页面被遮挡时停止', (tester) async {
      await tester.pumpWidget(_app(_text, tier: MotionTier.high));
      expect(_shimmering(tester), isTrue);
      await tester
          .pumpWidget(_app(_text, tier: MotionTier.high, tickerEnabled: false));
      expect(_shimmering(tester), isFalse);
      await tester.pumpWidget(_app(
          const ShimmerText(enabled: false, child: Text('正在思考…')),
          tier: MotionTier.high));
      expect(_shimmering(tester), isFalse);
      expect(_mask, findsNothing);
    });

    test('高光在周期起止时完全位于文字之外', () {
      for (final t in [0.0, 1.0]) {
        final g = shimmerGradient(Colors.white, t);
        final m = g.transform!.transform(const Rect.fromLTWH(0, 0, 100, 10));
        final dx = m!.getTranslation().x / 100;
        final lo = g.stops!.first + dx;
        final hi = g.stops!.last + dx;
        expect(hi <= 0 || lo >= 1, isTrue, reason: 't=$t lo=$lo hi=$hi');
      }
    });
  });

  group('ReasoningCompactBlock', () {
    testWidgets('手机思考标题稳定，不播放扫描文字', (tester) async {
      await tester.pumpWidget(_app(
          const ReasoningCompactBlock(reasoning: '', streaming: true),
          tier: MotionTier.high));
      expect(find.byType(ShimmerText), findsOneWidget);
      expect(_shimmering(tester), isFalse);

      await tester.pumpWidget(_app(
          const ReasoningCompactBlock(
              reasoning: '', duration: Duration(seconds: 3)),
          tier: MotionTier.high));
      await tester.pumpAndSettle();
      expect(_shimmering(tester), isFalse);
      expect(_mask, findsNothing);
    });
  });

  group('NexusExecutionStatus 外发光环', () {
    testWidgets('桌面运行光环与呼吸同相，α ≤ 0.25', (tester) async {
      await tester.pumpWidget(_app(_status(NexusExecutionState.running),
          tier: MotionTier.high, desktop: true));
      final ring = _ring(tester)!;
      expect(ring.mode, ExecutionGlowRingMode.breathing);
      await tester.pump(const Duration(milliseconds: 700));
      expect(ring.intensity, inInclusiveRange(0, 1));
      expect(
          ring.intensity,
          closeTo(
              NexusMotion.curveBreathing.transform(ring.pulse.value), 1e-9));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('low 档或 reduced 时没有光环', (tester) async {
      await tester.pumpWidget(
          _app(_status(NexusExecutionState.running), tier: MotionTier.low));
      expect(_ring(tester), isNull);
      await tester.pumpWidget(_app(_status(NexusExecutionState.running),
          level: MotionLevel.reduced, tier: MotionTier.high));
      await tester.pumpAndSettle();
      expect(_ring(tester), isNull);
    });

    testWidgets('running → succeeded：光环 180ms 内收拢并结束', (tester) async {
      await tester.pumpWidget(_app(_status(NexusExecutionState.running),
          tier: MotionTier.high, desktop: true));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(_app(_status(NexusExecutionState.succeeded),
          tier: MotionTier.high, desktop: true));
      final ring = _ring(tester)!;
      expect(ring.mode, ExecutionGlowRingMode.collapsing);
      expect(ring.intensity, closeTo(1, 1e-9));
      await tester.pump(const Duration(milliseconds: 90));
      expect(ring.intensity, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(ring.intensity, closeTo(0, 1e-9));
    });

    testWidgets('手机执行状态无外发光环，完成后无循环帧', (tester) async {
      await tester.pumpWidget(
          _app(_status(NexusExecutionState.running), tier: MotionTier.high));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_ring(tester), isNull);
      await tester.pumpWidget(
          _app(_status(NexusExecutionState.succeeded), tier: MotionTier.high));
      await tester.pumpAndSettle();
      expect(_ring(tester), isNull);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('其他状态（等待确认 / 失败）不画光环', (tester) async {
      for (final s in [
        NexusExecutionState.waitingForUser,
        NexusExecutionState.failed,
        NexusExecutionState.idle,
      ]) {
        await tester.pumpWidget(_app(_status(s), tier: MotionTier.high));
        await tester.pumpAndSettle();
        expect(_ring(tester), isNull, reason: '$s');
      }
    });
  });
}
