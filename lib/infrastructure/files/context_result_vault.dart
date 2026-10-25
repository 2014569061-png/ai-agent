import 'dart:convert';

import '../../domain/personal_context.dart';
import '../../domain/result_card.dart';
import '../database/app_database.dart';
import '../database/personal_context_store.dart';
import '../database/result_action_store.dart';

const contextResultVaultTables = <String, String>{
  'personalContextEntities': personalContextEntitiesTable,
  'personalContextRelations': personalContextRelationsTable,
  'personalContextAliases': personalContextAliasesTable,
  'personalContextTombstones': personalContextTombstonesTable,
  'personalContextRevisions': personalContextRevisionsTable,
  'resultCards': 'result_cards',
  'resultActions': 'result_actions',
};

const contextResultVaultColumns = <String, Map<String, String>>{
  'personalContextEntities': {
    'id': 'id',
    'kind': 'kind',
    'label': 'label',
    'normalized_key': 'normalizedKey',
    'qualifier': 'qualifier',
    'source': 'source',
    'confirmation': 'confirmation',
    'lifecycle': 'lifecycle',
    'authorization': 'authorization',
    'revision': 'revision',
    'project_id': 'projectId',
    'valid_until': 'validUntil',
    'attributes_json': 'attributesJson',
    'origin_ref': 'originRef',
    'correction_note': 'correctionNote',
    'confirmed_at': 'confirmedAt',
    'created_at': 'createdAt',
    'updated_at': 'updatedAt',
    'forgotten_at': 'forgottenAt',
  },
  'personalContextRelations': {
    'id': 'id',
    'from_entity_id': 'fromEntityId',
    'to_entity_id': 'toEntityId',
    'relation_type': 'relationType',
    'source': 'source',
    'confirmation': 'confirmation',
    'created_at': 'createdAt',
    'updated_at': 'updatedAt',
  },
  'personalContextAliases': {
    'id': 'id',
    'entity_id': 'entityId',
    'alias': 'alias',
    'normalized_alias': 'normalizedAlias',
    'created_at': 'createdAt',
  },
  'personalContextTombstones': {
    'normalized_key': 'normalizedKey',
    'project_id': 'projectId',
    'reason': 'reason',
    'forgotten_at': 'forgottenAt',
    'entity_id': 'entityId',
  },
  'personalContextRevisions': {
    'id': 'id',
    'entity_id': 'entityId',
    'revision': 'revision',
    'label': 'label',
    'source': 'source',
    'confirmation': 'confirmation',
    'valid_until': 'validUntil',
    'attributes_json': 'attributesJson',
    'recorded_at': 'recordedAt',
    'change_kind': 'changeKind',
    'correction_note': 'correctionNote',
  },
  'resultCards': {
    'id': 'id',
    'kind': 'kind',
    'resource_type': 'resourceType',
    'resource_id': 'resourceId',
    'resource_version': 'resourceVersion',
    'title': 'title',
    'summary': 'summary',
    'snapshot_json': 'snapshotJson',
    'status': 'status',
    'revision': 'revision',
    'task_id': 'taskId',
    'turn_id': 'turnId',
    'created_at': 'createdAt',
    'updated_at': 'updatedAt',
  },
  'resultActions': {
    'id': 'id',
    'card_id': 'cardId',
    'card_revision': 'cardRevision',
    'action_type': 'actionType',
    'status': 'status',
    'idempotency_key': 'idempotencyKey',
    'risk': 'risk',
    'approval_id': 'approvalId',
    'approval_expires_at': 'approvalExpiresAt',
    'error_code': 'errorCode',
    'message': 'message',
    'result_json': 'resultJson',
    'attempts': 'attempts',
    'revision': 'revision',
    'created_at': 'createdAt',
    'updated_at': 'updatedAt',
  },
};

bool backupHasPersonalContextSection(Map<String, dynamic> data) =>
    data.containsKey('personalContextEntities') ||
    data.containsKey('personalContextTombstones') ||
    data.containsKey('personalContextRelations') ||
    data.containsKey('personalContextAliases') ||
    data.containsKey('personalContextRevisions');

bool backupHasResultActionSection(Map<String, dynamic> data) =>
    data.containsKey('resultCards') || data.containsKey('resultActions');

void validateContextResultVault(Map<String, dynamic> data) {
  Never invalid(String msg) => throw FormatException(msg);
  bool id(dynamic v, {bool empty = false}) =>
      v is String && v.length <= 256 && (empty || v.isNotEmpty);
  bool text(dynamic v, {int max = 4096, bool empty = true}) =>
      v is String && v.length <= max && (empty || v.isNotEmpty);
  bool optDate(dynamic v) =>
      v == null || (v is String && v.length <= 40 && DateTime.tryParse(v) != null);
  bool reqDate(dynamic v) =>
      v is String && v.length <= 40 && DateTime.tryParse(v) != null;
  bool jsonMapString(dynamic v, {int maxBytes = 32768}) {
    if (v is! String || utf8.encode(v).length > maxBytes) return false;
    try {
      return jsonDecode(v) is Map<String, dynamic>;
    } on FormatException {
      return false;
    }
  }

  final entityIds = <String>{};
  for (final r in (data['personalContextEntities'] as List? ?? const [])) {
    if (r is! Map ||
        !id(r['id']) ||
        !entityIds.add(r['id'] as String) ||
        PersonalContextEntityKind.tryParse(r['kind'] as String?) == null ||
        !text(r['label'], max: 512, empty: false) ||
        !text(r['normalizedKey'], max: 512, empty: false) ||
        !text(r['qualifier'], max: 256) ||
        PersonalContextSource.tryParse(r['source'] as String?) == null ||
        PersonalContextConfirmation.tryParse(
                r['confirmation'] as String?) ==
            null ||
        PersonalContextLifecycle.tryParse(r['lifecycle'] as String?) ==
            null ||
        PersonalContextAuthorization.tryParse(
                r['authorization'] as String?) ==
            null ||
        r['revision'] is! int ||
        (r['revision'] as int) < 1 ||
        !id(r['projectId'], empty: true) ||
        !optDate(r['validUntil']) ||
        !jsonMapString(r['attributesJson']) ||
        !text(r['originRef'], max: 512) ||
        !text(r['correctionNote'], max: 1024) ||
        !optDate(r['confirmedAt']) ||
        !reqDate(r['createdAt']) ||
        !reqDate(r['updatedAt']) ||
        !optDate(r['forgottenAt'])) {
      invalid('个人上下文实体备份格式错误');
    }
  }

  final relationIds = <String>{};
  for (final r in (data['personalContextRelations'] as List? ?? const [])) {
    if (r is! Map ||
        !id(r['id']) ||
        !relationIds.add(r['id'] as String) ||
        !id(r['fromEntityId']) ||
        !id(r['toEntityId']) ||
        !entityIds.contains(r['fromEntityId']) ||
        !entityIds.contains(r['toEntityId']) ||
        !text(r['relationType'], max: 128, empty: false) ||
        PersonalContextSource.tryParse(r['source'] as String?) == null ||
        PersonalContextConfirmation.tryParse(
                r['confirmation'] as String?) ==
            null ||
        !reqDate(r['createdAt']) ||
        !reqDate(r['updatedAt'])) {
      invalid('个人上下文关系备份格式错误');
    }
  }

  final aliasIds = <String>{};
  for (final r in (data['personalContextAliases'] as List? ?? const [])) {
    if (r is! Map ||
        !id(r['id']) ||
        !aliasIds.add(r['id'] as String) ||
        !id(r['entityId']) ||
        !entityIds.contains(r['entityId']) ||
        !text(r['alias'], max: 256, empty: false) ||
        !text(r['normalizedAlias'], max: 256, empty: false) ||
        !reqDate(r['createdAt'])) {
      invalid('个人上下文别名备份格式错误');
    }
  }

  final tombstoneKeys = <String>{};
  for (final r in (data['personalContextTombstones'] as List? ?? const [])) {
    if (r is! Map ||
        !text(r['normalizedKey'], max: 512, empty: false) ||
        !id(r['projectId'], empty: true) ||
        !tombstoneKeys
            .add('${r['projectId']}::${r['normalizedKey']}') ||
        !text(r['reason'], max: 512) ||
        !reqDate(r['forgottenAt']) ||
        !id(r['entityId'], empty: true)) {
      invalid('个人上下文遗忘墓碑备份格式错误');
    }
  }

  final revisionIds = <String>{};
  for (final r in (data['personalContextRevisions'] as List? ?? const [])) {
    if (r is! Map ||
        !id(r['id']) ||
        !revisionIds.add(r['id'] as String) ||
        !id(r['entityId']) ||
        r['revision'] is! int ||
        (r['revision'] as int) < 1 ||
        !text(r['label'], max: 512, empty: false) ||
        PersonalContextSource.tryParse(r['source'] as String?) == null ||
        PersonalContextConfirmation.tryParse(
                r['confirmation'] as String?) ==
            null ||
        !optDate(r['validUntil']) ||
        !jsonMapString(r['attributesJson']) ||
        !reqDate(r['recordedAt']) ||
        !text(r['changeKind'], max: 64, empty: false) ||
        !text(r['correctionNote'], max: 1024)) {
      invalid('个人上下文修订记录备份格式错误');
    }
  }

  final cardIds = <String>{};
  for (final r in (data['resultCards'] as List? ?? const [])) {
    if (r is! Map ||
        !id(r['id']) ||
        !cardIds.add(r['id'] as String) ||
        ResultCardKind.fromWire(r['kind'] as String? ?? '') == null ||
        !text(r['resourceType'], max: 128, empty: false) ||
        !text(r['resourceId'], max: 256, empty: false) ||
        r['resourceVersion'] is! int ||
        (r['resourceVersion'] as int) < 1 ||
        !text(r['title'], max: 512, empty: false) ||
        !text(r['summary'], max: 4096) ||
        !jsonMapString(r['snapshotJson']) ||
        ResultCardStatus.fromWire(r['status'] as String? ?? '') ==
            ResultCardStatus.unknown ||
        r['revision'] is! int ||
        (r['revision'] as int) < 1 ||
        !id(r['taskId'], empty: true) ||
        !id(r['turnId'], empty: true) ||
        !optDate(r['createdAt']) ||
        !optDate(r['updatedAt'])) {
      invalid('结果卡备份格式错误');
    }
  }

  final actionIds = <String>{};
  final idempotencyKeys = <String>{};
  for (final r in (data['resultActions'] as List? ?? const [])) {
    if (r is! Map ||
        !id(r['id']) ||
        !actionIds.add(r['id'] as String) ||
        !id(r['cardId']) ||
        !cardIds.contains(r['cardId']) ||
        r['cardRevision'] is! int ||
        (r['cardRevision'] as int) < 0 ||
        ResultActionRegistry.find(r['actionType'] as String? ?? '') == null ||
        !text(r['status'], max: 64, empty: false) ||
        !text(r['idempotencyKey'], max: 512, empty: false) ||
        !idempotencyKeys.add(r['idempotencyKey'] as String) ||
        !text(r['risk'], max: 64, empty: false) ||
        (r['approvalId'] != null && !id(r['approvalId'], empty: true)) ||
        !optDate(r['approvalExpiresAt']) ||
        (r['errorCode'] != null && !text(r['errorCode'], max: 64)) ||
        !text(r['message'], max: 2048) ||
        !jsonMapString(r['resultJson']) ||
        r['attempts'] is! int ||
        (r['attempts'] as int) < 0 ||
        r['revision'] is! int ||
        (r['revision'] as int) < 1 ||
        !optDate(r['createdAt']) ||
        !optDate(r['updatedAt'])) {
      invalid('结果卡动作记录备份格式错误');
    }
  }
}

class ContextResultRestoreSummary {
  const ContextResultRestoreSummary({
    required this.restoredEntities,
    required this.skippedForgottenEntities,
    required this.restoredTombstones,
    required this.restoredResultCards,
    required this.restoredResultActions,
  });

  final int restoredEntities;
  final int skippedForgottenEntities;
  final int restoredTombstones;
  final int restoredResultCards;
  final int restoredResultActions;
}

Future<ContextResultRestoreSummary> restoreContextResultVault(
  AppDatabase db,
  Map<String, dynamic> data, {
  required List<Map<String, Object?>> preservedLocalTombstones,
}) async {
  await ensurePersonalContextTables(db);
  await ensureResultActionTables(db);

  var restoredEntities = 0;
  var skippedForgottenEntities = 0;
  var restoredTombstones = 0;
  var restoredResultCards = 0;
  var restoredResultActions = 0;

  if (backupHasPersonalContextSection(data)) {
    final mergedTombstones = <String, Map<String, Object?>>{};
    for (final local in preservedLocalTombstones) {
      final key =
          '${local['project_id'] ?? ''}::${local['normalized_key'] ?? ''}';
      mergedTombstones[key] = local;
    }
    for (final raw in (data['personalContextTombstones'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(raw as Map);
      final key = '${m['projectId'] ?? ''}::${m['normalizedKey'] ?? ''}';
      mergedTombstones.putIfAbsent(
        key,
        () => <String, Object?>{
          'normalized_key': m['normalizedKey'],
          'project_id': m['projectId'] ?? '',
          'reason': m['reason'] ?? '',
          'forgotten_at': m['forgottenAt'],
          'entity_id': m['entityId'] ?? '',
        },
      );
    }

    for (final t in mergedTombstones.values) {
      await db.customStatement(
        'INSERT OR REPLACE INTO $personalContextTombstonesTable '
        '(normalized_key, project_id, reason, forgotten_at, entity_id) '
        'VALUES (?, ?, ?, ?, ?)',
        [
          t['normalized_key'],
          t['project_id'],
          t['reason'],
          t['forgotten_at'],
          t['entity_id'],
        ],
      );
      restoredTombstones++;
    }

    bool isBlockedByTombstone(Map<String, dynamic> entity) {
      final normKey = entity['normalizedKey'] as String? ?? '';
      final projId = entity['projectId'] as String? ?? '';
      final originRef = (entity['originRef'] as String? ?? '').trim();
      if (mergedTombstones.containsKey('::$normKey') ||
          (projId.isNotEmpty &&
              mergedTombstones.containsKey('$projId::$normKey'))) {
        return true;
      }
      if (originRef.isNotEmpty) {
        final srcKey = personalContextSourceTombstoneKey(originRef);
        if (mergedTombstones.containsKey('::$srcKey') ||
            (projId.isNotEmpty &&
                mergedTombstones.containsKey('$projId::$srcKey'))) {
          return true;
        }
      }
      return false;
    }

    final allowedEntityIds = <String>{};
    final entityFields = contextResultVaultColumns['personalContextEntities']!;
    for (final raw in (data['personalContextEntities'] as List? ?? const [])) {
      final row = Map<String, dynamic>.from(raw as Map);
      if (row['lifecycle'] != 'forgotten' && isBlockedByTombstone(row)) {
        skippedForgottenEntities++;
        continue;
      }
      allowedEntityIds.add(row['id'] as String);
      await db.customStatement(
        'INSERT INTO $personalContextEntitiesTable '
        '(${entityFields.keys.join(',')}) '
        'VALUES (${List.filled(entityFields.length, '?').join(',')})',
        [for (final f in entityFields.values) row[f]],
      );
      restoredEntities++;
    }

    final aliasFields = contextResultVaultColumns['personalContextAliases']!;
    for (final raw in (data['personalContextAliases'] as List? ?? const [])) {
      final row = Map<String, dynamic>.from(raw as Map);
      if (!allowedEntityIds.contains(row['entityId'])) continue;
      await db.customStatement(
        'INSERT INTO $personalContextAliasesTable '
        '(${aliasFields.keys.join(',')}) '
        'VALUES (${List.filled(aliasFields.length, '?').join(',')})',
        [for (final f in aliasFields.values) row[f]],
      );
    }

    final relFields = contextResultVaultColumns['personalContextRelations']!;
    for (final raw in (data['personalContextRelations'] as List? ?? const [])) {
      final row = Map<String, dynamic>.from(raw as Map);
      if (!allowedEntityIds.contains(row['fromEntityId']) ||
          !allowedEntityIds.contains(row['toEntityId'])) {
        continue;
      }
      await db.customStatement(
        'INSERT INTO $personalContextRelationsTable '
        '(${relFields.keys.join(',')}) '
        'VALUES (${List.filled(relFields.length, '?').join(',')})',
        [for (final f in relFields.values) row[f]],
      );
    }

    final revFields = contextResultVaultColumns['personalContextRevisions']!;
    for (final raw in (data['personalContextRevisions'] as List? ?? const [])) {
      final row = Map<String, dynamic>.from(raw as Map);
      if (!allowedEntityIds.contains(row['entityId'])) continue;
      await db.customStatement(
        'INSERT INTO $personalContextRevisionsTable '
        '(${revFields.keys.join(',')}) '
        'VALUES (${List.filled(revFields.length, '?').join(',')})',
        [for (final f in revFields.values) row[f]],
      );
    }
  }

  if (backupHasResultActionSection(data)) {
    final cardFields = contextResultVaultColumns['resultCards']!;
    for (final raw in (data['resultCards'] as List? ?? const [])) {
      final row = Map<String, dynamic>.from(raw as Map);
      await db.customStatement(
        'INSERT INTO result_cards '
        '(${cardFields.keys.join(',')}) '
        'VALUES (${List.filled(cardFields.length, '?').join(',')})',
        [for (final f in cardFields.values) row[f]],
      );
      restoredResultCards++;
    }

    final actionFields = contextResultVaultColumns['resultActions']!;
    for (final raw in (data['resultActions'] as List? ?? const [])) {
      final row = Map<String, dynamic>.from(raw as Map);
      if (const {'prepared', 'pending_confirm', 'running'}
          .contains(row['status'])) {
        // Restoring a backup must never leave a dangling approval or
        // auto-replay an in-flight action.
        row['status'] = ResultActionStatus.failed.wireName;
        row['errorCode'] = ResultActionErrorCode.unknown.wireName;
        row['approvalId'] = null;
        row['approvalExpiresAt'] = null;
        row['message'] = '备份恢复后不自动继续未完成动作，请重新发起';
      }
      await db.customStatement(
        'INSERT INTO result_actions '
        '(${actionFields.keys.join(',')}) '
        'VALUES (${List.filled(actionFields.length, '?').join(',')})',
        [for (final f in actionFields.values) row[f]],
      );
      restoredResultActions++;
    }
  }

  return ContextResultRestoreSummary(
    restoredEntities: restoredEntities,
    skippedForgottenEntities: skippedForgottenEntities,
    restoredTombstones: restoredTombstones,
    restoredResultCards: restoredResultCards,
    restoredResultActions: restoredResultActions,
  );
}
