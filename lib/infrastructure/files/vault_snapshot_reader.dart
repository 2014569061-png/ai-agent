import 'package:drift/drift.dart';
import '../database/app_database.dart';
import 'context_result_vault.dart';
import 'vault_manifest.dart';
import 'run_plan_vault.dart';
import 'mobile_module_vault.dart';

/// Keyset export, with a SQL preflight before materializing large text columns.
class VaultSnapshotReader {
  VaultSnapshotReader(this.db);
  final AppDatabase db;
  int _rows = 0;
  int _bytes = 0;

  Future<List<Map<String, dynamic>>> rows<T>(TableInfo<Table, T> table,
      Map<String, dynamic> Function(T) encode) async {
    final name = table.actualTableName.replaceAll('"', '""');
    final size = table.$columns
        .map((c) =>
            'coalesce(length(CAST("${c.$name.replaceAll('"', '""')}" AS BLOB)), 0)')
        .join(' + ');
    await _check(name, size);
    final result = <Map<String, dynamic>>[];
    var cursor = 0;
    while (true) {
      final page = await db.customSelect(
        'SELECT *, rowid AS vault_rowid FROM "$name" WHERE rowid > ? '
        'ORDER BY rowid ASC LIMIT 250',
        variables: [Variable<int>(cursor)],
        readsFrom: {table},
      ).get();
      if (page.isEmpty) break;
      for (final row in page) {
        result.add(encode(await table.mapFromRow(row)));
      }
      cursor = page.last.read<int>('vault_rowid');
    }
    return result;
  }

  Future<void> _check(String name, String size) async {
    final totals = await db
        .customSelect(
          'SELECT count(*) AS n, coalesce(sum($size), 0) AS b FROM "$name"',
        )
        .getSingle();
    _rows += totals.read<int>('n');
    _bytes += totals.read<int>('b');
    if (_rows > VaultLimits.maxRows || _bytes > VaultLimits.maxJsonBytes ~/ 2) {
      throw const FormatException('本地数据超过备份容量上限，请先归档');
    }
  }

  Future<List<Map<String, dynamic>>> memoryForgetRules() async {
    await _check('memory_forget_rules',
        'length(fingerprint) + length(source_digest) + length(forgotten_at) + length(reason)');
    final result = <Map<String, dynamic>>[];
    var cursor = 0;
    while (true) {
      final page = await db.customSelect(
          'SELECT *, rowid AS vault_rowid '
          'FROM memory_forget_rules WHERE rowid > ? ORDER BY rowid LIMIT 250',
          variables: [Variable<int>(cursor)]).get();
      if (page.isEmpty) break;
      for (final row in page) {
        result.add({
          'fingerprint': row.read<String>('fingerprint'),
          'sourceDigest': row.read<String>('source_digest'),
          'forgottenAt': row.read<String>('forgotten_at'),
          'reason': row.read<String>('reason')
        });
      }
      cursor = page.last.read<int>('vault_rowid');
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> knowledgeScopes() async {
    await _check('knowledge_doc_scopes', 'length(doc_id) + length(project_id)');
    final result = <Map<String, dynamic>>[];
    var cursor = 0;
    while (true) {
      final page = await db.customSelect(
          'SELECT *, rowid AS vault_rowid '
          'FROM knowledge_doc_scopes WHERE rowid > ? ORDER BY rowid LIMIT 250',
          variables: [Variable<int>(cursor)]).get();
      if (page.isEmpty) break;
      for (final row in page) {
        result.add({
          'docId': row.read<String>('doc_id'),
          'projectId': row.read<String>('project_id')
        });
      }
      cursor = page.last.read<int>('vault_rowid');
    }
    return result;
  }

  Future<Map<String, List<Map<String, dynamic>>>> runPlans() async {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final section in runPlanVaultTables.keys) {
      final table = runPlanVaultTables[section]!;
      final fields = runPlanVaultColumns[section]!;
      await _check(
          table,
          fields.keys
              .map((name) => 'coalesce(length(CAST("$name" AS BLOB)),0)')
              .join(' + '));
      final items = <Map<String, dynamic>>[];
      var cursor = 0;
      while (true) {
        final page = await db.customSelect(
            'SELECT *, rowid AS vault_rowid FROM $table '
            'WHERE rowid > ? ORDER BY rowid LIMIT 250',
            variables: [Variable<int>(cursor)]).get();
        if (page.isEmpty) break;
        for (final row in page) {
          items.add({
            for (final field in fields.entries) field.value: row.data[field.key]
          });
        }
        cursor = page.last.read<int>('vault_rowid');
      }
      result[section] = items;
    }
    return result;
  }

  Future<Map<String, List<Map<String, dynamic>>>> mobileModules() async {
    await ensureMobileModuleTables(db);
    final result = <String, List<Map<String, dynamic>>>{};
    for (final entry in mobileModuleVaultTables.entries) {
      final columns = mobileModuleVaultColumns[entry.key]!;
      await _check(
          entry.value,
          columns
              .map((c) => 'coalesce(length(CAST("$c" AS BLOB)),0)')
              .join(' + '));
      result[entry.key] = [
        for (final row in await db
            .customSelect(
                'SELECT ${columns.join(',')} FROM ${entry.value} ORDER BY id')
            .get())
          row.data
      ];
    }
    return result;
  }

  Future<Map<String, List<Map<String, dynamic>>>>
      contextAndResultActions() async {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final section in contextResultVaultTables.keys) {
      final table = contextResultVaultTables[section]!;
      final fields = contextResultVaultColumns[section]!;
      await _check(
          table,
          fields.keys
              .map((name) => 'coalesce(length(CAST("$name" AS BLOB)),0)')
              .join(' + '));
      final items = <Map<String, dynamic>>[];
      var cursor = 0;
      while (true) {
        final page = await db.customSelect(
            'SELECT *, rowid AS vault_rowid FROM $table '
            'WHERE rowid > ? ORDER BY rowid LIMIT 250',
            variables: [Variable<int>(cursor)]).get();
        if (page.isEmpty) break;
        for (final row in page) {
          items.add({
            for (final field in fields.entries) field.value: row.data[field.key]
          });
        }
        cursor = page.last.read<int>('vault_rowid');
      }
      result[section] = items;
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> artifacts() async {
    const fields = {
      'id': 'id',
      'project_id': 'projectId',
      'task_id': 'taskId',
      'run_id': 'runId',
      'kind': 'kind',
      'relative_path': 'relativePath',
      'hash': 'hash',
      'bytes': 'bytes',
      'inspection_json': 'inspectionJson',
      'created_at': 'createdAt'
    };
    await _check(
        'artifacts',
        fields.keys
            .map((name) => 'coalesce(length(CAST("$name" AS BLOB)), 0)')
            .join(' + '));
    final result = <Map<String, dynamic>>[];
    var cursor = 0;
    while (true) {
      final page = await db.customSelect(
          'SELECT *, rowid AS vault_rowid FROM artifacts '
          'WHERE rowid > ? ORDER BY rowid LIMIT 250',
          variables: [Variable<int>(cursor)]).get();
      if (page.isEmpty) break;
      for (final row in page) {
        result.add({
          for (final field in fields.entries) field.value: row.data[field.key]
        });
      }
      cursor = page.last.read<int>('vault_rowid');
    }
    return result;
  }
}
