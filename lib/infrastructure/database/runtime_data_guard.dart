import 'package:drift/drift.dart';
import '../../domain/runtime_data_scope.dart';

/// The state is deliberately in sync_meta: it survives user-data restoration,
/// is shared by all SQLite connections/isolates, and is never exported.
const runtimeStateId = '_runtime_maintenance_v1';

/// Validates and mutates in the SAME SQLite transaction. A separate preflight
/// SELECT is insufficient: maintenance could commit between the check and write.
class RuntimeDataGuard extends QueryInterceptor {
  QueryExecutorUser? _user;

  @override
  Future<bool> ensureOpen(QueryExecutor executor, QueryExecutorUser user) {
    _user ??= user;
    // Schema creation runs before sync_meta exists.
    return RuntimeDataScope.control(() => executor.ensureOpen(user));
  }

  Future<void> _validate(QueryExecutor executor) async {
    final scope = RuntimeDataScope.current;
    if (scope?.revoked == true) throw const RuntimeDataRevoked();
    final rows = await executor.runSelect(
      'SELECT version, row_json FROM sync_meta WHERE object_id = ?',
      [runtimeStateId],
    );
    final epoch = rows.isEmpty ? 0 : rows.single['version'] as int;
    final owner = rows.isEmpty ? '' : rows.single['row_json'] as String;
    if (scope?.maintenanceOwner != null) {
      if (scope!.maintenanceOwner != owner || scope.epoch != epoch) {
        throw const RuntimeDataRevoked();
      }
    } else if (owner.isNotEmpty || (scope != null && scope.epoch != epoch)) {
      throw const RuntimeDataRevoked();
    }
  }

  Future<T> _write<T>(
      QueryExecutor executor, Future<T> Function(QueryExecutor) action) async {
    if (RuntimeDataScope.isControl) return action(executor);
    if (executor is TransactionExecutor) {
      await _validate(executor);
      return action(executor);
    }
    final transaction = executor.beginTransaction();
    await transaction.ensureOpen(_user!);
    try {
      await _validate(transaction);
      final result = await action(transaction);
      await transaction.send();
      return result;
    } catch (_) {
      await transaction.rollback();
      rethrow;
    }
  }

  @override
  Future<int> runInsert(
          QueryExecutor executor, String statement, List<Object?> args) =>
      _write(executor, (e) => e.runInsert(statement, args));
  @override
  Future<int> runUpdate(
          QueryExecutor executor, String statement, List<Object?> args) =>
      _write(executor, (e) => e.runUpdate(statement, args));
  @override
  Future<int> runDelete(
          QueryExecutor executor, String statement, List<Object?> args) =>
      _write(executor, (e) => e.runDelete(statement, args));
  @override
  Future<void> runCustom(
          QueryExecutor executor, String statement, List<Object?> args) =>
      _write(executor, (e) => e.runCustom(statement, args));
  @override
  Future<void> runBatched(
          QueryExecutor executor, BatchedStatements statements) =>
      _write(executor, (e) => e.runBatched(statements));
  @override
  Future<List<Map<String, Object?>>> runSelect(
      QueryExecutor executor, String statement, List<Object?> args) async {
    // INSERT/UPDATE ... RETURNING also travels through runSelect.
    if (!RegExp(r'^\s*(SELECT\b|PRAGMA\b|EXPLAIN\b)', caseSensitive: false)
        .hasMatch(statement)) {
      return _write(executor, (e) => e.runSelect(statement, args));
    }
    if (!RuntimeDataScope.isControl && RuntimeDataScope.current != null) {
      await _validate(executor);
    }
    return executor.runSelect(statement, args);
  }
}
