import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/widgets/empty_state_view.dart';
import 'package:mobile_agent/presentation/workspace/file_tree_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FileTreeSheet renders EmptyStateView when directory does not exist',
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
