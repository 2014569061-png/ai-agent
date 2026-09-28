// M5 发送反馈：发送按钮弹簧缩放、发送光圈、用户气泡弹簧升起及各档降级。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/widgets/chat_message_list.dart';
import 'package:mobile_agent/presentation/chat/widgets/floating_capsule_input.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/motion/motion_tier.dart';
import 'package:mobile_agent/presentation/motion/nexus_motion.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/widgets/nexus_pressable.dart';

const _sendKey = ValueKey('trailing_action_send_active');
const _slotKey = ValueKey('composer-primary-action-slot');

Widget _host(
  Widget child, {
  MotionLevel level = MotionLevel.full,
  MotionTier tier = MotionTier.high,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    builder: (context, c) => MotionTierScope(
      controller: MotionTierController(initial: tier),
      child: NexusMotionScope(level: level, child: c!),
    ),
    home: Scaffold(body: child),
  );
}

Widget _composer(TextEditingController controller, {bool running = false}) =>
    Align(
      alignment: Alignment.bottomCenter,
      child: FloatingCapsuleInput(
        controller: controller,
        isRunning: running,
        onSend: () {},
        onStop: () {},
        onAttachmentMenu: () {},
      ),
    );

AnimatedScale _scaleOf(WidgetTester tester, Key key) =>
    tester.widget<AnimatedScale>(find.descendant(
      of: find.byKey(key),
      matching: find.byType(AnimatedScale),
    ));

/// 光圈是前景层上唯一的描边圆；按钮本体只画填充圆。
bool _paintsRipple(WidgetTester tester) {
  final slotPaint = find
      .ancestor(of: find.byKey(_slotKey), matching: find.byType(CustomPaint))
      .first;
  var found = false;
  expect(
    tester.renderObject(slotPaint),
    paints
      ..everything((method, args) {
        if (method == #drawCircle) {
          final paint = args[2] as Paint;
          if (paint.style == PaintingStyle.stroke) {
            final radius = args[1] as double;
            expect(radius, inInclusiveRange(0, 28));
            expect(paint.color.a, lessThanOrEqualTo(0.35 + 1e-6));
            found = true;
          }
        }
        return true;
      }),
  );
  return found;
}

Future<void> _pressAndRelease(WidgetTester tester, Key key) async {
  final gesture = await tester.startGesture(tester.getCenter(find.byKey(key)));
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pump(const Duration(milliseconds: 60));
  expect(_scaleOf(tester, key).scale, NexusMotion.sendPressedScale);
  await gesture.up();
  await tester.pump();
}

ChatMessage _msg(MessageRole role, String text) =>
    ChatMessage(role: role, parts: [MessagePart.text(text)]);

void main() {
  test('allowOvershoot 保留弹簧过冲，默认曲线仍限制在 0..1', () {
    final lively =
        NexusSpringCurve(NexusMotion.springLively, allowOvershoot: true);
    final clamped = NexusSpringCurve(NexusMotion.springLively);
    var livelyMax = 0.0;
    var clampedMax = 0.0;
    for (var i = 1; i < 100; i++) {
      livelyMax = livelyMax > lively.transform(i / 100)
          ? livelyMax
          : lively.transform(i / 100);
      clampedMax = clampedMax > clamped.transform(i / 100)
          ? clampedMax
          : clamped.transform(i / 100);
    }
    expect(livelyMax, greaterThan(1.0));
    expect(livelyMax, lessThan(1.2));
    expect(clampedMax, lessThanOrEqualTo(1.0));
    expect(lively.transform(1), 1);
    expect(NexusMotion.curveSendRelease, isA<NexusSpringCurve>());
  });

  group('发送按钮', () {
    late TextEditingController controller;
    setUp(() => controller = TextEditingController(text: 'hi'));
    tearDown(() => controller.dispose());

    testWidgets('按下缩放到 0.9，松手用轻弹弹簧回到 1.0', (tester) async {
      await tester.pumpWidget(_host(_composer(controller)));
      await _pressAndRelease(tester, _sendKey);
      final release = _scaleOf(tester, _sendKey);
      expect(release.scale, 1.0);
      expect(release.curve, same(NexusMotion.curveSendRelease));
      expect(release.duration, NexusMotion.pressRelease);
      await tester.pumpAndSettle();
    });

    testWidgets('运行中的暂停按钮保持默认按压参数', (tester) async {
      controller.clear();
      await tester.pumpWidget(_host(_composer(controller, running: true)));
      final pressable = tester.widget<NexusPressable>(find.descendant(
        of: find.byKey(const ValueKey('trailing_action_pause')),
        matching: find.byType(NexusPressable),
      ));
      expect(pressable.pressedScale, 0.97);
      expect(pressable.releaseCurve, isNull);
      expect(pressable.releaseDuration, isNull);
    });

    testWidgets('发送时画出扩散光圈，结束后不再绘制', (tester) async {
      await tester.pumpWidget(_host(_composer(controller)));
      expect(_paintsRipple(tester), isFalse);
      await _pressAndRelease(tester, _sendKey);
      await tester.pump(const Duration(milliseconds: 140));
      expect(_paintsRipple(tester), isTrue);
      await tester.pumpAndSettle();
      expect(_paintsRipple(tester), isFalse);
    });

    testWidgets('低端档保留缩放但不画光圈', (tester) async {
      await tester
          .pumpWidget(_host(_composer(controller), tier: MotionTier.low));
      await _pressAndRelease(tester, _sendKey);
      await tester.pump(const Duration(milliseconds: 140));
      expect(_paintsRipple(tester), isFalse);
      await tester.pumpAndSettle();
    });

    testWidgets('reduced 下不缩放也不画光圈', (tester) async {
      await tester
          .pumpWidget(_host(_composer(controller), level: MotionLevel.reduced));
      final gesture =
          await tester.startGesture(tester.getCenter(find.byKey(_sendKey)));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 60));
      expect(_scaleOf(tester, _sendKey).scale, 1.0);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 140));
      expect(_paintsRipple(tester), isFalse);
      await tester.pumpAndSettle();
    });
  });

  group('新消息入场', () {
    late ScrollController scroll;
    setUp(() => scroll = ScrollController());
    tearDown(() => scroll.dispose());

    Widget list(List<ChatMessage> messages,
            {MotionLevel level = MotionLevel.full}) =>
        _host(
          ChatMessageList(
            sessionKey: 'm5',
            messages: messages,
            controller: scroll,
            running: true,
            onLongPress: (_) {},
            onRegenerate: () {},
          ),
          level: level,
        );

    ({double width, double bottom}) measure(WidgetTester tester, String text) {
      final f = find.text(text, findRichText: true).first;
      return (
        width: tester.getBottomRight(f).dx - tester.getTopLeft(f).dx,
        bottom: tester.getBottomRight(f).dy,
      );
    }

    testWidgets('用户气泡从右下角弹簧升起：16dp 位移、0.96 缩放、前半程淡入', (tester) async {
      final base = [_msg(MessageRole.assistant, 'earlier')];
      await tester.pumpWidget(list(base));
      await tester.pumpAndSettle();
      await tester
          .pumpWidget(list([...base, _msg(MessageRole.user, 'user says hi')]));
      final start = measure(tester, 'user says hi');
      final fade = tester.widget<FadeTransition>(find
          .ancestor(
            of: find.text('user says hi', findRichText: true).first,
            matching: find.descendant(
              of: find.byType(ChatMessageList),
              matching: find.byType(FadeTransition),
            ),
          )
          .last);
      expect(fade.opacity.value, 0);

      await tester.pump(NexusMotion.bubbleRise ~/ 2);
      expect(fade.opacity.value, closeTo(1, 1e-6));

      await tester.pumpAndSettle();
      final end = measure(tester, 'user says hi');
      expect(start.bottom - end.bottom, inInclusiveRange(15, 19));
      expect(start.width / end.width, closeTo(0.96, 0.005));
    });

    testWidgets('L3：助手气泡弹簧入场（自 0.97 放大并上移落定）', (tester) async {
      final base = [_msg(MessageRole.user, 'question')];
      await tester.pumpWidget(list(base));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
          list([...base, _msg(MessageRole.assistant, 'assistant reply')]));
      final start = measure(tester, 'assistant reply');
      await tester.pumpAndSettle();
      final end = measure(tester, 'assistant reply');
      expect(start.width, closeTo(end.width * 0.97, 1));
      expect(start.bottom, greaterThan(end.bottom));
    });

    testWidgets('reduced 下用户气泡直接出现', (tester) async {
      final base = [_msg(MessageRole.assistant, 'earlier')];
      await tester.pumpWidget(list(base, level: MotionLevel.reduced));
      await tester.pumpAndSettle();
      await tester.pumpWidget(list(
          [...base, _msg(MessageRole.user, 'user says hi')],
          level: MotionLevel.reduced));
      final start = measure(tester, 'user says hi');
      await tester.pumpAndSettle();
      final end = measure(tester, 'user says hi');
      expect(start.bottom, closeTo(end.bottom, 0.01));
      expect(start.width, closeTo(end.width, 0.01));
    });
  });
}
