import '../domain/unique_id.dart';
import '../infrastructure/database/app_database.dart';

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
          existing.taskId != taskId) {
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

  Future<void> heartbeat({
    required AppDatabase db,
    required ExecutionLease lease,
    Duration ttl = const Duration(minutes: 2),
  }) async {
    await db.transaction(() async {
      final current = await db.findExecutionLease(lease.resourceKey);
      // A stale heartbeat must never resurrect a lease already taken by a
      // newer run after the original lease expired.
      if (current == null ||
          current.ownerToken != lease.ownerToken ||
          current.generation != lease.generation) {
        return;
      }
      final now = DateTime.now();
      await db.saveExecutionLease(lease.copyWith(
        heartbeatAt: now,
        expiresAt: now.add(ttl),
      ));
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
