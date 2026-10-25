import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../application/approval_bridge.dart';
import '../application/artifact_service.dart';
import '../application/development_verification.dart';
import '../application/providers.dart';
import '../application/result_action_approval_scope.dart';
import '../application/result_action_service.dart';
import '../domain/approval_action_codec.dart';
import '../domain/models.dart';
import '../domain/result_card.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/database/result_action_approval_store.dart';
import '../infrastructure/database/result_action_store.dart';
import '../presentation/artifacts/artifact_center_page.dart';

bool _registered = false;
void registerResultActionApprovalChecks() {
  if (!kDebugMode || _registered) return;
  _registered = true;
  registerExtension(
      'ext.nexus.resultApprovalContract',
      (method, params) async =>
          ServiceExtensionResponse.result(jsonEncode(await _checks())));
  registerExtension(
      'ext.nexus.resultApprovalFixture',
      (method, params) async => ServiceExtensionResponse.result(
          jsonEncode(await _uiAction(params['mode'] ?? 'inspect'))));
}

Future<Map<String, dynamic>> _checks() async {
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

  await check('sql_default_rejects_page_forged_approval_dto', (f) async {
    final action = await f.prepare();
    final run =
        await f.service.confirm(action.id, f.proof('ui-confirm-forged'));
    return run.hasError && !run.succeeded && f.calls == 0;
  });
  await check('undecided_ticket_is_not_approval_authority', (f) async {
    final scope = await f.scope();
    final run = await f.service.confirm(scope.ticket.actionId, scope.approval);
    return run.hasError && f.calls == 0;
  });
  await check('one_time_approved_ticket_confirms_and_executes', (f) async {
    final scope = await f.scope();
    if (await scope.invoke(() async => ToolApproval.allowOnce) !=
        ToolApproval.allowOnce) {
      return false;
    }
    final confirmed =
        await f.service.confirm(scope.ticket.actionId, scope.approval);
    final run = await f.service.execute(scope.ticket.actionId);
    await scope.close();
    return !confirmed.pendingConfirmation &&
        !confirmed.hasError &&
        run.succeeded &&
        f.calls == 1 &&
        await f.pendingCount() == 0 &&
        await f.auditCount() == 1;
  });
  await check('reject_is_durable_and_never_dispatches', (f) async {
    final scope = await f.scope();
    final decision = await scope.invoke(() async => ToolApproval.reject);
    final run = await f.service.execute(scope.ticket.actionId);
    return decision == ToolApproval.reject &&
        !run.succeeded &&
        f.calls == 0 &&
        await f.db.findPendingApprovalDecision(scope.requestId) ==
            approvalDenyAction &&
        await f.auditCount() == 1;
  });
  await check('session_grant_escalation_is_rejected', (f) async {
    final scope = await f.scope();
    return await scope.invoke(() async => ToolApproval.allowSession) ==
            ToolApproval.reject &&
        await f.grantCount() == 0 &&
        f.calls == 0;
  });
  await check('persistent_grant_escalation_is_rejected', (f) async {
    final scope = await f.scope();
    return await scope.invoke(() async => ToolApproval.allowAlways) ==
            ToolApproval.reject &&
        await f.grantCount() == 0 &&
        f.calls == 0;
  });
  await check('approval_cannot_be_moved_to_another_action', (f) async {
    final scope = await f.scope();
    await scope.invoke(() async => ToolApproval.allowOnce);
    final other = await f.prepare(key: 'another-explicit-intent');
    final run = await f.service.confirm(other.id, scope.approval);
    return run.hasError && f.calls == 0;
  });
  await check('caller_cannot_extend_ticket_deadline', (f) async {
    final scope = await f.scope();
    await scope.invoke(() async => ToolApproval.allowOnce);
    final run = await f.service
        .confirm(scope.ticket.actionId, f.proof(scope.requestId));
    return run.hasError && f.calls == 0;
  });
  await check('closing_page_scope_revokes_confirmed_ticket', (f) async {
    final scope = await f.scope();
    await scope.invoke(() async => ToolApproval.allowOnce);
    await f.service.confirm(scope.ticket.actionId, scope.approval);
    await scope.close();
    final run = await f.service.execute(scope.ticket.actionId);
    return run.hasError && f.calls == 0 && await f.pendingCount() == 0;
  });
  await check('different_isolate_owner_cannot_resume_old_permission',
      (f) async {
    final scope = await f.scope();
    await scope.invoke(() async => ToolApproval.allowOnce);
    final action = (await f.repo.findAction(scope.ticket.actionId))!;
    return !await ResultActionApprovalStore(f.db,
            ownerId: 'different-process-fixture')
        .verify(
            action: action,
            card: f.card,
            approvalId: scope.requestId,
            expiresAt: scope.ticket.expiresAt);
  });
  await check('card_revision_change_invalidates_waiting_scope', (f) async {
    final scope = await f.scope();
    final decision = await scope.invoke(() async {
      await f.repo.saveCard(f.card.copyWith(revision: 2));
      return ToolApproval.allowOnce;
    });
    return decision == ToolApproval.reject &&
        !await scope.isCurrent() &&
        f.calls == 0;
  });
  await check('target_change_after_confirm_blocks_execution', (f) async {
    final scope = await f.scope();
    await scope.invoke(() async => ToolApproval.allowOnce);
    await f.service.confirm(scope.ticket.actionId, scope.approval);
    await f.db.customStatement(
        "UPDATE result_cards SET resource_id='different-target', revision=2");
    final run = await f.service.execute(scope.ticket.actionId);
    return run.hasError && f.calls == 0;
  });
  await check('deleted_pending_row_cannot_be_forged_back_by_dto', (f) async {
    final scope = await f.scope();
    await scope.invoke(() async => ToolApproval.allowOnce);
    final proof = scope.approval;
    await scope.close();
    return (await f.service.confirm(scope.ticket.actionId, proof)).hasError &&
        f.calls == 0;
  });
  await check('tampered_binding_fails_closed', (f) async {
    final scope = await f.scope();
    await scope.invoke(() async => ToolApproval.allowOnce);
    await f.db.customStatement(
        'UPDATE pending_approvals SET summary=? WHERE request_id=?',
        ['{"type":"result_action","schema":1}', scope.requestId]);
    return (await f.service.confirm(scope.ticket.actionId, scope.approval))
            .hasError &&
        f.calls == 0;
  });
  await check(
      'background_bridge_approve_uses_same_binding_and_cleans_transport',
      (f) async {
    final notifications = _Notifications(f.db, approvalApproveAction);
    final bridge = ApprovalBridge(
        pollInterval: const Duration(milliseconds: 5),
        notifications: notifications);
    final scope = await f.scope(bridge: bridge);
    final decision = await scope.invoke(() async =>
        await bridge.requestDecision(
                    toolName: scope.ticket.callType,
                    summary: '结果卡操作需要批准（仅本次）',
                    risk: scope.risk.name,
                    database: f.db,
                    approvalScope: scope) ==
                true
            ? ToolApproval.allowOnce
            : ToolApproval.reject);
    final confirmed =
        await f.service.confirm(scope.ticket.actionId, scope.approval);
    final run = await f.service.execute(scope.ticket.actionId);
    return decision == ToolApproval.allowOnce &&
        !confirmed.hasError &&
        run.succeeded &&
        notifications.shown == 1 &&
        notifications.cancelled == 1 &&
        f.calls == 1 &&
        !notifications.body.contains('SENSITIVE_TITLE');
  });
  await check('background_bridge_denial_never_dispatches', (f) async {
    final notifications = _Notifications(f.db, approvalDenyAction);
    final bridge = ApprovalBridge(
        pollInterval: const Duration(milliseconds: 5),
        notifications: notifications);
    final scope = await f.scope(bridge: bridge);
    final approved = await bridge.requestDecision(
        toolName: scope.ticket.callType,
        summary: '结果卡操作需要批准（仅本次）',
        risk: scope.risk.name,
        database: f.db,
        approvalScope: scope);
    return approved == false && f.calls == 0 && notifications.cancelled == 1;
  });
  await check('timeout_rejects_without_grant_or_dispatch', (f) async {
    final scope = await f.scope(timeout: const Duration(milliseconds: 100));
    final decision = await scope.invoke(() => Completer<ToolApproval>().future);
    return decision == ToolApproval.reject &&
        f.calls == 0 &&
        await f.grantCount() == 0;
  });
  await check('late_notification_cannot_change_first_decision', (f) async {
    final scope = await f.scope();
    await f.db.decidePendingApproval(scope.requestId, approvalDenyAction);
    final changed = await f.db
        .decidePendingApproval(scope.requestId, approvalApproveAction);
    return !changed &&
        (await f.service.confirm(scope.ticket.actionId, scope.approval))
            .hasError;
  });
  await check('cleared_data_is_not_resurrected_by_old_approval', (f) async {
    final scope = await f.scope();
    await scope.invoke(() async => ToolApproval.allowOnce);
    await f.service.confirm(scope.ticket.actionId, scope.approval);
    await f.db.clearAllUserData();
    final run = await f.service.execute(scope.ticket.actionId);
    return !run.succeeded &&
        f.calls == 0 &&
        await f.pendingCount() == 0 &&
        (await f.repo.listCards()).isEmpty;
  });
  await check('two_services_cannot_both_claim_same_action', (f) async {
    final scope = await f.scope();
    await scope.invoke(() async => ToolApproval.allowOnce);
    await f.service.confirm(scope.ticket.actionId, scope.approval);
    final other = f.makeService(f.db);
    final runs = await Future.wait([
      f.service.execute(scope.ticket.actionId),
      other.execute(scope.ticket.actionId)
    ]);
    return f.calls == 1 && runs.where((r) => r.executed).length == 1;
  });
  await check('two_sqlite_connections_cannot_double_dispatch', (f) async {
    final scope = await f.scope();
    await scope.invoke(() async => ToolApproval.allowOnce);
    await f.service.confirm(scope.ticket.actionId, scope.approval);
    final second = AppDatabase(NativeDatabase(f.databaseFile));
    try {
      await second.customStatement('PRAGMA busy_timeout=1000');
      await f.db.customStatement('PRAGMA busy_timeout=1000');
      final other = f.makeService(second);
      final runs = await Future.wait([
        f.service.execute(scope.ticket.actionId),
        other.execute(scope.ticket.actionId)
      ]);
      return f.calls == 1 && runs.where((r) => r.executed).length == 1;
    } finally {
      await second.close();
    }
  });
  await check('repeat_confirmation_is_idempotent', (f) async {
    final scope = await f.scope();
    await scope.invoke(() async => ToolApproval.allowOnce);
    final first =
        await f.service.confirm(scope.ticket.actionId, scope.approval);
    final again =
        await f.service.confirm(scope.ticket.actionId, scope.approval);
    return !again.hasError &&
        first.action?.revision == again.action?.revision &&
        (await f.service.execute(scope.ticket.actionId)).succeeded &&
        f.calls == 1;
  });
  await check('old_response_cannot_replace_already_bound_approval', (f) async {
    final scope = await f.scope();
    await scope.invoke(() async => ToolApproval.allowOnce);
    await f.service.confirm(scope.ticket.actionId, scope.approval);
    final wrong = await f.service
        .confirm(scope.ticket.actionId, f.proof('other-request'));
    return wrong.hasError &&
        (await f.repo.findAction(scope.ticket.actionId))?.approvalId ==
            scope.requestId &&
        (await f.service.execute(scope.ticket.actionId)).succeeded &&
        f.calls == 1;
  });
  await check('late_execution_result_does_not_reinsert_deleted_action',
      (f) async {
    final scope = await f.scope();
    await scope.invoke(() async => ToolApproval.allowOnce);
    await f.service.confirm(scope.ticket.actionId, scope.approval);
    f.beforeResult = () async {
      await f.db.customStatement('DELETE FROM result_actions');
    };
    final run = await f.service.execute(scope.ticket.actionId);
    return run.hasError &&
        run.executed &&
        f.calls == 1 &&
        await f.repo.findAction(scope.ticket.actionId) == null;
  });
  for (final boundary in [
    'page_closed',
    'approval_removed',
    'target_changed'
  ]) {
    await check('last_dispatch_guard_rejects_$boundary', (f) async {
      final scope = await f.scope();
      await scope.invoke(() async => ToolApproval.allowOnce);
      await f.service.confirm(scope.ticket.actionId, scope.approval);
      f.beforeDispatch = () async {
        if (boundary == 'approval_removed') {
          await scope.close();
        }
        if (boundary == 'target_changed') {
          await f.repo.saveCard(f.card.copyWith(revision: 2));
        }
      };
      final run = await f.service.execute(scope.ticket.actionId,
          canContinue: () => boundary != 'page_closed');
      return !run.succeeded && f.calls == 0;
    });
  }
  return {
    'type': 'ResultApprovalContractChecks',
    'fixtureOnly': true,
    'storage': 'owned_temporary_sqlite_file',
    'notificationTransport': 'fixture_notifier_no_os_notifications',
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
  Directory? base;
  AppDatabase? _db;
  AppDatabase get db => _db!;
  File get databaseFile => File(p.join(base!.path, 'checks.sqlite'));
  SqlResultActionRepository get repo => SqlResultActionRepository(db);
  late ResultActionService service;
  final scopes = <ResultActionApprovalScope>[];
  int calls = 0;
  Future<void> Function()? beforeDispatch;
  Future<void> Function()? beforeResult;
  final card = const ResultCard(
      id: 'approval-card',
      kind: ResultCardKind.file,
      resourceType: 'artifact',
      resourceId: 'fixture-artifact',
      resourceVersion: 1,
      title: 'SENSITIVE_TITLE',
      summary: 'Synthetic only');

  Future<void> init() async {
    base = await Directory.systemTemp.createTemp('nexus-result-approval-');
    _db = AppDatabase(NativeDatabase(databaseFile));
    await repo.saveCard(card);
    service = makeService(db);
  }

  ResultActionService makeService(AppDatabase database) => ResultActionService(
      repository: SqlResultActionRepository(database),
      resources: this,
      permissions: this,
      executor: this);
  Future<ResultActionRecord> prepare({String? key}) async =>
      (await service.prepare(card, 'file.share', idempotencyKey: key)).action!;
  Future<ResultActionApprovalScope> scope(
      {ApprovalBridge bridge = const ApprovalBridge(),
      Duration timeout = const Duration(minutes: 5)}) async {
    final action = await prepare();
    final scope = (await ResultActionApprovalScope.open(db, action.id,
        bridge: bridge, timeout: timeout))!;
    scopes.add(scope);
    return scope;
  }

  ResultActionApproval proof(String id) => ResultActionApproval(
      approvalId: id,
      cardId: card.id,
      actionType: 'file.share',
      grantedAt: DateTime.now().toUtc(),
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 4)));
  Future<int> count(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS c FROM $table').getSingle())
          .read<int>('c');
  Future<int> pendingCount() => count('pending_approvals');
  Future<int> grantCount() => count('run_plan_grants');
  Future<int> auditCount() => count('audit_logs');
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
          message: 'Dispatch guard rejected');
    }
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 15));
    await beforeResult?.call();
    return const ResultActionExecutionResult.succeeded();
  }

  Future<void> close() async {
    for (final scope in scopes) {
      await scope.close();
    }
    await _db?.close();
    if (base != null && await base!.exists()) {
      await base!.delete(recursive: true);
    }
  }
}

class _Notifications implements ApprovalNotifications {
  _Notifications(this.db, this.decision);
  final AppDatabase db;
  final String decision;
  int shown = 0, cancelled = 0;
  String body = '';
  @override
  Future<void> show(
      {required int id,
      required String body,
      required String requestId}) async {
    shown++;
    this.body = body;
    await db.decidePendingApproval(requestId, decision);
  }

  @override
  Future<void> cancel(int id) async {
    cancelled++;
  }
}

// Real production file UI, backed only by an owned temporary DB and payload.
Directory? _uiRoot;
AppDatabase? _uiDb;
Route<void>? _uiRoute, _cover;
NavigatorState? _navigator;
final _innerNavigator = GlobalKey<NavigatorState>();
Future<Map<String, dynamic>> _uiAction(String mode) async {
  if (mode == 'open') {
    if (_uiRoute != null) throw StateError('Close owned fixture first');
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
    if (navigator == null) throw StateError('No app navigator');
    final root = _uiRoot =
        await Directory.systemTemp.createTemp('nexus-result-approval-ui-');
    final db = _uiDb =
        AppDatabase(NativeDatabase(File(p.join(root.path, 'ui.sqlite'))));
    final workspace = await Directory(p.join(root.path, 'workspace')).create();
    await File(p.join(workspace.path, 'ScopeShare.txt'))
        .writeAsString('RESULT_APPROVAL_SYNTHETIC_FILE');
    final artifacts = ArtifactService(
        rootDirectory: () async => Directory(p.join(root.path, 'payloads')));
    await artifacts.record(
        db: db,
        taskId: 'isolated-approval-task',
        runId: 'isolated-approval-run',
        workspacePath: workspace.path,
        inspection: const ArtifactInspection(
            relativePath: 'ScopeShare.txt', exists: true));
    final route = _uiRoute = MaterialPageRoute<void>(
        builder: (_) => ProviderScope(
            overrides: [databaseProvider.overrideWith((ref) async => db)],
            child: Navigator(
                key: _innerNavigator,
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('隔离验收 · 结果审批')),
                        body: ArtifactCenterPage(service: artifacts))))));
    _navigator = navigator;
    unawaited(navigator!.push(route));
  } else if (mode == 'change') {
    final repo = SqlResultActionRepository(_uiDb!);
    final card = (await repo.listCards()).single;
    await repo.saveCard(card.copyWith(revision: card.revision + 1));
  } else if (mode == 'cover') {
    final cover = _cover = DialogRoute<void>(
        context: _navigator!.context,
        builder: (_) => const AlertDialog(title: Text('隔离遮盖层 · 结果审批')));
    unawaited(_navigator!.push(cover));
  } else if (mode == 'uncover') {
    if (_cover?.isActive == true) _navigator!.removeRoute(_cover!);
    _cover = null;
  } else if (mode == 'close') {
    if (_cover?.isActive == true) _navigator!.removeRoute(_cover!);
    if (_uiRoute?.isActive == true) _navigator!.removeRoute(_uiRoute!);
    _cover = null;
    _uiRoute = null;
    // Wait for page disposal to remove its own root-navigator approval route.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final remaining = _uiDb == null
        ? 0
        : (await _uiDb!.customSelect('SELECT * FROM pending_approvals').get())
            .length;
    await _uiDb?.close();
    _uiDb = null;
    if (_uiRoot != null && await _uiRoot!.exists()) {
      await _uiRoot!.delete(recursive: true);
    }
    _uiRoot = null;
    _navigator = null;
    return {
      'fixtureOnly': true,
      'modelCalls': 0,
      'pendingAfterClose': remaining
    };
  } else if (mode != 'inspect') {
    throw ArgumentError('Fixed modes only');
  }
  final db = _uiDb!;
  Future<int> count(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS c FROM $table').getSingle())
          .read<int>('c');
  final actions = await db
      .customSelect('SELECT status,attempts,approval_id FROM result_actions')
      .get();
  return {
    'fixtureOnly': true,
    'modelCalls': 0,
    'pending': await count('pending_approvals'),
    'planGrants': await count('run_plan_grants'),
    'audit': await count('audit_logs'),
    'actions': [
      for (final row in actions)
        {
          'status': row.data['status'],
          'attempts': row.data['attempts'],
          'approved': row.data['approval_id'] != null
        }
    ]
  };
}
