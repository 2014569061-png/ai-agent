import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/application/dashboard_service.dart';
import 'package:mobile_agent/presentation/chat/chat_scroll_coordinator.dart';
import 'package:mobile_agent/presentation/chat/widgets/chat_message_list.dart';
import 'package:mobile_agent/presentation/dashboard/widgets/kpi_card_grid.dart';
import 'package:mobile_agent/presentation/l10n/app_strings.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/widgets/nexus_metric_tile.dart';

class RecordingScrollController extends ScrollController {
  Duration? lastDuration;
  int jumps = 0;
  @override
  Future<void> animateTo(double offset,
      {required Duration duration, required Curve curve}) {
    lastDuration = duration;
    return super.animateTo(offset, duration: duration, curve: curve);
  }

  @override
  void jumpTo(double value) {
    jumps++;
    super.jumpTo(value);
  }
}

Widget host(Widget child, MotionLevel level, bool systemOff) => MaterialApp(
      home: NexusMotionScope(
          level: level,
          child: MediaQuery(
            data: MediaQueryData(disableAnimations: systemOff),
            child: Scaffold(body: child),
          )),
    );

void main() {
  for (final level in MotionLevel.values) {
    for (final systemOff in [false, true]) {
      final off = systemOff || level == MotionLevel.off;
      testWidgets('return to latest respects $level / systemOff=$systemOff',
          (tester) async {
        final controller = RecordingScrollController();
        late BuildContext context;
        final coordinator = ChatScrollCoordinator(controller,
            isRunning: () => false,
            adjustDuration: (base) =>
                MotionPreferences.adjustDuration(context, base, listen: false));
        await tester.pumpWidget(host(Builder(builder: (c) {
          context = c;
          return ListView(
              controller: controller,
              children: List.generate(
                  30, (i) => SizedBox(height: 80, child: Text('$i'))));
        }), level, systemOff));
        coordinator.scrollToBottom();
        if (off) {
          expect(controller.lastDuration, isNull);
          expect(controller.jumps, 1);
          expect(controller.position.extentAfter, 0);
        } else {
          expect(controller.lastDuration,
              Duration(milliseconds: level == MotionLevel.reduced ? 120 : 260));
        }
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        coordinator.dispose();
        controller.dispose();
      });

      testWidgets('message fallback respects $level / systemOff=$systemOff',
          (tester) async {
        final controller = RecordingScrollController();
        final key = GlobalKey<ChatMessageListState>();
        await tester.pumpWidget(host(
            ChatMessageList(
              key: key,
              messages: const [],
              controller: controller,
              running: false,
              onLongPress: (_) {},
              onRegenerate: () {},
              trailingWidgets: const [SizedBox(height: 2000)],
            ),
            level,
            systemOff));
        await tester.pumpAndSettle();
        controller.lastDuration = null;
        controller.jumps = 0;
        key.currentState!.scrollToMessageId('missing');
        if (off) {
          expect(controller.lastDuration, isNull);
          expect(controller.jumps, 1);
        } else {
          expect(controller.lastDuration, isNotNull);
          if (level == MotionLevel.reduced) {
            expect(controller.lastDuration, const Duration(milliseconds: 120));
          }
        }
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      });
    }
  }

  testWidgets('queued tail-follow reads changed preference at execution',
      (tester) async {
    final controller = RecordingScrollController();
    var duration = const Duration(milliseconds: 180);
    final coordinator = ChatScrollCoordinator(controller,
        isRunning: () => false, adjustDuration: (_) => duration);
    Widget list(int count) => MaterialApp(
        home: SizedBox(
            height: 200,
            child: ListView(
                controller: controller,
                children:
                    List.generate(count, (_) => const SizedBox(height: 100)))));
    await tester.pumpWidget(list(2));
    final old = [ChatMessage(id: 'a', role: MessageRole.user, parts: [])];
    final next = [
      ...old,
      ChatMessage(id: 'b', role: MessageRole.user, parts: [])
    ];
    coordinator.messagesChanged(
        previous: old,
        next: next,
        resetSession: false,
        running: false,
        completed: true);
    duration = Duration.zero;
    await tester.pumpWidget(list(20));
    expect(controller.lastDuration, isNull);
    expect(controller.jumps, 1);
    expect(controller.position.extentAfter, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    coordinator.dispose();
    controller.dispose();
  });

  testWidgets('cache KPI is explanatory rather than an empty action',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: KpiCardGrid(
      kpis: DashboardKpis(
          todayConversations: 0,
          todayTokens: 0,
          todayPromptTokens: 0,
          todayCachedTokens: 0,
          runningTasks: 0,
          taskSuccessRate: null,
          weeklyHelpfulTasks: 0,
          taskFeedbackRate: null,
          taskFeedbackSamples: 0),
    ))));
    final tile = tester
        .widgetList<NexusMetricTile>(find.byType(NexusMetricTile))
        .singleWhere((tile) => tile.label == AppStrings.cacheHitRate);
    expect(tile.onTap, isNull);
    expect(tile.explanation, AppStrings.cacheHitRateHint);
  });
}
