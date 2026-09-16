import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/terminal/termux_ssh_credentials.dart';
import 'package:mobile_agent/presentation/terminal/terminal_accessory_bar.dart';
import 'package:mobile_agent/presentation/terminal/terminal_page.dart';
import 'package:xterm/xterm.dart';

void main() {
  testWidgets(
      'TerminalPage renders properly with appbar, terminal view and accessory bar',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TerminalPage(
          autoConnect: false,
          initialConfig: SSHTerminalConfig(
            host: '127.0.0.1',
            port: 8022,
          ),
        ),
      ),
    );

    await tester.pump();

    // Verify title and buttons
    expect(find.text('Linux 交互终端'), findsOneWidget);
    expect(find.byType(TerminalView), findsOneWidget);
    expect(find.byType(TerminalAccessoryBar), findsOneWidget);

    // Verify actions
    expect(find.byTooltip('发送诊断给 Agent'), findsOneWidget);
    expect(find.byTooltip('放大字体'), findsOneWidget);
    expect(find.byTooltip('缩小字体'), findsOneWidget);
    expect(find.byTooltip('清屏'), findsOneWidget);
    expect(find.byTooltip('设置与配置向导'), findsOneWidget);
  });

  testWidgets('Termux SSH setup explains whoami username and separate bridge',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TerminalPage(
          autoConnect: false,
          initialConfig: SSHTerminalConfig(),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('设置与配置向导'));
    await tester.pumpAndSettle();

    expect(find.text('用户名（Termux whoami）'), findsOneWidget);
    expect(find.textContaining('SSH/PTY'), findsOneWidget);
    expect(find.textContaining('RUN_COMMAND'), findsOneWidget);
    expect(find.textContaining('whoami'), findsWidgets);
    expect(find.textContaining('8022'), findsWidgets);
  });
}
