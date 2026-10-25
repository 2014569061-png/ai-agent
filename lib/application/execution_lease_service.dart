import 'dart:async';

import '../domain/unique_id.dart';
import '../infrastructure/database/app_database.dart';
import 'project_service.dart';

class ExecutionLeaseConflict implements Exception {
  const ExecutionLeaseConflict(this.message);
  final String message;
  @override
  String toString() => message;
}

class ExecutionLeaseService {
  const ExecutionLeaseService();

  static String workspaceKey(String canonicalPath) =>
      'workspace:${canonicalPath.replaceAll('\\', '/')}';

  static String runtimeKey([String runtimeId = 'local']) =>
      'runtime:$runtimeId';

  Future<bool> isOccupied(AppDatabase db, String resourceKey) async {
    final lease = await db.findExecutionLease(resourceKey);
    return lease != null && lease.expiresAt.isAfter(DateTime.now());
  }

  Future<ExecutionLease> acquire({
    required AppDatabase db,
    required String resourceKey,
    required String taskId,
    required String runId,
    Duration ttl = const Duration(minutes: 2),
    String? ownerToken,
  }) async {
    // The read/check/write must be one transaction. Without it, two callers
    // can both observe an expired (or missing) row and start writing the same
    // workspace concurrently.
    return db.transaction(() async {
      final now = DateTime.now();
      final existing = await db.findExecutionLease(resourceKey);
      if (existing != null &&
          existing.expiresAt.isAfter(now) &&
          (existing.ownerToken != ownerToken || existing.runId != runId)) {
        throw ExecutionLeaseConflict('同一资源已被任务 ${existing.taskId} 占用');
      }
      final lease = ExecutionLease(
        resourceKey: resourceKey,
        taskId: taskId,
        runId: runId,
        ownerToken: ownerToken ?? UniqueId.generate('lease'),
        generation: (existing?.generation ?? 0) + 1,
        heartbeatAt: now,
        expiresAt: now.add(ttl),
      );
      await db.saveExecutionLease(lease);
      return lease;
    });
  }

  /// 刷新成功返回 true。租约已被别人拿走或行已消失时返回 false，
  /// 调用方必须停掉仍在写工作区的 run。数据库错误继续抛出。
  Future<bool> heartbeat({
    required AppDatabase db,
    required ExecutionLease lease,
    Duration ttl = const Duration(minutes: 2),
  }) async {
    return db.transaction(() async {
      final current = await db.findExecutionLease(lease.resourceKey);
      // A stale heartbeat must never resurrect a lease already taken by a
      // newer run after the original lease expired.
      if (current == null ||
          current.ownerToken != lease.ownerToken ||
          current.generation != lease.generation) {
        return false;
      }
      final now = DateTime.now();
      await db.saveExecutionLease(lease.copyWith(
        heartbeatAt: now,
        expiresAt: now.add(ttl),
      ));
      return true;
    });
  }

  Future<void> release({
    required AppDatabase db,
    required String resourceKey,
    required String ownerToken,
  }) async {
    await db.transaction(() async {
      final existing = await db.findExecutionLease(resourceKey);
      if (existing == null || existing.ownerToken != ownerToken) return;
      await db.deleteExecutionLease(resourceKey);
    });
  }
}

/// Explicitly borrowed by nested repair runs; only its outer owner closes it.
class WorkspaceLeaseGuard {
  WorkspaceLeaseGuard._(this.db, this.service, this.lease, this.onLost)
      : _validUntil = lease.expiresAt;
  final AppDatabase db;
  final ExecutionLeaseService service;
  final ExecutionLease lease;
  final void Function() onLost;
  Timer? _timer;
  Future<void>? _refresh;
  bool _closed = false;
  bool _lost = false;
  int _failures = 0;
  DateTime _validUntil;
  bool get active => !_closed && !_lost;

  static Future<WorkspaceLeaseGuard> open({
    required AppDatabase db,
    required String workspacePath,
    required String taskId,
    required String runId,
    required void Function() onLost,
    ExecutionLeaseService service = const ExecutionLeaseService(),
    Duration interval = const Duration(seconds: 30),
    int failureLimit = 3,
  }) async {
    final lease = await service.acquire(
        db: db,
        resourceKey: ExecutionLeaseService.workspaceKey(
            ProjectService.canonicalizePath(workspacePath)),
        taskId: taskId,
        runId: runId);
    final guard = WorkspaceLeaseGuard._(db, service, lease, onLost);
    guard._timer = Timer.periodic(interval, (_) {
      if (DateTime.now().isAfter(guard._validUntil)) {
        guard._lose();
      }
      // Serialize heartbeats so slow failures cannot race successful refreshes.
      if (!guard.active || guard._refresh != null) return;
      guard._refresh = guard._heartbeat(failureLimit).whenComplete(() {
        guard._refresh = null;
      });
    });
    return guard;
  }

  Future<void> _heartbeat(int failureLimit) async {
    try {
      if (!await service
          .heartbeat(db: db, lease: lease)
          .timeout(const Duration(seconds: 20))) {
        _lose();
      } else {
        _failures = 0;
        final current = await db.findExecutionLease(lease.resourceKey);
        if (current?.ownerToken != lease.ownerToken ||
            current?.generation != lease.generation) {
          _lose();
        } else {
          _validUntil = current!.expiresAt;
        }
      }
    } catch (_) {
      if (++_failures >= failureLimit) _lose();
    }
  }

  void _lose() {
    if (!active) return;
    _lost = true;
    _timer?.cancel();
    onLost();
  }

  Future<void> validate(
      {required AppDatabase database,
      required String workspacePath,
      required String taskId}) async {
    final current = await db.findExecutionLease(lease.resourceKey);
    if (!active ||
        !identical(database, db) ||
        lease.taskId != taskId ||
        lease.resourceKey !=
            ExecutionLeaseService.workspaceKey(
                ProjectService.canonicalizePath(workspacePath)) ||
        current?.ownerToken != lease.ownerToken ||
        current?.generation != lease.generation ||
        !(current?.expiresAt.isAfter(DateTime.now()) ?? false)) {
      _lose();
      throw const ExecutionLeaseConflict('工作区租约已失效，无法继续执行');
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    await _refresh;
    await service.release(
        db: db, resourceKey: lease.resourceKey, ownerToken: lease.ownerToken);
  }
}
