import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  testWidgets('TerminalView widget test', (tester) async {
    final terminal = Terminal(maxLines: 500);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalView(terminal),
        ),
      ),
    );
    expect(find.byType(TerminalView), findsOneWidget);
  });
}
