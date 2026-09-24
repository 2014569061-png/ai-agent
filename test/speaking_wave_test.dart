// M10 朗读声波条：伪波形参数、分档、真实电平接口，以及只在正在朗读的消息上显示。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/widgets/chat_message_list.dart';
import 'package:mobile_agent/presentation/chat/widgets/message_bubble.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/motion/motion_tier.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/widgets/speaking_wave.dart';

Widget _app(
  Widget child, {
  MotionLevel level = MotionLevel.full,
  MotionTier? tier,
  bool tickerEnabled = true,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
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
      body: TickerMode(enabled: tickerEnabled, child: Center(child: child)),
    ),
  );
}

bool _looping(WidgetTester tester) =>
    (tester.state(find.byType(SpeakingWave)) as dynamic).isLooping as bool;

ChatMessage _message(MessageRole role, String text) =>
    ChatMessage(role: role, parts: [MessagePart.text(text)]);

void main() {
  test('伪波形：高度在 4–14dp，相位依次错开', () {
    for (var ms = 0.0; ms < 7200; ms += 17) {
      for (var i = 0; i < SpeakingWave.barCount; i++) {
        expect(
            SpeakingWave.pseudoHeight(i, ms),
            inInclusiveRange(
                SpeakingWave.minBarHeight, SpeakingWave.maxBarHeight));
      }
    }
    final heights = [
      for (var i = 0; i < SpeakingWave.barCount; i++)
        SpeakingWave.pseudoHeight(i, 300),
    ];
    expect(heights.toSet().length, greaterThan(1));
    // 一整轮（7200ms）后回到同一帧，循环无缝。
    for (var i = 0; i < SpeakingWave.barCount; i++) {
      expect(SpeakingWave.pseudoHeight(i, 7200 + 123),
          closeTo(SpeakingWave.pseudoHeight(i, 123), 1e-9));
    }
  });

  test('真实电平：0 为最低，1 时最高一根达到 14dp', () {
    for (var i = 0; i < SpeakingWave.barCount; i++) {
      expect(SpeakingWave.levelHeight(i, 0), SpeakingWave.minBarHeight);
    }
    expect(SpeakingWave.levelHeight(1, 1), SpeakingWave.maxBarHeight);
    expect(SpeakingWave.levelHeight(1, 5), SpeakingWave.maxBarHeight);
  });

  testWidgets('真实 App（有 Scope）时伪波形循环，卸载后停止', (tester) async {
    await tester.pumpWidget(_app(const SpeakingWave(), tier: MotionTier.high));
    expect(_looping(tester), isTrue);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('无 Scope 时静态，pumpAndSettle 可结束', (tester) async {
    await tester.pumpWidget(_app(const SpeakingWave()));
    await tester.pumpAndSettle();
    expect(_looping(tester), isFalse);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('reduced / off：显示静态喇叭图标', (tester) async {
    for (final level in [MotionLevel.reduced, MotionLevel.off]) {
      await tester.pumpWidget(
          _app(const SpeakingWave(), level: level, tier: MotionTier.high));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
      expect(_looping(tester), isFalse);
    }
  });

  testWidgets('页面被遮挡时停止', (tester) async {
    await tester.pumpWidget(_app(const SpeakingWave(), tier: MotionTier.high));
    expect(_looping(tester), isTrue);
    await tester.pumpWidget(_app(const SpeakingWave(),
        tier: MotionTier.high, tickerEnabled: false));
    expect(_looping(tester), isFalse);
  });

  testWidgets('传入真实电平时不自带循环，随电平重绘', (tester) async {
    final level = ValueNotifier<double>(0.2);
    addTearDown(level.dispose);
    await tester
        .pumpWidget(_app(SpeakingWave(level: level), tier: MotionTier.high));
    expect(_looping(tester), isFalse);
    level.value = 0.9;
    await tester.pump();
    await tester.pumpAndSettle();
  });

  test('SpeakingAtIndex：只在目标索引匹配时为 true，并按 (源, 索引) 判等', () {
    final source = ValueNotifier<int?>(null);
    final a = SpeakingAtIndex(source, 1);
    var calls = 0;
    void listener() => calls++;
    a.addListener(listener);
    expect(a.value, isFalse);
    source.value = 1;
    expect(a.value, isTrue);
    source.value = 2;
    expect(a.value, isFalse);
    expect(calls, 2);
    a.removeListener(listener);
    expect(SpeakingAtIndex(source, 1), SpeakingAtIndex(source, 1));
    expect(SpeakingAtIndex(source, 1), isNot(SpeakingAtIndex(source, 2)));
    source.dispose();
  });

  testWidgets('气泡操作行：朗读中显示声波条，否则显示朗读图标', (tester) async {
    final speaking = ValueNotifier<bool>(false);
    addTearDown(speaking.dispose);
    await tester.pumpWidget(_app(
      MessageBubble(
        message: _message(MessageRole.assistant, '你好'),
        isLast: true,
        running: false,
        onLongPress: () {},
        onRegenerate: () {},
        onSpeak: () {},
        speakingListenable: speaking,
      ),
    ));
    expect(find.byType(SpeakingWave), findsNothing);
    speaking.value = true;
    await tester.pump();
    expect(find.byType(SpeakingWave), findsOneWidget);
    expect(find.byTooltip('停止朗读'), findsOneWidget);
  });

  testWidgets('消息列表：只有正在朗读的那条回复显示声波条', (tester) async {
    final controller = ScrollController();
    final speakingIndex = ValueNotifier<int?>(null);
    addTearDown(controller.dispose);
    addTearDown(speakingIndex.dispose);
    await tester.pumpWidget(_app(
      SizedBox(
        width: 400,
        height: 800,
        child: ChatMessageList(
          messages: [
            _message(MessageRole.user, '问题一'),
            _message(MessageRole.assistant, '回答一'),
            _message(MessageRole.user, '问题二'),
            _message(MessageRole.assistant, '回答二'),
          ],
          controller: controller,
          running: false,
          onLongPress: (_) {},
          onRegenerate: () {},
          onSpeak: (_) {},
          speakingIndexListenable: speakingIndex,
        ),
      ),
    ));
    await tester.pump();
    expect(find.byType(SpeakingWave), findsNothing);
    expect(find.byTooltip('朗读'), findsNWidgets(2));

    speakingIndex.value = 3;
    await tester.pump();
    expect(find.byType(SpeakingWave), findsOneWidget);
    expect(find.byTooltip('朗读'), findsOneWidget);
    expect(find.byTooltip('停止朗读'), findsOneWidget);

    speakingIndex.value = null;
    await tester.pump();
    expect(find.byType(SpeakingWave), findsNothing);
  });
}
