import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/files/vault_exporter_io.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config_store.dart';

/// 备份导出 / 恢复 / 清库三者范围一致性的结构性守护。
///
/// 历史事故：导出清单漏了 Tasks、RunRecords、RunEvents、AuditLogs 等表，而恢复前
/// 会调用 clearAllUserData() 把它们删掉，于是「刚备份再恢复」就会丢开发任务与运行
/// 历史。只靠单个往返用例覆盖不到「以后新增了表但忘了加进导出」这种情况，所以这里
/// 用 db.allTables 做全表枚举断言。
///
/// 表名 → 备份 JSON 键名：绝大多数是 snake_case → camelCase，只有历史遗留的
/// prompt_templates 例外（导出沿用 prompts，以兼容既有备份文件）。
const _jsonKeyOverrides = <String, String>{
  'prompt_templates': 'prompts',
};

/// 明确不随备份迁移的表，两者都不被 clearAllUserData 清空，因此不会造成数据丢失：
/// - sync_meta：运行态元数据（上次同步位点等），属于设备本地状态。
/// - account_meta：账号与余额的本地缓存，由账号体系而非备份恢复。
const _notBackedUp = <String>{'sync_meta', 'account_meta'};

String _jsonKeyFor(String tableName) =>
    _jsonKeyOverrides[tableName] ?? _camelCase(tableName);

String _camelCase(String snake) {
  final parts = snake.split('_').where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) return snake;
  final buffer = StringBuffer(parts.first);
  for (final part in parts.skip(1)) {
    buffer.write(part[0].toUpperCase());
    buffer.write(part.substring(1));
  }
  return buffer.toString();
}

class _EmptyProviderStore extends ProviderConfigStore {
  @override
  Future<List<ProviderConfig>> loadAll() async => const [];

  @override
  Future<String> readToolKey(String name) async => '';
}

Future<int> _rowCount(AppDatabase db, String table) async {
  final row = await db
      .customSelect('SELECT COUNT(*) AS c FROM $table')
      .getSingle();
  return row.read<int>('c');
}

void main() {
  test('备份导出覆盖所有会被 clearAllUserData 清空的表', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final json = await buildVaultJson(db, providerStore: _EmptyProviderStore());

    final missing = <String>[];
    for (final table in db.allTables) {
      final name = table.actualTableName;
      if (_notBackedUp.contains(name)) continue;
      if (!json.containsKey(_jsonKeyFor(name))) missing.add(name);
    }
    expect(
      missing,
      isEmpty,
      reason: '以下表会被 clearAllUserData 清空却不在备份导出中，恢复时会丢数据：$missing',
    );

    // artifacts 走裸 SQL 建表，不在 allTables 里，需要单独确认它仍在导出清单中。
    expect(json.containsKey('artifacts'), isTrue);
  });

  test('clearAllUserData 清空所有会被恢复覆盖的表', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.now();

    await db
        .into(db.drafts)
        .insert(DraftsCompanion.insert(draftKey: 'd1', updatedAt: now));
    await db.into(db.auditLogs).insert(AuditLogsCompanion.insert(
        id: 'audit-1', type: 'tool', detail: '{}', createdAt: now));
    await db.into(db.logRecords).insert(LogRecordsCompanion.insert(
        logId: 'log-1',
        level: 'info',
        category: 'system',
        message: 'm',
        createdAt: now));
    await db.into(db.runControls).insert(RunControlsCompanion.insert(
        id: 'rc-1',
        clientControlId: 'client-1',
        taskId: 'task-1',
        kind: 'pause',
        createdAt: now));
    await db.into(db.executionLeases).insert(ExecutionLeasesCompanion.insert(
        resourceKey: 'res-1',
        taskId: 'task-1',
        runId: 'run-1',
        ownerToken: 'owner-1',
        heartbeatAt: now,
        expiresAt: now));
    await db.into(db.taskFeedback).insert(TaskFeedbackCompanion.insert(
        taskId: 'task-1', helpful: true, createdAt: now, updatedAt: now));
    await db
        .into(db.collaborationRuns)
        .insert(CollaborationRunsCompanion.insert(
          id: 'collab-1',
          taskId: 'task-1',
          mode: 'analysis',
          status: 'draft',
          createdAt: now,
          updatedAt: now,
        ));

    await db.clearAllUserData();

    final remaining = <String>[];
    for (final table in db.allTables) {
      final name = table.actualTableName;
      if (_notBackedUp.contains(name)) continue;
      if (await _rowCount(db, name) > 0) remaining.add(name);
    }
    expect(remaining, isEmpty, reason: '恢复前应被清空却仍有数据：$remaining');
  });

  test('备份恢复保留审计日志、任务反馈与协作历史', () async {
    final source = AppDatabase(NativeDatabase.memory());
    final target = AppDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await source.close();
      await target.close();
    });
    final now = DateTime.now();

    await source.into(source.auditLogs).insert(AuditLogsCompanion.insert(
        id: 'audit-1',
        type: 'tool',
        detail: '{"decision":"allow"}',
        createdAt: now));
    await source.into(source.logRecords).insert(LogRecordsCompanion.insert(
        logId: 'log-1',
        level: 'warning',
        category: 'tool',
        message: 'm',
        createdAt: now));
    await source.into(source.taskFeedback).insert(TaskFeedbackCompanion.insert(
        taskId: 'task-1', helpful: true, createdAt: now, updatedAt: now));
    await source
        .into(source.collaborationRuns)
        .insert(CollaborationRunsCompanion.insert(
          id: 'collab-1',
          taskId: 'task-1',
          mode: 'analysis',
          status: 'completed',
          createdAt: now,
          updatedAt: now,
        ));

    final json = await buildVaultJson(source, providerStore: _EmptyProviderStore());
    await restoreVault(target, json, providerStore: _EmptyProviderStore());

    expect((await target.allAuditLogs()).single.id, 'audit-1');
    expect((await target.allLogRecords()).single.logId, 'log-1');
    expect((await target.allTaskFeedback()).single.taskId, 'task-1');
    expect((await target.allCollaborationRuns()).single.id, 'collab-1');
  });
}
