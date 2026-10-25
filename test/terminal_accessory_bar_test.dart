import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/terminal/terminal_accessory_bar.dart';

void main() {
  testWidgets(
      'terminal keys retain 48dp targets with large text in both themes',
      (tester) async {
    tester.view.physicalSize = const Size(320, 180);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        await tester.pumpWidget(MaterialApp(
          theme: dark ? ThemeData.dark() : ThemeData.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
              body: TerminalAccessoryBar(
            onSendInput: (_) {},
            onSendCtrl: (_) {},
          )),
        ));
        await tester.pumpAndSettle();
        for (final label in ['ESC', 'TAB', 'CTRL']) {
          final key = find
              .ancestor(of: find.text(label), matching: find.byType(InkWell))
              .first;
          final size = tester.getSize(key);
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
        }
        expect(tester.takeException(), isNull);
      }
    }
  });

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
