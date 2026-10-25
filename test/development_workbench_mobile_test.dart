import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/development_workflow.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/workspace/development_workbench_page.dart';

void main() {
  testWidgets('workbench workflow picker fits narrow and landscape double text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final root = Directory.systemTemp.createTempSync('mobile-workbench-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/index.html')
        .writeAsStringSync('<!doctype html><title>UI fixture</title>');

    for (final size in [const Size(320, 640), const Size(640, 320)]) {
      tester.view.physicalSize = size;
      for (final dark in [false, true]) {
        await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: DevelopmentWorkbenchPage(workspacePath: root.path),
          ),
        ));
        await tester.runAsync(() async {
          for (var attempt = 0; attempt < 200; attempt++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            await tester.pump();
            if (find.text('当前项目：静态网页').evaluate().isNotEmpty) return;
          }
          fail('Workbench did not finish bounded fixture detection.');
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: 'Workbench overflow at $size, dark=$dark');
        final picker =
            find.byType(DropdownButtonFormField<DevelopmentWorkflow>);
        await tester.ensureVisible(picker);
        await tester.pumpAndSettle();
        final button = tester.widget<DropdownButton<DevelopmentWorkflow>>(
          find.descendant(
            of: picker,
            matching: find.byType(DropdownButton<DevelopmentWorkflow>),
          ),
        );
        expect(button.isExpanded, isTrue);
        await tester.tap(picker);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tapAt(const Offset(3, 3));
        await tester.pumpAndSettle();
      }
    }
  });
}
