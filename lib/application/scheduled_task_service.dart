import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/unique_id.dart';
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

  bool isDue(DateTime now, DateTime? lastRunAt) {
    final scheduled = latestScheduledAt(now);
    if (scheduled == null) return false;
    return lastRunAt == null || lastRunAt.isBefore(scheduled);
  }

  DateTime? latestScheduledAt(DateTime now) {
    for (var daysAgo = 0; daysAgo <= 7; daysAgo++) {
      final date = now.subtract(Duration(days: daysAgo));
      if (days.isNotEmpty && !days.contains(date.weekday)) continue;
      final candidate = DateTime(date.year, date.month, date.day, hour, minute);
      if (!candidate.isAfter(now)) return candidate;
    }
    return null;
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
      id: UniqueId.generate('sched', now: now),
      name: name,
      prompt: prompt,
      cron: schedule.toCron(),
      agentId: agentId,
      enabled: true,
      lastResult: null,
      lastRunAt: null,
      createdAt: now,
      updatedAt: now,
    );
    await db.saveScheduledTask(task);
    return task;
  }

  Future<List<ScheduledTask>> dueTasks(AppDatabase db, DateTime now) async {
    final all = await db.allScheduledTasks();
    return all
        .where((task) =>
            task.enabled &&
            ScheduleSpec.fromCron(task.cron)
                .isDue(now, task.lastRunAt ?? task.createdAt))
        .toList();
  }
}

final scheduledTaskServiceProvider =
    Provider<ScheduledTaskService>((ref) => ScheduledTaskService());
