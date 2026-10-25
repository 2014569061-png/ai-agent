/// Debug-only foreground UI harness using the production approval helper.
/// All task/audit/permission rows are isolated in an owned memory database.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/development_execution_service.dart';
import '../application/persisted_run_fence.dart';
import '../application/providers.dart';
import '../application/run_controller.dart';
import '../application/task_service.dart';
import '../domain/models.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/providers/tool_trust_store.dart';
import '../presentation/widgets/tool_approval_helper.dart';

bool _registered = false;
AppDatabase? _db;
AgentRunController? _controller;
PersistedRunFence? _fence;
String? _task;
NavigatorState? _navigator;
Route<void>? _route;
Route<void>? _cover;
final _host = GlobalKey<_ApprovalFixtureState>();
final _trust = ToolTrustStore();
void registerApprovalScopeUiChecks() {
  if (!kDebugMode || _registered) return;
  _registered = true;
  registerExtension(
      'ext.nexus.approvalScopeFixture',
      (method, params) async => ServiceExtensionResponse.result(
          jsonEncode(await _action(params['mode'] ?? 'inspect'))));
}

Future<Map<String, dynamic>> _action(String mode) async {
  if (mode == 'open') {
    if (_route != null) throw StateError('Close owned fixture first');
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
    final db = _db = AppDatabase(NativeDatabase.memory());
    final task = await TaskService().create(
        db: db,
        conversationId: 'isolated-approval-ui',
        type: 'general',
        requestJson: '{}');
    _task = task.id;
    _controller = AgentRunController();
    _fence = await PersistedRunFence.open(
        db: db,
        controller: _controller!,
        taskId: task.id,
        runId: 'isolated-approval-ui-run');
    final route = _route = MaterialPageRoute<void>(
        builder: (_) => ProviderScope(overrides: [
              databaseProvider.overrideWith((ref) async => db),
              toolTrustStoreProvider.overrideWith((ref) async => _trust),
            ], child: _ApprovalFixture(key: _host)));
    _navigator = navigator;
    unawaited(navigator!.push(route));
  } else if (mode == 'correct') {
    final result = await DevelopmentExecutionService(db: _db!).submitControl(
        TaskControlRequest(
            taskId: _task!,
            runId: 'isolated-approval-ui-run',
            kind: TaskControlKind.followUp,
            clientControlId: 'ui-control-${_controller!.durablePlanRevision}',
            payload: const {'text': 'Synthetic replacement target'}));
    if (result.status != 'pending') {
      throw StateError('Fixture correction rejected');
    }
    await _controller!.synchronize();
  } else if (mode == 'cover') {
    if (_cover != null) throw StateError('Cover already open');
    final cover = _cover = DialogRoute<void>(
        context: _host.currentContext!,
        builder: (_) => const AlertDialog(
            title: Text('隔离遮盖层'), content: Text('旧审批失效时此层必须保留')));
    unawaited(_navigator!.push(cover));
  } else if (mode == 'uncover') {
    final cover = _cover;
    _cover = null;
    if (cover != null && cover.isActive) _navigator!.removeRoute(cover);
  } else if (mode == 'close') {
    _controller?.cancel();
    await _host.currentState?.pending;
    await _fence?.close();
    _controller?.seal();
    if (_cover?.isActive == true) _navigator!.removeRoute(_cover!);
    if (_route?.isActive == true) _navigator!.removeRoute(_route!);
    _cover = null;
    _route = null;
    _navigator = null;
    _fence = null;
    _controller = null;
    _task = null;
    await Future<void>.delayed(Duration.zero);
    await _db?.close();
    _db = null;
  } else if (mode != 'inspect') {
    throw ArgumentError('Unknown fixed action');
  }
  return {
    'fixtureOnly': true,
    'mode': mode,
    'modelCalls': 0,
    'externalActions': 0,
    'decision': _host.currentState?.decision.name ?? 'none',
    'planVersion': _controller?.durablePlanRevision,
    'planTrusted':
        _controller?.isPlanToolTrusted('fixture_scope_gate') ?? false,
    'globalSessionGrants': _trust.sessionAllowed.length,
    'globalPersistentGrants': _trust.alwaysAllowed.length,
    'pendingRows': _db == null
        ? 0
        : (await _db!
                .customSelect('SELECT request_id FROM pending_approvals')
                .get())
            .length,
    'scopeRows': _db == null
        ? 0
        : (await _db!
                .customSelect('SELECT request_id FROM run_approval_scopes')
                .get())
            .length,
    'planGrantRows': _db == null
        ? 0
        : (await _db!
                .customSelect('SELECT tool_name FROM run_plan_grants')
                .get())
            .length
  };
}

class _ApprovalFixture extends ConsumerStatefulWidget {
  const _ApprovalFixture({super.key});
  @override
  ConsumerState<_ApprovalFixture> createState() => _ApprovalFixtureState();
}

class _ApprovalFixtureState extends ConsumerState<_ApprovalFixture> {
  ToolApproval decision = ToolApproval.reject;
  Future<ToolApproval>? pending;
  Future<void> open() async {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        pending != null) {
      return;
    }
    const call = ToolCall(
        id: 'isolated-approval-call',
        name: 'fixture_scope_gate',
        arguments: {'target': 'SCOPE_ORIGINAL'});
    final scope = await _controller!.openApproval(
        call, ToolRisk.requiresConfirmation, _controller!.durablePlanRevision);
    if (scope == null || !mounted) return;
    final waiting = pending = scope.invoke(() => promptToolApproval(
        context, ref, call, ToolRisk.requiresConfirmation, false,
        approvalScope: scope));
    final result = await waiting;
    pending = null;
    if (mounted) {
      setState(() {
        decision = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('隔离验收 · 持久审批')),
      body: Column(children: [
        const Text('仅操作隔离计数与内存数据库，不执行工具'),
        Text('隔离审批状态：${decision.name}'),
        FilledButton(onPressed: open, child: const Text('打开隔离审批'))
      ]));
}
