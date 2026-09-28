// L2 输入胶囊形变 + 发送飞出：通道时效、FLIP 落地、胶囊聚焦舒展与降级。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/chat/widgets/floating_capsule_input.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/motion/motion_tier.dart';
import 'package:mobile_agent/presentation/motion/send_flight.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

Widget _host(Widget child, {MotionLevel level = MotionLevel.full}) =>
    MaterialApp(
      theme: AppTheme.light(),
      builder: (context, c) => MotionTierScope(
        controller: MotionTierController(initial: MotionTier.high),
        child: NexusMotionScope(level: level, child: c!),
      ),
      home: Scaffold(body: child),
    );

Widget _composer(TextEditingController controller) => Align(
      alignment: Alignment.bottomCenter,
      child: FloatingCapsuleInput(
        controller: controller,
        isRunning: false,
        onSend: () {},
        onStop: () {},
        onAttachmentMenu: () {},
      ),
    );

double _translateY(WidgetTester tester) {
  final t = tester.widget<Transform>(find
      .descendant(
          of: find.byType(SendFlightLanding), matching: find.byType(Transform))
      .first);
  return t.transform.getTranslation().y;
}

double _opacity(WidgetTester tester) => tester
    .widget<Opacity>(find.descendant(
        of: find.byType(SendFlightLanding), matching: find.byType(Opacity)))
    .opacity;

void main() {
  tearDown(SendFlightBus.reset);

  test('通道：认领一次即清空，超过时间窗作废', () {
    var now = Duration.zero;
    SendFlightBus.clock = () => now;
    SendFlightBus.launch(const Rect.fromLTWH(0, 500, 300, 40));
    expect(SendFlightBus.claim()?.source.bottom, 540);
    expect(SendFlightBus.claim(), isNull);

    SendFlightBus.launch(const Rect.fromLTWH(0, 500, 300, 40));
    now += SendFlightBus.window + const Duration(milliseconds: 1);
    expect(SendFlightBus.claim(), isNull);
    expect(SendFlightBus.hasPending, isFalse);

    SendFlightBus.launch(const Rect.fromLTWH(0, 500, 300, 40));
    SendFlightBus.cancel();
    expect(SendFlightBus.claim(), isNull);
  });

  Widget landing(SendFlight flight, VoidCallback onLanded) => Stack(
        children: [
          Positioned(
            top: 100,
            right: 16,
            child: SendFlightLanding(
              flight: flight,
              onLanded: onLanded,
              child: const SizedBox(width: 160, height: 40),
            ),
          ),
        ],
      );

  testWidgets('落地：首帧不可见测量，随后从输入框底边弹簧飞到原位', (tester) async {
    var landed = 0;
    const flight =
        SendFlight(source: Rect.fromLTWH(12, 500, 300, 40), at: Duration.zero);
    await tester.pumpWidget(_host(landing(flight, () => landed++)));
    expect(_opacity(tester), 0);

    await tester.pump();
    final bottom = tester.getBottomLeft(find.byType(SendFlightLanding)).dy;
    // 起点：气泡底边对齐输入框底边（540）。
    expect(_translateY(tester), closeTo(540 - bottom, 1));
    expect(_opacity(tester), 1);

    await tester.pump(const Duration(milliseconds: 120));
    final mid = _translateY(tester);
    expect(mid, lessThan(540 - bottom));
    await tester.pumpAndSettle();
    expect(_translateY(tester), closeTo(0, 0.5));
    expect(landed, 1);
  });

  testWidgets('落地：来源在气泡上方（异常）时直接显示', (tester) async {
    var landed = 0;
    const flight =
        SendFlight(source: Rect.fromLTWH(12, 0, 300, 40), at: Duration.zero);
    await tester.pumpWidget(_host(landing(flight, () => landed++)));
    await tester.pump();
    expect(_translateY(tester), 0);
    expect(landed, 1);
  });

  testWidgets('胶囊：点击发送发起飞出；reduced 下不发起', (tester) async {
    for (final level in [MotionLevel.full, MotionLevel.reduced]) {
      SendFlightBus.reset();
      final controller = TextEditingController(text: '你好');
      await tester.pumpWidget(_host(_composer(controller), level: level));
      await tester
          .tap(find.byKey(const ValueKey('trailing_action_send_active')));
      expect(SendFlightBus.hasPending, level == MotionLevel.full);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('胶囊：聚焦时向两侧舒展 8dp，失焦收回', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(_host(_composer(controller)));
    final rest = tester.getSize(find.byType(TextField)).width;
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(
        tester.getSize(find.byType(TextField)).width, closeTo(rest + 8, 0.5));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(TextField)).width, closeTo(rest, 0.5));
  });

  testWidgets('胶囊：输入多行时高度弹簧增长而非跳变', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(_host(_composer(controller)));
    final field = find
        .ancestor(
            of: find.byType(TextField), matching: find.byType(AnimatedSize))
        .first;
    final start = tester.getSize(field).height;
    controller.text = '第一行\n第二行\n第三行';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final mid = tester.getSize(field).height;
    await tester.pumpAndSettle();
    final end = tester.getSize(field).height;
    expect(end, greaterThan(start + 20));
    expect(mid, greaterThan(start));
    expect(mid, lessThan(end));
  });

  testWidgets('胶囊销毁时作废未认领的飞行', (tester) async {
    final controller = TextEditingController(text: 'hi');
    await tester.pumpWidget(_host(_composer(controller)));
    await tester.tap(find.byKey(const ValueKey('trailing_action_send_active')));
    expect(SendFlightBus.hasPending, isTrue);
    await tester.pumpWidget(_host(const SizedBox()));
    expect(SendFlightBus.hasPending, isFalse);
  });
}
