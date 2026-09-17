import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/task_service.dart';
import 'package:mobile_agent/presentation/tasks/task_details_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('task details renders structured results from a stable snapshot',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final task = _task(
      structuredResult: const StructuredTaskResult(
        findings: [
          {'title': '发现一', 'detail': '需要处理'},
        ],
        actions: ['采取动作一'],
        nextSteps: ['执行下一步'],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: TaskDetailsPage(task: task)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('结构化产物'), findsOneWidget);
    expect(find.text('发现一：需要处理'), findsOneWidget);
    expect(find.text('采取动作一'), findsOneWidget);
    expect(find.text('执行下一步'), findsOneWidget);
  });

  testWidgets('task details tolerates a missing structured result',
      (tester) async {
    final task = _task();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: TaskDetailsPage(task: task)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('结构化产物'), findsNothing);
    expect(find.text('任务总览'), findsOneWidget);
  });
}

DevelopmentTaskInfo _task({StructuredTaskResult? structuredResult}) {
  final now = DateTime(2026, 9, 17, 12);
  return DevelopmentTaskInfo(
    id: 'task-test',
    conversationId: '',
    type: 'agent',
    status: 'queued',
    prompt: '测试任务',
    title: '测试任务详情',
    sourceType: 'manual',
    workspacePath: null,
    model: null,
    summary: null,
    runId: null,
    createdAt: now,
    updatedAt: now,
    resumeCount: 0,
    structuredResult: structuredResult,
  );
}
