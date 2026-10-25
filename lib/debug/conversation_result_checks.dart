import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../application/artifact_service.dart';
import '../application/chat_controller.dart' show ToolActivity;
import '../application/development_verification.dart';
import '../application/providers.dart';
import '../application/result_action_approval_scope.dart';
import '../application/result_action_service.dart';
import '../domain/models.dart' as model;
import '../domain/result_card.dart';
import '../domain/tool_result.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/database/conversation_result_store.dart';
import '../infrastructure/database/result_action_store.dart';
import '../presentation/chat/widgets/chat_empty_state.dart';
import '../presentation/chat/widgets/chat_message_list.dart';
import '../presentation/chat/widgets/conversation_result_timeline.dart';
import '../presentation/chat/widgets/plan_panel.dart';
import '../presentation/chat/widgets/tool_activity_section.dart';
import '../presentation/chat/widgets/result_card_view.dart';
import 'page_coverage_checks.dart';

bool _registered = false;
void registerConversationResultChecks() {
  if (!kDebugMode || _registered) return;
  _registered = true;
  registerPageCoverageChecks();
  registerExtension(
      'ext.nexus.conversationResultsContract',
      (m, args) async =>
          ServiceExtensionResponse.result(jsonEncode(await _checks())));
  registerExtension(
      'ext.nexus.conversationResultsFixture',
      (m, args) async => ServiceExtensionResponse.result(
          jsonEncode(await _ui(args['mode'] ?? 'inspect'))));
}

Future<Map<String, dynamic>> _checks() async {
  final cases = <Map<String, dynamic>>[];
  Future<void> check(String name, Future<bool> Function(_Fixture) body) async {
    final f = _Fixture();
    try {
      await f.init();
      cases.add({'name': name, 'passed': await body(f)});
    } catch (e) {
      cases.add({'name': name, 'passed': false, 'error': '${e.runtimeType}'});
    } finally {
      await f.close();
    }
  }

  await check(
      'conversation_membership_not_global_recent_results',
      (f) async =>
          (await f.repo().page())
              .items
              .map((c) => c.id)
              .toSet()
              .containsAll({'a1', 'a2'}) &&
          (await f.repo().page()).items.length == 2);
  await check(
      'project_scope_matches_both_task_and_conversation',
      (f) async =>
          (await f.repo(conversation: 'p', project: 'project-p').page())
              .items
              .single
              .id ==
          'p1');
  await check('missing_project_does_not_mean_all_projects',
      (f) async => (await f.repo(conversation: 'p').page()).items.isEmpty);
  await check('wrong_project_cannot_read_same_conversation',
      (f) async => await f.repo(project: 'project-p').findCard('a1') == null);
  await check('blank_conversation_is_not_wildcard',
      (f) async => (await f.repo(conversation: '').page()).items.isEmpty);
  await check('task_scope_excludes_other_tasks_in_same_chat',
      (f) async => (await f.repo(task: 'ta1').page()).items.single.id == 'a1');
  await check('run_scope_excludes_other_runs_of_same_task', (f) async {
    await f.save('a3', task: 'ta1', run: 'new-run');
    return (await f.repo(task: 'ta1', run: 'run-a1').page()).items.single.id ==
        'a1';
  });
  await check(
      'blank_task_or_run_is_not_wildcard',
      (f) async =>
          (await f.repo(task: '').page()).items.isEmpty &&
          (await f.repo(run: '').page()).items.isEmpty);
  await check('task_project_mismatch_hides_result', (f) async {
    await f.db.customStatement(
        "UPDATE tasks SET project_id='project-p' WHERE id='ta1'");
    return await f.repo().findCard('a1') == null;
  });
  await check('conversation_project_change_revokes_old_scope', (f) async {
    await f.db.customStatement(
        "UPDATE conversations SET project_id='project-p' WHERE id='a'");
    return (await f.repo().page()).items.isEmpty;
  });
  await check('deleted_task_revokes_result_membership', (f) async {
    await f.db.customStatement("DELETE FROM tasks WHERE id='ta1'");
    return await f.repo().findCard('a1') == null;
  });
  await check('deleted_conversation_revokes_membership', (f) async {
    await f.db.customStatement("DELETE FROM conversations WHERE id='a'");
    return (await f.repo().page()).items.isEmpty;
  });
  await check('paging_tied_creation_times_never_skips_or_duplicates',
      (f) async {
    for (var i = 0; i < 23; i++) {
      await f.save('page-${i.toString().padLeft(2, '0')}');
    }
    final ids = <String>[];
    ConversationResultCursor? cursor;
    do {
      final page = await f.repo().page(after: cursor, limit: 3);
      ids.addAll(page.items.map((c) => c.id));
      cursor = page.next;
    } while (cursor != null);
    return ids.length == 25 &&
        ids.toSet().length == 25 &&
        ids.contains('page-00');
  });
  await check('null_legacy_created_at_is_pageable', (f) async {
    await f.db.customStatement(
        "UPDATE result_cards SET created_at=NULL WHERE id='a1'");
    final first = await f.repo().page(limit: 1);
    final next = await f.repo().page(after: first.next, limit: 1);
    return first.items.single.id == 'a2' &&
        next.items.single.id == 'a1' &&
        next.next == null;
  });
  for (final changed in ['conversation', 'project', 'task', 'run', 'kind']) {
    await check('cursor_rejected_after_${changed}_change', (f) async {
      final cursor = (await f.repo().page(limit: 1)).next;
      try {
        await f
            .repo(
                conversation: changed == 'conversation' ? 'b' : 'a',
                project: changed == 'project' ? 'project-p' : null,
                task: changed == 'task' ? 'ta1' : null,
                run: changed == 'run' ? 'run-a1' : null)
            .page(
                after: cursor,
                kind: changed == 'kind' ? ResultCardKind.file : null);
        return false;
      } on ArgumentError {
        return true;
      }
    });
  }
  await check('page_limit_is_bounded', (f) async {
    var rejected = 0;
    for (final limit in [0, -1, 51]) {
      try {
        await f.repo().page(limit: limit);
      } on ArgumentError {
        rejected++;
      }
    }
    return rejected == 3;
  });
  await check('updates_do_not_move_creation_cursor', (f) async {
    final first = await f.repo().page(limit: 1);
    await f.base.saveCard(
        (await f.base.findCard('a1'))!.copyWith(updatedAt: DateTime.utc(2030)));
    return (await f.repo().page(after: first.next, limit: 1)).items.single.id ==
        'a1';
  });
  for (final mismatch in ['task', 'run', 'project']) {
    await check('artifact_${mismatch}_binding_is_checked', (f) async {
      await f.artifactCard(
          task: mismatch == 'task' ? 'tb' : 'ta1',
          run: mismatch == 'run' ? 'foreign-run' : 'artifact-run',
          project: mismatch == 'project' ? 'project-p' : '');
      return await f.repo().findCard('artifact-card') == null;
    });
  }
  await check('artifact_matching_task_run_project_is_visible', (f) async {
    await f.artifactCard();
    return (await f.repo().findCard('artifact-card'))?.resourceId ==
        'artifact-file';
  });
  await check('scoped_sql_defaults_to_durable_approval_verifier', (f) async {
    final service = f.service();
    final action =
        (await service.prepare((await f.base.findCard('a1'))!, 'file.share'))
            .action!;
    final now = DateTime.now().toUtc();
    final result = await service.confirm(
        action.id,
        ResultActionApproval(
            approvalId: 'page-forged',
            cardId: 'a1',
            actionType: 'file.share',
            grantedAt: now,
            expiresAt: now.add(const Duration(minutes: 1))));
    return result.hasError && f.calls == 0;
  });
  await check('foreign_card_cannot_be_prepared_or_actions_queried', (f) async {
    final foreign = (await f.base.findCard('b1'))!;
    final result = await f.service().prepare(foreign, 'file.preview');
    return result.hasError &&
        (await f.repo().listActions('b1')).isEmpty &&
        f.calls == 0;
  });
  await check('prepared_action_loses_access_after_reparent', (f) async {
    final service = f.service();
    final action =
        (await service.prepare((await f.base.findCard('a1'))!, 'file.preview'))
            .action!;
    await f.db
        .customStatement("UPDATE tasks SET conversation_id='b' WHERE id='ta1'");
    return !(await service.execute(action.id)).succeeded && f.calls == 0;
  });
  await check('approved_action_loses_access_after_task_delete', (f) async {
    final service = f.service();
    final action =
        (await service.prepare((await f.base.findCard('a1'))!, 'file.share'))
            .action!;
    final scope = (await ResultActionApprovalScope.open(f.db, action.id))!;
    f.scopes.add(scope);
    await scope.invoke(() async => model.ToolApproval.allowOnce);
    await service.confirm(action.id, scope.approval);
    await f.db.customStatement("DELETE FROM tasks WHERE id='ta1'");
    return !(await service.execute(action.id)).succeeded && f.calls == 0;
  });
  await check('membership_rechecked_at_final_dispatch_boundary', (f) async {
    final service = f.service();
    final action =
        (await service.prepare((await f.base.findCard('a1'))!, 'file.preview'))
            .action!;
    f.beforeDispatch = () => f.db
        .customStatement("UPDATE tasks SET conversation_id='b' WHERE id='ta1'");
    return !(await service.execute(action.id)).succeeded && f.calls == 0;
  });
  await check('source_page_switch_rejects_final_dispatch', (f) async {
    final service = f.service();
    final action =
        (await service.prepare((await f.base.findCard('a1'))!, 'file.preview'))
            .action!;
    return !(await service.execute(action.id, canContinue: () => false))
            .succeeded &&
        f.calls == 0;
  });
  await check('scoped_repositories_share_same_sql_cas', (f) async {
    final first = f.service(), second = f.service();
    final action =
        (await first.prepare((await f.base.findCard('a1'))!, 'file.preview'))
            .action!;
    await Future.wait([first.execute(action.id), second.execute(action.id)]);
    return f.calls == 1;
  });
  await check('foreign_card_write_is_rejected', (f) async {
    try {
      final card = (await f.base.findCard('b1'))!;
      await f.repo().saveCard(
          ResultCard.fromJson({...card.toJson(), 'title': 'changed'}));
      return false;
    } on StateError {
      return (await f.base.findCard('b1'))!.title == 'b1';
    }
  });
  await check('foreign_action_reads_are_filtered', (f) async {
    final service = f.service(conversation: 'b');
    final action =
        (await service.prepare((await f.base.findCard('b1'))!, 'file.preview'))
            .action!;
    return await f.repo().findAction(action.id) == null &&
        await f.repo().findActionByIdempotencyKey(action.idempotencyKey) ==
            null;
  });
  await check('card_scope_cannot_be_changed_by_refresh_write', (f) async {
    final original = (await f.base.findCard('a1'))!;
    final altered = ResultCard.fromJson({...original.toJson(), 'taskId': 'tb'});
    try {
      await f.repo().saveCard(altered);
      return false;
    } on StateError {
      return (await f.base.findCard('a1'))!.taskId == 'ta1';
    }
  });
  await check('scope_change_during_claim_is_not_written', (f) async {
    final action = (await f
            .service()
            .prepare((await f.base.findCard('a1'))!, 'file.preview'))
        .action!;
    await f.db.customStatement("DELETE FROM conversations WHERE id='a'");
    final changed = await f.repo().compareAndSaveAction(
        action.copyWith(revision: action.revision + 1),
        expectedRevision: action.revision);
    return !changed &&
        (await f.base.findAction(action.id))!.revision == action.revision;
  });
  await check('missing_action_error_is_visible_failed_feedback_not_idle',
      (f) async {
    final feedback = ResultCardActionFeedback.fromRun(const ResultActionRun(
        error: ResultActionErrorCode.unauthorized,
        feedback: 'No scoped action'));
    return feedback.phase == ResultCardFeedbackPhase.failed &&
        feedback.message == 'No scoped action';
  });
  await check('empty_message_conversation_retains_scoped_results', (f) async {
    await f.db
        .customStatement("DELETE FROM messages WHERE conversation_id='a'");
    final items = (await f.repo(conversation: 'a').page()).items;
    return items.map((c) => c.id).toSet().containsAll({'a1', 'a2'}) &&
        items.length == 2;
  });
  await check('pagination_cursor_deduplicates_and_loads_older_results',
      (f) async {
    for (var i = 1; i <= 10; i++) {
      final id = 'p-${i.toString().padLeft(2, '0')}';
      await f.save(id, task: 'ta2', run: 'run-a2');
      await f.db.customStatement(
          "UPDATE result_cards SET created_at='2020-01-01T00:00:${i.toString().padLeft(2, '0')}.000Z' WHERE id='$id'");
    }
    final p1 = await f.repo().page(limit: 10);
    final p2 = await f.repo().page(after: p1.next, limit: 10);
    final ids = {...p1.items.map((c) => c.id), ...p2.items.map((c) => c.id)};
    return p1.items.length == 10 &&
        p1.next != null &&
        p2.items.length == 2 &&
        p2.next == null &&
        ids.length == 12 &&
        ids.contains('p-01');
  });
  await check('read_failure_recovery_restores_exact_scoped_cards', (f) async {
    await f.db.customStatement(
        'ALTER TABLE result_cards RENAME TO result_cards_broken');
    var failed = false;
    try {
      await f.repo().page();
    } catch (_) {
      failed = true;
    }
    await f.db.customStatement(
        'ALTER TABLE result_cards_broken RENAME TO result_cards');
    final recovered = (await f.repo().page()).items;
    return failed &&
        recovered.map((c) => c.id).toSet().containsAll({'a1', 'a2'}) &&
        recovered.length == 2;
  });
  return {
    'type': 'ConversationResultContractChecks',
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

class _Fixture
    implements
        ResultResourceReader,
        ResultPermissionChecker,
        ResultActionExecutor {
  Directory? root;
  AppDatabase? _db;
  AppDatabase get db => _db!;
  SqlResultActionRepository get base => SqlResultActionRepository(db);
  final scopes = <ResultActionApprovalScope>[];
  int calls = 0;
  Future<void> Function()? beforeDispatch;
  final now = DateTime.utc(2026, 10, 19, 12);
  Future<void> init() async {
    root = await Directory.systemTemp.createTemp('nexus-chat-results-');
    _db =
        AppDatabase(NativeDatabase(File(p.join(root!.path, 'checks.sqlite'))));
    for (final (id, project) in [
      ('a', null),
      ('b', null),
      ('p', 'project-p')
    ]) {
      await db.into(db.conversations).insert(ConversationsCompanion.insert(
          id: id,
          title: Value(id),
          projectId: Value(project),
          createdAt: now,
          updatedAt: now));
    }
    for (final (id, conversation, project) in [
      ('ta1', 'a', null),
      ('ta2', 'a', null),
      ('tb', 'b', null),
      ('tp', 'p', 'project-p')
    ]) {
      await db.into(db.tasks).insert(TasksCompanion.insert(
          id: id,
          conversationId: conversation,
          projectId: Value(project),
          requestJson: '{}',
          createdAt: now,
          updatedAt: now));
    }
    await save('a1');
    await save('a2', task: 'ta2', run: 'run-a2');
    await save('b1', task: 'tb');
    await save('p1', task: 'tp');
  }

  ConversationResultRepository repo(
          {String conversation = 'a',
          String? project,
          String? task,
          String? run}) =>
      ConversationResultRepository(
          db,
          ConversationResultScope(conversation,
              projectId: project, taskId: task, runId: run));
  ResultActionService service({String conversation = 'a'}) =>
      ResultActionService(
          repository: repo(conversation: conversation),
          resources: this,
          permissions: this,
          executor: this);
  Future<void> save(String id, {String task = 'ta1', String run = 'run-a1'}) =>
      base.saveCard(ResultCard(
          id: id,
          kind: ResultCardKind.file,
          resourceType: 'fixture',
          resourceId: 'file-$id',
          resourceVersion: 1,
          title: id,
          summary: 'Synthetic result',
          taskId: task,
          turnId: run,
          createdAt: now,
          updatedAt: now));
  Future<void> artifactCard(
      {String task = 'ta1',
      String run = 'artifact-run',
      String project = ''}) async {
    await db.saveArtifactRecord(ProjectArtifact(
            id: 'artifact-file',
            projectId: project,
            taskId: task,
            runId: run,
            kind: 'text',
            relativePath: 'synthetic.txt',
            hash: 'fixture',
            bytes: 1,
            createdAt: now)
        .toJson());
    await base.saveCard(ResultCard(
        id: 'artifact-card',
        kind: ResultCardKind.file,
        resourceType: 'artifact',
        resourceId: 'artifact-file',
        resourceVersion: 1,
        title: 'Synthetic',
        summary: '',
        taskId: 'ta1',
        turnId: 'artifact-run',
        createdAt: now));
  }

  @override
  Future<ResultResourceSnapshot?> read(
          {required String resourceType, required String resourceId}) async =>
      ResultResourceSnapshot(
          resourceType: resourceType, resourceId: resourceId, version: 1);
  @override
  Future<bool> canPerform(ResultActionSpec spec, ResultCard card) async => true;
  @override
  Future<ResultActionExecutionResult> execute(
      ResultActionExecutionRequest request) async {
    await beforeDispatch?.call();
    if (request.canContinue != null && !await request.canContinue!()) {
      return const ResultActionExecutionResult.failed(
          message: 'Scoped dispatch denied');
    }
    calls++;
    return const ResultActionExecutionResult.succeeded();
  }

  Future<void> close() async {
    for (final scope in scopes) {
      await scope.close();
    }
    await _db?.close();
    if (root != null && await root!.exists()) {
      await root!.delete(recursive: true);
    }
  }
}

_Fixture? _uiFixture;
ArtifactService? _artifacts;
Route<void>? _route;
NavigatorState? _navigator;
FlutterExceptionHandler? _prevOnError;
int _uiErrors = 0;
final _innerNavigator = GlobalKey<NavigatorState>();
final _host = GlobalKey<_TranscriptFixtureState>();
Future<Map<String, dynamic>> _ui(String mode) async {
  if (mode == 'open') {
    if (_route != null) throw StateError('Close owned fixture first');
    _uiErrors = 0;
    _prevOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      _uiErrors++;
      _prevOnError?.call(details);
    };
    NavigatorState? navigator;
    void visit(Element e) {
      if (navigator != null) return;
      if (e is StatefulElement && e.state is NavigatorState) {
        navigator = e.state as NavigatorState;
      } else {
        e.visitChildElements(visit);
      }
    }

    WidgetsBinding.instance.rootElement?.visitChildElements(visit);
    if (navigator == null) throw StateError('No navigator');
    final f = _uiFixture = _Fixture();
    await f.init();
    await f.db.customStatement('DELETE FROM result_cards');
    _artifacts = ArtifactService(
        rootDirectory: () async => Directory(p.join(f.root!.path, 'payloads')));
    final workspace =
        await Directory(p.join(f.root!.path, 'workspace')).create();
    for (final (task, run, name) in [
      ('ta1', 'run-a1', 'ChatResultA.txt'),
      ('ta2', 'run-a2', 'OlderResultA.txt'),
      ('tb', 'run-b', 'PrivateResultB.txt')
    ]) {
      await File(p.join(workspace.path, name))
          .writeAsString('CHAT_RESULT_SYNTHETIC_CONTENT');
      await _artifacts!.record(
          db: f.db,
          taskId: task,
          runId: run,
          workspacePath: workspace.path,
          inspection: ArtifactInspection(relativePath: name, exists: true));
    }
    final route = _route = MaterialPageRoute<void>(
        builder: (_) => ProviderScope(
            overrides: [databaseProvider.overrideWith((ref) async => f.db)],
            child: NavigatorPopHandler(
                onPopWithResult: (_) =>
                    unawaited(_innerNavigator.currentState?.maybePop()),
                child: Navigator(
                    key: _innerNavigator,
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                        builder: (_) => _TranscriptFixture(key: _host))))));
    _navigator = navigator;
    unawaited(navigator!.push(route));
  } else if (mode == 'switch') {
    _host.currentState!.switchConversation();
  } else if (mode == 'switchWhileDetail') {
    _host.currentState!.switchConversation();
  } else if (mode == 'deleteTask') {
    await _uiFixture!.db.customStatement("DELETE FROM tasks WHERE id='ta1'");
  } else if (mode == 'lateResult') {
    final f = _uiFixture!;
    final workspace = p.join(f.root!.path, 'workspace');
    await File(p.join(workspace, 'LateResultA.txt'))
        .writeAsString('Late synthetic result');
    await _artifacts!.record(
        db: f.db,
        taskId: 'ta1',
        runId: 'run-a1',
        workspacePath: workspace,
        inspection: const ArtifactInspection(
            relativePath: 'LateResultA.txt', exists: true));
  } else if (mode == 'emptyMessages') {
    _host.currentState!.setEmptyMessages(true);
  } else if (mode == 'normalMessages') {
    _host.currentState!.setEmptyMessages(false);
  } else if (mode == 'seedPage') {
    final f = _uiFixture!;
    final workspace = p.join(f.root!.path, 'workspace');
    for (var i = 1; i <= 10; i++) {
      final name = 'PageOld${i.toString().padLeft(2, '0')}.txt';
      await File(p.join(workspace, name)).writeAsString('Page result $i');
      final art = await _artifacts!.record(
          db: f.db,
          taskId: 'ta2',
          runId: 'run-a2',
          workspacePath: workspace,
          inspection: ArtifactInspection(relativePath: name, exists: true));
      await f.db.customStatement(
          "UPDATE result_cards SET created_at='2020-01-01T00:00:${i.toString().padLeft(2, '0')}.000Z' WHERE resource_id='${art.id}'");
    }
  } else if (mode == 'scrollBottom') {
    _host.currentState!.scrollToBottom();
  } else if (mode == 'scrollTop') {
    _host.currentState!.scrollToTop();
  } else if (mode == 'breakRead') {
    await _uiFixture!.db.customStatement(
        'ALTER TABLE result_cards RENAME TO result_cards_broken');
  } else if (mode == 'restoreRead') {
    await _uiFixture!.db.customStatement(
        'ALTER TABLE result_cards_broken RENAME TO result_cards');
  } else if (mode == 'largeText') {
    _host.currentState!.setTextScale(2.0);
  } else if (mode == 'normalText') {
    _host.currentState!.setTextScale(1.0);
  } else if (mode == 'backgroundPause') {
    _host.currentState!.setRunning(false);
    for (final s in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      WidgetsBinding.instance.handleAppLifecycleStateChanged(s);
    }
    final f = _uiFixture!;
    final workspace = p.join(f.root!.path, 'workspace');
    await File(p.join(workspace, 'BackgroundResumedA.txt'))
        .writeAsString('Resumed synthetic result');
    await _artifacts!.record(
        db: f.db,
        taskId: 'ta2',
        runId: 'run-a2',
        workspacePath: workspace,
        inspection: const ArtifactInspection(
            relativePath: 'BackgroundResumedA.txt', exists: true));
  } else if (mode == 'foregroundResume') {
    for (final s in const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      WidgetsBinding.instance.handleAppLifecycleStateChanged(s);
    }
  } else if (mode == 'showTools') {
    _host.currentState!.setShowToolTimeline(true);
  } else if (mode == 'hideTools') {
    _host.currentState!.setShowToolTimeline(false);
  } else if (mode == 'close') {
    if (_route?.isActive == true) _navigator!.removeRoute(_route!);
    _route = null;
    FlutterError.onError = _prevOnError;
    _prevOnError = null;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await _uiFixture?.close();
    _uiFixture = null;
    _artifacts = null;
    _navigator = null;
    return {'fixtureOnly': true, 'modelCalls': 0, 'closed': true};
  } else if (mode != 'inspect') {
    throw ArgumentError('Fixed modes only');
  }
  final db = _uiFixture!.db;
  final actions =
      await db.customSelect('SELECT status,attempts FROM result_actions').get();
  return {
    'fixtureOnly': true,
    'modelCalls': 0,
    'conversation': _host.currentState?.conversation,
    'uiErrors': _uiErrors,
    'pending': (await db
            .customSelect('SELECT request_id FROM pending_approvals')
            .get())
        .length,
    'actions': [
      for (final row in actions)
        {'status': row.data['status'], 'attempts': row.data['attempts']}
    ]
  };
}

class _TranscriptFixture extends StatefulWidget {
  const _TranscriptFixture({super.key});
  @override
  State<_TranscriptFixture> createState() => _TranscriptFixtureState();
}

class _TranscriptFixtureState extends State<_TranscriptFixture> {
  final scroll = ScrollController();
  String conversation = 'a';
  bool emptyMessages = false;
  bool showToolTimeline = false;
  bool running = true;
  double textScale = 1.0;
  void switchConversation() =>
      setState(() => conversation = conversation == 'a' ? 'b' : 'a');
  void setEmptyMessages(bool v) => setState(() => emptyMessages = v);
  void setShowToolTimeline(bool v) => setState(() => showToolTimeline = v);
  void setRunning(bool v) => setState(() => running = v);
  void setTextScale(double v) => setState(() => textScale = v);
  void scrollToBottom() {
    if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
  }

  void scrollToTop() {
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final captured = conversation;
    bool current() => mounted && captured == conversation;
    final scope = ConversationResultScope(conversation);
    final timeline = ConversationResultTimeline(
        key: ValueKey('conversation-results-$conversation-$emptyMessages'),
        scope: scope,
        running: running,
        artifacts: _artifacts!,
        sourceIsCurrent: current);
    return MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
            appBar: AppBar(title: Text('隔离聊天结果 · $conversation'), actions: [
              TextButton(
                  onPressed: switchConversation, child: const Text('切换会话'))
            ]),
            body: Column(children: [
              PlanPanel(
                  plan: const model.PlanState(status: 'completed', steps: [
                    model.PlanStep(
                        id: 'step-1', description: '合成文件', status: 'completed')
                  ]),
                  onApprove: () {},
                  onCancel: () {},
                  onOpenResults: () => unawaited(openConversationResults(
                      context,
                      scope: ConversationResultScope(conversation,
                          taskId: conversation == 'a' ? 'ta1' : 'tb',
                          runId: conversation == 'a' ? 'run-a1' : 'run-b'),
                      sourceIsCurrent: current,
                      artifacts: _artifacts!))),
              if (showToolTimeline)
                ToolActivityTimeline(
                    activities: const [
                      ToolActivity(
                          call: model.ToolCall(
                              id: 'tool-1',
                              name: 'write_file',
                              arguments: {'path': 'ChatResultA.txt'}),
                          risk: model.ToolRisk.safe,
                          status: '已完成',
                          ok: true,
                          effect: ToolEffect.applied)
                    ],
                    running: false,
                    compact: false,
                    onOpenResults: () => unawaited(openConversationResults(
                        context,
                        scope: ConversationResultScope(conversation,
                            taskId: conversation == 'a' ? 'ta1' : 'tb',
                            runId: conversation == 'a' ? 'run-a1' : 'run-b'),
                        sourceIsCurrent: current,
                        artifacts: _artifacts!))),
              Expanded(
                  child: emptyMessages
                      ? ChatEmptyState(
                          hasWorkspace: true,
                          providerConfigured: true,
                          workspaceLabel: 'workspace',
                          modelLabel: 'fixture-only',
                          trailing: timeline)
                      : ChatMessageList(
                          messages: [
                            model.ChatMessage(
                                id: 'synthetic-$conversation',
                                role: model.MessageRole.assistant,
                                parts: const [
                                  model.MessagePart.text('隔离结果时间线，不调用模型。')
                                ])
                          ],
                          controller: scroll,
                          running: false,
                          onLongPress: (_) {},
                          onRegenerate: () {},
                          sessionKey: conversation,
                          trailingWidgets: [timeline])),
            ])));
  }
}
