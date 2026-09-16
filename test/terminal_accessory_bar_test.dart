import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/terminal/terminal_accessory_bar.dart';

void main() {
  testWidgets('TerminalAccessoryBar renders keys and fires callbacks',
      (tester) async {
    String? lastInput;
    String? lastCtrl;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalAccessoryBar(
            onSendInput: (val) => lastInput = val,
            onSendCtrl: (val) => lastCtrl = val,
          ),
        ),
      ),
    );

    // Verify key existence
    expect(find.text('ESC'), findsOneWidget);
    expect(find.text('TAB'), findsOneWidget);
    expect(find.text('CTRL'), findsOneWidget);
    expect(find.text('Ctrl+C'), findsOneWidget);
    expect(find.text('↑'), findsOneWidget);

    // Tap ESC
    await tester.tap(find.text('ESC'));
    expect(lastInput, '\x1b');

    // Tap TAB
    await tester.tap(find.text('TAB'));
    expect(lastInput, '\t');

    // Tap Ctrl+C
    await tester.tap(find.text('Ctrl+C'));
    expect(lastCtrl, 'C');

    // Tap UP arrow
    await tester.tap(find.text('↑'));
    expect(lastInput, '\x1b[A');
  });
}
