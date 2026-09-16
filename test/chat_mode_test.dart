import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/widgets/capsule_top_bar.dart';
import 'package:mobile_agent/presentation/chat/widgets/floating_capsule_input.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

void main() {
  test('ChatState defaults to chat mode and keeps planMode compatible', () {
    const initial = ChatState();
    expect(initial.mode, ChatMode.chat);
    expect(initial.planMode, isFalse);

    final agent = initial.copyWith(mode: ChatMode.agent);
    expect(agent.mode, ChatMode.agent);
    expect(agent.planMode, isFalse);

    final plan = agent.copyWith(mode: ChatMode.plan);
    expect(plan.mode, ChatMode.plan);
    expect(plan.planMode, isTrue);

    final chat = plan.copyWith(planMode: false);
    expect(chat.mode, ChatMode.chat);
    expect(chat.planMode, isFalse);
  });

  test('ChatMode exposes the three user-facing descriptions', () {
    expect(ChatMode.chat.label, '聊天');
    expect(ChatMode.agent.label, 'Agent');
    expect(ChatMode.plan.label, '计划');
    expect(ChatMode.chat.description, contains('不主动执行工具'));
    expect(ChatMode.agent.description, contains('操作工作区'));
    expect(ChatMode.plan.description, contains('确认后执行'));
  });

  test('ReasoningMode provides the standard/deep/auto profiles', () {
    expect(ReasoningMode.values.map((mode) => mode.label), ['标准', '深度', '自动']);
    expect(ReasoningModeX.parse(null), ReasoningMode.standard);
    expect(ReasoningModeX.parse(null, legacyDeepEnabled: true),
        ReasoningMode.auto);
    expect(ReasoningModeX.parse('deep'), ReasoningMode.deep);
  });

  test('composer defaults to the chat mode entry', () {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final input = FloatingCapsuleInput(
      controller: controller,
      isRunning: false,
      onSend: _noop,
      onStop: _noop,
      onAttachmentMenu: _noop,
    );
    expect(input.modeLabel, '聊天');
    expect(const ToolSettings().webBrowsing, isFalse);
  });

  testWidgets('composer exposes the full access approval mode entry',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var approvalTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: FloatingCapsuleInput(
            controller: controller,
            isRunning: false,
            onSend: _noop,
            onStop: _noop,
            onAttachmentMenu: _noop,
            approvalMode: ApprovalMode.fullAccess,
            onApprovalModeTap: () => approvalTapped = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 审批模式入口是圆形磁贴：可读名称只出现在语义标签里。
    expect(find.bySemanticsLabel('完全访问'), findsOneWidget);
    expect(find.text('完全访问'), findsNothing);
    expect(find.text('@Workspace'), findsNothing);
    await tester.tap(find.bySemanticsLabel('完全访问'));
    expect(approvalTapped, isTrue);
  });

  testWidgets('top bar keeps model, workspace and mode visible',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var modeTapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: CapsuleTopBar(
            modelLabel: 'Claude Sonnet',
            workspaceLabel: 'mobile_agent',
            modeLabel: 'Agent',
            sessionTitle: '当前会话',
            onMenu: _noop,
            onNewChat: _noop,
            onModeTap: () => modeTapped++,
          ),
        ),
      ),
    );

    expect(find.text('当前会话'), findsOneWidget);
    expect(find.textContaining('Claude Sonnet · mobile_agent'), findsOneWidget);
    expect(find.textContaining('上下文 0 / 128k'), findsOneWidget);
    expect(find.text('Agent'), findsOneWidget);

    await tester.tap(find.text('Agent'));
    expect(modeTapped, 1);
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
