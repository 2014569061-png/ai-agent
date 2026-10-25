import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/database/run_plan_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/task_service.dart';
import 'package:mobile_agent/presentation/tasks/task_details_page.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final seed = await TaskService().create(db: db, conversationId: '',
        requestJson: '{}');
    await db.saveTask(seed.copyWith(id: 'task-test', status: 'queued'));
  });

  testWidgets('unknown task outcome shows verification path without replay',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final task = await TaskService().create(db: db, conversationId: '',
        requestJson: '{}');
    final store = RunPlanStore(db);
    final token = await store.bind(taskId: task.id, runId: 'isolated-ui');
    await store.claim(token, 'unknown-ui-call');
    await TaskService().updateStatus(db, task.id, 'paused',
        runId: token.runId, planVersion: token.version);
    final paused = (await db.findTask(task.id))!;
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
      child: MaterialApp(home: TaskDetailsPage(task: TaskService().describe(paused))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('恢复前需要核实'), findsOneWidget);
    expect(find.text('重新核实执行记录'), findsOneWidget);
    await tester.tap(find.text('重新核实执行记录'));
    await tester.pumpAndSettle();
    final row = await db.customSelect(
        'SELECT state,effect FROM run_dispatch_claims').getSingle();
    expect(row.read<String>('state'), 'dispatched');
    expect(row.read<String>('effect'), 'unknown');
    expect((await store.head(task.id))!.token.runId, 'isolated-ui');
  });

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
        overrides: [databaseProvider.overrideWith((ref) async => db)],
        child: MaterialApp(home: TaskDetailsPage(task: task)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('结构化产物'), findsOneWidget);
    expect(find.text('发现一：需要处理'), findsOneWidget);
    expect(find.text('采取动作一'), findsOneWidget);
    expect(find.text('执行下一步'), findsOneWidget);
  });

  testWidgets('long task details remain usable with double text in both themes',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const title = '需要完整展示状态与后续操作的超长移动端开发任务名称';
    for (final size in [const Size(320, 640), const Size(640, 320)]) {
      tester.view.physicalSize = size;
      for (final dark in [false, true]) {
        await tester.pumpWidget(ProviderScope(
          overrides: [databaseProvider.overrideWith((ref) async => db)],
          child: MaterialApp(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: TaskDetailsPage(
                task: _task(
              title: title,
              model: 'organization/deepseek-mobile-acceptance-long-model-name',
              structuredResult: const StructuredTaskResult(
                findings: [
                  {'title': '长任务检查', 'detail': '保持结果、状态和操作可读'}
                ],
                actions: ['保留现有工作区改动并完成验证'],
                nextSteps: ['在横屏和窄屏中检查完整操作路径'],
              ),
            )),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.byType(TaskDetailsPage), findsOneWidget);
        expect(find.text(title), findsWidgets);
        expect(tester.takeException(), isNull,
            reason: 'Task details overflow at $size, dark=$dark');
      }
    }
  });

  testWidgets('task details tolerates a missing structured result',
      (tester) async {
    final task = _task();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWith((ref) async => db)],
        child: MaterialApp(home: TaskDetailsPage(task: task)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('结构化产物'), findsNothing);
    expect(find.text('任务总览'), findsOneWidget);
  });
}

DevelopmentTaskInfo _task({
  StructuredTaskResult? structuredResult,
  String title = '测试任务详情',
  String? model,
}) {
  final now = DateTime(2026, 9, 17, 12);
  return DevelopmentTaskInfo(
    id: 'task-test',
    conversationId: '',
    type: 'agent',
    status: 'queued',
    prompt: '测试任务',
    title: title,
    sourceType: 'manual',
    workspacePath: null,
    model: model,
    summary: null,
    runId: null,
    createdAt: now,
    updatedAt: now,
    resumeCount: 0,
    structuredResult: structuredResult,
  );
}
