import 'run_approval_scope.dart';
import 'dart:async';
import 'dart:convert';
import '../domain/tool_codes.dart';
import '../domain/tool_result.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/database/run_plan_store.dart';
import 'run_controller.dart';

/// Adapter from durable storage into the existing controller/tool pipeline.
/// No model/provider/tool implementation lives here.
class PersistedRunFence {
  PersistedRunFence._(this.store, this.controller, this.token);
  final RunPlanStore store;
  final AgentRunController controller;
  RunPlanToken token;
  Future<void>? _sync;
  Timer? _timer;
  bool _closed = false;

  static Future<PersistedRunFence> open(
      {required AppDatabase db,
      required AgentRunController controller,
      required String taskId,
      required String runId,
      String? expectedPreviousRunId}) async {
    final store = RunPlanStore(db);
    final previous = await store.head(taskId);
    final expected = expectedPreviousRunId ??
        (previous != null &&
                !const {'running', 'paused'}.contains(previous.state)
            ? previous.token.runId
            : null);
    final token = await store.bind(
        taskId: taskId, runId: runId, expectedPreviousRunId: expected);
    final fence = PersistedRunFence._(store, controller, token);
    controller.attachDurableFence(
        version: token.version,
        openApproval: (call, risk, version) => RunApprovalScope.open(
            db: db,
            token: RunPlanToken(taskId, runId, version),
            call: call,
            risk: risk,
            invalidated: controller.whenRevisionChanges(
                controller.controlRevision, controller.durablePlanRevision),
            remember: controller.rememberPlanTool),
        synchronize: fence.synchronize,
        verify: (version) =>
            store.isCurrent(RunPlanToken(taskId, runId, version)),
        claim: fence.claim,
        settle: fence.settle,
        finish: fence.finish);
    await fence.synchronize();
    fence._timer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (fence._closed || controller.isSealed || controller.isCancelled) {
        return;
      }
      unawaited(fence.synchronize().catchError((Object _) {
        controller.cancel();
      }));
    });
    return fence;
  }

  Future<void> synchronize() {
    if (_closed) return Future<void>.value();
    final pending = _sync;
    if (pending != null) return pending;
    final operation = _synchronize();
    _sync = operation;
    unawaited(operation.whenComplete(() {
      if (identical(_sync, operation)) _sync = null;
    }).catchError((Object _) {}));
    return operation;
  }

  Future<void> _synchronize() async {
    final head = await store.head(token.taskId);
    if (head == null ||
        head.token.runId != token.runId ||
        head.state == 'interrupted') {
      controller.cancel();
      return;
    }
    if (!head.pendingControls) {
      token = head.token;
      controller.setDurableVersion(token.version);
      if (head.state == 'paused') controller.pause();
      if (head.state == 'cancelled') controller.cancel();
      return;
    }
    final batch = await store.consume(token.taskId, token.runId);
    token = batch.head.token;
    controller.setDurableVersion(token.version);
    for (final control in batch.controls) {
      if (control.kind == 'followUp') {
        final payload = jsonDecode(control.payloadJson) as Map<String, dynamic>;
        final text = payload['text'];
        final local = payload['localControlRevision'];
        // Compatibility with an already locally queued pre-protocol UI request.
        if (text is String &&
            !(local is int && local <= controller.controlRevision)) {
          controller.steer(text);
        }
      } else if (control.kind == 'pause') {
        controller.pause();
      } else if (control.kind == 'resume') {
        controller.resume();
      } else if (control.kind == 'cancel') {
        controller.cancel();
      }
    }
  }

  Future<ToolResult?> claim(int version, String callId) async {
    try {
      final result = await store.claim(
          RunPlanToken(token.taskId, token.runId, version), callId);
      if (result == RunDispatchClaim.granted) return null;
      return ToolResult.failure(
          code: result == RunDispatchClaim.superseded
              ? ToolCodes.revisionConflict
              : ToolCodes.toolError,
          message: result == RunDispatchClaim.superseded
              ? '持久计划或活动运行已变化，旧调用未派发；请重新读取用户指令'
              : '该调用已有派发记录，副作用未重新执行。请核实原结果，不得盲目重试',
          data: {
            'reason': result == RunDispatchClaim.superseded
                ? 'plan_superseded'
                : 'dispatch_already_claimed'
          },
          effect: result == RunDispatchClaim.superseded
              ? ToolEffect.none
              : ToolEffect.unknown);
    } catch (_) {
      return ToolResult.failure(
          code: ToolCodes.toolError,
          message: '无法确认派发占位，未再次派发；请检查原调用状态',
          data: const {'reason': 'dispatch_claim_unconfirmed'},
          effect: ToolEffect.unknown);
    }
  }

  Future<ToolResult> settle(
      int version, String callId, ToolResult result) async {
    try {
      if (await store.settle(RunPlanToken(token.taskId, token.runId, version),
          callId, result.effect)) {
        return result;
      }
    } catch (_) {
      // A failed settlement is indistinguishable from a lost acknowledgement.
      // Return the unknown-effect result below; never replay this dispatch.
    }
    return ToolResult.failure(
        code: ToolCodes.toolError,
        message: '工具已越过执行边界，但结算记录未确认；保留原结果线索，请先核实，勿重复执行',
        data: {
          ...?result.data,
          'priorCode': result.code,
          'priorEffect': result.effect.name,
          'reason': 'dispatch_settlement_unconfirmed'
        },
        effect: ToolEffect.unknown);
  }

  Future<bool> finish() async {
    await synchronize();
    return store.finish(token, 'completed');
  }

  Future<void> close() async {
    if (_closed) return;
    _timer?.cancel();
    try {
      await controller.waitForPersistence();
      await synchronize();
      final head = await store.head(token.taskId);
      if (head != null &&
          head.token.runId == token.runId &&
          const {'running', 'paused', 'queued'}.contains(head.state)) {
        await store.interrupt(head.token);
      }
    } finally {
      _closed = true;
    }
  }
}
