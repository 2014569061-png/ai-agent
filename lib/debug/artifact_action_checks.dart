import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import '../application/artifact_result_actions.dart';
import '../application/artifact_service.dart';
import '../application/development_verification.dart';
import '../application/non_file_result_actions.dart';
import '../application/mobile_workflow_service.dart';
import '../application/result_action_service.dart';
import '../domain/result_card.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/database/result_action_store.dart';
import '../infrastructure/database/result_action_approval_store.dart';
import '../domain/approval_action_codec.dart';
import 'result_card_checks.dart';

/// Runs SQLite + private-copy integration on the emulator in an owned scratch
/// directory. OS preview/share boundaries are counters here, not delivery proof.
Future<Map<String, dynamic>> runArtifactActionChecks() async {
  final cases = <Map<String, dynamic>>[];
  Future<void> check(String name, Future<bool> Function(_Fixture) run) async {
    final f = _Fixture();
    try {
      await f.init();
      cases.add({'name': name, 'passed': await run(f)});
    } catch (error) {
      cases.add(
          {'name': name, 'passed': false, 'error': '${error.runtimeType}'});
    } finally {
      await f.close();
    }
  }

  await check('record_atomically_publishes_real_file_card', (f) async {
    final card = await f.repository.findCard('artifact-${f.artifact.id}');
    return card?.resourceId == f.artifact.id &&
        card?.taskId == 'isolated-action-task' &&
        card?.resourceVersion == 1 &&
        await f.file.readAsString() == 'ARTIFACT_ACTION_SOURCE';
  });
  await check('preview_uses_verified_copy_not_snapshot_path', (f) async {
    await f.repository.saveCard(f.card.copyWith(snapshot: const {
      'path': '/outside/never-open',
      'command': 'never-execute'
    }));
    final prepared = await f.prepare('file.preview');
    final run = await f.actions.execute(prepared.action!.id);
    return run.succeeded && f.previews == 1 && f.shares == 0;
  });
  await check('share_requires_confirmation_before_os_boundary', (f) async {
    final prepared = await f.prepare('file.share');
    final run = await f.actions.execute(prepared.action!.id);
    return prepared.pendingConfirmation &&
        run.pendingConfirmation &&
        f.shares == 0;
  });
  await check('confirmed_share_no_longer_blocks_ui_execution', (f) async {
    final prepared = await f.prepare('file.share');
    final confirmed = await f.confirm(prepared);
    if (confirmed.pendingConfirmation || confirmed.hasError) return false;
    final run = await f.actions.execute(prepared.action!.id);
    return run.succeeded &&
        f.shares == 1 &&
        run.feedback.contains('不代表接收方') &&
        run.action?.result['delivery'] == 'system_handoff_only';
  });
  await check('share_dismissal_is_not_delivery_success', (f) async {
    f.outcome = ArtifactShareOutcome.dismissed;
    final prepared = await f.prepare('file.share');
    await f.confirm(prepared);
    final run = await f.actions.execute(prepared.action!.id);
    return !run.succeeded && run.feedback.contains('已取消') && f.shares == 1;
  });
  await check('unknown_share_outcome_is_not_delivery_success', (f) async {
    f.outcome = ArtifactShareOutcome.unavailable;
    final prepared = await f.prepare('file.share');
    await f.confirm(prepared);
    final run = await f.actions.execute(prepared.action!.id);
    return !run.succeeded && run.feedback.contains('状态未知') && f.shares == 1;
  });
  await check('preview_rejection_does_not_mark_success', (f) async {
    f.previewAccepted = false;
    final prepared = await f.prepare('file.preview');
    return !(await f.actions.execute(prepared.action!.id)).succeeded &&
        f.previews == 1;
  });
  await check('tampered_payload_after_prepare_is_conflict', (f) async {
    final prepared = await f.prepare('file.preview');
    await f.file.writeAsString('TAMPERED');
    final run = await f.actions.execute(prepared.action!.id);
    return run.error == ResultActionErrorCode.conflict && f.previews == 0;
  });
  await check('deleted_payload_after_confirm_blocks_share', (f) async {
    final prepared = await f.prepare('file.share');
    await f.confirm(prepared);
    await f.file.delete();
    final run = await f.actions.execute(prepared.action!.id);
    return run.error == ResultActionErrorCode.stale && f.shares == 0;
  });
  await check('unverified_hash_is_unavailable', (f) async {
    await f.db.saveArtifactRecord({...f.artifact.toJson(), 'hash': ''});
    final run = await f.prepare('file.preview');
    return run.error == ResultActionErrorCode.stale && f.previews == 0;
  });
  await check('read_only_at_dispatch_blocks_platform_operation', (f) async {
    final prepared = await f.prepare('file.preview');
    f.interactive = false;
    final run = await f.actions.execute(prepared.action!.id);
    return !run.succeeded && f.previews == 0;
  });
  await check('parallel_execute_shares_one_os_handoff', (f) async {
    final prepared = await f.prepare('file.share');
    await f.confirm(prepared);
    final runs = await Future.wait(
        List.generate(3, (_) => f.actions.execute(prepared.action!.id)));
    return runs.every((r) => r.succeeded) && f.shares == 1;
  });
  await check('sqlite_reopen_does_not_replay_completed_handoff', (f) async {
    final prepared = await f.prepare('file.share');
    await f.confirm(prepared);
    if (!(await f.actions.execute(prepared.action!.id)).succeeded) return false;
    await f.db.close();
    f.openDatabase();
    final saved = await f.repository.findAction(prepared.action!.id);
    final run = await f.actions.execute(prepared.action!.id);
    return saved?.status == ResultActionStatus.succeeded &&
        run.succeeded &&
        !run.executed &&
        f.shares == 1;
  });
  await check('unwired_action_cannot_reach_file_adapter', (f) async {
    final run = await f.executor.execute(ResultActionExecutionRequest(
        idempotencyKey: 'synthetic-forged',
        executorKey: 'route.open',
        actionType: 'route.open',
        card: f.card));
    return !run.ok && f.previews == 0 && f.shares == 0;
  });
  await check('platform_exception_persists_failed_not_success', (f) async {
    f.throwShare = true;
    final prepared = await f.prepare('file.share');
    await f.confirm(prepared);
    final run = await f.actions.execute(prepared.action!.id);
    return run.status == ResultActionStatus.failed &&
        f.shares == 1 &&
        (await f.repository.findAction(prepared.action!.id))?.status ==
            ResultActionStatus.failed;
  });
  await check('card_publish_failure_rolls_back_artifact_and_private_copy',
      (f) async {
    final before = (await f.artifacts.list(f.db)).length;
    final folders =
        await Directory(p.join(f.base.path, 'payloads')).list().length;
    await f.db.customStatement('DROP TABLE result_cards');
    try {
      await f.record();
      return false;
    } catch (_) {
      return (await f.artifacts.list(f.db)).length == before &&
          await Directory(p.join(f.base.path, 'payloads')).list().length ==
              folders;
    }
  });
  await check('data_clear_removes_cards_and_delivery_history', (f) async {
    final prepared = await f.prepare('file.share');
    await f.confirm(prepared);
    await f.actions.execute(prepared.action!.id);
    await f.db.clearAllUserData();
    return (await f.repository.listCards()).isEmpty &&
        await f.repository.findAction(prepared.action!.id) == null &&
        (await f.artifacts.list(f.db)).isEmpty;
  });
  await check(
      'composite_executor_dispatches_route_open_and_rejects_control_chars',
      (f) async {
    final routedQueries = <String>[];
    final composite = ResultActionService(
      repository: f.repository,
      resources: CompositeResultResourceReader(
        db: f.db,
        repository: f.repository,
        artifactReader: ArtifactResultResourceReader(
          lookup: f.lookup,
          artifacts: f.artifacts,
        ),
      ),
      permissions: _Permissions(),
      executor: CompositeResultActionExecutor(
        db: f.db,
        repository: f.repository,
        artifactExecutor: f.executor,
        canInteract: () => f.interactive,
        openRoute: (query, _) async {
          routedQueries.add(query);
          return true;
        },
      ),
    );
    final routeCard = ResultCard(
      id: 'route-card-1',
      kind: ResultCardKind.route,
      resourceType: 'route',
      resourceId: 'route-1',
      resourceVersion: 1,
      title: '上海虹桥站路线',
      summary: '地铁路线导航',
      snapshot: const {'query': '上海虹桥火车站'},
      createdAt: DateTime.utc(2026, 10, 19),
      updatedAt: DateTime.utc(2026, 10, 19),
    );
    await f.repository.saveCard(routeCard);
    final prepared = await composite.prepare(routeCard, 'route.open');
    if (prepared.action == null) return false;
    final run = await composite.execute(prepared.action!.id);
    final badCard = ResultCard(
      id: 'route-card-bad',
      kind: ResultCardKind.route,
      resourceType: 'route',
      resourceId: 'route-bad',
      resourceVersion: 1,
      title: 'bad\nquery',
      summary: 'bad\nquery',
      snapshot: const {'query': 'bad\nquery'},
      createdAt: DateTime.utc(2026, 10, 19),
      updatedAt: DateTime.utc(2026, 10, 19),
    );
    await f.repository.saveCard(badCard);
    final badPrepared = await composite.prepare(badCard, 'route.open');
    return run.succeeded &&
        routedQueries.length == 1 &&
        routedQueries.single == '上海虹桥火车站' &&
        run.action?.result['delivery'] == 'system_map_handoff_only' &&
        badPrepared.error == ResultActionErrorCode.stale;
  });
  await check('composite_executor_handles_non_file_actions_with_confirmation',
      (f) async {
    var diffReviewed = 0;
    var calendarAdjusted = 0;
    var workflowTrialRan = 0;
    final composite = ResultActionService(
      repository: f.repository,
      resources: CompositeResultResourceReader(
        db: f.db,
        repository: f.repository,
        artifactReader: ArtifactResultResourceReader(
          lookup: f.lookup,
          artifacts: f.artifacts,
        ),
      ),
      permissions: _Permissions(),
      executor: CompositeResultActionExecutor(
        db: f.db,
        repository: f.repository,
        artifactExecutor: f.executor,
        canInteract: () => f.interactive,
        openRoute: (_, __) async => true,
        reviewDiff: (_, __, ___) async {
          diffReviewed++;
          return true;
        },
        adjustCalendar: (_, __) async {
          calendarAdjusted++;
          return true;
        },
        trialRunWorkflow: (_) async {
          workflowTrialRan++;
          return true;
        },
      ),
    );
    final diffCard = ResultCard(
      id: 'diff-card-1',
      kind: ResultCardKind.codeDiff,
      resourceType: 'change_set',
      resourceId: 'diff-1',
      resourceVersion: 1,
      title: '代码差异',
      summary: '查看修改',
      snapshot: const {
        'files': ['lib/main.dart']
      },
      createdAt: DateTime.utc(2026, 10, 19),
      updatedAt: DateTime.utc(2026, 10, 19),
    );
    await f.repository.saveCard(diffCard);
    final diffPrep = await composite.prepare(diffCard, 'diff.review');
    final diffRun = await composite.execute(diffPrep.action!.id);

    final calCard = ResultCard(
      id: 'cal-card-1',
      kind: ResultCardKind.calendar,
      resourceType: 'calendar_event',
      resourceId: 'cal-1',
      resourceVersion: 1,
      title: '项目评审会',
      summary: '下午三点',
      snapshot: const {
        'title': '项目评审会',
        'startEpochMs': 1792425600000,
        'endEpochMs': 1792429200000,
      },
      createdAt: DateTime.utc(2026, 10, 19),
      updatedAt: DateTime.utc(2026, 10, 19),
    );
    await f.repository.saveCard(calCard);
    final calPrep = await composite.prepare(calCard, 'calendar.adjust');
    final calTicket =
        (await ResultActionApprovalStore(f.db).open(calPrep.action!.id))!;
    await f.db
        .decidePendingApproval(calTicket.requestId, approvalApproveAction);
    await composite.confirm(
      calPrep.action!.id,
      ResultActionApproval(
        approvalId: calTicket.requestId,
        cardId: calCard.id,
        actionType: 'calendar.adjust',
        grantedAt: DateTime.now().toUtc(),
        expiresAt: calTicket.expiresAt,
      ),
    );
    final calRun = await composite.execute(calPrep.action!.id);

    final workflow =
        (await MobileWorkflowService(f.db).listDefinitions()).first;
    final wfCard = ResultCard(
      id: 'wf-card-1',
      kind: ResultCardKind.workflowTrial,
      resourceType: 'workflow',
      resourceId: workflow.id,
      resourceVersion: workflow.version,
      title: '构建检查工作流',
      summary: '沙箱试运行',
      createdAt: DateTime.utc(2026, 10, 19),
      updatedAt: DateTime.utc(2026, 10, 19),
    );
    await f.repository.saveCard(wfCard);
    final wfPrep = await composite.prepare(wfCard, 'workflow.trial_run');
    final wfTicket =
        (await ResultActionApprovalStore(f.db).open(wfPrep.action!.id))!;
    await f.db.decidePendingApproval(wfTicket.requestId, approvalApproveAction);
    await composite.confirm(
      wfPrep.action!.id,
      ResultActionApproval(
        approvalId: wfTicket.requestId,
        cardId: wfCard.id,
        actionType: 'workflow.trial_run',
        grantedAt: DateTime.now().toUtc(),
        expiresAt: wfTicket.expiresAt,
      ),
    );
    final wfRun = await composite.execute(wfPrep.action!.id);

    return diffRun.succeeded &&
        diffReviewed == 1 &&
        calRun.succeeded &&
        calendarAdjusted == 1 &&
        wfRun.succeeded &&
        workflowTrialRan == 1;
  });
  cases.addAll(await runResultCardChecks());
  return {
    'type': 'ArtifactActionContractChecks',
    'fixtureOnly': true,
    'storage': 'owned_temporary_sqlite_file',
    'platformBoundaries': 'counted_callbacks_not_real_intents',
    'modelCalls': 0,
    'platformMutations': 0,
    'persistentDataMutations': 0,
    'cases': cases,
    'total': cases.length,
    'passed': cases.where((c) => c['passed'] == true).length,
  };
}

class _Fixture {
  late Directory base;
  AppDatabase? _database;
  AppDatabase get db => _database!;
  SqlResultActionRepository get repository => SqlResultActionRepository(db);
  late ArtifactService artifacts;
  late ProjectArtifact artifact;
  late ResultCard card;
  late File file;
  late ArtifactResultActionExecutor executor;
  late ResultActionService actions;
  int previews = 0, shares = 0;
  bool interactive = true, previewAccepted = true, throwShare = false;
  ArtifactShareOutcome outcome = ArtifactShareOutcome.handedOff;

  Future<void> init() async {
    base = await Directory.systemTemp.createTemp('nexus-artifact-actions-');
    final workspace = await Directory(p.join(base.path, 'workspace')).create();
    await File(p.join(workspace.path, 'sample.txt'))
        .writeAsString('ARTIFACT_ACTION_SOURCE');
    artifacts = ArtifactService(
        rootDirectory: () async => Directory(p.join(base.path, 'payloads')));
    openDatabase();
    artifact = await record();
    file = await artifacts.verifiedPayload(artifact);
    card = (await repository.findCard('artifact-${artifact.id}'))!;
  }

  void openDatabase() {
    _database =
        AppDatabase(NativeDatabase(File(p.join(base.path, 'checks.sqlite'))));
    executor = ArtifactResultActionExecutor(
      lookup: lookup,
      artifacts: artifacts,
      canInteract: () => interactive,
      openPreview: (a) async {
        previews++;
        return previewAccepted && a.id == artifact.id;
      },
      shareFile: (f) async {
        shares++;
        if (throwShare) throw StateError('Synthetic unavailable share plugin');
        if (await f.readAsString() != 'ARTIFACT_ACTION_SOURCE') {
          throw StateError('Wrong file passed to OS boundary');
        }
        return outcome;
      },
    );
    actions = ResultActionService(
        repository: repository,
        resources:
            ArtifactResultResourceReader(lookup: lookup, artifacts: artifacts),
        permissions: _Permissions(),
        executor: executor);
  }

  Future<ProjectArtifact> record() => artifacts.record(
      db: db,
      taskId: 'isolated-action-task',
      runId: 'isolated-action-run',
      workspacePath: p.join(base.path, 'workspace'),
      inspection:
          const ArtifactInspection(relativePath: 'sample.txt', exists: true));

  Future<ProjectArtifact?> lookup(String id) async {
    final rows = await artifacts.list(db);
    return rows.where((a) => a.id == id).firstOrNull;
  }

  Future<ResultActionRun> prepare(String type) async =>
      actions.prepare((await repository.findCard(card.id))!, type);

  Future<ResultActionRun> confirm(ResultActionRun run) async {
    final now = DateTime.now().toUtc();
    final ticket = (await ResultActionApprovalStore(db).open(run.action!.id))!;
    await db.decidePendingApproval(ticket.requestId, approvalApproveAction);
    return actions.confirm(
        run.action!.id,
        ResultActionApproval(
            approvalId: ticket.requestId,
            cardId: card.id,
            actionType: run.action!.actionType,
            grantedAt: now,
            expiresAt: ticket.expiresAt));
  }

  Future<void> close() async {
    await _database?.close();
    if (await base.exists()) await base.delete(recursive: true);
  }
}

class _Permissions implements ResultPermissionChecker {
  @override
  Future<bool> canPerform(ResultActionSpec spec, ResultCard card) async => true;
}
