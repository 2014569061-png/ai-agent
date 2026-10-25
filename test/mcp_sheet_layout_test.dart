import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/mcp/mcp_servers_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MCP 配置表单在窄屏大字体和键盘下仍可到达保存按钮', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: const McpServersPage(),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byTooltip('添加 MCP 服务器'));
    await tester.pump(const Duration(milliseconds: 600));

    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pump(const Duration(milliseconds: 600));

    final save = find.byType(FilledButton).last;
    await tester.ensureVisible(save);
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.getBottomLeft(save).dy, lessThanOrEqualTo(480));
  });
}
