import '../application/personal_context_service.dart';
import '../domain/personal_context.dart';
import '../infrastructure/database/personal_context_store.dart';

// F17 关联个人上下文的固定用例。
//
// 合同报告约束：fixtureOnly=true、modelCalls=0、persistentDataMutations=0。
// 因此本文件只使用内存假仓储 + 固定时钟 + 确定性 id 生成器：不建
// AppDatabase、不读写真实数据库、不发网络请求、不调模型。这样这些用例在
// 单元测试、调试页和验收脚本里都能重复运行且互不污染。

/// 运行全部个人上下文用例。
///
/// 返回结构沿用 `tts_lifecycle_checks.dart` 的约定：每条
/// `{'name': snake_case, 'passed': bool}`，抛错时额外带
/// `'error': runtimeType.toString()`。所有值都是 JSON-safe，便于被验收脚本
/// 直接序列化。
Future<List<Map<String, dynamic>>> runPersonalContextChecks() async {
  final cases = <Map<String, dynamic>>[];

  Future<void> check(String name, Future<bool> Function() run) async {
    try {
      cases.add(<String, dynamic>{'name': name, 'passed': await run()});
    } catch (error) {
      cases.add(<String, dynamic>{
        'name': name,
        'passed': false,
        'error': error.runtimeType.toString(),
      });
    }
  }

  final base = DateTime.utc(2026, 10, 19, 8);

  await check('same_name_person_requires_qualifier', () async {
    final fixture = _memoryFixture(() => base);
    final service = fixture.service;
    final a = await service.add(
      label: '王工',
      kind: PersonalContextEntityKind.person,
      qualifier: '甲方',
    );
    final b = await service.add(
      label: '王工',
      kind: PersonalContextEntityKind.person,
      qualifier: '乙方',
    );
    final byNameOnly =
        await service.resolve(const PersonalContextLookup(reference: '王工'));
    final byQualifier = await service.resolve(
      const PersonalContextLookup(reference: '王工', qualifier: '甲方'),
    );
    return byNameOnly.status == PersonalContextResolutionStatus.ambiguous &&
        byNameOnly.candidates.length == 2 &&
        byQualifier.isResolved &&
        byQualifier.entity!.id == a.id &&
        a.id != b.id;
  });

  await check('same_name_file_disambiguated_by_project', () async {
    final fixture = _memoryFixture(() => base);
    final service = fixture.service;
    final fileA = await service.add(
      label: '需求评审方案.pdf',
      kind: PersonalContextEntityKind.file,
      projectId: 'proj-a',
    );
    final fileB = await service.add(
      label: '需求评审方案.pdf',
      kind: PersonalContextEntityKind.file,
      projectId: 'proj-b',
    );
    final inA = await service.resolve(
      const PersonalContextLookup(
        reference: '需求评审方案.pdf',
        projectId: 'proj-a',
      ),
    );
    final inB = await service.resolve(
      const PersonalContextLookup(
        reference: '需求评审方案.pdf',
        projectId: 'proj-b',
      ),
    );
    // 没有项目上下文时不能召回项目私有文件，否则会串项目。
    final withoutProject = await service.resolve(
      const PersonalContextLookup(reference: '需求评审方案.pdf'),
    );
    return inA.isResolved &&
        inA.entity!.id == fileA.id &&
        inB.isResolved &&
        inB.entity!.id == fileB.id &&
        withoutProject.status == PersonalContextResolutionStatus.missing;
  });

  await check('multi_project_recall_isolation', () async {
    final fixture = _memoryFixture(() => base);
    final service = fixture.service;
    await service.add(
      label: '项目计划',
      kind: PersonalContextEntityKind.topic,
      projectId: 'proj-a',
    );
    await service.add(
      label: '公司愿景',
      kind: PersonalContextEntityKind.topic,
    );
    final crossProject = await service.resolve(
      const PersonalContextLookup(reference: '项目计划', projectId: 'proj-b'),
    );
    final global = await service.resolve(
      const PersonalContextLookup(reference: '公司愿景', projectId: 'proj-b'),
    );
    return crossProject.status == PersonalContextResolutionStatus.missing &&
        global.isResolved;
  });

  await check('expired_temporary_task_not_recalled', () async {
    final fixture = _memoryFixture(() => base);
    final service = fixture.service;
    await service.add(
      label: '明天下午交付初稿',
      kind: PersonalContextEntityKind.temporaryTask,
      validUntil: base.add(const Duration(hours: 4)),
    );
    final stillValid = await service.resolve(
      const PersonalContextLookup(reference: '明天下午交付初稿'),
      now: base.add(const Duration(hours: 1)),
    );
    final expired = await service.resolve(
      const PersonalContextLookup(reference: '明天下午交付初稿'),
      now: base.add(const Duration(hours: 5)),
    );
    return stillValid.isResolved &&
        expired.status == PersonalContextResolutionStatus.expired;
  });

  await check('expired_entry_excluded_from_injection', () async {
    final fixture = _memoryFixture(() => base);
    await fixture.service.add(
      label: '本周五之前回复合同',
      kind: PersonalContextEntityKind.temporaryTask,
      validUntil: base.add(const Duration(hours: 4)),
    );
    final laterService = PersonalContextService(
      fixture.repository,
      now: () => base.add(const Duration(days: 2)),
      idGenerator: (prefix) => '$prefix-late',
    );
    final block = await laterService.buildInjectionBlock();
    return block.isEmpty;
  });

  await check('inferred_entry_never_auto_confirmed', () async {
    final fixture = _memoryFixture(() => base);
    final service = fixture.service;
    final entity = await service.add(
      label: '张总偏好先看结论',
      kind: PersonalContextEntityKind.preference,
      source: PersonalContextSource.inferred,
      // 调用方即使声称已确认，推测来源也必须落成待确认。
      confirmation: PersonalContextConfirmation.confirmed,
    );
    return entity.confirmation == PersonalContextConfirmation.unconfirmed &&
        entity.provenanceLabel == '推测（未确认）';
  });

  await check('confirmed_inference_labeled_as_speculation', () async {
    final fixture = _memoryFixture(() => base);
    final service = fixture.service;
    final entity = await service.add(
      label: '李经理负责采购',
      kind: PersonalContextEntityKind.person,
      source: PersonalContextSource.inferred,
    );
    await service.confirm(entity.id);
    final block = await service.buildInjectionBlock();
    return block.contains('推测（已确认）') && block.contains('"speculative":true');
  });

  await check('unconfirmed_entry_excluded_from_injection', () async {
    final fixture = _memoryFixture(() => base);
    final service = fixture.service;
    await service.add(
      label: '下季度重点做海外市场',
      kind: PersonalContextEntityKind.topic,
      confirmation: PersonalContextConfirmation.unconfirmed,
    );
    final block = await service.buildInjectionBlock();
    final lookup = await service.resolve(
      const PersonalContextLookup(
        reference: '下季度重点做海外市场',
        includeUnconfirmed: false,
      ),
    );
    return block.isEmpty &&
        lookup.status == PersonalContextResolutionStatus.missing;
  });

  await check('revoked_authorization_excluded_from_recall', () async {
    final fixture = _memoryFixture(() => base);
    final service = fixture.service;
    await service.add(
      label: '内部报价单.xlsx',
      kind: PersonalContextEntityKind.file,
      source: PersonalContextSource.authorizedMaterial,
      authorization: PersonalContextAuthorization.revoked,
    );
    final resolution = await service
        .resolve(const PersonalContextLookup(reference: '内部报价单.xlsx'));
    final block = await service.buildInjectionBlock();
    return resolution.status == PersonalContextResolutionStatus.missing &&
        block.isEmpty;
  });

  await check('forget_cascades_alias_and_relation', () async {
    final fixture = _memoryFixture(() => base);
    final service = fixture.service;
    final person = await service.add(
      label: '张总',
      kind: PersonalContextEntityKind.person,
    );
    final project = await service.add(
      label: '星火计划',
      kind: PersonalContextEntityKind.project,
    );
    await service.addAlias(person.id, '老张');
    await service.addRelation(person.id, project.id, relationType: '负责');
    final report = await service.forget(person.id);
    final aliases = await service.aliases(entityId: person.id);
    final relations = await service.relations(entityId: person.id);
    return report.removedAliases == 1 &&
        report.removedRelations == 1 &&
        aliases.isEmpty &&
        relations.isEmpty;
  });

  await check('tombstone_blocks_silent_reentry', () async {
    final fixture = _memoryFixture(() => base);
    final service = fixture.service;
    final entity = await service.add(
      label: '临时外包联系人',
      kind: PersonalContextEntityKind.person,
    );
    await service.forget(entity.id);
    var blockedCode = PersonalContextErrorCode.invalid;
    try {
      await service.add(
        label: '临时外包联系人',
        kind: PersonalContextEntityKind.person,
      );
    } on PersonalContextException catch (error) {
      blockedCode = error.code;
    }
    // 用户明确重添仅放行一次；保留墓碑，不能顺带开放后续自动提取。
    final restored = await service.add(
      label: '临时外包联系人',
      kind: PersonalContextEntityKind.person,
      allowForgottenReentry: true,
    );
    final tombstones = await service.tombstones();
    return blockedCode == PersonalContextErrorCode.blocked &&
        restored.id != entity.id &&
        tombstones.isNotEmpty;
  });

  await check('forgotten_entity_not_recalled_and_scope_reported', () async {
    final fixture = _memoryFixture(() => base);
    final service = fixture.service;
    final entity = await service.add(
      label: '旧供应商合同',
      kind: PersonalContextEntityKind.file,
      projectId: 'proj-a',
    );
    await service.addAlias(entity.id, '老合同');
    final scope = await service.describeForgetScope(entity.id);
    await service.forget(entity.id);
    final resolution = await service.resolve(
      const PersonalContextLookup(
        reference: '旧供应商合同',
        projectId: 'proj-a',
      ),
    );
    return scope['aliasCount'] == 1 &&
        (scope['scope'] as String).contains('proj-a') &&
        resolution.status == PersonalContextResolutionStatus.blocked;
  });

  await check('correction_keeps_history_and_bumps_revision', () async {
    var now = base;
    final fixture = _memoryFixture(() => now);
    final service = fixture.service;
    final created = await service.add(
      label: '预算方案',
      kind: PersonalContextEntityKind.file,
      source: PersonalContextSource.userExplicit,
    );
    now = base.add(const Duration(hours: 2));
    final corrected = await service.correct(
      created.id,
      label: '预算方案（终版）',
      correctionNote: '用户确认以终版为准',
      expectedRevision: created.revision,
    );
    final history = await service.revisions(created.id);
    return corrected.revision == created.revision + 1 &&
        corrected.label == '预算方案（终版）' &&
        history.length == 1 &&
        history.first.revision == created.revision &&
        history.first.label == created.label &&
        history.first.source == created.source &&
        history.first.recordedAt == created.updatedAt &&
        corrected.correctionNote == '用户确认以终版为准';
  });

  await check('stale_revision_rejected_on_correct', () async {
    final fixture = _memoryFixture(() => base);
    final service = fixture.service;
    final entity = await service.add(
      label: '季度目标',
      kind: PersonalContextEntityKind.topic,
    );
    var code = PersonalContextErrorCode.invalid;
    try {
      await service.correct(
        entity.id,
        label: '季度目标（改）',
        expectedRevision: entity.revision + 9,
      );
    } on PersonalContextException catch (error) {
      code = error.code;
    }
    return code == PersonalContextErrorCode.stale;
  });

  await check('ambiguous_reference_never_auto_selected', () async {
    final fixture = _memoryFixture(() => base);
    final service = fixture.service;
    final first = await service.add(
      label: '第二季度市场方案',
      kind: PersonalContextEntityKind.file,
      projectId: 'proj-a',
    );
    final second = await service.add(
      label: '第二季度渠道方案',
      kind: PersonalContextEntityKind.file,
      projectId: 'proj-a',
    );
    await service.addAlias(first.id, '上次那份方案');
    await service.addAlias(second.id, '上次那份方案');
    final resolution = await service.resolve(const PersonalContextLookup(
      reference: '上次那份方案',
      // 两条记录都属于 proj-a；没有项目上下文的通用对话本就不该召回它们，
      // 这里显式带上项目，验证"同名候选"这一层。
      projectId: 'proj-a',
    ));
    var code = PersonalContextErrorCode.invalid;
    var candidateCount = 0;
    try {
      resolution.requireEntity();
    } on PersonalContextException catch (error) {
      code = error.code;
      candidateCount = error.candidates.length;
    }
    return resolution.status == PersonalContextResolutionStatus.ambiguous &&
        resolution.entity == null &&
        code == PersonalContextErrorCode.conflict &&
        candidateCount == 2;
  });

  await check('alias_resolves_cross_task_reference', () async {
    final fixture = _memoryFixture(() => base);
    final service = fixture.service;
    final target = await service.add(
      label: '第三季度发布方案',
      kind: PersonalContextEntityKind.file,
      qualifier: 'v3',
    );
    await service.addAlias(target.id, '上次那份方案');
    final resolution =
        await service.resolve(const PersonalContextLookup(reference: '上次那份方案'));
    return resolution.isResolved && resolution.entity!.id == target.id;
  });

  await check('sensitive_action_rejects_inferred_object', () async {
    final fixture = _memoryFixture(() => base);
    final service = fixture.service;
    final guessed = await service.add(
      label: '王工负责付款审批',
      kind: PersonalContextEntityKind.person,
      source: PersonalContextSource.inferred,
    );
    await service.confirm(guessed.id);
    final stated = await service.add(
      label: '李工负责付款审批',
      kind: PersonalContextEntityKind.person,
    );
    var unauthorizedCode = PersonalContextErrorCode.invalid;
    try {
      await service.requireUnique(
        const PersonalContextLookup(
          reference: '王工负责付款审批',
          forSensitiveAction: true,
        ),
      );
    } on PersonalContextException catch (error) {
      unauthorizedCode = error.code;
    }
    final statedResolution = await service.requireUnique(
      const PersonalContextLookup(
        reference: '李工负责付款审批',
        forSensitiveAction: true,
      ),
    );
    return unauthorizedCode == PersonalContextErrorCode.unauthorized &&
        statedResolution.id == stated.id;
  });

  await check('injection_budget_truncates_with_notice', () async {
    final fixture = _memoryFixture(() => base);
    final service = fixture.service;
    for (var index = 0; index < 8; index++) {
      await service.add(
        label: '长期项目背景条目编号$index',
        kind: PersonalContextEntityKind.topic,
        attributes: <String, Object?>{'note': '很长的说明文字' * 4},
      );
    }
    final block = await service.buildInjectionBlock(budget: 260);
    return block.contains('超出预算未注入') &&
        block.contains(PersonalContextService.injectionHeader);
  });

  await check('empty_store_injection_is_empty_string', () async {
    final fixture = _memoryFixture(() => base);
    final block =
        await fixture.service.buildInjectionBlock(contextTokens: 32000);
    return block.isEmpty;
  });

  await check('conflicts_group_duplicate_keys', () async {
    final fixture = _memoryFixture(() => base);
    final service = fixture.service;
    await service.add(
      label: '年度预算表',
      kind: PersonalContextEntityKind.file,
      allowDuplicate: true,
    );
    await service.add(
      label: '年度预算表',
      kind: PersonalContextEntityKind.file,
      allowDuplicate: true,
    );
    final conflicts = await service.conflicts();
    return conflicts.length == 1 && conflicts.first.entities.length == 2;
  });

  await check('wire_unknown_kind_reports_unsupported', () async {
    final fixture = _memoryFixture(() => base);
    var code = PersonalContextErrorCode.invalid;
    try {
      await fixture.service.addFromWire(<String, Object?>{
        'kind': 'spaceship',
        'label': '企业号',
        'source': 'user_explicit',
      });
    } on PersonalContextException catch (error) {
      code = error.code;
    }
    return code == PersonalContextErrorCode.unsupported;
  });

  await check('normalized_key_ignores_punctuation_and_width', () async {
    final fixture = _memoryFixture(() => base);
    final service = fixture.service;
    final entity = await service.add(
      label: '《方案（终版）》',
      kind: PersonalContextEntityKind.file,
    );
    final resolution = await service
        .resolve(const PersonalContextLookup(reference: ' 方案(终版) '));
    return resolution.isResolved &&
        resolution.entity!.id == entity.id &&
        entity.normalizedKey == 'file:方案(终版)';
  });

  return cases;
}

// -----------------------------------------------------------------------------
// 纯内存假仓储
// -----------------------------------------------------------------------------

/// 只在内存里保存实体/关系/别名/墓碑/历史的仓储实现。
///
/// 不 import drift、不创建数据库文件，任何一次用例结束数据即随对象销毁；
/// 合同报告据此可以断言没有持久化副作用。
class _MemoryPersonalContextRepository implements PersonalContextRepository {
  final Map<String, PersonalContextEntity> _entities =
      <String, PersonalContextEntity>{};
  final Map<String, PersonalContextRelation> _relations =
      <String, PersonalContextRelation>{};
  final Map<String, PersonalContextAlias> _aliases =
      <String, PersonalContextAlias>{};
  final Map<String, PersonalContextTombstone> _tombstones =
      <String, PersonalContextTombstone>{};
  final Map<String, PersonalContextRevision> _revisions =
      <String, PersonalContextRevision>{};

  static String _tombstoneId(String normalizedKey, String? projectId) =>
      '$normalizedKey@@${projectId ?? ''}';

  @override
  Future<void> ensureReady() async {}

  @override
  Future<PersonalContextEntity?> findEntity(String id) async => _entities[id];

  @override
  Future<List<PersonalContextEntity>> listEntities({
    bool includeForgotten = false,
  }) async {
    final result = _entities.values
        .where((entity) => includeForgotten || !entity.isForgotten)
        .toList(growable: false);
    final sorted = List<PersonalContextEntity>.from(result)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sorted;
  }

  @override
  Future<List<PersonalContextEntity>> findEntitiesByKey(
      String normalizedKey) async {
    return _entities.values
        .where((entity) => entity.normalizedKey == normalizedKey)
        .toList(growable: false);
  }

  @override
  Future<void> insertEntity(PersonalContextEntity entity,
      {bool allowForgottenReentry = false}) async {
    final blocked = await findTombstone(
        normalizedKey: entity.normalizedKey,
        projectId: entity.projectId,
        originRef: entity.originRef);
    if (blocked != null &&
        !(allowForgottenReentry &&
            entity.source == PersonalContextSource.userExplicit)) {
      throw const PersonalContextException(
          PersonalContextErrorCode.blocked, 'Forgotten');
    }
    if (_entities.containsKey(entity.id)) {
      throw StateError('duplicate entity ${entity.id}');
    }
    _entities[entity.id] = entity;
  }

  @override
  Future<int> updateEntity(
    PersonalContextEntity entity, {
    required int expectedRevision,
    PersonalContextRevision? previousRevision,
  }) async {
    final current = _entities[entity.id];
    if (current == null ||
        current.isForgotten ||
        current.revision != expectedRevision) {
      return 0;
    }
    if (current.normalizedKey != entity.normalizedKey &&
        await findTombstone(
                normalizedKey: entity.normalizedKey,
                projectId: entity.projectId,
                originRef: entity.originRef) !=
            null) {
      throw const PersonalContextException(
          PersonalContextErrorCode.blocked, 'Forgotten');
    }
    _entities[entity.id] = entity;
    if (previousRevision != null) {
      await appendRevision(previousRevision);
    }
    return 1;
  }

  @override
  Future<List<PersonalContextRelation>> listRelations(
      {String? entityId}) async {
    return _relations.values
        .where((relation) =>
            entityId == null ||
            relation.fromEntityId == entityId ||
            relation.toEntityId == entityId)
        .toList(growable: false);
  }

  @override
  Future<void> insertRelation(PersonalContextRelation relation) async {
    if (_entities[relation.fromEntityId]?.isForgotten != false ||
        _entities[relation.toEntityId]?.isForgotten != false) {
      throw const PersonalContextException(
          PersonalContextErrorCode.blocked, 'Forgotten');
    }
    _relations[relation.id] = relation;
  }

  @override
  Future<List<PersonalContextAlias>> listAliases({String? entityId}) async {
    return _aliases.values
        .where((alias) => entityId == null || alias.entityId == entityId)
        .toList(growable: false);
  }

  @override
  Future<void> insertAlias(PersonalContextAlias alias) async {
    if (_entities[alias.entityId]?.isForgotten != false) {
      throw const PersonalContextException(
          PersonalContextErrorCode.blocked, 'Forgotten');
    }
    _aliases[alias.id] = alias;
  }

  @override
  Future<PersonalContextTombstone?> findTombstone({
    required String normalizedKey,
    required String? projectId,
    String originRef = '',
  }) async {
    final requested = unqualifiedPersonalContextKey(normalizedKey);
    final sourceKey = personalContextSourceTombstoneKey(originRef);
    for (final tombstone in _tombstones.values) {
      if (tombstone.projectId != null && tombstone.projectId != projectId) {
        continue;
      }
      if (unqualifiedPersonalContextKey(tombstone.normalizedKey) == requested ||
          (sourceKey.isNotEmpty && tombstone.normalizedKey == sourceKey)) {
        return tombstone;
      }
      final forgotten = _entities[tombstone.entityId];
      if (forgotten != null) {
        if (originRef.trim().isNotEmpty &&
            forgotten.originRef.trim() == originRef.trim()) {
          return tombstone;
        }
        for (final revision in await listRevisions(forgotten.id)) {
          if (buildPersonalContextKey(
                  kind: forgotten.kind, label: revision.label) ==
              requested) {
            return tombstone;
          }
        }
      }
    }
    return null;
  }

  @override
  Future<List<PersonalContextTombstone>> listTombstones() async =>
      _tombstones.values.toList(growable: false);

  @override
  Future<void> putTombstone(PersonalContextTombstone tombstone) async {
    _tombstones[_tombstoneId(tombstone.normalizedKey, tombstone.projectId)] =
        tombstone;
  }

  @override
  Future<void> deleteTombstone({
    required String normalizedKey,
    required String? projectId,
  }) async {
    _tombstones.remove(_tombstoneId(normalizedKey, projectId));
  }

  @override
  Future<void> appendRevision(PersonalContextRevision revision) async {
    _revisions[revision.id] = revision;
  }

  @override
  Future<List<PersonalContextRevision>> listRevisions(String entityId) async {
    final revisions = _revisions.values
        .where((revision) => revision.entityId == entityId)
        .toList()
      ..sort((a, b) => a.revision.compareTo(b.revision));
    return revisions;
  }

  @override
  Future<PersonalContextForgetReport> forgetEntity({
    required PersonalContextEntity forgotten,
    required PersonalContextTombstone tombstone,
  }) async {
    final current = _entities[forgotten.id];
    if (current == null ||
        current.isForgotten ||
        current.revision != forgotten.revision - 1) {
      throw const PersonalContextException(
          PersonalContextErrorCode.stale, 'Changed');
    }
    final blockedKeys = <String>{
      tombstone.normalizedKey,
      unqualifiedPersonalContextKey(current.normalizedKey),
      if (current.originRef.trim().isNotEmpty)
        personalContextSourceTombstoneKey(current.originRef),
      for (final alias
          in _aliases.values.where((a) => a.entityId == current.id))
        buildPersonalContextKey(kind: current.kind, label: alias.alias),
      for (final r in await listRevisions(current.id))
        buildPersonalContextKey(kind: current.kind, label: r.label),
    };
    final removedAliases =
        _aliases.values.where((alias) => alias.entityId == forgotten.id).length;
    final removedRelations = _relations.values
        .where((relation) =>
            relation.fromEntityId == forgotten.id ||
            relation.toEntityId == forgotten.id)
        .length;
    final keptRevisions = _revisions.values
        .where((revision) => revision.entityId == forgotten.id)
        .length;
    _aliases.removeWhere((_, alias) => alias.entityId == forgotten.id);
    _relations.removeWhere((_, relation) =>
        relation.fromEntityId == forgotten.id ||
        relation.toEntityId == forgotten.id);
    _entities[forgotten.id] = forgotten;
    for (final key in blockedKeys) {
      await putTombstone(PersonalContextTombstone(
          normalizedKey: key,
          projectId: tombstone.projectId,
          reason: tombstone.reason,
          forgottenAt: tombstone.forgottenAt,
          entityId: tombstone.entityId));
    }
    return PersonalContextForgetReport(
      entity: forgotten,
      removedAliases: removedAliases,
      removedRelations: removedRelations,
      keptRevisions: keptRevisions,
      tombstone: tombstone,
    );
  }
}

/// 组装一个"服务 + 内存仓储 + 固定时钟 + 确定性 id"的夹具。
({
  PersonalContextService service,
  _MemoryPersonalContextRepository repository,
}) _memoryFixture(DateTime Function() clock) {
  final repository = _MemoryPersonalContextRepository();
  var sequence = 0;
  return (
    repository: repository,
    service: PersonalContextService(
      repository,
      now: clock,
      idGenerator: (prefix) => '$prefix-${++sequence}',
    ),
  );
}
