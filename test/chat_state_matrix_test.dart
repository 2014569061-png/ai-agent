import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/error_humanizer.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/session_metrics.dart';
import 'package:mobile_agent/presentation/chat/widgets/message_bubble.dart';
import 'package:mobile_agent/presentation/chat/widgets/floating_capsule_input.dart';
import 'package:mobile_agent/presentation/chat/widgets/session_metrics_sheet.dart';
import 'package:mobile_agent/presentation/chat/widgets/tool_approval_sheet.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    for (final dark in [false, true]) {
      for (final state in [
        'empty',
        'stream',
        'stopped',
        'failed',
        'approval',
        'metrics'
      ]) {
        testWidgets('large text $width dark=$dark state=$state',
            (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final controller = TextEditingController();
          final running = state == 'stream';
          var retried = false;
          final Widget body;
          if (state == 'approval') {
            body = const SingleChildScrollView(
                child: ToolApprovalSheet(
                    call: ToolCall(
                        id: 'test',
                        name: 'read_file',
                        arguments: {'path': 'lib/main.dart'}),
                    risk: ToolRisk.safe,
                    allowSessionTrust: false));
          } else if (state == 'metrics') {
            body = const SessionMetricsSheet(
                metrics: SessionMetrics.empty,
                liveContextTokens: 0,
                contextLimit: 32000);
          } else {
            body = Column(children: [
              Expanded(
                  child: ListView(children: [
                if (state != 'empty')
                  MessageBubble(
                      message: ChatMessage(
                          role: MessageRole.assistant,
                          modelName:
                              'A-very-long-model-name-for-layout-testing',
                          parts: [
                            MessagePart.text(state == 'failed'
                                ? formatErrorForMessage('timeout')
                                : state == 'stopped'
                                    ? '已停止，保留已生成的内容。'
                                    : '正在生成一段内容。')
                          ]),
                      isLast: true,
                      running: running,
                      onLongPress: () {},
                      onRegenerate: () => retried = true,
                      onEditPrompt: () {},
                      onSwitchModel: () {}),
              ])),
              FloatingCapsuleInput(
                  controller: controller,
                  isRunning: running,
                  onSend: () {},
                  onStop: () {},
                  onAttachmentMenu: () {},
                  onModeTap: () {}),
            ]);
          }
          await tester.pumpWidget(MaterialApp(
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              home: MediaQuery(
                  data: MediaQueryData(
                      size: Size(width, 900),
                      textScaler: const TextScaler.linear(2),
                      disableAnimations: true),
                  child: NexusMotionScope(
                      level: MotionLevel.off, child: Scaffold(body: body)))));
          await tester.pump(const Duration(milliseconds: 200));
          expect(tester.takeException(), isNull);
          if (state == 'failed') {
            await tester.ensureVisible(find.text('重试'));
            await tester.tap(find.text('重试'));
            expect(retried, isTrue);
          }
          if (state == 'approval') {
            expect(find.text('确认执行'), findsOneWidget);
            expect(find.text('拒绝'), findsOneWidget);
          }
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        });
      }
    }
  }
}
