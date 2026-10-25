import 'dart:async';
import '../../domain/runtime_data_scope.dart';
import '../../domain/unique_id.dart';
import 'app_database.dart';
import 'runtime_maintenance_store.dart';

/// Shared lease primitive for application work and infrastructure startup jobs.
class RuntimeDataExecution {
  const RuntimeDataExecution({
    this.pollInterval = const Duration(milliseconds: 500),
    this.runLease = const Duration(seconds: 30),
  });
  final Duration pollInterval;
  final Duration runLease;
  static final Map<String, (AppDatabase, void Function())> _cancel = {};

  static void cancelFor(AppDatabase db) {
    for (final entry in List.of(_cancel.values)) {
      if (identical(entry.$1, db)) {
        try {
          entry.$2();
        } catch (_) {/* still drain every executor */}
      }
    }
  }

  Future<T> run<T>(AppDatabase db, Future<T> Function() action,
      {void Function()? cancel}) async {
    final parent = RuntimeDataScope.current;
    if (parent != null && (parent.revoked || parent.maintenanceOwner != null)) {
      throw const RuntimeDataRevoked();
    }
    final store = RuntimeMaintenanceStore(db);
    final id = UniqueId.generate('_runtime_run');
    // Each nested executor retains its own lease: a scheduler timeout must not
    // make an unresponsive tool disappear from the maintenance drain barrier.
    final epoch =
        await store.register(id, runLease, expectedEpoch: parent?.epoch);
    final scope = RuntimeDataScope.run(epoch);
    void revoke() {
      if (scope.revoked) return;
      scope.revoked = true;
      cancel?.call();
    }

    _cancel[id] = (db, revoke);
    var checking = false;
    final timer = Timer.periodic(pollInterval, (_) async {
      if (checking) return;
      checking = true;
      try {
        if (!await store.renew(id, epoch, runLease)) revoke();
      } catch (_) {
        // A failed heartbeat is not permission to continue writing.
        revoke();
      } finally {
        checking = false;
      }
    });
    try {
      return await scope.enter(action);
    } finally {
      scope.revoked = true;
      timer.cancel();
      _cancel.remove(id);
      await store.release(id);
    }
  }
}
