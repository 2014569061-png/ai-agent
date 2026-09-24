import 'package:drift/drift.dart';
import '../database/app_database.dart';
import 'vault_manifest.dart';

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
