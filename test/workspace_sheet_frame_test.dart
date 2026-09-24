import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/workspace/file_tree_sheet.dart';
import 'package:mobile_agent/presentation/workspace/workspace_sheet_frame.dart';

void main() {
  testWidgets('工作区弹层在窄屏大字体和键盘下保留底部操作', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => WorkspaceSheetFrame(
                child: Column(
                  children: [
                    const Expanded(child: Center(child: Text('作业输出'))),
                    const TextField(),
                    FilledButton(
                      onPressed: () {},
                      child: const Text('执行操作'),
                    ),
                  ],
                ),
              ),
            ),
            child: const Text('打开弹层'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开弹层'));
    await tester.pumpAndSettle();

    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();

    expect(tester.getBottomLeft(find.text('执行操作')).dy, lessThanOrEqualTo(480));
    expect(tester.takeException(), isNull);
  });

  testWidgets('文件树弹层在 320dp 和 2 倍字体下不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => WorkspaceSheetFrame(
                child: FileTreeSheet(
                  workspacePath: Directory.systemTemp.path,
                  directoryLoader: (_) async => const [],
                ),
              ),
            ),
            child: const Text('打开文件树'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开文件树'));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(FileTreeSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
