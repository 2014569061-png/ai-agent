import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/session_metrics.dart';
import 'package:mobile_agent/presentation/chat/widgets/capsule_top_bar.dart';
import 'package:mobile_agent/presentation/chat/widgets/floating_capsule_input.dart';
import 'package:mobile_agent/presentation/chat/widgets/message_bubble.dart';
import 'package:mobile_agent/presentation/chat/widgets/session_metrics_bar.dart';
import 'package:mobile_agent/presentation/chat/widgets/session_metrics_sheet.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/theme/mobile_theme.dart';
import 'package:mobile_agent/presentation/widgets/liquid_glass.dart';

void main() {
  for (final width in [320.0, 360.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final dark in [false, true]) {
        for (final material in GlassIntensity.values) {
          testWidgets('chat layout $width $scale dark=$dark material=$material',
              (tester) async {
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final controller = TextEditingController();
            final boundary = GlobalKey();
            await tester.pumpWidget(MaterialApp(
              theme:
                  MobileTheme.apply(dark ? AppTheme.dark() : AppTheme.light()),
              home: MediaQuery(
                data: MediaQueryData(
                    size: Size(width, 900),
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true),
                child: NexusMotionScope(
                  level: MotionLevel.off,
                  child: Scaffold(
                      body: RepaintBoundary(
                          key: boundary,
                          child: Column(children: [
                            CapsuleTopBar(
                                sessionTitle: '一个较长的会话标题',
                                modelLabel: 'Example model',
                                workspaceLabel: '项目',
                                modeLabel: '聊天',
                                glassIntensity: material,
                                onMenu: () {},
                                onNewChat: () {}),
                            Expanded(
                                child: ListView(children: [
                              MessageBubble(
                                  message: ChatMessage(
                                      role: MessageRole.assistant,
                                      parts: [
                                        const MessagePart.text('简洁回复，正文优先。')
                                      ]),
                                  isLast: true,
                                  running: false,
                                  onLongPress: () {},
                                  onRegenerate: () {}),
                            ])),
                            SessionMetricsHud(
                                messages: [
                                  ChatMessage(
                                      role: MessageRole.user, parts: const [])
                                ],
                                totalSteps: 0,
                                toolActivities: const [],
                                running: false,
                                onTap: () {}),
                            FloatingCapsuleInput(
                                controller: controller,
                                glassIntensity: material,
                                onSend: () {},
                                onStop: () {},
                                onAttachmentMenu: () {},
                                onModeTap: () {},
                                onApprovalModeTap: () {},
                                modeLabel: '聊天',
                                approvalMode: ApprovalMode.fullAccess,
                                isRunning: false),
                          ]))),
                ),
              ),
            ));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.byKey(const ValueKey('quiet-assistant-reply')),
                findsOneWidget);
            expect(find.textContaining('上下文 0 /'), findsNothing);
            expect(find.text('会话详情 · 1 轮'), findsOneWidget);
            expect(find.byTooltip('复制'), findsOneWidget);
            final slot = tester.getRect(
                find.byKey(const ValueKey('composer-primary-action-slot')));
            expect(slot.size, const Size(48, 48));
            if (const bool.fromEnvironment('CAPTURE_UI')) {
              await tester.runAsync(() async {
                final image = await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
                final bytes =
                    await image.toByteData(format: ui.ImageByteFormat.png);
                final dir = Directory('device-check/20260922-ui-polish');
                await dir.create(recursive: true);
                await File(
                        '${dir.path}/chat-${width.toInt()}-$scale-$dark-${material.name}.png')
                    .writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            await tester.pumpWidget(const SizedBox.shrink());
            controller.dispose();
          });
        }
      }
    }
  }

  testWidgets('metrics opens as overview; diagnostics remain reachable',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SessionMetricsSheet(
      metrics: SessionMetrics.empty,
      liveContextTokens: 100,
      contextLimit: 32000,
    ))));
    expect(find.text('输入 / 输出'), findsOneWidget);
    expect(find.text('详细诊断'), findsOneWidget);
    expect(find.text('步骤'), findsNothing);
    expect(find.text('未记录'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('metrics-details-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('步骤'), findsOneWidget);
    expect(find.text('Token 构成'), findsOneWidget);
  });

  testWidgets(
      'composer action slot stable across send, running and keyboard; tools are named',
      (tester) async {
    final controller = TextEditingController(text: '消息');
    Future<void> pump(bool running, double keyboard) =>
        tester.pumpWidget(MaterialApp(
            home: MediaQuery(
                data: MediaQueryData(
                    viewInsets: EdgeInsets.only(bottom: keyboard)),
                child: Scaffold(
                    body: Align(
                        alignment: Alignment.bottomCenter,
                        child: FloatingCapsuleInput(
                            controller: controller,
                            isRunning: running,
                            onSend: () {},
                            onStop: () {},
                            onAttachmentMenu: () {},
                            onModeTap: () {}))))));
    await pump(false, 0);
    await tester.pumpAndSettle();
    final before = tester
        .getRect(find.byKey(const ValueKey('composer-primary-action-slot')));
    await pump(true, 0);
    await tester.pumpAndSettle();
    expect(
        tester.getRect(
            find.byKey(const ValueKey('composer-primary-action-slot'))),
        before);
    await pump(true, 260);
    await tester.pumpAndSettle();
    expect(
        tester.getSize(
            find.byKey(const ValueKey('composer-primary-action-slot'))),
        const Size(48, 48));
    await tester.tap(find.byTooltip('更多输入工具'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('插入代码块'));
    await tester.pumpAndSettle();
    expect(controller.text, contains('```'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
