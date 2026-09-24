import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/tools/command_tool.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/workspace/terminal_job_panel.dart';

void main() {
  testWidgets('job completion crossfades stop action to completion mark',
      (tester) async {
    Widget host(bool completed) => MaterialApp(
          home: Scaffold(
            body: NexusMotionScope(
              level: MotionLevel.full,
              child: TerminalJobPanel(
                jobs: [
                  TerminalJobSnapshot(
                    jobId: 'job-1',
                    command: 'flutter test',
                    completed: completed,
                    exitCode: completed ? 0 : null,
                  ),
                ],
                activeJobId: 'job-1',
                onSelect: (_) {},
                onCancel: (_) {},
              ),
            ),
          ),
        );

    await tester.pumpWidget(host(false));
    expect(find.byTooltip('停止该作业'), findsOneWidget);

    await tester.pumpWidget(host(true));
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    expect(find.byTooltip('停止该作业'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byTooltip('停止该作业'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
