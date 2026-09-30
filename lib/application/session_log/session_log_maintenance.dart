import 'session_event.dart';
import 'session_event_store.dart';

/// 会话日志的启动期维护。
abstract final class SessionLogMaintenance {
  /// 超过这个时长没有新事件的未封口运行才视为已中断。
  ///
  /// 不能在启动时一律封口：定时任务运行在 WorkManager 的后台 isolate 中，
  /// UI 进程启动时它可能仍在写日志。前台运行不会跨进程存活；后台定时任务
  /// 有 2 分钟超时，15 分钟留足余量。
  static const staleAfter = Duration(minutes: 15);

  /// 会话日志附件的保留期：超过这个时长未再被请求使用的附件会被清理，
  /// 之后解码为占位文本（Messages 表与界面不受影响）。
  static const blobRetention = Duration(days: 30);

  static bool _startupDone = false;

  /// 每个进程只执行一次的启动维护：先封口、清理附件，再依次执行 [extraSteps]
  /// （旧数据导入、影子比对等）。每一步单独兜底，失败交给 [onError]，
  /// 不影响后续步骤与启动。
  static Future<void> runOnStartup(
    SessionEventStore store, {
    List<Future<Object?> Function()> extraSteps = const [],
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    if (_startupDone) return;
    _startupDone = true;
    for (final step in [
      () => sealStaleRuns(store),
      () => store.pruneBlobs(
          unusedSince: DateTime.now().subtract(blobRetention)),
      ...extraSteps,
    ]) {
      try {
        await step();
      } on Object catch (error, stackTrace) {
        onError?.call(error, stackTrace);
      }
    }
  }

  /// 给长时间无活动的未封口运行补写 `turn/end`（status = interrupted）。
  ///
  /// refs 取该运行最后一次请求的消息，即模型最后确实看到的内容；之后未落日志
  /// 的输出无从恢复（Messages 表仍保留 UI 所见内容）。返回封口的运行数。
  static Future<int> sealStaleRuns(
    SessionEventStore store, {
    DateTime? now,
    Duration staleAfter = SessionLogMaintenance.staleAfter,
  }) async {
    final cutoff = (now ?? DateTime.now()).subtract(staleAfter);
    final stale = (await store.unsealedRuns())
        .where((run) => run.lastActivity.isBefore(cutoff))
        .toList();
    for (final run in stale) {
      final events = await store.events(run.conversationId);
      final lastRequest = events.lastWhere(
        (e) => e.runId == run.runId && e.type == SessionEventType.requestSent,
        orElse: () => events.first,
      );
      await store.append(
        conversationId: run.conversationId,
        type: SessionEventType.turnEnd,
        runId: run.runId,
        payload: {
          'status': 'interrupted',
          'refs': lastRequest.type == SessionEventType.requestSent
              ? lastRequest.refs
              : const <int>[],
          'reason': 'process_ended',
          'sealedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
        },
      );
    }
    return stale.length;
  }
}
