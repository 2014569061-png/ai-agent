import '../infrastructure/database/runtime_data_execution.dart';
import 'nexus_guard.dart';
import '../domain/runtime_data_scope.dart';
import '../domain/unique_id.dart';
import '../domain/session_operation_guard.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/database/runtime_maintenance_store.dart';

class DataMaintenanceRefreshFailure implements Exception {
  const DataMaintenanceRefreshFailure();
  @override
  String toString() => '数据操作已完成，但界面刷新失败，请重新打开应用';
}

/// Admission, cancellation and durable epochs are shared by every execution path.
class DataMaintenanceService {
  const DataMaintenanceService({
    this.pollInterval = const Duration(milliseconds: 500),
    this.runLease = const Duration(seconds: 30),
    this.drainTimeout = const Duration(seconds: 10),
  });
  final Duration pollInterval;
  final Duration runLease;
  final Duration drainTimeout;
  Future<T> run<T>(AppDatabase db, Future<T> Function() action,
          {void Function()? cancel}) =>
      RuntimeDataExecution(pollInterval: pollInterval, runLease: runLease)
          .run(db, action, cancel: cancel);

  Future<void> recoverInterrupted(AppDatabase db,
          {required Future<void> Function() refresh}) =>
      _maintain(db, () async {}, refresh: refresh, recovery: true);

  Future<T> maintain<T>(AppDatabase db, Future<T> Function() action,
          {Future<void> Function()? refresh}) =>
      _maintain(db, action, refresh: refresh);

  Future<T> _maintain<T>(AppDatabase db, Future<T> Function() action,
      {Future<void> Function()? refresh, bool recovery = false}) async {
    if (RuntimeDataScope.current != null) {
      throw const RuntimeDataRevoked('不能从运行中的 Agent 内部覆盖数据');
    }
    final store = RuntimeMaintenanceStore(db);
    final owner = UniqueId.generate('maintenance');
    final epoch = recovery
        ? await store.recoverAndBegin(owner)
        : await store.begin(owner);
    final scope = RuntimeDataScope.maintenance(epoch, owner);
    try {
      RuntimeDataExecution.cancelFor(db);
      final deadline = DateTime.now().add(drainTimeout);
      while (await store.liveRuns() != 0) {
        if (!DateTime.now().isBefore(deadline)) {
          throw const RuntimeDataRevoked('任务未在限时内退出，未执行数据覆盖；请停止任务后重试');
        }
        await Future<void>.delayed(pollInterval);
      }
      return await SessionOperationGuard.restore(
          'application-data',
          () => scope.enter(() async {
                var actionFailed = false;
                try {
                  return await action();
                } catch (_) {
                  actionFailed = true;
                  rethrow;
                } finally {
                  // Reload after rollback too, but never mask its primary error.
                  try {
                    await refresh?.call();
                  } catch (error, stack) {
                    NexusGuard.silently<void>('maintenance.refresh',
                        () => Error.throwWithStackTrace(error, stack));
                    if (!actionFailed) {
                      throw const DataMaintenanceRefreshFailure();
                    }
                  }
                }
              }));
    } finally {
      scope.revoked = true;
      await store.finish(owner, epoch);
    }
  }
}
