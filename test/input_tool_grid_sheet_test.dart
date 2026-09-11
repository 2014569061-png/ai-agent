import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/widgets/input_tool_grid_sheet.dart';
import 'package:mobile_agent/presentation/chat/widgets/floating_capsule_input.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

void main() {
  testWidgets('InputToolGridSheet renders all tools and triggers callbacks',
      (tester) async {
    bool promptCalled = false;
    bool mcpCalled = false;
    bool terminalCalled = false;
    bool dashboardCalled = false;
    bool planModeCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                InputToolGridSheet.show(
                  context,
                  onCommandMenu: () => promptCalled = true,
                  onMcpMenu: () => mcpCalled = true,
                  onTerminalPreview: () => terminalCalled = true,
                  onEnvSetup: () {},
                  onOpenDashboard: () => dashboardCalled = true,
                  planModeEnabled: true,
                  onPlanModeToggle: () => planModeCalled = true,
                  approvalMode: ApprovalMode.ask,
                  onApprovalModeTap: () {},
                );
              },
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ),
    );

    // 打开 Sheet
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // 验证标题与各工具
    expect(find.text('工作台工具箱'), findsOneWidget);
    expect(find.text('提示词库'), findsOneWidget);
    expect(find.text('MCP 服务'), findsOneWidget);
    expect(find.text('终端预览'), findsOneWidget);
    expect(find.text('开发环境'), findsOneWidget);
    expect(find.text('仪表盘'), findsOneWidget);
    expect(find.text('计划模式'), findsOneWidget);
    expect(find.text('审批策略'), findsOneWidget);

    // 点击提示词库
    await tester.tap(find.text('提示词库'));
    await tester.pumpAndSettle();
    expect(promptCalled, isTrue);

    // 重新打开 Sheet 并点击 MCP 服务
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MCP 服务'));
    await tester.pumpAndSettle();
    expect(mcpCalled, isTrue);

    // 重新打开 Sheet 并点击终端预览
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('终端预览'));
    await tester.pumpAndSettle();
    expect(terminalCalled, isTrue);

    // 重新打开 Sheet 并点击仪表盘
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('仪表盘'));
    await tester.pumpAndSettle();
    expect(dashboardCalled, isTrue);

    // 重新打开 Sheet 并点击计划模式
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('计划模式'));
    await tester.pumpAndSettle();
    expect(planModeCalled, isTrue);
  });

  testWidgets('首页输入区只呈现「深度思考 / 智能搜索」两个能力 chip', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    bool deepToggled = false;
    bool webToggled = false;
    bool attachTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: FloatingCapsuleInput(
            controller: controller,
            isRunning: false,
            onSend: () {},
            onStop: () {},
            onAttachmentMenu: () => attachTapped = true,
            onDeepThinkingToggle: () => deepToggled = true,
            onWebSearchToggle: () => webToggled = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 占位符按新规范显示为「发消息」
    expect(find.text('发消息'), findsOneWidget);

    // 只保留两个能力 chip，不再出现「工具 / 计划」
    expect(find.text('深度思考'), findsOneWidget);
    expect(find.text('智能搜索'), findsOneWidget);
    expect(find.text('工具'), findsNothing);
    expect(find.text('计划'), findsNothing);

    await tester.tap(find.text('深度思考'));
    await tester.pumpAndSettle();
    expect(deepToggled, isTrue);

    await tester.tap(find.text('智能搜索'));
    await tester.pumpAndSettle();
    expect(webToggled, isTrue);

    // 「＋」按钮触发附件 / 更多工具菜单
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    expect(attachTapped, isTrue);
  });

  testWidgets('有输入内容时语音键切换为发送键', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    bool sent = false;
    bool voiceTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: FloatingCapsuleInput(
            controller: controller,
            isRunning: false,
            onSend: () => sent = true,
            onStop: () {},
            onAttachmentMenu: () {},
            onVoiceInput: () => voiceTapped = true,
            onDeepThinkingToggle: () {},
            onWebSearchToggle: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 空输入 → 语音键
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.graphic_eq_rounded));
    await tester.pumpAndSettle();
    expect(voiceTapped, isTrue);

    // 有输入 → 发送键
    controller.text = '你好';
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(find.byIcon(Icons.graphic_eq_rounded), findsNothing);

    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();
    expect(sent, isTrue);
  });
}
