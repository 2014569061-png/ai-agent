import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/error_humanizer.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/widgets/message_bubble.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

/// 预算暂停不是错误：正文写入暂停标记，气泡渲染成暂停卡并提供续跑入口。
void main() {
  group('run pause notice text', () {
    test('round-trips kind, maxSteps and runId', () {
      final text = '已完成前两步。\n\n${formatRunPauseForMessage(
        kind: RunPauseKind.budget,
        maxSteps: 40,
        runId: 'run-1',
      )}';
      final split = splitRunPauseNotice(text);
      expect(split.main, '已完成前两步。');
      expect(split.notice?.kind, RunPauseKind.budget);
      expect(split.notice?.maxSteps, 40);
      expect(split.notice?.runId, 'run-1');
      expect(split.notice?.title, contains('40'));
    });

    test('recognizes legacy budget pauses rendered as unknown errors', () {
      final legacy =
          '部分结果\n\n${formatErrorForMessage('已达到单次执行步数预算，任务已暂停，可继续执行')}';
      final split = splitRunPauseNotice(legacy);
      expect(split.notice?.kind, RunPauseKind.budget);
      expect(split.main, '部分结果');
    });

    test('a reply that merely quotes the phrase is not a pause', () {
      const reply = '界面提示「已达到单次执行步数预算」说明任务轮数用完了。';
      final split = splitRunPauseNotice(reply);
      expect(split.notice, isNull);
      expect(split.main, reply);
    });

    test('strip keeps only the human sentence', () {
      final text = '正文\n\n${formatRunPauseForMessage(
        kind: RunPauseKind.budget,
        maxSteps: 16,
      )}';
      final stripped = stripRunPauseMarker(text);
      expect(stripped, isNot(contains(kRunPauseMarker)));
      expect(stripped, isNot(contains('maxSteps')));
      expect(stripped, contains('已执行 16 轮'));
    });
  });

  Future<void> pumpBubble(
    WidgetTester tester, {
    required bool isLast,
    VoidCallback? onResumeRun,
    VoidCallback? onRegenerate,
  }) async {
    final pause = formatRunPauseForMessage(
      kind: RunPauseKind.budget,
      maxSteps: 40,
      runId: 'run-1',
    );
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 900),
          disableAnimations: true,
        ),
        child: NexusMotionScope(
          level: MotionLevel.off,
          child: Scaffold(
            body: ListView(children: [
              MessageBubble(
                message: ChatMessage(
                  role: MessageRole.assistant,
                  modelName: 'test-model',
                  parts: [MessagePart.text('已完成一部分。\n\n$pause')],
                ),
                isLast: isLast,
                running: false,
                onLongPress: () {},
                onRegenerate: onRegenerate ?? () {},
                onSwitchModel: () {},
                onResumeRun: onResumeRun,
              ),
            ]),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('last paused reply shows the pause card with continue actions',
      (tester) async {
    var resumed = false;
    var restarted = false;
    await pumpBubble(
      tester,
      isLast: true,
      onResumeRun: () => resumed = true,
      onRegenerate: () => restarted = true,
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('run-pause-notice')), findsOneWidget);
    expect(find.textContaining('已执行 40 轮'), findsOneWidget);
    expect(find.textContaining('未预期的错误'), findsNothing);
    expect(find.textContaining(kRunPauseMarker), findsNothing);
    expect(
        find.byKey(const ValueKey('run-pause-switch-model')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('run-pause-continue')));
    expect(resumed, isTrue);
    await tester.tap(find.byKey(const ValueKey('run-pause-restart')));
    expect(restarted, isTrue);
  });

  testWidgets('older pause notices keep the text but hide the actions',
      (tester) async {
    await pumpBubble(tester, isLast: false, onResumeRun: () {});
    expect(find.byKey(const ValueKey('run-pause-notice')), findsOneWidget);
    expect(find.byKey(const ValueKey('run-pause-continue')), findsNothing);
    expect(find.byKey(const ValueKey('run-pause-restart')), findsNothing);
  });
}
