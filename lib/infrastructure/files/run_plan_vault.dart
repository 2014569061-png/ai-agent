import 'dart:convert';
import '../../domain/tool_result.dart';
import '../database/app_database.dart';

const runPlanVaultTables = {
  'runPlanHeads': 'run_plan_heads',
  'planRevisions': 'plan_revisions',
  'runDispatchClaims': 'run_dispatch_claims',
};
const runPlanVaultColumns = <String, Map<String, String>>{
  'runPlanHeads': {
    'task_id': 'taskId',
    'run_id': 'runId',
    'version': 'version',
    'state': 'state',
    'pending_controls': 'pendingControls'
  },
  'planRevisions': {
    'task_id': 'taskId',
    'version': 'version',
    'run_id': 'runId',
    'kind': 'kind',
    'control_id': 'controlId',
    'payload_json': 'payloadJson',
    'created_at': 'createdAt'
  },
  'runDispatchClaims': {
    'run_id': 'runId',
    'call_id': 'callId',
    'task_id': 'taskId',
    'plan_version': 'planVersion',
    'state': 'state',
    'effect': 'effect',
    'created_at': 'createdAt',
    'settled_at': 'settledAt'
  },
};

/// Validate the complete protocol graph before publishing files/deleting rows.
void validateRunPlanVault(Map<String, dynamic> data) {
  Never invalid() => throw const FormatException('持久计划或派发记录格式错误');
  bool id(dynamic v, {bool empty = false}) =>
      v is String && v.length <= 256 && (empty || v.isNotEmpty);
  bool date(dynamic v) =>
      v is String && v.length <= 40 && DateTime.tryParse(v) != null;
  final tasks = {for (final r in (data['tasks'] as List? ?? const [])) r['id']};
  final versions = <String, Map<int, String>>{};
  final controlIds = <String>{};
  for (final r in (data['planRevisions'] as List? ?? const [])) {
    if (!id(r['taskId']) ||
        !tasks.contains(r['taskId']) ||
        !id(r['runId'], empty: true) ||
        r['version'] is! int ||
        r['version'] <= 0 ||
        !date(r['createdAt']) ||
        !const {'start', 'followUp', 'pause', 'resume', 'cancel'}
            .contains(r['kind']) ||
        r['payloadJson'] is! String ||
        utf8.encode(r['payloadJson'] as String).length > 16384) {
      invalid();
    }
    try {
      if (jsonDecode(r['payloadJson'] as String) is! Map<String, dynamic>) {
        invalid();
      }
    } on FormatException {
      invalid();
    }
    final byVersion = versions.putIfAbsent(r['taskId'] as String, () => {});
    if (byVersion.containsKey(r['version'])) invalid();
    byVersion[r['version'] as int] = r['runId'] as String;
    if (r['controlId'] != null &&
        (!id(r['controlId']) || !controlIds.add(r['controlId'] as String))) {
      invalid();
    }
  }
  final headTasks = <String>{}, runIds = <String>{};
  for (final r in (data['runPlanHeads'] as List? ?? const [])) {
    if (!id(r['taskId']) ||
        !headTasks.add(r['taskId'] as String) ||
        !tasks.contains(r['taskId']) ||
        !id(r['runId'], empty: true) ||
        ((r['runId'] as String).isNotEmpty &&
            !runIds.add(r['runId'] as String)) ||
        r['version'] is! int ||
        r['version'] <= 0 ||
        versions[r['taskId']]?[r['version']] != r['runId'] ||
        !const {
          'queued',
          'running',
          'paused',
          'completed',
          'failed',
          'cancelled',
          'interrupted'
        }.contains(r['state']) ||
        !const {0, 1}.contains(r['pendingControls'])) {
      invalid();
    }
  }
  if (versions.keys.any((id) => !headTasks.contains(id))) invalid();
  final dispatchIds = <String>{};
  for (final r in (data['runDispatchClaims'] as List? ?? const [])) {
    if (!id(r['taskId']) ||
        !id(r['runId']) ||
        !id(r['callId']) ||
        !dispatchIds.add(jsonEncode([r['runId'], r['callId']])) ||
        r['planVersion'] is! int ||
        versions[r['taskId']]?[r['planVersion']] != r['runId'] ||
        !const {'dispatched', 'settled'}.contains(r['state']) ||
        !ToolEffect.values.any((e) => e.name == r['effect']) ||
        !date(r['createdAt']) ||
        (r['state'] == 'dispatched' &&
            (r['effect'] != 'unknown' || r['settledAt'] != null)) ||
        (r['state'] == 'settled' && !date(r['settledAt']))) {
      invalid();
    }
  }
}

Future<void> restoreRunPlanVault(
    AppDatabase db, Map<String, dynamic> data) async {
  // All rows are validated before restore starts; values are parameterized.
  for (final section in [
    'planRevisions',
    'runDispatchClaims',
    'runPlanHeads'
  ]) {
    final fields = runPlanVaultColumns[section]!;
    for (final raw in (data[section] as List? ?? const [])) {
      final row = Map<String, dynamic>.from(raw as Map);
      if (section == 'runPlanHeads' &&
          const {'running', 'paused', 'queued'}.contains(row['state'])) {
        // A restored process is never the previous active execution owner.
        row['state'] = 'interrupted';
      }
      await db.customStatement(
          'INSERT INTO ${runPlanVaultTables[section]} '
          '(${fields.keys.join(',')}) VALUES (${List.filled(fields.length, '?').join(',')})',
          [for (final field in fields.values) row[field]]);
    }
  }
}
