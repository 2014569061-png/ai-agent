import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../domain/personal_context.dart';
import 'app_database.dart';

// F17 个人上下文的 SQL 仓储。
//
// 与 `run_plan_store.dart` / `memory_forget_store.dart` 保持一致：不引入
// build_runner 生成物，全部写裸 SQL，这样 schema 迁移与仓储实现是同一份
// 事实来源，也避免为新表再跑一次 codegen。

const String personalContextEntitiesTable = 'personal_context_entities';
const String personalContextRelationsTable = 'personal_context_relations';
const String personalContextAliasesTable = 'personal_context_aliases';
const String personalContextTombstonesTable =
    'personal_context_forget_tombstones';
const String personalContextRevisionsTable =
    'personal_context_entity_revisions';

/// A source-wide veto for future extraction, not an entity identity claim.
/// Hashes remain private data; they are not anonymization of low-entropy IDs.
String personalContextSourceTombstoneKey(String originRef) =>
    originRef.trim().isEmpty
        ? ''
        : 'source-sha256:${sha256.convert(utf8.encode(originRef.trim()))}';

/// 幂等建表：由 Lead 在 `AppDatabase` 的 schema 32 迁移与 onCreate 里接线。
///
/// 只用 `CREATE TABLE/INDEX/TRIGGER IF NOT EXISTS`，所以重复调用、迁移中断后
/// 重入都安全；调用方不需要自己判断"建过没有"。
Future<void> ensurePersonalContextTables(AppDatabase db) async {
  await db.customStatement('''
    CREATE TABLE IF NOT EXISTS $personalContextEntitiesTable (
      id TEXT NOT NULL PRIMARY KEY,
      kind TEXT NOT NULL,
      label TEXT NOT NULL,
      normalized_key TEXT NOT NULL,
      qualifier TEXT NOT NULL DEFAULT '',
      source TEXT NOT NULL,
      confirmation TEXT NOT NULL,
      lifecycle TEXT NOT NULL,
      authorization TEXT NOT NULL,
      revision INTEGER NOT NULL DEFAULT 1,
      project_id TEXT NOT NULL DEFAULT '',
      valid_until TEXT,
      attributes_json TEXT NOT NULL DEFAULT '{}',
      origin_ref TEXT NOT NULL DEFAULT '',
      correction_note TEXT NOT NULL DEFAULT '',
      confirmed_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      forgotten_at TEXT
    )
  ''');
  await db.customStatement('''
    CREATE TABLE IF NOT EXISTS $personalContextRelationsTable (
      id TEXT NOT NULL PRIMARY KEY,
      from_entity_id TEXT NOT NULL,
      to_entity_id TEXT NOT NULL,
      relation_type TEXT NOT NULL,
      source TEXT NOT NULL,
      confirmation TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await db.customStatement('''
    CREATE TABLE IF NOT EXISTS $personalContextAliasesTable (
      id TEXT NOT NULL PRIMARY KEY,
      entity_id TEXT NOT NULL,
      alias TEXT NOT NULL,
      normalized_alias TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');
  // 墓碑不存原文，只存归一化键：删除后不能再由墓碑把内容泄露出来。
  await db.customStatement('''
    CREATE TABLE IF NOT EXISTS $personalContextTombstonesTable (
      normalized_key TEXT NOT NULL,
      project_id TEXT NOT NULL DEFAULT '',
      reason TEXT NOT NULL,
      forgotten_at TEXT NOT NULL,
      entity_id TEXT NOT NULL DEFAULT '',
      PRIMARY KEY (normalized_key, project_id)
    )
  ''');
  // 更正历史保留每一版来源与时间；遗忘只标记不物理删除，便于审计。
  await db.customStatement('''
    CREATE TABLE IF NOT EXISTS $personalContextRevisionsTable (
      id TEXT NOT NULL PRIMARY KEY,
      entity_id TEXT NOT NULL,
      revision INTEGER NOT NULL,
      label TEXT NOT NULL,
      source TEXT NOT NULL,
      confirmation TEXT NOT NULL,
      valid_until TEXT,
      attributes_json TEXT NOT NULL DEFAULT '{}',
      recorded_at TEXT NOT NULL,
      change_kind TEXT NOT NULL,
      correction_note TEXT NOT NULL DEFAULT ''
    )
  ''');
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS nexus_pctx_entities_key '
    'ON $personalContextEntitiesTable (normalized_key, lifecycle)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS nexus_pctx_entities_kind '
    'ON $personalContextEntitiesTable (kind, lifecycle)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS nexus_pctx_entities_project '
    'ON $personalContextEntitiesTable (project_id, lifecycle)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS nexus_pctx_relations_from '
    'ON $personalContextRelationsTable (from_entity_id)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS nexus_pctx_relations_to '
    'ON $personalContextRelationsTable (to_entity_id)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS nexus_pctx_aliases_entity '
    'ON $personalContextAliasesTable (entity_id)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS nexus_pctx_aliases_normalized '
    'ON $personalContextAliasesTable (normalized_alias)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS nexus_pctx_revisions_entity '
    'ON $personalContextRevisionsTable (entity_id, revision)',
  );
  // 物理删除实体时自动清理别名与关系；遗忘流程走软删除，由事务显式清理，
  // 两者互补可避免任何一条路径留下悬空引用。
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS nexus_pctx_entity_cleanup
    AFTER DELETE ON $personalContextEntitiesTable
    BEGIN
      DELETE FROM $personalContextAliasesTable WHERE entity_id = OLD.id;
      DELETE FROM $personalContextRelationsTable
        WHERE from_entity_id = OLD.id OR to_entity_id = OLD.id;
    END
  ''');
}

/// 仓储抽象。
///
/// 抽象出来是为了两件事：SQL 实现可以替换（备份恢复/测试），以及
/// `lib/debug/personal_context_checks.dart` 能用纯内存实现验证级联与消歧，
/// 不触碰真实数据库。
abstract class PersonalContextRepository {
  /// 确保表结构就绪。SQL 实现会幂等执行建表语句。
  Future<void> ensureReady();

  Future<PersonalContextEntity?> findEntity(String id);

  /// 列出全部实体，默认不含已遗忘；过滤/排序规则放在服务层，避免同一规则
  /// 在 SQL 与内存实现里各写一遍而逐渐分叉。
  Future<List<PersonalContextEntity>> listEntities(
      {bool includeForgotten = false});

  Future<List<PersonalContextEntity>> findEntitiesByKey(String normalizedKey);

  Future<void> insertEntity(PersonalContextEntity entity,
      {bool allowForgottenReentry = false});

  /// 带版本前置条件的更新，返回受影响行数（0 表示版本已过期）。
  Future<int> updateEntity(
    PersonalContextEntity entity, {
    required int expectedRevision,
    PersonalContextRevision? previousRevision,
  });

  Future<List<PersonalContextRelation>> listRelations({String? entityId});

  Future<void> insertRelation(PersonalContextRelation relation);

  Future<List<PersonalContextAlias>> listAliases({String? entityId});

  Future<void> insertAlias(PersonalContextAlias alias);

  Future<PersonalContextTombstone?> findTombstone({
    required String normalizedKey,
    required String? projectId,
    String originRef = '',
  });

  Future<List<PersonalContextTombstone>> listTombstones();

  Future<void> putTombstone(PersonalContextTombstone tombstone);

  Future<void> deleteTombstone({
    required String normalizedKey,
    required String? projectId,
  });

  Future<void> appendRevision(PersonalContextRevision revision);

  Future<List<PersonalContextRevision>> listRevisions(String entityId);

  /// 在一次事务内完成遗忘：写墓碑、软删除实体、清除别名与关系。
  ///
  /// 单独抽成一个方法而不是让服务层逐条调用，是因为"墓碑写入"和"关系清理"
  /// 必须原子：中途失败要么什么都没遗忘，要么用户看到完整的删除范围。
  Future<PersonalContextForgetReport> forgetEntity({
    required PersonalContextEntity forgotten,
    required PersonalContextTombstone tombstone,
  });
}

/// 裸 SQL 实现。
class SqlitePersonalContextStore implements PersonalContextRepository {
  SqlitePersonalContextStore(this.db);

  final AppDatabase db;

  Future<void>? _ready;

  @override
  Future<void> ensureReady() => _ready ??= ensurePersonalContextTables(db);

  static String _iso(DateTime value) => value.toUtc().toIso8601String();

  static DateTime _parseTime(Object? raw) {
    if (raw is String && raw.isNotEmpty) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed.toUtc();
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  static DateTime? _parseNullableTime(Object? raw) {
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw)?.toUtc();
    }
    return null;
  }

  static String _projectColumn(String? projectId) => projectId ?? '';

  static Map<String, Object?> _decodeAttributes(Object? raw) {
    if (raw is! String || raw.isEmpty) return const <String, Object?>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, Object?>.unmodifiable(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } on FormatException {
      // 损坏的属性不阻断读取：上下文条目本身仍然有效。
    }
    return const <String, Object?>{};
  }

  static String _encodeAttributes(Map<String, Object?> attributes) {
    try {
      return jsonEncode(attributes);
    } on JsonUnsupportedObjectError {
      // 不可序列化的值降级成空对象，避免一条坏属性毁掉整次写入。
      return '{}';
    }
  }

  PersonalContextEntity _entityFromRow(QueryRow row) {
    return PersonalContextEntity(
      id: row.read<String>('id'),
      kind: PersonalContextEntityKind.tryParse(row.read<String>('kind')) ??
          PersonalContextEntityKind.other,
      label: row.read<String>('label'),
      normalizedKey: row.read<String>('normalized_key'),
      qualifier: row.read<String>('qualifier'),
      source: PersonalContextSource.tryParse(row.read<String>('source')) ??
          PersonalContextSource.inferred,
      confirmation: PersonalContextConfirmation.tryParse(
              row.read<String>('confirmation')) ??
          PersonalContextConfirmation.unconfirmed,
      lifecycle:
          PersonalContextLifecycle.tryParse(row.read<String>('lifecycle')) ??
              PersonalContextLifecycle.active,
      authorization: PersonalContextAuthorization.tryParse(
              row.read<String>('authorization')) ??
          PersonalContextAuthorization.notRequired,
      revision: row.read<int>('revision'),
      projectId: _nullableProject(row.read<String>('project_id')),
      validUntil: _parseNullableTime(row.readNullable<String>('valid_until')),
      attributes: _decodeAttributes(row.read<String>('attributes_json')),
      originRef: row.read<String>('origin_ref'),
      correctionNote: row.read<String>('correction_note'),
      confirmedAt: _parseNullableTime(row.readNullable<String>('confirmed_at')),
      createdAt: _parseTime(row.read<String>('created_at')),
      updatedAt: _parseTime(row.read<String>('updated_at')),
      forgottenAt: _parseNullableTime(row.readNullable<String>('forgotten_at')),
    );
  }

  static String? _nullableProject(String raw) => raw.isEmpty ? null : raw;

  PersonalContextRelation _relationFromRow(QueryRow row) {
    return PersonalContextRelation(
      id: row.read<String>('id'),
      fromEntityId: row.read<String>('from_entity_id'),
      toEntityId: row.read<String>('to_entity_id'),
      relationType: row.read<String>('relation_type'),
      source: PersonalContextSource.tryParse(row.read<String>('source')) ??
          PersonalContextSource.userExplicit,
      confirmation: PersonalContextConfirmation.tryParse(
              row.read<String>('confirmation')) ??
          PersonalContextConfirmation.confirmed,
      createdAt: _parseTime(row.read<String>('created_at')),
      updatedAt: _parseTime(row.read<String>('updated_at')),
    );
  }

  PersonalContextAlias _aliasFromRow(QueryRow row) {
    return PersonalContextAlias(
      id: row.read<String>('id'),
      entityId: row.read<String>('entity_id'),
      alias: row.read<String>('alias'),
      normalizedAlias: row.read<String>('normalized_alias'),
      createdAt: _parseTime(row.read<String>('created_at')),
    );
  }

  PersonalContextTombstone _tombstoneFromRow(QueryRow row) {
    return PersonalContextTombstone(
      normalizedKey: row.read<String>('normalized_key'),
      projectId: _nullableProject(row.read<String>('project_id')),
      reason:
          PersonalContextTombstoneReason.tryParse(row.read<String>('reason')) ??
              PersonalContextTombstoneReason.forgotten,
      forgottenAt: _parseTime(row.read<String>('forgotten_at')),
      entityId: row.read<String>('entity_id'),
    );
  }

  PersonalContextRevision _revisionFromRow(QueryRow row) {
    return PersonalContextRevision(
      id: row.read<String>('id'),
      entityId: row.read<String>('entity_id'),
      revision: row.read<int>('revision'),
      label: row.read<String>('label'),
      source: PersonalContextSource.tryParse(row.read<String>('source')) ??
          PersonalContextSource.inferred,
      confirmation: PersonalContextConfirmation.tryParse(
              row.read<String>('confirmation')) ??
          PersonalContextConfirmation.unconfirmed,
      validUntil: _parseNullableTime(row.readNullable<String>('valid_until')),
      attributes: _decodeAttributes(row.read<String>('attributes_json')),
      recordedAt: _parseTime(row.read<String>('recorded_at')),
      changeKind: row.read<String>('change_kind'),
      correctionNote: row.read<String>('correction_note'),
    );
  }

  static const String _entityColumns = 'id, kind, label, normalized_key, '
      'qualifier, source, confirmation, lifecycle, authorization, revision, '
      'project_id, valid_until, attributes_json, origin_ref, correction_note, '
      'confirmed_at, created_at, updated_at, forgotten_at';

  @override
  Future<PersonalContextEntity?> findEntity(String id) async {
    await ensureReady();
    final rows = await db.customSelect(
      'SELECT $_entityColumns FROM $personalContextEntitiesTable WHERE id = ?',
      variables: [Variable<String>(id)],
    ).get();
    if (rows.isEmpty) return null;
    return _entityFromRow(rows.first);
  }

  @override
  Future<List<PersonalContextEntity>> listEntities({
    bool includeForgotten = false,
  }) async {
    await ensureReady();
    final where = includeForgotten ? '' : "WHERE lifecycle = 'active'";
    final rows = await db
        .customSelect(
          'SELECT $_entityColumns FROM $personalContextEntitiesTable '
          '$where ORDER BY updated_at DESC, id ASC',
        )
        .get();
    return rows.map(_entityFromRow).toList(growable: false);
  }

  @override
  Future<List<PersonalContextEntity>> findEntitiesByKey(
      String normalizedKey) async {
    await ensureReady();
    final rows = await db.customSelect(
      'SELECT $_entityColumns FROM $personalContextEntitiesTable '
      'WHERE normalized_key = ? ORDER BY updated_at DESC, id ASC',
      variables: [Variable<String>(normalizedKey)],
    ).get();
    return rows.map(_entityFromRow).toList(growable: false);
  }

  @override
  Future<void> insertEntity(PersonalContextEntity entity,
      {bool allowForgottenReentry = false}) async {
    await ensureReady();
    await db.transaction(() async {
      final blocked = await findTombstone(
          normalizedKey: entity.normalizedKey,
          projectId: entity.projectId,
          originRef: entity.originRef);
      if (blocked != null &&
          !(allowForgottenReentry &&
              entity.source == PersonalContextSource.userExplicit)) {
        throw const PersonalContextException(
            PersonalContextErrorCode.blocked, '该名称、旧称或来源已被遗忘，需要用户明确确认后才能重新添加');
      }
      // A confirmed re-entry is one new entity, not deletion of the privacy rule.
      // A later automatic extraction must still pass this check.
      await db.customStatement(
        'INSERT INTO $personalContextEntitiesTable '
        '($_entityColumns) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          entity.id,
          entity.kind.wireName,
          entity.label,
          entity.normalizedKey,
          entity.qualifier,
          entity.source.wireName,
          entity.confirmation.wireName,
          entity.lifecycle.wireName,
          entity.authorization.wireName,
          entity.revision,
          _projectColumn(entity.projectId),
          entity.validUntil == null ? null : _iso(entity.validUntil!),
          _encodeAttributes(entity.attributes),
          entity.originRef,
          entity.correctionNote,
          entity.confirmedAt == null ? null : _iso(entity.confirmedAt!),
          _iso(entity.createdAt),
          _iso(entity.updatedAt),
          entity.forgottenAt == null ? null : _iso(entity.forgottenAt!),
        ],
      );
    });
  }

  @override
  Future<int> updateEntity(
    PersonalContextEntity entity, {
    required int expectedRevision,
    PersonalContextRevision? previousRevision,
  }) {
    // 版本校验与更新放在同一事务里，否则并发写入可能都通过校验。
    return db.transaction(() async {
      await ensureReady();
      final current = await db.customSelect(
        'SELECT revision, lifecycle, normalized_key FROM $personalContextEntitiesTable WHERE id = ?',
        variables: [Variable<String>(entity.id)],
      ).get();
      if (current.isEmpty) return 0;
      if (current.first.read<int>('revision') != expectedRevision) return 0;
      if (current.first.read<String>('lifecycle') != 'active') return 0;
      if (entity.normalizedKey !=
              current.first.read<String>('normalized_key') &&
          await findTombstone(
                  normalizedKey: entity.normalizedKey,
                  projectId: entity.projectId,
                  originRef: entity.originRef) !=
              null) {
        throw const PersonalContextException(
            PersonalContextErrorCode.blocked, '更正目标命中遗忘记录，不能通过改名重新写入');
      }
      await db.customStatement(
        'UPDATE $personalContextEntitiesTable SET '
        'kind = ?, label = ?, normalized_key = ?, qualifier = ?, source = ?, '
        'confirmation = ?, lifecycle = ?, authorization = ?, revision = ?, '
        'project_id = ?, valid_until = ?, attributes_json = ?, origin_ref = ?, '
        'correction_note = ?, confirmed_at = ?, updated_at = ?, forgotten_at = ? '
        'WHERE id = ? AND revision = ?',
        [
          entity.kind.wireName,
          entity.label,
          entity.normalizedKey,
          entity.qualifier,
          entity.source.wireName,
          entity.confirmation.wireName,
          entity.lifecycle.wireName,
          entity.authorization.wireName,
          entity.revision,
          _projectColumn(entity.projectId),
          entity.validUntil == null ? null : _iso(entity.validUntil!),
          _encodeAttributes(entity.attributes),
          entity.originRef,
          entity.correctionNote,
          entity.confirmedAt == null ? null : _iso(entity.confirmedAt!),
          _iso(entity.updatedAt),
          entity.forgottenAt == null ? null : _iso(entity.forgottenAt!),
          entity.id,
          expectedRevision,
        ],
      );
      if (previousRevision != null) await appendRevision(previousRevision);
      return 1;
    });
  }

  @override
  Future<List<PersonalContextRelation>> listRelations(
      {String? entityId}) async {
    await ensureReady();
    final List<QueryRow> rows;
    if (entityId == null) {
      rows = await db
          .customSelect(
            'SELECT * FROM $personalContextRelationsTable '
            'ORDER BY created_at ASC, id ASC',
          )
          .get();
    } else {
      rows = await db.customSelect(
        'SELECT * FROM $personalContextRelationsTable '
        'WHERE from_entity_id = ? OR to_entity_id = ? '
        'ORDER BY created_at ASC, id ASC',
        variables: [Variable<String>(entityId), Variable<String>(entityId)],
      ).get();
    }
    return rows.map(_relationFromRow).toList(growable: false);
  }

  @override
  Future<void> insertRelation(PersonalContextRelation relation) async {
    await ensureReady();
    await db.transaction(() async {
      await _requireActive(relation.fromEntityId);
      await _requireActive(relation.toEntityId);
      await db.customStatement(
        'INSERT INTO $personalContextRelationsTable '
        '(id, from_entity_id, to_entity_id, relation_type, source, confirmation, '
        'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          relation.id,
          relation.fromEntityId,
          relation.toEntityId,
          relation.relationType,
          relation.source.wireName,
          relation.confirmation.wireName,
          _iso(relation.createdAt),
          _iso(relation.updatedAt),
        ],
      );
    });
  }

  @override
  Future<List<PersonalContextAlias>> listAliases({String? entityId}) async {
    await ensureReady();
    final List<QueryRow> rows;
    if (entityId == null) {
      rows = await db
          .customSelect(
            'SELECT * FROM $personalContextAliasesTable ORDER BY created_at ASC, id ASC',
          )
          .get();
    } else {
      rows = await db.customSelect(
        'SELECT * FROM $personalContextAliasesTable WHERE entity_id = ? '
        'ORDER BY created_at ASC, id ASC',
        variables: [Variable<String>(entityId)],
      ).get();
    }
    return rows.map(_aliasFromRow).toList(growable: false);
  }

  @override
  Future<void> insertAlias(PersonalContextAlias alias) async {
    await ensureReady();
    await db.transaction(() async {
      await _requireActive(alias.entityId);
      await db.customStatement(
        'INSERT INTO $personalContextAliasesTable '
        '(id, entity_id, alias, normalized_alias, created_at) VALUES (?, ?, ?, ?, ?)',
        [
          alias.id,
          alias.entityId,
          alias.alias,
          alias.normalizedAlias,
          _iso(alias.createdAt),
        ],
      );
    });
  }

  Future<void> _requireActive(String id) async {
    final entity = await findEntity(id);
    if (entity == null || entity.isForgotten) {
      throw const PersonalContextException(
          PersonalContextErrorCode.blocked, '条目不存在或已遗忘，未写入别名或关联');
    }
  }

  @override
  Future<PersonalContextTombstone?> findTombstone({
    required String normalizedKey,
    required String? projectId,
    String originRef = '',
  }) async {
    await ensureReady();
    final rows = await db.customSelect(
      'SELECT t.*, e.origin_ref AS forgotten_origin, e.kind AS forgotten_kind '
      'FROM $personalContextTombstonesTable t '
      'LEFT JOIN $personalContextEntitiesTable e ON e.id = t.entity_id '
      'WHERE t.project_id = ? OR t.project_id = \'\' '
      'ORDER BY t.forgotten_at DESC',
      variables: [
        Variable<String>(_projectColumn(projectId)),
      ],
    ).get();
    final requestedName = unqualifiedPersonalContextKey(normalizedKey);
    final origin = originRef.trim();
    final sourceKey = personalContextSourceTombstoneKey(origin);
    final checkedHistory = <String>{};
    for (final row in rows) {
      final tombstone = _tombstoneFromRow(row);
      if ((sourceKey.isNotEmpty && tombstone.normalizedKey == sourceKey) ||
          unqualifiedPersonalContextKey(tombstone.normalizedKey) ==
              requestedName ||
          (origin.isNotEmpty &&
              row.readNullable<String>('forgotten_origin')?.trim() == origin)) {
        return tombstone;
      }
      // Legacy schema-32 tombstones did not include pre-correction names. The
      // retained history lets us enforce them without rewriting the user's DB.
      final kind = PersonalContextEntityKind.tryParse(
          row.readNullable<String>('forgotten_kind'));
      if (kind != null && checkedHistory.add(tombstone.entityId)) {
        for (final revision in await listRevisions(tombstone.entityId)) {
          if (buildPersonalContextKey(kind: kind, label: revision.label) ==
              requestedName) {
            return tombstone;
          }
        }
      }
    }
    return null;
  }

  @override
  Future<List<PersonalContextTombstone>> listTombstones() async {
    await ensureReady();
    final rows = await db
        .customSelect(
          'SELECT * FROM $personalContextTombstonesTable ORDER BY forgotten_at DESC',
        )
        .get();
    return rows.map(_tombstoneFromRow).toList(growable: false);
  }

  @override
  Future<void> putTombstone(PersonalContextTombstone tombstone) async {
    await ensureReady();
    // 同一归一化键重复遗忘是正常操作（遗忘后再次授权并再次遗忘），用 upsert
    // 覆盖而不是报主键冲突。
    await db.customStatement(
      'INSERT INTO $personalContextTombstonesTable '
      '(normalized_key, project_id, reason, forgotten_at, entity_id) '
      'VALUES (?, ?, ?, ?, ?) '
      'ON CONFLICT (normalized_key, project_id) DO UPDATE SET '
      'reason = excluded.reason, forgotten_at = excluded.forgotten_at, '
      'entity_id = excluded.entity_id',
      [
        tombstone.normalizedKey,
        _projectColumn(tombstone.projectId),
        tombstone.reason.wireName,
        _iso(tombstone.forgottenAt),
        tombstone.entityId,
      ],
    );
  }

  @override
  Future<void> deleteTombstone({
    required String normalizedKey,
    required String? projectId,
  }) async {
    await ensureReady();
    await db.customStatement(
      'DELETE FROM $personalContextTombstonesTable '
      'WHERE normalized_key = ? AND project_id = ?',
      [normalizedKey, _projectColumn(projectId)],
    );
  }

  @override
  Future<void> appendRevision(PersonalContextRevision revision) async {
    await ensureReady();
    await db.customStatement(
      'INSERT INTO $personalContextRevisionsTable '
      '(id, entity_id, revision, label, source, confirmation, valid_until, '
      'attributes_json, recorded_at, change_kind, correction_note) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        revision.id,
        revision.entityId,
        revision.revision,
        revision.label,
        revision.source.wireName,
        revision.confirmation.wireName,
        revision.validUntil == null ? null : _iso(revision.validUntil!),
        _encodeAttributes(revision.attributes),
        _iso(revision.recordedAt),
        revision.changeKind,
        revision.correctionNote,
      ],
    );
  }

  @override
  Future<List<PersonalContextRevision>> listRevisions(String entityId) async {
    await ensureReady();
    final rows = await db.customSelect(
      'SELECT * FROM $personalContextRevisionsTable WHERE entity_id = ? '
      'ORDER BY revision ASC, recorded_at ASC',
      variables: [Variable<String>(entityId)],
    ).get();
    return rows.map(_revisionFromRow).toList(growable: false);
  }

  @override
  Future<PersonalContextForgetReport> forgetEntity({
    required PersonalContextEntity forgotten,
    required PersonalContextTombstone tombstone,
  }) {
    return db.transaction(() async {
      await ensureReady();
      final current = await findEntity(forgotten.id);
      if (current == null ||
          current.isForgotten ||
          current.revision != forgotten.revision - 1) {
        throw const PersonalContextException(
            PersonalContextErrorCode.stale, '条目已被修改或遗忘，请刷新后重试');
      }
      final aliases = await listAliases(entityId: forgotten.id);
      final history = await listRevisions(forgotten.id);
      final relationRows = await db.customSelect(
        'SELECT COUNT(*) AS c FROM $personalContextRelationsTable '
        'WHERE from_entity_id = ? OR to_entity_id = ?',
        variables: [
          Variable<String>(forgotten.id),
          Variable<String>(forgotten.id)
        ],
      ).get();
      final revisionRows = await db.customSelect(
        'SELECT COUNT(*) AS c FROM $personalContextRevisionsTable WHERE entity_id = ?',
        variables: [Variable<String>(forgotten.id)],
      ).get();
      final removedAliases = aliases.length;
      final removedRelations = relationRows.first.read<int>('c');
      final keptRevisions = revisionRows.first.read<int>('c');

      await db.customStatement(
        'INSERT INTO $personalContextTombstonesTable '
        '(normalized_key, project_id, reason, forgotten_at, entity_id) '
        'VALUES (?, ?, ?, ?, ?) '
        'ON CONFLICT (normalized_key, project_id) DO UPDATE SET '
        'reason = excluded.reason, forgotten_at = excluded.forgotten_at, '
        'entity_id = excluded.entity_id',
        [
          tombstone.normalizedKey,
          _projectColumn(tombstone.projectId),
          tombstone.reason.wireName,
          _iso(tombstone.forgottenAt),
          tombstone.entityId,
        ],
      );
      // Persist aliases and all historical labels before cascading deletion.
      // Qualifiers distinguish active names, never weaken a forget decision.
      final blockedNames = <String>{
        unqualifiedPersonalContextKey(current.normalizedKey),
        if (current.originRef.trim().isNotEmpty)
          personalContextSourceTombstoneKey(current.originRef),
        for (final alias in aliases)
          buildPersonalContextKey(kind: current.kind, label: alias.alias),
        for (final revision in history)
          buildPersonalContextKey(kind: current.kind, label: revision.label),
      };
      for (final key in blockedNames) {
        await putTombstone(PersonalContextTombstone(
            normalizedKey: key,
            projectId: tombstone.projectId,
            reason: tombstone.reason,
            forgottenAt: tombstone.forgottenAt,
            entityId: tombstone.entityId));
      }
      await db.customStatement(
        'UPDATE $personalContextEntitiesTable SET '
        'lifecycle = ?, revision = ?, updated_at = ?, forgotten_at = ? '
        'WHERE id = ?',
        [
          forgotten.lifecycle.wireName,
          forgotten.revision,
          _iso(forgotten.updatedAt),
          forgotten.forgottenAt == null ? null : _iso(forgotten.forgottenAt!),
          forgotten.id,
        ],
      );
      // 别名与关系必须一起删：否则"已遗忘的人"还能通过别名或关系被召回。
      await db.customStatement(
        'DELETE FROM $personalContextAliasesTable WHERE entity_id = ?',
        [forgotten.id],
      );
      await db.customStatement(
        'DELETE FROM $personalContextRelationsTable '
        'WHERE from_entity_id = ? OR to_entity_id = ?',
        [forgotten.id, forgotten.id],
      );
      return PersonalContextForgetReport(
        entity: forgotten,
        removedAliases: removedAliases,
        removedRelations: removedRelations,
        keptRevisions: keptRevisions,
        tombstone: tombstone,
      );
    });
  }
}
