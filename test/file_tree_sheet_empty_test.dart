import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/widgets/empty_state_view.dart';
import 'package:mobile_agent/presentation/workspace/file_tree_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'FileTreeSheet keeps navigation inside the workspace and shows no fake Git state',
      (tester) async {
    final separator = Platform.pathSeparator;
    final workspacePath =
        '${Directory.systemTemp.path}${separator}nexus-file-tree';
    final childPath = '$workspacePath${separator}lib';
    final filePath = '$workspacePath${separator}main.dart';
    final outsidePath = '${Directory.systemTemp.path}${separator}outside';
    final entities = <String, List<FileSystemEntity>>{
      workspacePath: [
        Directory(childPath),
        Directory(outsidePath),
        File(filePath)
      ],
      childPath: const [],
    };

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: FileTreeSheet(
            workspacePath: workspacePath,
            directoryLoader: (path) async => entities[path] ?? const [],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('git: main*'), findsNothing);
    expect(find.text('M'), findsNothing);
    final atRoot = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_upward_rounded),
    );
    expect(atRoot.onPressed, isNull);

    await tester.tap(find.text('outside/'));
    await tester.pump();
    expect(find.text(workspacePath), findsOneWidget);
    final stillAtRoot = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_upward_rounded),
    );
    expect(stillAtRoot.onPressed, isNull);

    await tester.tap(find.text('lib/'));
    await tester.pump();
    final inChild = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_upward_rounded),
    );
    expect(inChild.onPressed, isNotNull);

    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    final backAtRoot = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_upward_rounded),
    );
    expect(backAtRoot.onPressed, isNull);
  });

  testWidgets(
      'FileTreeSheet renders EmptyStateView when directory does not exist',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: FileTreeSheet(workspacePath: '/path/does/not/exist/nexus'),
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(EmptyStateView), findsOneWidget);
    expect(find.text('目录读取失败'), findsOneWidget);
  });
}
