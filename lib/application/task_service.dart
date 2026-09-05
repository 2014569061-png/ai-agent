import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../infrastructure/database/app_database.dart';

/// 后台任务状态服务（C2）：把 Agent 执行状态写入 Tasks 表，用于断点恢复与通知。
class TaskService {
  /// 是否存在仍在运行（可能已中断）的任务。
  Future<List<Task>> runningTasks(AppDatabase db) => db.runningTasks();

  Future<Task> create({
    required AppDatabase db,
    required String conversationId,
    required String requestJson,
    String type = 'agent',
  }) async {
    final now = DateTime.now();
    final task = Task(
      id: 'task-${now.microsecondsSinceEpoch}',
      conversationId: conversationId,
      type: type,
      status: 'running',
      requestJson: requestJson,
      progressJson: '{}',
      resumeCount: 0,
      createdAt: now,
      updatedAt: now,
    );
    await db.saveTask(task);
    return task;
  }

  Future<void> updateStatus(AppDatabase db, String id, String status) =>
      db.updateTaskStatus(id, status);

  /// 恢复时自增 resumeCount，并刷新 updatedAt。
  Future<void> markResumed(AppDatabase db, String id) async {
    final task = await db.findTask(id);
    if (task == null) return;
    await db.saveTask(task.copyWith(
      resumeCount: task.resumeCount + 1,
      updatedAt: DateTime.now(),
    ));
  }
}

final taskServiceProvider = Provider<TaskService>((ref) => TaskService());
