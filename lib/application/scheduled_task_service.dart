import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../infrastructure/database/app_database.dart';

/// 定时任务调度规格（C5）。cron 字段存 JSON：
/// `{"hour":9,"minute":0,"days":[1,2,3,4,5]}`，days 为空表示每天。
/// days 用 ISO 星期（1=周一 … 7=周日）。
class ScheduleSpec {
  const ScheduleSpec(
      {required this.hour, required this.minute, this.days = const []});

  final int hour;
  final int minute;
  final List<int> days;

  static ScheduleSpec fromCron(String cron) {
    try {
      final map = jsonDecode(cron) as Map<String, dynamic>;
      return ScheduleSpec(
        hour: (map['hour'] as num?)?.toInt() ?? 9,
        minute: (map['minute'] as num?)?.toInt() ?? 0,
        days: (map['days'] as List<dynamic>? ?? const [])
            .whereType<num>()
            .map((e) => e.toInt())
            .toList(),
      );
    } catch (_) {
      return const ScheduleSpec(hour: 9, minute: 0);
    }
  }

  String toCron() => jsonEncode({'hour': hour, 'minute': minute, 'days': days});

  /// 是否到点（15 分钟宽限窗口，适配 WorkManager 的最小周期粒度）。
  /// [lastRunAt] 传上次执行时间（用 updatedAt 近似），避免同周期重复执行。
  bool isDue(DateTime now, DateTime? lastRunAt) {
    if (days.isNotEmpty && !days.contains(now.weekday)) return false;
    final scheduled = DateTime(now.year, now.month, now.day, hour, minute);
    if (now.isBefore(scheduled)) return false;
    if (now.difference(scheduled) > const Duration(minutes: 15)) return false;
    if (lastRunAt != null && !lastRunAt.isBefore(scheduled)) return false;
    return true;
  }
}

/// 定时任务服务（C5）：CRUD + 到点判断。
class ScheduledTaskService {
  Future<ScheduledTask> create({
    required AppDatabase db,
    required String name,
    required String prompt,
    required ScheduleSpec schedule,
    String? agentId,
  }) async {
    final now = DateTime.now();
    final task = ScheduledTask(
      id: 'sched-${now.microsecondsSinceEpoch}',
      name: name,
      prompt: prompt,
      cron: schedule.toCron(),
      agentId: agentId,
      enabled: true,
      lastResult: null,
      createdAt: now,
      updatedAt: now,
    );
    await db.saveScheduledTask(task);
    return task;
  }

  Future<List<ScheduledTask>> dueTasks(AppDatabase db, DateTime now) async {
    final all = await db.allScheduledTasks();
    return all
        .where((t) =>
            t.enabled && ScheduleSpec.fromCron(t.cron).isDue(now, t.updatedAt))
        .toList();
  }
}

final scheduledTaskServiceProvider =
    Provider<ScheduledTaskService>((ref) => ScheduledTaskService());
