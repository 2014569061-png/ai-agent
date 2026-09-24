// M4 按压光感：卡片内 InkWell 的光斑、NexusPressable 的跟随光斑与分档。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/motion/motion_tier.dart';
import 'package:mobile_agent/presentation/widgets/nexus_pressable.dart';
import 'package:mobile_agent/presentation/widgets/nexus_touch_light.dart';
import 'package:mobile_agent/presentation/widgets/section_card.dart';

Widget _app(
  Widget child, {
  MotionLevel level = MotionLevel.full,
  MotionTier? tier,
  Brightness brightness = Brightness.light,
}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
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
    home: Scaffold(body: Center(child: child)),
  );
}

Widget _card() => SizedBox(
      width: 200,
      height: 80,
      child: SectionCard(
        child: InkWell(
          key: const Key('ink'),
          onTap: () {},
          child: const SizedBox.expand(),
        ),
      ),
    );

InteractiveInkFeatureFactory _factoryAt(WidgetTester tester, Finder f) =>
    Theme.of(tester.element(f)).splashFactory;

void main() {
  testWidgets('SectionCard 内的 InkWell 使用按压光斑（浅色 / 深色）', (tester) async {
    await tester.pumpWidget(_app(_card()));
    expect(_factoryAt(tester, find.byKey(const Key('ink'))),
        same(NexusTouchLight.lightFactory));
    await tester.pumpWidget(_app(_card(), brightness: Brightness.dark));
    await tester.pumpAndSettle();
    expect(_factoryAt(tester, find.byKey(const Key('ink'))),
        same(NexusTouchLight.darkFactory));
  });

  testWidgets('卡片以外的 InkWell 保持系统默认水波纹', (tester) async {
    await tester.pumpWidget(_app(InkWell(
      key: const Key('plain'),
      onTap: () {},
      child: const SizedBox(width: 50, height: 50),
    )));
    final factory = _factoryAt(tester, find.byKey(const Key('plain')));
    expect(factory, isNot(same(NexusTouchLight.lightFactory)));
    expect(factory, isNot(same(NoSplash.splashFactory)));
  });

  testWidgets('按下立即画出光斑，抬起后淡出并移除', (tester) async {
    await tester.pumpWidget(_app(_card()));
    final gesture = await tester
        .startGesture(tester.getCenter(find.byKey(const Key('ink'))));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));
    final ink = Material.of(tester.element(find.byKey(const Key('ink'))))
        as RenderObject;
    expect(ink, paints..circle());

    await gesture.up();
    await tester.pumpAndSettle();
    expect(ink, isNot(paints..circle()));
  });

  testWidgets('低端档 / reduced / off：卡片内不画光斑', (tester) async {
    for (final app in [
      _app(_card(), tier: MotionTier.low),
      _app(_card(), level: MotionLevel.reduced),
      _app(_card(), level: MotionLevel.off),
    ]) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app);
      expect(_factoryAt(tester, find.byKey(const Key('ink'))),
          same(NoSplash.splashFactory));
    }
  });

  NexusPressLightPainter? painterOf(WidgetTester tester) {
    final paints = tester.widgetList<CustomPaint>(find.descendant(
      of: find.byType(NexusPressable),
      matching: find.byType(CustomPaint),
    ));
    for (final p in paints) {
      final painter = p.foregroundPainter;
      if (painter is NexusPressLightPainter) return painter;
    }
    return null;
  }

  testWidgets('NexusPressable：按下出现光斑并跟随手指，抬起后淡出', (tester) async {
    await tester.pumpWidget(_app(NexusPressable(
      onTap: () {},
      child: const ColoredBox(
          color: Colors.white, child: SizedBox(width: 120, height: 60)),
    )));
    final topLeft = tester.getTopLeft(find.byType(NexusPressable));
    final gesture = await tester.startGesture(topLeft + const Offset(20, 20));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));
    final painter = painterOf(tester)!;
    expect(painter.strength.value, 1);
    expect(painter.position.value, const Offset(20, 20));

    await gesture.moveBy(const Offset(10, 5));
    await tester.pump();
    expect(painter.position.value, const Offset(30, 25));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(painter.strength.value, 0);
  });

  testWidgets('NexusPressable：低端档不画光斑，缩放保留', (tester) async {
    await tester.pumpWidget(_app(
      NexusPressable(
        onTap: () {},
        child: const ColoredBox(
            color: Colors.white, child: SizedBox(width: 120, height: 60)),
      ),
      tier: MotionTier.low,
    ));
    expect(painterOf(tester), isNull);
    final gesture = await tester
        .startGesture(tester.getCenter(find.byType(NexusPressable)));
    await tester.pump(const Duration(milliseconds: 120));
    expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 0.97);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  test('颜色：深色白光 α 0.14，浅色品牌色 α 0.08', () {
    expect(NexusTouchLight.colorFor(dark: true).a, closeTo(0.14, 0.005));
    expect(NexusTouchLight.colorFor(dark: false).a, closeTo(0.08, 0.005));
  });
}
