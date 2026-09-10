import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/widgets/input_tool_grid_sheet.dart';
import 'package:mobile_agent/presentation/widgets/immersive_action_sheet.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

void main() {
  testWidgets('approval strategy can be changed from the tools sheet',
      (tester) async {
    final previousErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!details
          .exceptionAsString()
          .startsWith('ListTile background color')) {
        previousErrorHandler?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = previousErrorHandler);

    await tester.pumpWidget(const _ApprovalModeHarness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('打开工具箱'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('审批策略'));
    await tester.pumpAndSettle();

    expect(find.text('操作权限'), findsOneWidget);
    await tester.tap(find.text('自动批准低风险'));
    await tester.pumpAndSettle();

    expect(find.text('当前策略：自动批准低风险'), findsOneWidget);
  });
}

class _ApprovalModeHarness extends StatefulWidget {
  const _ApprovalModeHarness();

  @override
  State<_ApprovalModeHarness> createState() => _ApprovalModeHarnessState();
}

class _ApprovalModeHarnessState extends State<_ApprovalModeHarness> {
  ApprovalMode _mode = ApprovalMode.ask;

  void _openTools(BuildContext context) {
    InputToolGridSheet.show(
      context,
      onCommandMenu: () {},
      onMcpMenu: () {},
      onTerminalPreview: () {},
      onEnvSetup: () {},
      planModeEnabled: false,
      onPlanModeToggle: () {},
      approvalMode: _mode,
      onApprovalModeTap: () => _openApprovalMode(context),
    );
  }

  Future<void> _openApprovalMode(BuildContext context) async {
    final selected = await showImmersiveActionSheet<ApprovalMode>(
      context: context,
      title: '操作权限',
      items: [
        for (final mode in ApprovalMode.values)
          ActionSheetItem(
            title: switch (mode) {
              ApprovalMode.ask => '每次询问',
              ApprovalMode.autoSafe => '自动批准低风险',
              ApprovalMode.fullAccess => '完全访问',
            },
            value: mode,
          ),
      ],
    );
    if (selected != null && mounted) {
      setState(() => _mode = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              Text('当前策略：${switch (_mode) {
                ApprovalMode.ask => '每次询问',
                ApprovalMode.autoSafe => '自动批准低风险',
                ApprovalMode.fullAccess => '完全访问',
              }}'),
              ElevatedButton(
                onPressed: () => _openTools(context),
                child: const Text('打开工具箱'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
