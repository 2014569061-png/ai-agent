import 'dart:convert';

import 'package:drift/drift.dart' show QueryRow, Variable;
import 'package:drift/native.dart' show SqliteException;

import '../../domain/result_card.dart';
import 'app_database.dart';

/// 结果卡与动作记录的仓储协议。
///
/// 抽象出接口是为了让 debug 合同检查可以注入内存假仓储，
/// 也避免应用层直接依赖 drift 的 SQL 细节。
abstract class ResultActionRepository {
  Future<ResultCard?> findCard(String cardId);

  Future<List<ResultCard>> listCards({
    ResultCardKind? kind,
    int limit = 50,
  });

  Future<void> saveCard(ResultCard card);

  Future<ResultActionRecord?> findAction(String actionId);

  Future<ResultActionRecord?> findActionByIdempotencyKey(String key);

  Future<List<ResultActionRecord>> listActions(String cardId);

  Future<void> saveAction(ResultActionRecord action);
}

/// A durable compare-and-set boundary. Separate service instances/isolate
/// callbacks cannot both acquire execution of the same SQL action.
abstract interface class ConditionalResultActionRepository
    implements ResultActionRepository {
  AppDatabase get db;
  Future<bool> compareAndSaveAction(ResultActionRecord action,
      {required int expectedRevision,
      ResultCard? expectedCard,
      Future<bool> Function()? authorize});
}

/// 幂等创建结果卡/动作表。
///
/// Lead 负责在 schema 迁移中调用；这里保持 `IF NOT EXISTS` 以便
/// 迁移重放和测试初始化都不会报错，也不会删除已有记录。
Future<void> ensureResultActionTables(AppDatabase db) async {
  await db.transaction(() async {
    await db.customStatement('''
CREATE TABLE IF NOT EXISTS result_cards (
  id TEXT NOT NULL PRIMARY KEY,
  kind TEXT NOT NULL,
  resource_type TEXT NOT NULL,
  resource_id TEXT NOT NULL,
  resource_version INTEGER NOT NULL,
  title TEXT NOT NULL,
  summary TEXT NOT NULL,
  snapshot_json TEXT NOT NULL DEFAULT '{}',
  status TEXT NOT NULL,
  revision INTEGER NOT NULL DEFAULT 1,
  task_id TEXT NOT NULL DEFAULT '',
  turn_id TEXT NOT NULL DEFAULT '',
  created_at TEXT,
  updated_at TEXT
)''');
    await db.customStatement('''
CREATE TABLE IF NOT EXISTS result_actions (
  id TEXT NOT NULL PRIMARY KEY,
  card_id TEXT NOT NULL,
  card_revision INTEGER NOT NULL DEFAULT 0,
  action_type TEXT NOT NULL,
  status TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  risk TEXT NOT NULL,
  approval_id TEXT,
  approval_expires_at TEXT,
  error_code TEXT,
  message TEXT NOT NULL DEFAULT '',
  result_json TEXT NOT NULL DEFAULT '{}',
  attempts INTEGER NOT NULL DEFAULT 0,
  revision INTEGER NOT NULL DEFAULT 1,
  created_at TEXT,
  updated_at TEXT
)''');
    await db.customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_result_actions_idempotency '
        'ON result_actions (idempotency_key)');
    await db
        .customStatement('CREATE INDEX IF NOT EXISTS idx_result_actions_card '
            'ON result_actions (card_id, created_at)');
    await db
        .customStatement('CREATE INDEX IF NOT EXISTS idx_result_cards_updated '
            'ON result_cards (updated_at)');
  });
}

/// 裸 SQL 实现。所有读写都在 `customSelect`/`customStatement` 上完成，
/// 不引入 build_runner codegen。
class SqlResultActionRepository
    implements ResultActionRepository, ConditionalResultActionRepository {
  SqlResultActionRepository(this.db);

  @override
  final AppDatabase db;

  static const _cardColumns =
      'id, kind, resource_type, resource_id, resource_version, title, summary, '
      'snapshot_json, status, revision, task_id, turn_id, created_at, updated_at';
  static const _actionColumns =
      'id, card_id, card_revision, action_type, status, idempotency_key, risk, '
      'approval_id, approval_expires_at, error_code, message, result_json, '
      'attempts, revision, created_at, updated_at';

  @override
  Future<ResultCard?> findCard(String cardId) async {
    final row = await db.customSelect(
        'SELECT $_cardColumns FROM result_cards WHERE id = ? LIMIT 1',
        variables: [Variable<String>(cardId)]).getSingleOrNull();
    return row == null ? null : _cardFromRow(row);
  }

  @override
  Future<List<ResultCard>> listCards({
    ResultCardKind? kind,
    int limit = 50,
  }) async {
    final rows = kind == null
        ? await db.customSelect(
            'SELECT $_cardColumns FROM result_cards '
            'ORDER BY updated_at DESC, id DESC LIMIT ?',
            variables: [Variable<int>(limit)]).get()
        : await db.customSelect(
            'SELECT $_cardColumns FROM result_cards WHERE kind = ? '
            'ORDER BY updated_at DESC, id DESC LIMIT ?',
            variables: [
                Variable<String>(kind.wireName),
                Variable<int>(limit),
              ]).get();
    return [for (final row in rows) _cardFromRow(row)];
  }

  @override
  Future<void> saveCard(ResultCard card) async {
    await db.customStatement('''
INSERT INTO result_cards (
  id, kind, resource_type, resource_id, resource_version, title, summary,
  snapshot_json, status, revision, task_id, turn_id, created_at, updated_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT (id) DO UPDATE SET
  kind = excluded.kind,
  resource_type = excluded.resource_type,
  resource_id = excluded.resource_id,
  resource_version = excluded.resource_version,
  title = excluded.title,
  summary = excluded.summary,
  snapshot_json = excluded.snapshot_json,
  status = excluded.status,
  revision = excluded.revision,
  task_id = excluded.task_id,
  turn_id = excluded.turn_id,
  updated_at = excluded.updated_at,
  created_at = COALESCE(result_cards.created_at, excluded.created_at)
''', [
      card.id,
      card.kind.wireName,
      card.resourceType,
      card.resourceId,
      card.resourceVersion,
      card.title,
      card.summary,
      _encodeMap(card.snapshot),
      card.status.wireName,
      card.revision,
      card.taskId,
      card.turnId,
      _stamp(card.createdAt),
      _stamp(card.updatedAt ?? DateTime.now()),
    ]);
  }

  @override
  Future<ResultActionRecord?> findAction(String actionId) async {
    final row = await db.customSelect(
        'SELECT $_actionColumns FROM result_actions WHERE id = ? LIMIT 1',
        variables: [Variable<String>(actionId)]).getSingleOrNull();
    return row == null ? null : _actionFromRow(row);
  }

  @override
  Future<ResultActionRecord?> findActionByIdempotencyKey(String key) async {
    final row = await db.customSelect(
        'SELECT $_actionColumns FROM result_actions '
        'WHERE idempotency_key = ? LIMIT 1',
        variables: [Variable<String>(key)]).getSingleOrNull();
    return row == null ? null : _actionFromRow(row);
  }

  @override
  Future<List<ResultActionRecord>> listActions(String cardId) async {
    final rows = await db.customSelect(
        'SELECT $_actionColumns FROM result_actions WHERE card_id = ? '
        'ORDER BY created_at ASC, id ASC',
        variables: [Variable<String>(cardId)]).get();
    return [for (final row in rows) _actionFromRow(row)];
  }

  @override
  Future<void> saveAction(ResultActionRecord action) async {
    await db.customStatement('''
INSERT INTO result_actions (
  id, card_id, card_revision, action_type, status, idempotency_key, risk,
  approval_id, approval_expires_at, error_code, message, result_json,
  attempts, revision, created_at, updated_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT (id) DO UPDATE SET
  card_revision = excluded.card_revision,
  status = excluded.status,
  approval_id = excluded.approval_id,
  approval_expires_at = excluded.approval_expires_at,
  error_code = excluded.error_code,
  message = excluded.message,
  result_json = excluded.result_json,
  attempts = excluded.attempts,
  revision = excluded.revision,
  updated_at = excluded.updated_at
''', [
      action.id,
      action.cardId,
      action.cardRevision,
      action.actionType,
      action.status.wireName,
      action.idempotencyKey,
      action.risk.wireName,
      action.approvalId,
      _stamp(action.approvalExpiresAt),
      action.errorCode?.wireName,
      action.message,
      _encodeMap(action.result),
      action.attempts,
      action.revision,
      _stamp(action.createdAt),
      _stamp(action.updatedAt ?? DateTime.now()),
    ]);
  }

  @override
  Future<bool> compareAndSaveAction(ResultActionRecord action,
      {required int expectedRevision,
      ResultCard? expectedCard,
      Future<bool> Function()? authorize}) async {
    try {
      return await db.transaction(() async {
        if (authorize != null && !await authorize()) return false;
        final changed = await db.customUpdate('''
UPDATE result_actions SET card_revision=?, status=?, approval_id=?, approval_expires_at=?,
  error_code=?, message=?, result_json=?, attempts=?, revision=?, updated_at=?
WHERE id=? AND revision=?
${expectedCard == null ? '' : "AND EXISTS (SELECT 1 FROM result_cards c WHERE c.id=result_actions.card_id AND c.revision=? AND c.resource_type=? AND c.resource_id=? AND c.resource_version=? AND c.status='active')"}
''', variables: [
          Variable(action.cardRevision),
          Variable(action.status.wireName),
          Variable<String>(action.approvalId),
          Variable<String>(_stamp(action.approvalExpiresAt)),
          Variable<String>(action.errorCode?.wireName),
          Variable(action.message),
          Variable(_encodeMap(action.result)),
          Variable(action.attempts),
          Variable(action.revision),
          Variable<String>(_stamp(action.updatedAt ?? DateTime.now())),
          Variable(action.id),
          Variable(expectedRevision),
          if (expectedCard != null) ...[
            Variable(expectedCard.revision),
            Variable(expectedCard.resourceType),
            Variable(expectedCard.resourceId),
            Variable(expectedCard.resourceVersion),
          ],
        ]);
        return changed == 1;
      });
    } on SqliteException catch (error) {
      // Two connections can read before either upgrades its SQLite transaction.
      // A busy/locked loser never owns execution; don't replay or upsert it.
      if (error.resultCode == 5 || error.resultCode == 6) return false;
      rethrow;
    }
  }

  ResultCard _cardFromRow(QueryRow row) {
    final kind = ResultCardKind.fromWire(row.read<String>('kind'));
    if (kind == null) {
      throw StateError('结果卡类型损坏：${row.read<String>('kind')}');
    }
    final status = ResultCardStatus.fromWire(row.read<String>('status')) ??
        ResultCardStatus.unknown;
    return ResultCard(
      id: row.read<String>('id'),
      kind: kind,
      resourceType: row.read<String>('resource_type'),
      resourceId: row.read<String>('resource_id'),
      resourceVersion: row.read<int>('resource_version'),
      title: row.read<String>('title'),
      summary: row.read<String>('summary'),
      snapshot: _decodeMap(row.read<String>('snapshot_json')),
      status: status,
      revision: row.read<int>('revision'),
      taskId: row.read<String>('task_id'),
      turnId: row.read<String>('turn_id'),
      createdAt: _parseStamp(row.read<String?>('created_at')),
      updatedAt: _parseStamp(row.read<String?>('updated_at')),
    );
  }

  ResultActionRecord _actionFromRow(QueryRow row) {
    final status = ResultActionStatus.fromWire(row.read<String>('status'));
    final risk = ResultActionRisk.fromWire(row.read<String>('risk'));
    if (status == null || risk == null) {
      throw StateError('结果卡动作记录损坏：${row.read<String>('id')}');
    }
    return ResultActionRecord(
      id: row.read<String>('id'),
      cardId: row.read<String>('card_id'),
      cardRevision: row.read<int>('card_revision'),
      actionType: row.read<String>('action_type'),
      status: status,
      idempotencyKey: row.read<String>('idempotency_key'),
      risk: risk,
      approvalId: row.read<String?>('approval_id'),
      approvalExpiresAt: _parseStamp(row.read<String?>('approval_expires_at')),
      errorCode:
          ResultActionErrorCode.fromWire(row.read<String?>('error_code') ?? ''),
      message: row.read<String>('message'),
      result: _decodeMap(row.read<String>('result_json')),
      attempts: row.read<int>('attempts'),
      revision: row.read<int>('revision'),
      createdAt: _parseStamp(row.read<String?>('created_at')),
      updatedAt: _parseStamp(row.read<String?>('updated_at')),
    );
  }

  static String _encodeMap(Map<String, dynamic> value) => jsonEncode(value);

  static Map<String, dynamic> _decodeMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : const <String, dynamic>{};
    } on FormatException {
      // 损坏的快照只影响展示，不应让整页结果卡不可读。
      return const <String, dynamic>{};
    }
  }

  static String? _stamp(DateTime? value) => value?.toUtc().toIso8601String();

  static DateTime? _parseStamp(String? value) =>
      value == null ? null : DateTime.tryParse(value);
}
