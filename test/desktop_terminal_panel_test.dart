import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:mobile_agent/application/desktop_host_service.dart';
import 'package:mobile_agent/application/desktop_pty_session.dart';
import 'package:mobile_agent/presentation/terminal/desktop_terminal_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'changing workspace rebinds the panel and reopening keeps its terminal',
      (tester) async {
    Widget panel(String workspace) => MaterialApp(
        home: Scaffold(body: DesktopTerminalPanel(workspacePath: workspace)));
    final sessions = DesktopPtySessions.instance;
    await tester.pumpWidget(panel('panel-a'));
    final a = tester.widget<TerminalView>(find.byType(TerminalView)).terminal;
    await tester.pumpWidget(panel('panel-b'));
    final b = tester.widget<TerminalView>(find.byType(TerminalView)).terminal;
    expect(identical(a, b), false);
    expect(identical(b, sessions.forWorkspace('panel-b').terminal), true);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpWidget(panel('panel-a'));
    expect(
        identical(
            tester.widget<TerminalView>(find.byType(TerminalView)).terminal, a),
        true);
    await tester.pumpWidget(const SizedBox.shrink());
    await sessions.closeAll();
  });

  testWidgets('hiding a panel does not close its workspace shell',
      (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var closes = 0;
    messenger.setMockMethodCallHandler(DesktopHostService.channel,
        (call) async {
      if (call.method == 'openTerminal') return 71;
      if (call.method == 'readTerminal') {
        return {'bytes': <int>[], 'exitCode': 259};
      }
      if (call.method == 'closeTerminal') closes++;
      return null;
    });
    final sessions = DesktopPtySessions.instance;
    final session = sessions.forWorkspace('panel-persistent');
    await session.open();
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: DesktopTerminalPanel(workspacePath: 'panel-persistent'))));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(session.connected, true);
    expect(closes, 0);
    await tester.runAsync(sessions.closeAll);
    expect(closes, 1);
    messenger.setMockMethodCallHandler(DesktopHostService.channel, null);
  });
}
