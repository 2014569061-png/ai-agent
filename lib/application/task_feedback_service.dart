import '../infrastructure/database/app_database.dart';

/// Thin application seam for task feedback writes and north-star aggregates.
class TaskFeedbackService {
  const TaskFeedbackService();

  Future<TaskFeedbackData?> feedbackForTask(AppDatabase db, String taskId) =>
      db.feedbackForTask(taskId);

  Future<void> save({
    required AppDatabase db,
    required String taskId,
    String? runId,
    required bool helpful,
  }) =>
      db.saveTaskFeedback(
        taskId: taskId,
        runId: runId,
        helpful: helpful,
      );

  Future<TaskFeedbackMetrics> metrics(AppDatabase db) async {
    final samples = await db.taskFeedbackCount();
    final helpful = await db.helpfulTaskFeedbackCount();
    return TaskFeedbackMetrics(
      samples: samples,
      helpfulRate: samples == 0 ? null : helpful / samples * 100,
    );
  }
}

class TaskFeedbackMetrics {
  const TaskFeedbackMetrics({required this.samples, required this.helpfulRate});

  final int samples;
  final double? helpfulRate;
}
