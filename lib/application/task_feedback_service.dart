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

  Future<TaskFeedbackMetrics> metrics(AppDatabase db, {DateTime? since}) async {
    final samples = await db.developmentTaskFeedbackCount(since: since);
    final helpful = await db.helpfulDevelopmentTaskFeedbackCount(since: since);
    return TaskFeedbackMetrics(
      samples: samples,
      helpfulCount: helpful,
      helpfulRate: samples == 0 ? null : helpful / samples * 100,
    );
  }
}

class TaskFeedbackMetrics {
  const TaskFeedbackMetrics({
    required this.samples,
    required this.helpfulCount,
    required this.helpfulRate,
  });

  final int samples;
  final int helpfulCount;
  final double? helpfulRate;
}
