import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/presentation/chat/widgets/floating_capsule_input.dart';
import 'package:mobile_agent/presentation/chat/widgets/nexus_back_to_latest_button.dart';
import 'package:mobile_agent/presentation/chat/widgets/reasoning_block.dart';
import 'package:mobile_agent/presentation/chat/widgets/tool_activity_section.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

void main() {
  testWidgets('back-to-latest uses readable foreground on the blue pill',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Center(
            child: NexusBackToLatestButton(
              onTap: _noop,
              unreadCount: 2,
              isRunning: true,
            ),
          ),
        ),
      ),
    );

    final theme = AppTheme.light();
    final icon = tester.widget<Icon>(find.byIcon(Icons.arrow_downward_rounded));
    final running = tester.widget<Text>(find.text('生成中…'));
    final pill = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('生成中…'),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = pill.decoration! as BoxDecoration;

    expect(icon.color, theme.colorScheme.onPrimary);
    expect(running.style?.color, theme.colorScheme.onPrimary);
    expect(decoration.color, theme.colorScheme.primary);
  });

  testWidgets('reasoning header does not overflow with long status text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(320, 720)).copyWith(
            textScaler: const TextScaler.linear(1.35),
          ),
          child: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(8),
              child: ReasoningCompactBlock(
                reasoning: '',
                streaming: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('REASONING'), findsOneWidget);
  });

  testWidgets('compact tool timeline keeps completed failures out of the tail',
      (tester) async {
    const activity = ToolActivity(
      call: ToolCall(
        id: 'failed-1',
        name: 'terminal',
        arguments: {'command': 'which adb'},
      ),
      risk: ToolRisk.safe,
      status: '执行失败',
      ok: false,
      effect: ToolEffect.none,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: ToolActivityTimeline(
            activities: [activity],
            running: false,
            compact: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 项未完成，查看原因（点击展开）'), findsOneWidget);
    expect(find.text('未完成：执行命令 which adb'), findsNothing);

    await tester.tap(find.text('1 项未完成，查看原因（点击展开）'));
    await tester.pumpAndSettle();
    expect(find.text('未完成：执行命令 which adb'), findsOneWidget);
  });

  testWidgets('composer aligns magnets with left 2 and right 3 on narrow screens',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(640, 1440);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: FloatingCapsuleInput(
              controller: controller,
              isRunning: false,
              onSend: _noop,
              onStop: _noop,
              onAttachmentMenu: _noop,
              modeLabel: '聊天',
              onModeTap: _noop,
              onApprovalModeTap: _noop,
              approvalMode: ApprovalMode.fullAccess,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final mode = tester.getRect(find.bySemanticsLabel('聊天模式'));
    final approval = tester.getRect(find.bySemanticsLabel('完全访问'));
    final code = tester.getRect(find.bySemanticsLabel('插入代码块'));
    final attach = tester.getRect(find.bySemanticsLabel('添加附件或更多工具'));
    final send = tester.getRect(find.bySemanticsLabel(RegExp('发送')));

    // 左组：模式与审批策略紧凑靠左
    expect(mode.right, lessThanOrEqualTo(approval.left));
    // 右组与左组两端分开（SpaceBetween）
    expect(code.left, greaterThan(approval.right));
    // 右组内部紧凑靠右
    expect(attach.left - code.right, lessThanOrEqualTo(24));
    expect(send.left - attach.right, lessThanOrEqualTo(24));
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
