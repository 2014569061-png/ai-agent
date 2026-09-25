// S1 动效强度：偏好持久化、预算增益、各效果放大与对比度护栏。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/motion/motion_intensity.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/motion/motion_tier.dart';
import 'package:mobile_agent/presentation/motion/nexus_motion.dart';
import 'package:mobile_agent/presentation/theme/app_appearance_controller.dart';
import 'package:mobile_agent/presentation/theme/app_palette.dart';
import 'package:mobile_agent/presentation/widgets/ambient_glow.dart';
import 'package:mobile_agent/presentation/widgets/light_dust_field.dart';
import 'package:mobile_agent/presentation/widgets/nexus_touch_light.dart';
import 'package:shared_preferences/shared_preferences.dart';

double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

void main() {
  test('强度枚举：增益、标签、未知值回落到鲜明', () {
    expect(MotionIntensity.values.map((e) => e.gain), [1.0, 1.5, 2.0]);
    expect(MotionIntensity.values.map((e) => e.label), ['轻盈', '标准', '鲜明']);
    expect(MotionIntensity.parse(null), MotionIntensity.vivid);
    expect(MotionIntensity.parse('bogus'), MotionIntensity.vivid);
    expect(MotionIntensity.parse('subtle'), MotionIntensity.subtle);
    expect(amplify(12, 2, 0.5), 18);
    expect(amplify(12, 1, 0.5), 12);
  });

  test('偏好：默认鲜明，设置后持久化并可重新载入', () async {
    SharedPreferences.setMockInitialValues({});
    await AppAppearanceController.load();
    expect(
        AppAppearanceController.motionIntensity.value, MotionIntensity.vivid);
    await AppAppearanceController.setMotionIntensity(MotionIntensity.subtle);
    final prefs = await SharedPreferences.getInstance();
    expect(
        prefs.getString(AppAppearanceController.motionIntensityKey), 'subtle');
    AppAppearanceController.motionIntensity.value = MotionIntensity.vivid;
    await AppAppearanceController.load(prefs);
    expect(
        AppAppearanceController.motionIntensity.value, MotionIntensity.subtle);
  });

  test('预算：增益只放大粒子数，不改变开关；默认增益为 1', () {
    final base = MotionBudget.resolve(MotionLevel.full, MotionTier.high);
    expect(base.gain, 1);
    expect(base.particleCount, 28);
    final vivid =
        MotionBudget.resolve(MotionLevel.full, MotionTier.high, gain: 2);
    expect(vivid.particleCount, 48);
    expect(
        MotionBudget.resolve(MotionLevel.full, MotionTier.mid, gain: 2)
            .particleCount,
        24);
    expect(vivid.ambientDrift, base.ambientDrift);
    expect(vivid, isNot(base));
    for (final level in [MotionLevel.reduced, MotionLevel.off]) {
      final b = MotionBudget.resolve(level, MotionTier.high, gain: 2);
      expect(b.particleCount, 0);
      expect(b.hasContinuousDecoration, isFalse);
    }
    expect(
        MotionBudget.resolve(MotionLevel.full, MotionTier.low, gain: 2)
            .particleCount,
        0);
  });

  testWidgets('Scope：gainOf 跟随控制器强度，未挂载时为 1', (tester) async {
    final controller = MotionTierController(initial: MotionTier.high);
    late double gain;
    late MotionBudget budget;
    Widget probe() => Builder(builder: (context) {
          gain = MotionTierScope.gainOf(context);
          budget = MotionBudget.of(context);
          return const SizedBox();
        });
    await tester.pumpWidget(probe());
    expect(gain, 1);
    await tester
        .pumpWidget(MotionTierScope(controller: controller, child: probe()));
    expect(gain, 1);
    controller.intensity = MotionIntensity.vivid;
    await tester.pump();
    expect(gain, 2);
    expect(budget.gain, 2);
    expect(budget.particleCount, 48);
    controller.dispose();
  });

  test('光晕：α 与上限同比放大；深色鲜明档叠加后次级文字对比度仍 ≥ 4.5', () {
    final period = NexusMotion.ambientGlowPeriod.inMilliseconds / 1000;
    final base = AmbientGlowPainter.layerAlphas(period / 4, breathing: true);
    final vivid =
        AmbientGlowPainter.layerAlphas(period / 4, breathing: true, gain: 1.8);
    for (var i = 0; i < 2; i++) {
      expect(vivid[i], closeTo(base[i] * 1.8, 1e-9));
      expect(vivid[i], lessThanOrEqualTo(AmbientGlowPainter.maxAlpha * 1.8));
    }
    var c = AppPalette.darkCanvas;
    c = Color.alphaBlend(
        AmbientGlowPainter.secondaryColor.withValues(alpha: vivid[1]), c);
    c = Color.alphaBlend(
        AmbientGlowPainter.primaryColor.withValues(alpha: vivid[0]), c);
    expect(_contrast(AppPalette.darkTextMuted, c), greaterThanOrEqualTo(4.5));
  });

  test('光晕 painter：增益参与 shouldRepaint', () {
    final time = ValueNotifier<double>(0);
    AmbientGlowPainter make(double g) => AmbientGlowPainter(
          time: time,
          drift: true,
          breathing: true,
          singleLayer: false,
          radiusGain: g,
        );
    expect(make(1.25).shouldRepaint(make(1)), isTrue);
    expect(make(1).shouldRepaint(make(1)), isFalse);
    time.dispose();
  });

  test('光尘：半径与 α 随增益放大，α 有上限', () {
    const size = Size(360, 640);
    final base = LightDustSystem(count: 20)..resize(size);
    final vivid = LightDustSystem(count: 20, sizeGain: 1.5, alphaGain: 3)
      ..resize(size);
    for (var i = 0; i < 20; i++) {
      expect(vivid.radiusOf(i), closeTo(base.radiusOf(i) * 1.5, 1e-4));
      expect(vivid.radiusOf(i),
          lessThanOrEqualTo(LightDustSystem.maxRadius * 1.5 + 1e-4));
    }
    vivid.step(1);
    for (var i = 0; i < 20; i++) {
      expect(vivid.alphaOf(i),
          lessThanOrEqualTo(LightDustSystem.maxBoostedAlpha + 1e-6));
    }
  });

  test('触摸光：α / 半径随增益放大，工厂按组合复用', () {
    expect(NexusTouchLight.colorFor(dark: true, gain: 2).a,
        closeTo(NexusTouchLight.darkAlpha * 2, 0.01));
    expect(NexusTouchLight.colorFor(dark: false, gain: 2).a,
        closeTo(NexusTouchLight.lightAlpha * 2, 0.01));
    expect(NexusTouchLight.colorFor(dark: true, gain: 10).a,
        lessThanOrEqualTo(NexusTouchLight.maxBoostedAlpha + 0.01));
    const box = Size(100, 40);
    expect(NexusTouchLight.radiusFor(box, gain: 2),
        closeTo(40 * NexusTouchLight.radiusFactor * 1.3, 1e-9));
    expect(NexusTouchLight.factoryFor(dark: true), NexusTouchLight.darkFactory);
    expect(
        identical(NexusTouchLight.factoryFor(dark: true, gain: 2),
            NexusTouchLight.factoryFor(dark: true, gain: 2)),
        isTrue);
    expect(NexusTouchLight.factoryFor(dark: false, gain: 2),
        isNot(NexusTouchLight.factoryFor(dark: true, gain: 2)));
  });
}
