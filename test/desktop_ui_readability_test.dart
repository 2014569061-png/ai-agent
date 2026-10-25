import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/navigation/desktop_workspace_chrome.dart';
import 'package:mobile_agent/presentation/theme/desktop_theme.dart';
import 'package:mobile_agent/presentation/widgets/desktop_reading_column.dart';

void main() {
  Widget app(Widget child, {double scale = 1, bool desktop = true}) =>
      MaterialApp(
        theme:
            desktop ? DesktopTheme.apply(ThemeData.light()) : ThemeData.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: child),
      );

  testWidgets('large-text rail retains full accessible names and actions',
      (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(900, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selected = -1;
    try {
      for (final scale in [1.0, 1.5, 2.0]) {
        await tester.pumpWidget(app(
          Align(
              alignment: Alignment.centerLeft,
              child: DesktopActivityRail(
                items: const [
                  (icon: Icons.chat, label: '会话'),
                  (icon: Icons.dashboard, label: '工作台')
                ],
                selectedIndex: 0,
                onSelected: (value) => selected = value,
                onSettings: () {},
                onDevices: () {},
              )),
          scale: scale,
        ));
        await tester.pump();
        expect(find.text('工作台'), scale == 1 ? findsOneWidget : findsNothing);
        final node = tester.getSemantics(find.bySemanticsLabel('工作台'));
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        await tester.tap(find.byKey(const ValueKey('desktop-nav-工作台')));
        expect(selected, 1);
        expect(tester.takeException(), isNull);
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('reading column is centered, responsive and desktop only',
      (tester) async {
    const probe = ValueKey('reading-probe');
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final config in [
      (const Size(1440, 900), 1.0, true, 880.0),
      (const Size(1440, 900), 2.0, true, 1100.0),
      (const Size(600, 440), 2.0, true, 600.0),
      (const Size(1440, 900), 1.0, false, 1440.0),
    ]) {
      tester.view.physicalSize = config.$1;
      await tester.pumpWidget(app(
        const DesktopReadingColumn(
            child: SizedBox(key: probe, width: double.infinity, height: 30)),
        scale: config.$2,
        desktop: config.$3,
      ));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(probe)).width, closeTo(config.$4, 1));
      expect(tester.getCenter(find.byKey(probe)).dx,
          closeTo(config.$1.width / 2, 1));
      expect(tester.takeException(), isNull);
    }
  });
}
