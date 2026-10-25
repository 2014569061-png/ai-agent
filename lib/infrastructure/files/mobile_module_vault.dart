import 'dart:convert';

import '../database/app_database.dart';

const mobileModuleVaultTables = <String, String>{
  'reminders': 'nexus_reminders',
  'mobileWorkflows': 'nexus_mobile_workflows',
  'mobileWorkflowRuns': 'nexus_mobile_workflow_runs',
  'researchArtifacts': 'nexus_research_artifacts',
};

const mobileModuleVaultColumns = <String, List<String>>{
  'reminders': [
    'id',
    'title',
    'notes',
    'scheduled_at_utc',
    'timezone_id',
    'utc_offset_minutes',
    'dst_active',
    'exact_alarm_capability',
    'status',
    'snooze_count',
    'snoozed_until_utc',
    'version',
    'created_at',
    'updated_at'
  ],
  'mobileWorkflows': [
    'id',
    'name',
    'description',
    'version',
    'input_schema_json',
    'steps_json',
    'created_at',
    'updated_at'
  ],
  'mobileWorkflowRuns': [
    'id',
    'workflow_id',
    'workflow_version',
    'dry_run',
    'status',
    'inputs_json',
    'traces_json',
    'created_at'
  ],
  'researchArtifacts': [
    'id',
    'topic',
    'summary',
    'claims_json',
    'version',
    'created_at',
    'updated_at'
  ],
};

Future<void> ensureMobileModuleTables(AppDatabase db) async {
  // Keep this schema at the infrastructure boundary so backup never depends on
  // application services or seeds example workflows as an export side effect.
  await db.customStatement('CREATE TABLE IF NOT EXISTS nexus_reminders ('
      'id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL, notes TEXT NOT NULL DEFAULT \'\', '
      'scheduled_at_utc INTEGER NOT NULL, timezone_id TEXT NOT NULL, utc_offset_minutes INTEGER NOT NULL, '
      'dst_active INTEGER NOT NULL DEFAULT 0, exact_alarm_capability TEXT NOT NULL DEFAULT \'denied\', '
      'status TEXT NOT NULL, snooze_count INTEGER NOT NULL DEFAULT 0, snoozed_until_utc INTEGER, '
      'version INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)');
  await db.customStatement('CREATE TABLE IF NOT EXISTS nexus_mobile_workflows ('
      'id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, description TEXT NOT NULL, '
      'version INTEGER NOT NULL DEFAULT 1, input_schema_json TEXT NOT NULL DEFAULT \'[]\', '
      'steps_json TEXT NOT NULL DEFAULT \'[]\', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)');
  await db.customStatement(
      'CREATE TABLE IF NOT EXISTS nexus_mobile_workflow_runs ('
      'id TEXT PRIMARY KEY NOT NULL, workflow_id TEXT NOT NULL, workflow_version INTEGER NOT NULL, '
      'dry_run INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL, inputs_json TEXT NOT NULL DEFAULT \'{}\', '
      'traces_json TEXT NOT NULL DEFAULT \'[]\', created_at INTEGER NOT NULL)');
  await db.customStatement(
      'CREATE TABLE IF NOT EXISTS nexus_research_artifacts ('
      'id TEXT PRIMARY KEY NOT NULL, topic TEXT NOT NULL, summary TEXT NOT NULL, '
      'claims_json TEXT NOT NULL DEFAULT \'[]\', version INTEGER NOT NULL DEFAULT 1, '
      'created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)');
}

void validateMobileModuleVault(Map<String, dynamic> data) {
  const integerColumns = {
    'scheduled_at_utc',
    'utc_offset_minutes',
    'dst_active',
    'snooze_count',
    'snoozed_until_utc',
    'version',
    'created_at',
    'updated_at',
    'workflow_version',
    'dry_run'
  };
  for (final section in mobileModuleVaultTables.keys) {
    if (!data.containsKey(section)) continue;
    final rows = data[section];
    if (rows is! List) throw FormatException('备份数据段不是列表：$section');
    final ids = <String>{};
    final columns = mobileModuleVaultColumns[section]!;
    for (final raw in rows) {
      if (raw is! Map ||
          raw.length != columns.length ||
          columns.any((c) => !raw.containsKey(c)) ||
          raw['id'] is! String ||
          (raw['id'] as String).isEmpty ||
          (raw['id'] as String).length > 256 ||
          !ids.add(raw['id'] as String)) {
        throw FormatException('模块备份记录不合法：$section');
      }
      if (section == 'reminders' &&
          (!const {
                'scheduled',
                'snoozed',
                'completed',
                'cancelled',
                'missed',
                'paused'
              }.contains(raw['status']) ||
              !const {'granted', 'degraded_inexact', 'denied'}
                  .contains(raw['exact_alarm_capability']))) {
        throw const FormatException('提醒备份状态不合法');
      }
      for (final col in columns) {
        final value = raw[col];
        if (col == 'snoozed_until_utc' && value == null) continue;
        if (integerColumns.contains(col)) {
          if (value is! int ||
              ((col == 'version' || col == 'workflow_version') && value < 1)) {
            throw FormatException('模块备份数值不合法：$section/$col');
          }
        } else if (value is! String || value.length > 1024 * 1024) {
          throw FormatException('模块备份文本不合法：$section/$col');
        }
        if (col.endsWith('_json')) {
          final decoded = jsonDecode(value as String);
          final expectsMap = col == 'inputs_json';
          if (expectsMap ? decoded is! Map : decoded is! List) {
            throw FormatException('模块备份 JSON 不合法：$section/$col');
          }
        }
      }
    }
  }
}

Future<void> restoreMobileModuleVault(
    AppDatabase db, Map<String, dynamic> data) async {
  await ensureMobileModuleTables(db);
  for (final entry in mobileModuleVaultTables.entries) {
    if (!data.containsKey(entry.key)) continue;
    await db.customStatement('DELETE FROM ${entry.value}');
    final columns = mobileModuleVaultColumns[entry.key]!;
    for (final raw in data[entry.key] as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      if (entry.key == 'reminders' &&
          const {'scheduled', 'snoozed'}.contains(row['status'])) {
        row['status'] = 'paused';
        row['exact_alarm_capability'] = 'denied';
      }
      await db.customStatement(
          'INSERT INTO ${entry.value} (${columns.join(',')}) '
          'VALUES (${List.filled(columns.length, '?').join(',')})',
          [for (final c in columns) row[c]]);
    }
  }
}
