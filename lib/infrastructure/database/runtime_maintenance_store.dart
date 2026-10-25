import 'dart:convert';
import 'package:drift/drift.dart';
import 'runtime_process_probe.dart';
import '../../domain/runtime_data_scope.dart';
import 'app_database.dart';
import 'runtime_data_guard.dart';

class RuntimeMaintenanceState {
  const RuntimeMaintenanceState(this.epoch, this.owner);
  final int epoch;
  final String owner;
}

class RuntimeRecoveryStatus {
  const RuntimeRecoveryStatus(this.hasWork, this.canRecover, this.message);
  final bool hasWork;
  final bool canRecover;
  final String message;
}

/// Runtime-only metadata. It must not be cleared or imported with user data.
class RuntimeMaintenanceStore {
  RuntimeMaintenanceStore(this.db, {RuntimeProcessProbe? processProbe})
      : processProbe = processProbe ?? runtimeProcessProbe;
  final AppDatabase db;
  final RuntimeProcessProbe processProbe;
  static const _runs = '_runtime_runs_v1';
  static const _ownerProcessId = '_runtime_owner_process_v1';

  String _runMetadata(Duration lease) => jsonEncode({
        'expiresAt': DateTime.now().add(lease).millisecondsSinceEpoch,
        'process': processProbe.current?.toJson(),
      });

  Future<void> _recordOwner(String owner, int epoch) => _put(
      _ownerProcessId,
      '_runtime_owner_process',
      epoch,
      jsonEncode({'owner': owner, 'process': processProbe.current?.toJson()}));

  Future<RuntimeMaintenanceState> state() async {
    final row = await db.customSelect(
      'SELECT version, row_json FROM sync_meta WHERE object_id = ?',
      variables: [const Variable(runtimeStateId)],
    ).getSingleOrNull();
    return RuntimeMaintenanceState(
        row?.read<int>('version') ?? 0, row?.read<String>('row_json') ?? '');
  }

  Future<void> _put(String id, String kind, int epoch, String value) =>
      db.customStatement(
        'INSERT INTO sync_meta (object_id, "table", version, row_json, dirty, updated_at) '
        'VALUES (?, ?, ?, ?, 0, ?) ON CONFLICT(object_id) DO UPDATE SET '
        'version = excluded.version, row_json = excluded.row_json, updated_at = excluded.updated_at',
        [id, kind, epoch, value, DateTime.now().millisecondsSinceEpoch ~/ 1000],
      );

  Future<int> register(String id, Duration lease, {int? expectedEpoch}) =>
      RuntimeDataScope.control(() => db.transaction(() async {
            final current = await state();
            if (current.owner.isNotEmpty ||
                (expectedEpoch != null && expectedEpoch != current.epoch)) {
              throw const RuntimeDataRevoked();
            }
            await _put(id, _runs, current.epoch, _runMetadata(lease));
            return current.epoch;
          }));

  Future<bool> renew(String id, int epoch, Duration lease) =>
      RuntimeDataScope.control(() => db.transaction(() async {
            final current = await state();
            final changed = await db.customUpdate(
              'UPDATE sync_meta SET row_json = ? WHERE object_id = ? AND version = ?',
              variables: [
                Variable(_runMetadata(lease)),
                Variable(id),
                Variable(epoch),
              ],
              updates: {db.syncMeta},
            );
            return changed == 1 &&
                current.owner.isEmpty &&
                current.epoch == epoch;
          }));

  Future<void> release(String id) =>
      RuntimeDataScope.control(() => db.customStatement(
          'DELETE FROM sync_meta WHERE object_id = ? AND "table" = ?',
          [id, _runs]));

  Future<int> begin(String owner) =>
      RuntimeDataScope.control(() => db.transaction(() async {
            final current = await state();
            if (current.owner.isNotEmpty) {
              throw const RuntimeDataRevoked('已有数据维护操作正在进行');
            }
            final epoch = current.epoch + 1;
            await _put(runtimeStateId, '_runtime_state', epoch, owner);
            await _recordOwner(owner, epoch);
            return epoch;
          }));

  Future<int> liveRuns() => RuntimeDataScope.control(() async {
        final rows = await db.customSelect(
          'SELECT row_json FROM sync_meta WHERE "table" = ?',
          variables: [const Variable(_runs)],
        ).get();
        // A suspended/CPU-bound isolate can miss heartbeats without being dead.
        // Expiry is a diagnostic, NEVER proof that file/tool work has drained.
        // Only executor completion (release), or explicit recovery after proving
        // the former process stopped, may remove this barrier.
        return rows.length;
      });

  Future<void> finish(String owner, int epoch) =>
      RuntimeDataScope.control(() => db.customStatement(
            'UPDATE sync_meta SET row_json = ? WHERE object_id = ? AND row_json = ? AND version = ?',
            ['', runtimeStateId, owner, epoch],
          ));

  Map<String, dynamic>? _metadata(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Read-only diagnosis. Its result is informational, NOT an unlock token.
  Future<RuntimeRecoveryStatus> inspectRecovery() =>
      RuntimeDataScope.control(() => db.transaction(_inspectRecovery));

  Future<RuntimeRecoveryStatus> _inspectRecovery() async {
    final current = await state();
    final runs = await db.customSelect(
        'SELECT row_json FROM sync_meta WHERE "table" = ?',
        variables: [const Variable(_runs)]).get();
    if (current.owner.isEmpty && runs.isEmpty) {
      return const RuntimeRecoveryStatus(false, false, '没有中断的维护或遗留运行');
    }
    final identities = <RuntimeProcessIdentity?>[
      for (final row in runs)
        RuntimeProcessIdentity.fromJson(
            _metadata(row.read<String>('row_json'))?['process']),
    ];
    if (current.owner.isNotEmpty) {
      final row = await db.customSelect(
          'SELECT version, row_json FROM sync_meta WHERE object_id = ?',
          variables: [const Variable(_ownerProcessId)]).getSingleOrNull();
      final meta = row == null ? null : _metadata(row.read<String>('row_json'));
      identities.add(row?.read<int>('version') == current.epoch &&
              meta?['owner'] == current.owner
          ? RuntimeProcessIdentity.fromJson(meta?['process'])
          : null);
    }
    var unknown = false;
    for (final identity in identities) {
      final alive = identity == null ? null : processProbe.isAlive(identity);
      if (alive == true) {
        return const RuntimeRecoveryStatus(
            true, false, '原执行进程仍存活；请先停止任务。热重载或热重启不能作为进程退出证明');
      }
      unknown |= alive == null;
    }
    return unknown
        ? const RuntimeRecoveryStatus(
            true, false, '无法证明旧进程已退出（平台不支持、权限受限或记录缺少身份），已拒绝解除')
        : const RuntimeRecoveryStatus(
            true, true, '已确认遗留记录所属进程退出；可恢复运行能力，请保留原备份与恢复暂存文件');
  }

  /// Atomically re-prove every recorded process dead, discard ONLY its runtime
  /// rows, advance the epoch and acquire a NEW maintenance owner for refresh.
  /// No heartbeat timeout, caller boolean or old inspection can bypass evidence.
  Future<int> recoverAndBegin(String owner) =>
      RuntimeDataScope.control(() => db.transaction(() async {
            final status = await _inspectRecovery();
            if (!status.canRecover) throw RuntimeDataRevoked(status.message);
            final current = await state();
            final epoch = current.epoch + 1;
            await db.customStatement(
                'DELETE FROM sync_meta WHERE "table" = ?', [_runs]);
            await _put(runtimeStateId, '_runtime_state', epoch, owner);
            await _recordOwner(owner, epoch);
            return epoch;
          }));
}
