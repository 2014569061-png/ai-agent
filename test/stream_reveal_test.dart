// M6 流式回复出现：首 token 淡入一次、历史消息不动画、进度时间线平滑收起。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/widgets/message_bubble.dart';
import 'package:mobile_agent/presentation/chat/widgets/reasoning_block.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/motion/nexus_motion.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

Widget _host(Widget child, {MotionLevel level = MotionLevel.full}) {
  return MaterialApp(
    theme: AppTheme.light(),
    builder: (context, c) => NexusMotionScope(level: level, child: c!),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

Widget _bubble(String text, {bool running = true}) => MessageBubble(
      message: ChatMessage(
        role: MessageRole.assistant,
        parts: [MessagePart.text(text)],
      ),
      isLast: true,
      running: running,
      onLongPress: () {},
      onRegenerate: () {},
    );

double _opacityOf(WidgetTester tester, String text) {
  final fade = tester.widget<FadeTransition>(find
      .ancestor(
        of: find.textContaining(text, findRichText: true).first,
        matching: find.byType(FadeTransition),
      )
      .first);
  return fade.opacity.value;
}

Future<void> _unmount(WidgetTester tester) async {
  // 思考卡片运行中有 1s 计时器，结束前卸载，避免残留 Timer。
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  testWidgets('首个 token 到达时正文淡入 180ms，后续 token 不再重播', (tester) async {
    await tester.pumpWidget(_host(_bubble('')));
    await tester.pump();
    await tester.pumpWidget(_host(_bubble('Hello')));
    expect(_opacityOf(tester, 'Hello'), 0);

    await tester.pump(NexusMotion.answerReveal ~/ 2);
    final mid = _opacityOf(tester, 'Hello');
    expect(mid, greaterThan(0));
    expect(mid, lessThan(1));

    await tester.pump(NexusMotion.answerReveal);
    expect(_opacityOf(tester, 'Hello'), 1);

    // 继续追加 token：不重播淡入，也不创建新的动画帧。
    await tester.pumpWidget(_host(_bubble('Hello world')));
    expect(_opacityOf(tester, 'Hello world'), 1);
    await _unmount(tester);
  });

  testWidgets('历史 / 已完成消息直接显示，不播放淡入', (tester) async {
    await tester.pumpWidget(_host(_bubble('Done reply', running: false)));
    expect(_opacityOf(tester, 'Done reply'), 1);
    await tester.pump(NexusMotion.answerReveal ~/ 2);
    expect(_opacityOf(tester, 'Done reply'), 1);
  });

  testWidgets('reduced 下首个 token 直接显示', (tester) async {
    await tester.pumpWidget(_host(_bubble(''), level: MotionLevel.reduced));
    await tester.pump();
    await tester
        .pumpWidget(_host(_bubble('Hello'), level: MotionLevel.reduced));
    expect(_opacityOf(tester, 'Hello'), 1);
    await _unmount(tester);
  });

  testWidgets('淡入途中切换到 reduced 立即完成', (tester) async {
    await tester.pumpWidget(_host(_bubble('')));
    await tester.pump();
    await tester.pumpWidget(_host(_bubble('Hello')));
    await tester.pump(const Duration(milliseconds: 40));
    expect(_opacityOf(tester, 'Hello'), lessThan(1));
    await tester
        .pumpWidget(_host(_bubble('Hello'), level: MotionLevel.reduced));
    expect(_opacityOf(tester, 'Hello'), 1);
    await _unmount(tester);
  });

  group('进度时间线', () {
    final progress = ChatRunProgress.started(now: DateTime(2026, 9, 25));

    Widget block({required bool answered}) => ReasoningCompactBlock(
          key: const Key('rb'),
          reasoning: '',
          streaming: true,
          hasStartedAnswer: answered,
          progress: progress,
        );

    testWidgets('答案开始后时间线用 220ms 平滑收起并能 settle', (tester) async {
      await tester.pumpWidget(_host(block(answered: false)));
      await tester.pump();
      final expanded = tester.getSize(find.byKey(const Key('rb'))).height;

      await tester.pumpWidget(_host(block(answered: true)));
      await tester.pump(NexusMotion.base ~/ 2);
      final mid = tester.getSize(find.byKey(const Key('rb'))).height;

      await tester.pump(NexusMotion.base);
      final collapsed = tester.getSize(find.byKey(const Key('rb'))).height;
      expect(collapsed, lessThan(expanded));
      expect(mid, lessThan(expanded));
      expect(mid, greaterThan(collapsed));
      expect(tester.binding.transientCallbackCount, 0);
      await _unmount(tester);
    });

    testWidgets('reduced 下时间线立即收起', (tester) async {
      await tester.pumpWidget(
          _host(block(answered: false), level: MotionLevel.reduced));
      await tester.pump();
      await tester
          .pumpWidget(_host(block(answered: true), level: MotionLevel.reduced));
      await tester.pump();
      final now = tester.getSize(find.byKey(const Key('rb'))).height;
      await tester.pump(NexusMotion.base);
      expect(tester.getSize(find.byKey(const Key('rb'))).height, now);
      await _unmount(tester);
    });
  });
}
