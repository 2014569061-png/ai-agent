import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../infrastructure/database/app_database.dart';
import 'billing_api.dart';
import 'task_service.dart';

/// 仪表盘核心 KPI 指标集
class DashboardKpis {
  const DashboardKpis({
    required this.todayConversations,
    required this.todayTokens,
    required this.todayCachedTokens,
    required this.runningTasks,
    required this.taskSuccessRate,
  });

  final int todayConversations;
  final int todayTokens;
  final int todayCachedTokens;
  final int runningTasks;

  /// 近 7 天任务成功率（0-100）。无已完成/失败样本时为 null，UI 展示 `--`。
  final double? taskSuccessRate;

  double get cacheHitRate => todayTokens <= 0
      ? 0.0
      : (todayCachedTokens / todayTokens).clamp(0.0, 1.0);
}

/// 待办项类型（审批、计划确认、中断恢复）
enum TodoItemType { approval, plan, recoverable }

/// 仪表盘待办项
class DashboardTodoItem {
  const DashboardTodoItem({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    this.taskId,
    this.conversationId,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String description;
  final TodoItemType type;
  final String? taskId;
  final String? conversationId;
  final DateTime createdAt;
}

/// 仪表盘运行记录项
class DashboardRunItem {
  const DashboardRunItem({
    required this.id,
    required this.title,
    required this.status,
    required this.type,
    this.durationMs,
    required this.createdAt,
    this.conversationId,
  });

  final String id;
  final String title;
  final String status;
  final String type;
  final int? durationMs;
  final DateTime createdAt;
  final String? conversationId;
}

/// 仪表盘完整聚合数据载体
class DashboardSummary {
  const DashboardSummary({
    required this.kpis,
    required this.weeklyUsage,
    required this.recentRuns,
    required this.todos,
    required this.recentConversations,
  });

  final DashboardKpis kpis;
  final List<UsageDaily> weeklyUsage;
  final List<DashboardRunItem> recentRuns;
  final List<DashboardTodoItem> todos;
  final List<Conversation> recentConversations;
}

/// 仪表盘数据服务：SQLite 聚合查询（按时间过滤下沉到 SQL，避免全表拉取），
/// 纯函数式不可变返回。
class DashboardService {
  Future<DashboardSummary> loadSummary({
    required AppDatabase db,
    PlanState? currentPlanState,
    String? currentConversationId,
  }) async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final sevenDaysAgo = todayStart.subtract(const Duration(days: 6));

    // 并行发起各域查询，避免串行 DB 往返。
    final conversationsF = db.conversationsSince(todayStart);
    final weekConversationsF = db.conversationsSince(sevenDaysAgo);
    final runsF = db.runsSince(sevenDaysAgo);
    final weekTasksF = db.tasksSince(sevenDaysAgo);
    final runningTasksF = db.runningTasks();

    final todayConvs = await conversationsF;
    final weekConvs = await weekConversationsF;
    final runs = await runsF;
    final weekTasks = await weekTasksF;
    final runningTasks = await runningTasksF;

    // 1. 今日会话
    final todayConversations = todayConvs.length;

    // 2. Token 用量与 7 天趋势（窗口 = 近 7 个自然日，含今日）
    int todayTokens = 0;
    int todayCachedTokens = 0;
    final dailyTokensMap = <String, _DailyTokenBucket>{};
    for (int i = 0; i < 7; i++) {
      final d = sevenDaysAgo.add(Duration(days: i));
      dailyTokensMap[_dayKey(d)] = _DailyTokenBucket(day: _dayKey(d));
    }
    for (final run in runs) {
      final total = run.inputTokens + run.outputTokens;
      if (run.startedAt.isAfter(todayStart)) {
        todayTokens += total.toInt();
        todayCachedTokens += run.cachedTokens.toInt();
      }
      final dateKey = _dayKey(run.startedAt);
      if (dailyTokensMap.containsKey(dateKey)) {
        dailyTokensMap[dateKey]!.add(
          prompt: run.inputTokens,
          completion: run.outputTokens,
          cached: run.cachedTokens,
          costCents: run.estimatedCostCents ?? 0,
        );
      }
    }
    final weeklyUsage = dailyTokensMap.values
        .map((b) => b.toUsageDaily())
        .toList(growable: false);

    // 3. 任务状态与成功率（近 7 天窗口）
    int runningCount = runningTasks.length;
    int completedCount = 0;
    int failedCount = 0;

    final taskInfoList = <DevelopmentTaskInfo>[];
    for (final t in weekTasks) {
      final info = DevelopmentTaskInfo.fromTask(t);
      taskInfoList.add(info);

      final status = info.status.toLowerCase();
      if (status == 'awaiting_approval' || status == 'waiting_approval') {
        runningCount++;
      }

      if (status == 'completed' || status == 'success') {
        completedCount++;
      } else if (status == 'failed' || status == 'cancelled') {
        failedCount++;
      }
    }

    final totalFinished = completedCount + failedCount;
    final double successRate = totalFinished == 0
        ? 100.0
        : ((completedCount / totalFinished) * 100).clamp(0.0, 100.0);

    // 4. 最近运行项 (取前 6 条)
    final recentRuns = taskInfoList.take(6).map((info) {
      final duration = info.updatedAt.difference(info.createdAt).inMilliseconds;
      return DashboardRunItem(
        id: info.id,
        title: info.title,
        status: info.status,
        type: info.type,
        durationMs: duration > 0 ? duration : null,
        createdAt: info.createdAt,
        conversationId: info.conversationId,
      );
    }).toList(growable: false);

    // 5. 待办项聚合 (待审批、待确认计划、可恢复任务)
    final todos = <DashboardTodoItem>[];

    // 待审批（近 7 天窗口内创建/更新的任务）
    for (final info in taskInfoList) {
      final status = info.status.toLowerCase();
      if (status == 'awaiting_approval' || status == 'waiting_approval') {
        todos.add(DashboardTodoItem(
          id: 'approval-${info.id}',
          title: '工具调用待审批',
          description: info.title,
          type: TodoItemType.approval,
          taskId: info.id,
          conversationId: info.conversationId,
          createdAt: info.updatedAt,
        ));
      }
    }

    // 待确认计划（仅当前活跃会话的计划态）
    if (currentPlanState != null &&
        currentPlanState.status != 'cancelled' &&
        currentPlanState.status != 'executing' &&
        currentPlanState.status != 'completed' &&
        currentPlanState.steps.isNotEmpty) {
      todos.add(DashboardTodoItem(
        id: 'plan-${currentConversationId ?? "active"}',
        title: '待确认执行计划',
        description: currentPlanState.steps.first.description,
        type: TodoItemType.plan,
        conversationId: currentConversationId,
        createdAt: now,
      ));
    }

    // 可恢复任务（运行中被中断且可恢复的）
    for (final t in runningTasks) {
      if (t.resumeCount > 0) {
        final info = DevelopmentTaskInfo.fromTask(t);
        todos.add(DashboardTodoItem(
          id: 'resume-${t.id}',
          title: '中断任务可恢复',
          description: info.title,
          type: TodoItemType.recoverable,
          taskId: t.id,
          conversationId: t.conversationId,
          createdAt: t.updatedAt,
        ));
      }
    }

    // 6. 最近会话 (取前 5 条)
    final recentConversations = weekConvs.take(5).toList(growable: false);

    return DashboardSummary(
      kpis: DashboardKpis(
        todayConversations: todayConversations,
        todayTokens: todayTokens,
        todayCachedTokens: todayCachedTokens,
        runningTasks: runningCount,
        taskSuccessRate: successRate,
      ),
      weeklyUsage: weeklyUsage,
      recentRuns: recentRuns,
      todos: todos,
      recentConversations: recentConversations,
    );
  }
}

/// 日期桶 key：含年份，避免 7 天窗口跨年时（12/27-01/02）聚合串月。
String _dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 展示用短日期（MM-dd）。
String _shortDay(String fullKey) {
  final parts = fullKey.split('-');
  return parts.length == 3 ? '${parts[1]}-${parts[2]}' : fullKey;
}

class _DailyTokenBucket {
  _DailyTokenBucket({required this.day});
  final String day;
  int calls = 0;
  int prompt = 0;
  int completion = 0;
  int cached = 0;
  int cost = 0;

  void add(
      {required int prompt,
      required int completion,
      required int cached,
      required int costCents}) {
    calls++;
    this.prompt += prompt;
    this.completion += completion;
    this.cached += cached;
    cost += costCents;
  }

  UsageDaily toUsageDaily() => UsageDaily(
        // 展示层沿用 MM-dd 短格式；桶 key 用完整 yyyy-MM-dd 保证跨年正确。
        day: _shortDay(day),
        calls: calls,
        promptTokens: prompt,
        completionTokens: completion,
        cachedTokens: cached,
        spendCents: cost,
        costCents: cost,
      );
}

final dashboardServiceProvider = Provider<DashboardService>((ref) {
  return DashboardService();
});
