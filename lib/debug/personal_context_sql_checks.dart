import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../application/cost_budget_service.dart';
import '../application/knowledge_service.dart';
import '../application/mobile_workflow_service.dart';
import '../application/personal_context_service.dart';
import '../application/reminder_service.dart';
import '../application/remote_execution_probe.dart';
import '../application/research_artifact_service.dart';
import '../domain/provider_template.dart';
import '../domain/reminder.dart';
import '../domain/research_artifact.dart';
import '../application/providers.dart';
import '../domain/personal_context.dart';
import '../domain/result_card.dart';
import '../domain/mobile_workflow.dart';
import '../domain/unique_id.dart';
import '../domain/models.dart';
import '../domain/model_failure.dart';
import '../infrastructure/database/cost_budget_ledger.dart';
import '../infrastructure/providers/cost_budget_provider.dart';
import '../infrastructure/providers/provider_config.dart';
import '../infrastructure/providers/llm_provider.dart';
import 'package:dio/dio.dart' show CancelToken;
import '../infrastructure/database/app_database.dart';
import '../infrastructure/database/personal_context_store.dart';
import '../infrastructure/database/result_action_store.dart';
import '../infrastructure/files/vault_exporter_io.dart';
import '../infrastructure/notifications/notification_service.dart';
import '../presentation/settings/personal_context_page.dart';
import 'personal_context_checks.dart';

bool _registered = false;
void registerPersonalContextSqlChecks() {
  if (!kDebugMode || _registered) return;
  _registered = true;
  registerExtension(
      'ext.nexus.personalContextSqlContract',
      (method, params) async =>
          ServiceExtensionResponse.result(jsonEncode(await _checks())));
  registerExtension('ext.nexus.personalContextSqlFixture',
      (method, params) async {
    if (params['mode'] == 'delivery') {
      final f = _Fixture();
      final id = UniqueId.generate('notification-fixture');
      var scheduled = false, cancelled = false;
      ExactAlarmCapability? capability;
      try {
        await f.init();
        final service = ReminderService(f.db);
        final reminder = await service.create(
            id: id,
            title: 'NEXUS 通知边界隔离验收',
            scheduledAtUtc:
                DateTime.now().toUtc().add(const Duration(hours: 1)));
        capability = reminder.exactAlarmCapability;
        scheduled = await NotificationService.instance.isReminderScheduled(id);
        await service.cancel(id);
        cancelled = !await NotificationService.instance.isReminderScheduled(id);
      } finally {
        await NotificationService.instance.cancelReminder(id);
        await f.close();
      }
      return ServiceExtensionResponse.result(jsonEncode({
        'fixtureOnly': true,
        'modelCalls': 0,
        'realUserDataMutations': 0,
        'scheduled': scheduled,
        'cancelled': cancelled,
        'capability': capability.wireName,
        'passed':
            scheduled && cancelled && capability != ExactAlarmCapability.denied,
      }));
    } else if (params['mode'] == 'open') {
      await _open();
    } else if (params['mode'] == 'inspect') {
      final f = _uiFixture;
      if (f == null) throw StateError('Open owned fixture first');
      return ServiceExtensionResponse.result(jsonEncode({
        'fixtureOnly': true,
        'modelCalls': 0,
        'active': (await f.service.list()).length,
        'forgotten': (await f.service.list(includeForgotten: true))
            .where((e) => e.isForgotten)
            .length,
        'aliases': (await f.store.listAliases()).length,
        'relations': (await f.store.listRelations()).length,
        'tombstones': (await f.store.listTombstones()).length,
      }));
    } else if (params['mode'] == 'close') {
      if (_uiRoute != null) _uiNavigator?.removeRoute(_uiRoute!);
    } else {
      return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams, 'Fixed modes only');
    }
    return ServiceExtensionResponse.result(
        jsonEncode({'fixtureOnly': true, 'modelCalls': 0}));
  });
}

Future<bool> _rejects(
    Future<Object?> Function() run, PersonalContextErrorCode code) async {
  try {
    await run();
    return false;
  } on PersonalContextException catch (error) {
    return error.code == code;
  }
}

Future<Map<String, dynamic>> _checks() async {
  final cases = <Map<String, dynamic>>[];
  Future<void> check(
      String name, Future<bool> Function(_Fixture f) body) async {
    debugPrint('[context-contract] $name');
    final f = _Fixture();
    try {
      await f.init();
      cases.add({'name': name, 'passed': await body(f)});
    } catch (error) {
      cases.add(
          {'name': name, 'passed': false, 'error': '${error.runtimeType}'});
    } finally {
      await f.close();
    }
  }

  await check('sqlite_round_trip_preserves_provenance_and_project', (f) async {
    final entity =
        await f.add(qualifier: '甲方', project: ' project-a ', origin: 'doc:a');
    final saved = (await f.store.findEntity(entity.id))!;
    return saved.label == '验收联系人' &&
        saved.qualifier == '甲方' &&
        saved.projectId == 'project-a' &&
        saved.originRef == 'doc:a' &&
        saved.isConfirmed;
  });
  await check('qualifier_change_cannot_bypass_forget', (f) async {
    final entity = await f.add(qualifier: '甲方');
    await f.service.forget(entity.id);
    return _rejects(
        () => f.add(qualifier: '另一个限定词'), PersonalContextErrorCode.blocked);
  });
  await check('renamed_same_source_cannot_bypass_forget', (f) async {
    final entity = await f.add(origin: 'document:a#record:1');
    await f.service.forget(entity.id);
    return _rejects(
        () => f.add(label: '完全不同的新名称', origin: 'document:a#record:1'),
        PersonalContextErrorCode.blocked);
  });
  await check('historical_name_is_protected_after_correction', (f) async {
    final entity = await f.add(label: '原始名称');
    final next = await f.service.correct(entity.id, label: '更正名称');
    await f.service.forget(next.id);
    return _rejects(
        () => f.add(label: '原始名称'), PersonalContextErrorCode.blocked);
  });
  await check('alias_cannot_be_reimported_as_new_label', (f) async {
    final entity = await f.add();
    await f.service.addAlias(entity.id, '上次那位王工');
    await f.service.forget(entity.id);
    return (await f.store.listAliases()).isEmpty &&
        await _rejects(
            () => f.add(label: '上次那位王工'), PersonalContextErrorCode.blocked);
  });
  await check('source_guard_survives_same_name_tombstone_collision', (f) async {
    final a = await f.add(origin: 'source-a', qualifier: '甲');
    final b = await f.add(origin: 'source-b', qualifier: '乙');
    await f.service.forget(a.id);
    await f.service.forget(b.id);
    return await _rejects(() => f.add(label: '新的甲', origin: 'source-a'),
            PersonalContextErrorCode.blocked) &&
        await _rejects(() => f.add(label: '新的乙', origin: 'source-b'),
            PersonalContextErrorCode.blocked);
  });
  await check('project_forget_does_not_block_other_project', (f) async {
    final entity = await f.add(project: 'a', origin: 'shared-doc');
    await f.service.forget(entity.id);
    final other = await f.add(project: 'b', origin: 'shared-doc');
    return other.projectId == 'b' &&
        await _rejects(
            () => f.add(project: 'a'), PersonalContextErrorCode.blocked);
  });
  await check('global_forget_cannot_be_escaped_by_project_assignment',
      (f) async {
    final entity = await f.add();
    await f.service.forget(entity.id);
    return _rejects(
        () => f.add(project: 'new-project'), PersonalContextErrorCode.blocked);
  });
  await check('one_shot_reentry_does_not_erase_privacy_rule_or_old_edges',
      (f) async {
    final entity = await f.add(origin: 'source');
    await f.service.addAlias(entity.id, '旧别名');
    await f.service.forget(entity.id);
    final restored = await f.service.add(
        label: '验收联系人',
        kind: PersonalContextEntityKind.person,
        originRef: 'source',
        allowForgottenReentry: true);
    return restored.id != entity.id &&
        (await f.store.listTombstones()).isNotEmpty &&
        (await f.store.listAliases()).isEmpty &&
        await _rejects(() => f.add(label: '自动改名', origin: 'source'),
            PersonalContextErrorCode.blocked);
  });
  await check('inference_cannot_use_manual_reentry_override', (f) async {
    final entity = await f.add();
    await f.service.forget(entity.id);
    return _rejects(
        () => f.service.add(
            label: entity.label,
            kind: entity.kind,
            source: PersonalContextSource.inferred,
            allowForgottenReentry: true),
        PersonalContextErrorCode.blocked);
  });
  await check('wire_cannot_grant_itself_reentry', (f) async {
    final entity = await f.add();
    await f.service.forget(entity.id);
    return _rejects(
        () => f.service.addFromWire({
              'label': entity.label,
              'kind': entity.kind.wireName,
              'source': 'user_explicit',
              'allowForgottenReentry': true
            }),
        PersonalContextErrorCode.blocked);
  });
  await check('repository_insert_rechecks_forget_at_write_boundary', (f) async {
    final entity = await f.add();
    await f.service.forget(entity.id);
    return _rejects(
        () => f.store
            .insertEntity(entity.copyWith(id: 'late-insert', qualifier: 'new')),
        PersonalContextErrorCode.blocked);
  });
  await check('forgotten_parent_cannot_gain_alias_or_relation', (f) async {
    final entity = await f.add();
    final other = await f.add(label: '其他联系人');
    await f.service.forget(entity.id);
    final aliasRejected = await _rejects(
        () => f.store.insertAlias(PersonalContextAlias(
            id: 'late-alias',
            entityId: entity.id,
            alias: '迟到别名',
            normalizedAlias: '迟到别名',
            createdAt: f.now)),
        PersonalContextErrorCode.blocked);
    final relationRejected = await _rejects(
        () => f.store.insertRelation(PersonalContextRelation(
            id: 'late-relation',
            fromEntityId: entity.id,
            toEntityId: other.id,
            relationType: 'related_to',
            source: PersonalContextSource.userExplicit,
            confirmation: PersonalContextConfirmation.confirmed,
            createdAt: f.now,
            updatedAt: f.now)),
        PersonalContextErrorCode.blocked);
    return aliasRejected &&
        relationRejected &&
        (await f.store.listAliases()).isEmpty &&
        (await f.store.listRelations()).isEmpty;
  });
  await check('stale_correction_does_not_append_phantom_history', (f) async {
    final entity = await f.add();
    final rejected = await _rejects(
        () =>
            f.service.correct(entity.id, label: '错误的更正', expectedRevision: 99),
        PersonalContextErrorCode.stale);
    return rejected &&
        (await f.store.listRevisions(entity.id)).isEmpty &&
        (await f.service.get(entity.id)).revision == 1;
  });
  await check('history_write_failure_rolls_back_entity_change', (f) async {
    final entity = await f.add();
    await f.db.customStatement(
        'CREATE TRIGGER fail_history BEFORE INSERT ON $personalContextRevisionsTable '
        "BEGIN SELECT RAISE(ABORT, 'synthetic history failure'); END");
    try {
      await f.service.correct(entity.id, label: '不应保存');
      return false;
    } catch (_) {
      return (await f.service.get(entity.id)).label == entity.label &&
          (await f.store.listRevisions(entity.id)).isEmpty;
    }
  });
  await check('stale_forget_does_not_overwrite_new_revision', (f) async {
    final entity = await f.add();
    await f.service.addAlias(entity.id, '别名保留');
    final next = await f.service.correct(entity.id, label: '更新后的名称');
    final rejected = await _rejects(
        () => f.store.forgetEntity(
            forgotten: entity.copyWith(
                lifecycle: PersonalContextLifecycle.forgotten,
                revision: entity.revision + 1,
                forgottenAt: f.now),
            tombstone: PersonalContextTombstone(
                normalizedKey: entity.normalizedKey,
                forgottenAt: f.now,
                entityId: entity.id)),
        PersonalContextErrorCode.stale);
    return rejected &&
        (await f.service.get(entity.id)).revision == next.revision &&
        (await f.store.listTombstones()).isEmpty &&
        (await f.store.listAliases()).length == 1;
  });
  await check('forget_mid_transaction_failure_rolls_back_all_changes',
      (f) async {
    final entity = await f.add();
    await f.service.addAlias(entity.id, '保留别名');
    await f.db.customStatement(
        'CREATE TRIGGER fail_forget BEFORE DELETE ON $personalContextAliasesTable '
        "BEGIN SELECT RAISE(ABORT, 'synthetic forget failure'); END");
    try {
      await f.service.forget(entity.id);
      return false;
    } catch (_) {
      return !(await f.service.get(entity.id)).isForgotten &&
          (await f.store.listTombstones()).isEmpty &&
          (await f.store.listAliases()).length == 1;
    }
  });
  await check('reopen_sqlite_keeps_source_and_alias_guards', (f) async {
    final entity = await f.add(origin: 'durable-source');
    await f.service.addAlias(entity.id, '持久别名');
    await f.service.forget(entity.id);
    await f.reopen();
    return await _rejects(() => f.add(label: '重开后改名', origin: 'durable-source'),
            PersonalContextErrorCode.blocked) &&
        await _rejects(
            () => f.add(label: '持久别名'), PersonalContextErrorCode.blocked);
  });
  await check('second_connection_stale_update_cannot_write_history', (f) async {
    final entity = await f.add();
    final second = AppDatabase(NativeDatabase(f.databaseFile));
    try {
      final other = SqlitePersonalContextStore(second);
      await other.ensureReady();
      final stale = (await other.findEntity(entity.id))!;
      await f.service.correct(entity.id, label: '第一个连接的新值');
      final affected = await other.updateEntity(
          stale.copyWith(label: '旧回调', revision: 2),
          expectedRevision: stale.revision,
          previousRevision: PersonalContextRevision(
              id: 'stale-history',
              entityId: entity.id,
              revision: 1,
              label: stale.label,
              source: stale.source,
              confirmation: stale.confirmation,
              recordedAt: f.now));
      return affected == 0 &&
          (await f.store.listRevisions(entity.id)).length == 1 &&
          (await f.service.get(entity.id)).label == '第一个连接的新值';
    } finally {
      await second.close();
    }
  });
  await check('unauthorized_material_cannot_recall_or_inject', (f) async {
    final entity = await f.service.add(
        label: '未授权资料',
        kind: PersonalContextEntityKind.file,
        source: PersonalContextSource.authorizedMaterial);
    return !entity.isAuthorized &&
        (await f.service.buildInjectionBlock()).isEmpty &&
        !(await f.service
                .resolve(const PersonalContextLookup(reference: '未授权资料')))
            .isResolved;
  });
  await check('granted_material_remains_recallable', (f) async {
    final entity = await f.service.add(
        label: '已授权资料',
        kind: PersonalContextEntityKind.file,
        source: PersonalContextSource.authorizedMaterial,
        authorization: PersonalContextAuthorization.granted);
    return entity.isAuthorized &&
        (await f.service.buildInjectionBlock()).contains('已授权资料');
  });
  await check('data_clear_removes_all_personal_context_private_rows',
      (f) async {
    final entity = await f.add(origin: 'private-source');
    await f.service.correct(entity.id, label: '私有更正');
    await f.service.addAlias(entity.id, '私有别名');
    await f.service.forget(entity.id);
    await f.db.clearAllUserData();
    for (final table in _tables) {
      if ((await f.db
                  .customSelect('SELECT COUNT(*) AS c FROM $table')
                  .getSingle())
              .read<int>('c') !=
          0) {
        return false;
      }
    }
    return true;
  });
  await check('schema31_to32_creates_real_personal_context_tables', (f) async {
    for (final table in _tables) {
      await f.db.customStatement('DROP TABLE $table');
    }
    await f.db.customStatement('PRAGMA user_version = 31');
    await f.reopen();
    final entity = await f.add();
    return (await f.store.findEntity(entity.id)) != null &&
        (await f.db.customSelect('PRAGMA user_version').getSingle())
                .data
                .values
                .single ==
            32;
  });
  await check('legacy32_qualified_tombstone_and_history_still_block',
      (f) async {
    final entity = await f.add(label: '旧系统名称', qualifier: '甲');
    final next = await f.service.correct(entity.id, label: '旧系统新名称');
    // Simulates the old schema-32 forget shape: only a qualified tombstone,
    // retained history/entity, aliases already removed by the old app.
    await f.store.updateEntity(
        next.copyWith(
            lifecycle: PersonalContextLifecycle.forgotten,
            revision: next.revision + 1,
            forgottenAt: f.now),
        expectedRevision: next.revision);
    await f.store.putTombstone(PersonalContextTombstone(
        normalizedKey: next.normalizedKey,
        forgottenAt: f.now,
        entityId: next.id));
    await f.reopen();
    return await _rejects(
            () => f.add(label: '旧系统名称'), PersonalContextErrorCode.blocked) &&
        await _rejects(() => f.add(label: '旧系统新名称', qualifier: '乙'),
            PersonalContextErrorCode.blocked);
  });
  await check('forget_does_not_delete_other_existing_same_name_entity',
      (f) async {
    final a = await f.add(qualifier: '甲');
    final b = await f.add(qualifier: '乙');
    await f.service.forget(a.id);
    final found = await f.service.resolve(
        const PersonalContextLookup(reference: '验收联系人', qualifier: '乙'));
    return found.entity?.id == b.id && (await f.service.list()).length == 1;
  });
  await check('source_digest_never_becomes_reference_name', (f) async {
    final entity = await f.add(origin: 'sensitive-source');
    await f.service.forget(entity.id);
    final guard = (await f.store.listTombstones())
        .singleWhere((t) => t.normalizedKey.startsWith('source-sha256:'));
    return !guard.normalizedKey.contains('sensitive-source') &&
        !tombstoneMatchesReference(guard, guard.normalizedKey.split(':').last);
  });
  await check('rename_existing_entity_to_forgotten_name_is_blocked', (f) async {
    final old = await f.add(label: '禁止自动回库的名称');
    final active = await f.add(label: '另一个活动条目');
    await f.service.forget(old.id);
    final rejected = await _rejects(
        () => f.service.correct(active.id, label: old.label),
        PersonalContextErrorCode.blocked);
    return rejected && (await f.store.listRevisions(active.id)).isEmpty;
  });
  await check('wire_cannot_grant_its_own_material_authorization', (f) async {
    return _rejects(
        () => f.service.addFromWire({
              'label': '模型伪造授权',
              'kind': 'file',
              'source': 'authorized_material',
              'authorization': 'granted',
              'confirmation': 'confirmed',
            }),
        PersonalContextErrorCode.unauthorized);
  });
  await check('legacy_restore_preserves_local_context_and_warns_about_coverage',
      (f) async {
    final entity = await f.add(origin: 'keep-forget-rule');
    await f.service.forget(entity.id);
    await f.add(label: '本机仍有效的条目');
    final before = (await f.service.list(includeForgotten: true)).length;
    final report = await restoreVault(f.db, {'version': 1});
    return (await f.service.list(includeForgotten: true)).length == before &&
        report.warnings.any((w) => w.contains('本备份不含个人上下文')) &&
        await _rejects(() => f.add(label: '恢复后改名', origin: 'keep-forget-rule'),
            PersonalContextErrorCode.blocked);
  });
  await check(
      'full_vault_round_trip_restores_context_and_sanitizes_pending_result_actions',
      (f) async {
    final alice = await f.add(label: 'Alice', origin: 'full-vault-origin');
    final org = await f.service.add(
      kind: PersonalContextEntityKind.organization,
      label: 'NexusLab',
      source: PersonalContextSource.userExplicit,
      confirmation: PersonalContextConfirmation.confirmed,
    );
    await f.service.addAlias(org.id, 'NLab');
    await f.service.addRelation(
      alice.id,
      org.id,
      relationType: 'works_at',
    );
    await ensureResultActionTables(f.db);
    final resultRepo = SqlResultActionRepository(f.db);
    await resultRepo.saveCard(ResultCard(
      id: 'vault-card-1',
      kind: ResultCardKind.route,
      resourceType: 'route',
      resourceId: 'route-vault-1',
      resourceVersion: 1,
      title: '园区路线',
      summary: '从地铁站步行',
      snapshot: const {'query': 'NexusLab 园区'},
      createdAt: DateTime.utc(2026, 10, 19),
      updatedAt: DateTime.utc(2026, 10, 19),
    ));
    await resultRepo.saveAction(ResultActionRecord(
      id: 'vault-action-pending',
      cardId: 'vault-card-1',
      cardRevision: 1,
      actionType: 'route.open',
      status: ResultActionStatus.pendingConfirm,
      idempotencyKey: 'vault-card-1:route.open:v1',
      risk: ResultActionRisk.medium,
      approvalId: 'stale-approval-id',
      createdAt: DateTime.utc(2026, 10, 19),
      updatedAt: DateTime.utc(2026, 10, 19),
    ));
    final backup = await buildVaultJson(f.db);

    final targetDb = AppDatabase(NativeDatabase.memory());
    try {
      final targetStore = SqlitePersonalContextStore(targetDb);
      await targetStore.ensureReady();
      final targetService = PersonalContextService(
        targetStore,
        now: () => f.now,
      );
      // Local tombstone on target device must block re-importing forgotten origin.
      final localBlocked = await targetService.add(
        kind: PersonalContextEntityKind.person,
        label: 'LocalBlocked',
        source: PersonalContextSource.inferred,
        originRef: 'full-vault-origin',
      );
      await targetService.forget(localBlocked.id);

      final report = await restoreVault(targetDb, backup);
      final restoredEntities =
          await targetService.list(includeForgotten: false);
      final restoredRepo = SqlResultActionRepository(targetDb);
      final restoredCard = await restoredRepo.findCard('vault-card-1');
      final restoredAction =
          await restoredRepo.findAction('vault-action-pending');
      return !report.warnings.any((w) => w.contains('本备份不含个人上下文')) &&
          report.warnings.any((w) => w.contains('已按个人上下文遗忘墓碑跳过 1 条实体')) &&
          restoredEntities.length == 1 &&
          restoredEntities.single.label == 'NexusLab' &&
          restoredCard != null &&
          restoredAction != null &&
          restoredAction.status == ResultActionStatus.failed &&
          restoredAction.approvalId == null;
    } finally {
      await targetDb.close();
    }
  });
  await check('f10_reminder_service_dst_snooze_reschedule_and_complete',
      (f) async {
    final service = ReminderService(f.db, delivery: null);
    final dstTrigger = ReminderItem.computeNextTriggerUtc(
      year: 2026,
      month: 3,
      day: 8,
      hour: 2,
      minute: 30,
      baseUtcOffsetMinutes: -300,
      dstActive: true,
      dstSpringForwardGap: true,
    );
    final item = await service.create(
      title: '提交月度预算复盘',
      scheduledAtUtc: dstTrigger,
      timezoneId: 'America/New_York',
      utcOffsetMinutes: -240,
      dstActive: true,
      exactAlarmCapability: ExactAlarmCapability.degradedInexact,
      now: f.now,
    );
    final snoozed = await service.snooze(
      item.id,
      duration: const Duration(minutes: 15),
      now: f.now,
    );
    final completed = await service.complete(item.id, now: f.now);
    return dstTrigger == DateTime.utc(2026, 3, 8, 7, 30) &&
        ReminderItem.computeNextTriggerUtc(
                year: 2026,
                month: 11,
                day: 1,
                hour: 1,
                minute: 30,
                baseUtcOffsetMinutes: -300,
                dstActive: true,
                dstFallBackSecondOccurrence: true) ==
            DateTime.utc(2026, 11, 1, 6, 30) &&
        snoozed.status == ReminderStatus.snoozed &&
        snoozed.snoozeCount == 1 &&
        snoozed.version == 2 &&
        completed.status == ReminderStatus.completed &&
        completed.version == 3;
  });
  await check('f18_mobile_workflow_dry_run_and_confirmation_gate', (f) async {
    final wfService = MobileWorkflowService(f.db, reminderDelivery: null);
    final remService = ReminderService(f.db, delivery: null);
    final dryRun = await wfService.runWorkflow(
      workflowId: 'wf-daily-brief',
      inputs: const <String, String>{'topic': '架构评审纪要'},
      dryRun: true,
      highRiskConfirmed: false,
      now: f.now,
    );
    final blocked = await wfService.runWorkflow(
      workflowId: 'wf-daily-brief',
      inputs: const <String, String>{'topic': '架构评审纪要'},
      dryRun: false,
      highRiskConfirmed: false,
      now: f.now,
    );
    final confirmed = await wfService.runWorkflow(
      workflowId: 'wf-daily-brief',
      inputs: const <String, String>{'topic': '架构评审纪要'},
      dryRun: false,
      highRiskConfirmed: true,
      now: f.now,
    );
    final reminders = await remService.list();
    return dryRun.status == 'succeeded' &&
        blocked.status == 'blocked_confirmation' &&
        confirmed.status == 'succeeded' &&
        reminders.length == 1 &&
        reminders.single.title.contains('架构评审纪要');
  });
  await check('f19_research_artifact_citations_conflict_and_freshness',
      (f) async {
    final service = ResearchArtifactService(f.db);
    final created = await service.create(
      topic: '端侧模型量化延迟对比',
      summary: '核查 Q4_K_M 与 Q8_0 在移动端的首词延迟',
      claims: const <ResearchClaim>[
        ResearchClaim(
          id: 'c1',
          statement: 'Q4_K_M 内存占用降低约 45%',
          citations: <EvidenceCitation>[],
        ),
      ],
      now: f.now,
    );
    final withCite = await service.addCitation(
      artifactId: created.id,
      claimId: 'c1',
      citation: EvidenceCitation(
        id: 'cit-1',
        sourceTitle: 'Benchmark Report v1',
        sourceUri: 'https://example.com/bench-v1',
        excerpt: 'Q4_K_M uses 45% less RAM than Q8_0.',
        capturedAt: f.now.subtract(const Duration(days: 20)),
        verifiedAt: f.now.subtract(const Duration(days: 20)),
      ),
      now: f.now,
    );
    final staleLevel = withCite.claims.single.evaluateSupport(now: f.now);
    final refreshed = await service.refreshVerification(
      artifactId: created.id,
      verifyCitation: (_) async => true,
      now: f.now,
    );
    final supportedLevel = refreshed.claims.single.evaluateSupport(now: f.now);
    final conflicted = await service.addCitation(
      artifactId: created.id,
      claimId: 'c1',
      citation: EvidenceCitation(
        id: 'cit-2',
        sourceTitle: 'Counter Report',
        sourceUri: 'https://example.com/counter',
        excerpt: 'Contradicting measurement under thermal throttling.',
        capturedAt: f.now,
        verifiedAt: f.now,
        contradictsClaim: true,
      ),
      now: f.now,
    );
    return staleLevel == EvidenceSupportLevel.stale &&
        supportedLevel == EvidenceSupportLevel.supported &&
        conflicted.hasConflicts;
  });
  await check('f01_f22_device_capability_and_qr_template_round_trip',
      (f) async {
    final profile = DeviceCapabilityProfile.evaluate(
      cpuCores: 8,
      estimatedRamGb: 8,
    );
    final recommended = profile.buildRecommendedTemplate();
    final qrUri = recommended.toQrUri();
    final parsedFromQr = ProviderTemplate.parseQrOrJson(qrUri);
    return profile.recommendedTier == DeviceCapabilityTier.balancedCloud &&
        parsedFromQr.name == recommended.name &&
        parsedFromQr.contextTokens == 64000;
  });
  await check('f12_cost_budget_hard_stop_and_f13_remote_lease_reconcile',
      (f) async {
    const policy = CostBudgetPolicy(
      dailyLimitCents: 2000,
      monthlyLimitCents: 30000,
      hardStopEnabled: true,
    );
    final blocked = CostBudgetService.evaluatePolicy(
      policy: policy,
      dailySpentCents: 1950,
      monthlySpentCents: 5000,
      estimatedNextCallCents: 100,
    );
    final lease = RemotePairingLease(
      pairingId: 'pair-1',
      endpoint: 'http://10.0.2.2:8767',
      arch: 'AMD64',
      protocolVersion: 'nexus-remote/1',
      pairedAtUtc: f.now.subtract(const Duration(hours: 1)),
      leaseExpiresAtUtc: f.now.subtract(const Duration(minutes: 5)),
    );
    const runningJob = RemoteJobStatus(
      runId: 'run-1',
      jobId: 'job-1',
      status: 'running',
    );
    final expiredReconciled =
        lease.reconcileAfterDisconnect(runningJob, now: f.now);
    final renewed = lease.renew(now: f.now);
    final revoked = renewed.revoke();
    final revokedReconciled =
        revoked.reconcileAfterDisconnect(runningJob, now: f.now);
    return !blocked.allowed &&
        blocked.errorCode == 'COST_BUDGET_EXHAUSTED' &&
        expiredReconciled.status == 'lease_expired_needs_reconcile' &&
        renewed.isLeaseActive(now: f.now) &&
        revokedReconciled.status == 'pairing_revoked_halted';
  });
  await check('f03_f17_assistant_entry_hint_and_f09_knowledge_correction',
      (f) async {
    await f.add(label: '李雷', qualifier: '研发部');
    await f.add(label: '李雷', qualifier: '法务部');
    final ambiguousHint =
        await f.service.describeAssistantEntryHint('请把周报发给李雷');
    debugPrint('[context-contract] assistant hint resolved');
    final knowledge = KnowledgeService();
    final doc = await knowledge.ingest(
      db: f.db,
      name: '架构规范',
      sourceType: 'paste',
      content: '旧版网关默认端口为 8080。',
    );
    debugPrint('[context-contract] knowledge ingested');
    await knowledge.correctChunkContent(
      db: f.db,
      chunkId: '${doc.id}:chunk:0',
      newContent: '更正后网关默认端口为 9443。',
    );
    debugPrint('[context-contract] knowledge corrected');
    final injected = await knowledge.buildInjectionBlock(f.db, '网关默认端口');
    debugPrint('[context-contract] knowledge recalled');
    return ambiguousHint != null &&
        ambiguousHint.contains('研发部') &&
        ambiguousHint.contains('法务部') &&
        injected.contains('9443') &&
        !injected.contains('8080');
  });
  await check('reminder_delivery_reschedules_and_cancel_reaches_platform_port',
      (f) async {
    final delivery = _ReminderDeliveryFixture();
    final service = ReminderService(f.db, delivery: delivery);
    final item = await service.create(
        title: '通知边界',
        scheduledAtUtc: f.now.add(const Duration(hours: 1)),
        now: f.now);
    final snoozed = await service.snooze(item.id, now: f.now);
    await service.cancel(item.id, now: f.now);
    return delivery.scheduled.length == 2 &&
        delivery.cancelled.single == item.id &&
        item.exactAlarmCapability == ExactAlarmCapability.degradedInexact &&
        delivery.scheduled.last.effectiveTriggerUtc ==
            snoozed.effectiveTriggerUtc;
  });
  await check('reminder_duplicate_id_cannot_overwrite_existing_schedule',
      (f) async {
    final service = ReminderService(f.db, delivery: null);
    await service.create(id: 'same', title: '保留', scheduledAtUtc: f.now);
    try {
      await service.create(id: 'same', title: '覆盖', scheduledAtUtc: f.now);
      return false;
    } catch (_) {
      return (await service.findById('same'))?.title == '保留';
    }
  });
  await check('workflow_import_cannot_remove_side_effect_confirmation',
      (f) async {
    final service = MobileWorkflowService(f.db, reminderDelivery: null);
    await service.saveDefinition(WorkflowDefinition(
        id: 'unsafe',
        name: '省略确认标志',
        description: '',
        version: 1,
        inputSchema: const ['topic'],
        steps: const [
          WorkflowStepSpec(
              id: 'write', title: '写入', kind: WorkflowStepKind.createReminder),
        ],
        createdAt: f.now,
        updatedAt: f.now));
    final result = await service.runWorkflow(
        workflowId: 'unsafe', inputs: {'topic': '不得创建'}, now: f.now);
    return result.status == 'blocked_confirmation' &&
        (await ReminderService(f.db, delivery: null).list()).isEmpty;
  });
  await check('unknown_workflow_step_is_rejected_instead_of_transformed',
      (f) async {
    try {
      WorkflowStepSpec.fromJson({'id': 'bad', 'kind': 'send_external_money'});
      return false;
    } on FormatException {
      return true;
    }
  });
  await check('research_failed_source_check_preserves_stale_evidence',
      (f) async {
    final service = ResearchArtifactService(f.db);
    final old = f.now.subtract(const Duration(days: 30));
    final item = await service.create(
        topic: '待核查',
        summary: '',
        claims: [
          ResearchClaim(
            id: 'c',
            statement: '待核查结论',
            citations: [
              EvidenceCitation(
                  id: 'e',
                  sourceTitle: '来源',
                  sourceUri: 'https://example.invalid',
                  excerpt: '证据',
                  capturedAt: old,
                  verifiedAt: old)
            ],
          )
        ],
        now: f.now);
    final unchanged = await service.refreshVerification(
        artifactId: item.id, now: f.now, verifyCitation: (_) async => false);
    return unchanged.version == item.version &&
        unchanged.claims.single.evaluateSupport(now: f.now) ==
            EvidenceSupportLevel.stale;
  });
  await check(
      'knowledge_correction_rejects_deleted_chunk_and_keeps_valid_dates',
      (f) async {
    final service = KnowledgeService();
    try {
      await service.correctChunkContent(
          db: f.db, chunkId: 'deleted', newContent: '不得伪造更正');
      return false;
    } on StateError {
      final doc = await service.ingest(
          db: f.db, name: '更正日期', sourceType: 'paste', content: '旧内容');
      await service.correctChunkContent(
          db: f.db, chunkId: '${doc.id}:chunk:0', newContent: '更正内容');
      return (await f.db.findKnowledgeDoc(doc.id))!.updatedAt.year ==
          DateTime.now().year;
    }
  });
  await check(
      'cost_ledger_counts_full_month_and_serializes_concurrent_reservations',
      (f) async {
    final ledger = CostBudgetLedger(f.db);
    const limits = CostBudgetPolicy(
        dailyLimitCents: 1000, monthlyLimitCents: 1200, hardStopEnabled: true);
    final old = await ledger.reserve(limits, 400, now: DateTime(2026, 10, 1));
    final races = await Future.wait([
      ledger.reserve(limits, 600, now: DateTime(2026, 10, 19)),
      ledger.reserve(limits, 600, now: DateTime(2026, 10, 19)),
    ]);
    final snapshot = await ledger.snapshot(limits, now: DateTime(2026, 10, 19));
    return old.id != null &&
        races.where((r) => r.id != null).length == 1 &&
        snapshot.monthlySpentCents == 1000 &&
        snapshot.dailySpentCents == 600;
  });
  await check(
      'cost_provider_blocks_before_dispatch_and_keeps_missing_usage_reservation',
      (f) async {
    const limits = CostBudgetPolicy(
        dailyLimitCents: 1000, monthlyLimitCents: 1000, hardStopEnabled: true);
    final delegate = _BudgetProviderFixture();
    final provider = CostBudgetProvider(
        delegate,
        const ProviderConfig(
            baseUrl: 'https://example.invalid',
            model: 'fixture',
            apiKey: 'fixture',
            inputPricePerMillionCents: 1000000,
            outputPricePerMillionCents: 1000000),
        database: () async => f.db,
        policy: () async => limits,
        now: () => f.now);
    const request =
        UnifiedRequest(model: 'fixture', messages: [], maxTokens: 400);
    await provider.stream(request).toList();
    final events = await provider.stream(request).toList();
    return delegate.calls == 1 &&
        events.whereType<ProviderErrorEvent>().single.failureKind ==
            CostBudgetProvider.exhausted;
  });
  await check(
      'cost_provider_settles_reported_usage_and_unknown_prices_do_not_dispatch',
      (f) async {
    const limits = CostBudgetPolicy(
        dailyLimitCents: 1000, monthlyLimitCents: 1000, hardStopEnabled: true);
    final delegate = _BudgetProviderFixture(reportUsage: true);
    const config = ProviderConfig(
        baseUrl: 'https://example.invalid',
        model: 'fixture',
        apiKey: 'fixture',
        inputPricePerMillionCents: 1000000,
        outputPricePerMillionCents: 1000000);
    final provider = CostBudgetProvider(delegate, config,
        database: () async => f.db,
        policy: () async => limits,
        now: () => f.now);
    await provider
        .stream(
            const UnifiedRequest(model: 'fixture', messages: [], maxTokens: 20))
        .toList();
    final snapshot = await CostBudgetLedger(f.db).snapshot(limits, now: f.now);
    final unpriced = CostBudgetProvider(
        delegate,
        const ProviderConfig(
            baseUrl: 'https://example.invalid',
            model: 'unknown',
            apiKey: 'fixture'),
        database: () async => f.db,
        policy: () async => limits);
    final events = await unpriced
        .stream(const UnifiedRequest(model: 'unknown', messages: []))
        .toList();
    return snapshot.dailySpentCents == 5 &&
        delegate.calls == 1 &&
        events.whereType<ProviderErrorEvent>().single.failureKind ==
            CostBudgetProvider.pricingUnavailable &&
        !ModelFailure.classify('', failureKind: CostBudgetProvider.exhausted)
            .retryable;
  });
  await check(
      'mobile_module_vault_round_trip_pauses_reminders_and_preserves_workflows',
      (f) async {
    final reminders = ReminderService(f.db, delivery: null);
    await reminders.create(
        id: 'backup-rem', title: '备份提醒', scheduledAtUtc: f.now);
    final workflows = MobileWorkflowService(f.db, reminderDelivery: null);
    await workflows.runWorkflow(
        workflowId: 'wf-daily-brief', inputs: {'topic': '归档'}, dryRun: true);
    await ResearchArtifactService(f.db)
        .create(id: 'backup-research', topic: '备份研究', summary: '摘要');
    final backup = await buildVaultJson(f.db);
    final report = await restoreVault(f.db, backup);
    return (await reminders.findById('backup-rem'))?.status ==
            ReminderStatus.paused &&
        (await workflows.listRuns()).length == 1 &&
        (await ResearchArtifactService(f.db).findById('backup-research'))
                ?.topic ==
            '备份研究' &&
        report.warnings.any((w) => w.contains('提醒已暂停'));
  });
  await check('data_clear_removes_all_new_mobile_module_private_rows',
      (f) async {
    await ReminderService(f.db, delivery: null)
        .create(title: '私密事项', scheduledAtUtc: f.now);
    await MobileWorkflowService(f.db, reminderDelivery: null).listDefinitions();
    await ResearchArtifactService(f.db).create(topic: '私密研究', summary: '私密摘要');
    await CostBudgetLedger(f.db).reserve(
        const CostBudgetPolicy(
            dailyLimitCents: 100,
            monthlyLimitCents: 100,
            hardStopEnabled: true),
        10);
    await f.db.clearAllUserData();
    for (final table in [
      'nexus_reminders',
      'nexus_mobile_workflows',
      'nexus_mobile_workflow_runs',
      'nexus_research_artifacts',
      'nexus_cost_reservations'
    ]) {
      if ((await f.db
                  .customSelect('SELECT COUNT(*) AS c FROM $table')
                  .getSingle())
              .read<int>('c') !=
          0) {
        return false;
      }
    }
    return true;
  });
  cases.addAll(await runPersonalContextChecks());
  return {
    'type': 'PersonalContextSqlContractChecks',
    'fixtureOnly': true,
    'storage': 'owned_temporary_sqlite_file',
    'modelCalls': 0,
    'platformMutations': 0,
    'persistentDataMutations': 0,
    'cases': cases,
    'total': cases.length,
    'passed': cases.where((c) => c['passed'] == true).length
  };
}

const _tables = [
  personalContextAliasesTable,
  personalContextRelationsTable,
  personalContextRevisionsTable,
  personalContextTombstonesTable,
  personalContextEntitiesTable
];

class _ReminderDeliveryFixture implements ReminderDelivery {
  final scheduled = <ReminderItem>[];
  final cancelled = <String>[];
  @override
  Future<ExactAlarmCapability> schedule(ReminderItem reminder) async {
    scheduled.add(reminder);
    return ExactAlarmCapability.degradedInexact;
  }

  @override
  Future<void> cancel(String id) async {
    cancelled.add(id);
  }
}

class _BudgetProviderFixture implements LlmProvider {
  _BudgetProviderFixture({this.reportUsage = false});
  final bool reportUsage;
  int calls = 0;
  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    calls++;
    if (reportUsage) {
      yield const UsageEvent(promptTokens: 2, completionTokens: 3);
    }
    yield const CompletedEvent();
  }
}

class _Fixture {
  Directory? _base;
  AppDatabase? _db;
  AppDatabase get db => _db!;
  File get databaseFile => File(p.join(_base!.path, 'context.sqlite'));
  late SqlitePersonalContextStore store;
  late PersonalContextService service;
  final now = DateTime.utc(2026, 10, 19, 12);
  Future<void> init() async {
    _base =
        await Directory.systemTemp.createTemp('nexus-personal-context-sql-');
    _openDatabase();
    await store.ensureReady();
  }

  void _openDatabase() {
    _db = AppDatabase(NativeDatabase(databaseFile));
    store = SqlitePersonalContextStore(db);
    service = PersonalContextService(store, now: () => now);
  }

  Future<PersonalContextEntity> add(
          {String label = '验收联系人',
          String? qualifier,
          String? project,
          String origin = ''}) =>
      service.add(
          label: label,
          kind: PersonalContextEntityKind.person,
          qualifier: qualifier,
          projectId: project,
          originRef: origin);
  Future<void> reopen() async {
    await db.close();
    _openDatabase();
    await store.ensureReady();
  }

  Future<void> close() async {
    await _db?.close();
    if (_base != null && await _base!.exists()) {
      await _base!.delete(recursive: true);
    }
  }
}

_Fixture? _uiFixture;
Route<void>? _uiRoute;
NavigatorState? _uiNavigator;
Future<void> _open() async {
  if (_uiRoute != null) throw StateError('Close owned fixture first');
  NavigatorState? navigator;
  void visit(Element element) {
    if (navigator != null) return;
    if (element is StatefulElement && element.state is NavigatorState) {
      navigator = element.state as NavigatorState;
    } else {
      element.visitChildElements(visit);
    }
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  if (navigator == null) throw StateError('No app navigator');
  final f = _Fixture();
  try {
    await f.init();
    final old = await f.add(label: 'U04Fixture', qualifier: 'Old');
    await f.service.addAlias(old.id, 'U04Alias');
    final next = await f.service.correct(old.id, label: 'U04Renamed');
    await f.service.forget(next.id);
    final route = MaterialPageRoute<void>(
        builder: (_) => ProviderScope(
            overrides: [databaseProvider.overrideWith((ref) async => f.db)],
            child: Scaffold(
                appBar: AppBar(title: const Text('隔离验收 · 个人上下文')),
                body: const PersonalContextPage())));
    _uiFixture = f;
    _uiRoute = route;
    _uiNavigator = navigator;
    unawaited(navigator!.push(route).whenComplete(() async {
      if (identical(_uiRoute, route)) {
        _uiRoute = null;
        _uiNavigator = null;
        _uiFixture = null;
      }
      await f.close();
    }));
  } catch (_) {
    await f.close();
    rethrow;
  }
}
