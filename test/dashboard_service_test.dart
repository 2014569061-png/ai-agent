import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/dashboard_service.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DashboardService service;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    service = DashboardService();
  });

  tearDown(() async {
    await db.close();
  });

  test('loads summary from empty database', () async {
    final summary = await service.loadSummary(db: db);

    expect(summary.kpis.todayConversations, 0);
    expect(summary.kpis.todayTokens, 0);
    expect(summary.kpis.todayCachedTokens, 0);
    expect(summary.kpis.runningTasks, 0);
    expect(summary.kpis.taskSuccessRate, isNull);
    expect(summary.weeklyUsage.length, 7);
    expect(summary.recentRuns, isEmpty);
    expect(summary.todos, isEmpty);
    expect(summary.recentConversations, isEmpty);
  });

  test(
      'correctly aggregates today stats, weekly token trend, and task success rate',
      () async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterday = todayStart.subtract(const Duration(hours: 12));

    // 1. 会话
    await db.saveConversation(Conversation(
      id: 'conv-today',
      title: '今日会话',
      isPinned: false,
      isFavorite: false,
      tagsJson: '[]',
      createdAt: now,
      updatedAt: now,
    ));
    await db.saveConversation(Conversation(
      id: 'conv-yesterday',
      title: '昨日会话',
      isPinned: false,
      isFavorite: false,
      tagsJson: '[]',
      createdAt: yesterday,
      updatedAt: yesterday,
    ));

    // 2. 任务：1完成，1失败，1运行中
    await db.into(db.tasks).insert(Task(
          id: 'task-1',
          conversationId: 'conv-today',
          type: 'agent',
          status: 'completed',
          requestJson: jsonEncode({'title': '任务1'}),
          progressJson: '{}',
          resumeCount: 0,
          createdAt: now,
          updatedAt: now,
        ));
    await db.into(db.tasks).insert(Task(
          id: 'task-2',
          conversationId: 'conv-today',
          type: 'agent',
          status: 'failed',
          requestJson: jsonEncode({'title': '任务2'}),
          progressJson: '{}',
          resumeCount: 0,
          createdAt: now,
          updatedAt: now,
        ));
    await db.into(db.tasks).insert(Task(
          id: 'task-3',
          conversationId: 'conv-today',
          type: 'agent',
          status: 'running',
          requestJson: jsonEncode({'title': '任务3'}),
          progressJson: '{}',
          resumeCount: 0,
          createdAt: now,
          updatedAt: now,
        ));

    // 3. 运行记录 (Token 用量)
    await db.into(db.runRecords).insert(RunRecord(
          runId: 'run-1',
          conversationId: 'conv-today',
          model: 'gpt-4o',
          status: 'completed',
          startedAt: now,
          inputTokens: 1000,
          outputTokens: 500,
          cachedTokens: 200,
          eventCount: 3,
          retryCount: 0,
        ));

    final summary = await service.loadSummary(db: db);

    expect(summary.kpis.todayConversations, 1);
    expect(summary.kpis.todayTokens, 1500);
    expect(summary.kpis.todayCachedTokens, 200);
    expect(summary.kpis.runningTasks, 1);
    // 1 completed + 1 failed = 50%
    expect(summary.kpis.taskSuccessRate, 50.0);
    expect(summary.recentRuns.length, 3);
    expect(summary.recentConversations.length, 2);
    expect(summary.weeklyUsage.last.isToday, isTrue);
  });

  test('aggregates pending todos for approvals, plans, and recoverable tasks',
      () async {
    final now = DateTime.now();

    // 待审批任务
    await db.into(db.tasks).insert(Task(
          id: 'task-approval',
          conversationId: 'conv-1',
          type: 'agent',
          status: 'awaiting_approval',
          requestJson: jsonEncode({'title': '安装依赖 vite'}),
          progressJson: '{}',
          resumeCount: 0,
          createdAt: now,
          updatedAt: now,
        ));

    // 中断可恢复任务
    await db.into(db.tasks).insert(Task(
          id: 'task-recover',
          conversationId: 'conv-1',
          type: 'agent',
          status: 'running',
          requestJson: jsonEncode({'title': '代码重构'}),
          progressJson: '{}',
          resumeCount: 1,
          createdAt: now,
          updatedAt: now,
        ));

    // 待确认计划
    final planState = const PlanState(
      steps: [
        PlanStep(id: 's1', description: '执行数据库迁移'),
      ],
      status: 'planning',
    );

    final summary = await service.loadSummary(
      db: db,
      currentPlanState: planState,
      currentConversationId: 'conv-1',
    );

    expect(summary.todos.length, 3);
    expect(summary.todos.any((t) => t.type == TodoItemType.approval), isTrue);
    expect(summary.todos.any((t) => t.type == TodoItemType.plan), isTrue);
    expect(
        summary.todos.any((t) => t.type == TodoItemType.recoverable), isTrue);
  });
}
