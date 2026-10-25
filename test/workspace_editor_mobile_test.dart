import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/workspace/workspace_editor_page.dart';

void main() {
  testWidgets(
      'workspace editor supports line jumps and protects mobile unsaved edits',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final workspace = Directory.systemTemp.createTempSync('editor-mobile-');
    addTearDown(() => workspace.deleteSync(recursive: true));
    File('${workspace.path}${Platform.pathSeparator}main.txt')
        .writeAsStringSync('one\ntwo\nthree');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: WorkspaceEditorPage(
          workspacePath: workspace.path,
          relativePath: 'main.txt',
        ),
      ),
    );
    // File I/O must get real event-loop time outside the widget test's fake clock.
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 100; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (find.byType(TextField).evaluate().length == 1) return;
      }
      fail('Editor did not load the fixture within the bounded I/O wait.');
    });
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.byTooltip('跳至行'));
    await tester.pumpAndSettle();
    expect(find.text('跳至行'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.first, '3');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();
    final editor = tester.widget<TextField>(fields.last);
    expect(editor.controller!.selection.baseOffset, 8);

    await tester.enterText(fields.last, 'changed');
    await tester.pump();
    expect(find.byTooltip('保存修改'), findsOneWidget);

    final pop = tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    expect(find.text('放弃修改'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await pop;
    expect(tester.takeException(), isNull);
  });
}
