import 'dart:async';
import 'approval_decision_scope.dart';
import 'package:drift/drift.dart' show Variable;
import '../domain/models.dart';
import '../domain/unique_id.dart';
import '../domain/approval_action_codec.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/database/run_plan_store.dart';

/// Framework-created scope; never reconstructed from model-supplied arguments.
/// Temporary decisions/grants are intentionally excluded from vault restore.
class RunApprovalScope implements ApprovalDecisionScope {
  RunApprovalScope._(this.db, this.token, this.call, this.risk,
      this._revisionInvalidated, this._remember);
  @override
  final AppDatabase db;
  final RunPlanToken token;
  final ToolCall call;
  final ToolRisk risk;
  final Future<void> _revisionInvalidated;
  final Completer<void> _closedSignal = Completer<void>();
  @override
  Future<void> get invalidated =>
      Future.any<void>([_revisionInvalidated, _closedSignal.future]);
  final void Function(int version, String tool) _remember;
  @override
  final String requestId = UniqueId.generate('scoped-appr');
  bool _closed = false;
  static final Object _zoneKey = Object();
  static RunApprovalScope? get current =>
      Zone.current[_zoneKey] as RunApprovalScope?;

  static Future<RunApprovalScope?> open(
      {required AppDatabase db,
      required RunPlanToken token,
      required ToolCall call,
      required ToolRisk risk,
      required Future<void> invalidated,
      required void Function(int version, String tool) remember}) async {
    final scope =
        RunApprovalScope._(db, token, call, risk, invalidated, remember);
    final created = await db.transaction(() async {
      if (!await RunPlanStore(db).isCurrent(token)) return false;
      await db.insertPendingApproval(
          requestId: scope.requestId,
          toolName: call.name,
          summary: call.name,
          risk: risk.name,
          ttl: const Duration(minutes: 6));
      await db.customInsert(
          'INSERT INTO run_approval_scopes (request_id,task_id,run_id,plan_version,call_id) VALUES (?,?,?,?,?)',
          variables: [
            Variable(scope.requestId),
            Variable(token.taskId),
            Variable(token.runId),
            Variable(token.version),
            Variable(call.id)
          ]);
      return true;
    });
    return created ? scope : null;
  }

  @override
  Future<bool> isCurrent() async {
    if (_closed || !await RunPlanStore(db).isCurrent(token)) return false;
    return (await db.customSelect(
            'SELECT request_id FROM pending_approvals WHERE request_id=? AND expires_at>?',
            variables: [
          Variable(requestId),
          Variable(DateTime.now().toIso8601String())
        ]).get())
        .isNotEmpty;
  }

  Future<T> run<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_zoneKey: this});

  Future<bool> decide(ToolApproval decision) async {
    if (_closed) return false;
    return db.decidePendingApproval(
        requestId,
        decision == ToolApproval.reject
            ? approvalDenyAction
            : approvalApproveAction);
  }

  Future<ToolApproval> invoke(Future<ToolApproval> Function() body,
      {Duration timeout = const Duration(minutes: 5)}) async {
    Timer? expiryTimer;
    try {
      if (!await isCurrent()) return ToolApproval.reject;
      final expiry = Completer<ToolApproval>();
      expiryTimer = Timer(timeout, () => expiry.complete(ToolApproval.reject));
      final decision = await run(() => Future.any<ToolApproval>([
            body(),
            expiry.future,
            invalidated.then((_) => ToolApproval.reject),
          ]));
      final accepted = await db.transaction(() async {
        if (!await isCurrent()) return false;
        await decide(decision);
        final saved = await db.findPendingApprovalDecision(requestId);
        if (saved != approvalApproveAction || decision == ToolApproval.reject) {
          return false;
        }
        if (decision == ToolApproval.allowSession ||
            decision == ToolApproval.allowAlways) {
          await db.customInsert(
              'INSERT OR IGNORE INTO run_plan_grants (task_id,run_id,plan_version,tool_name) VALUES (?,?,?,?)',
              variables: [
                Variable(token.taskId),
                Variable(token.runId),
                Variable(token.version),
                Variable(call.name)
              ]);
        }
        return true;
      });
      if (accepted &&
          (decision == ToolApproval.allowSession ||
              decision == ToolApproval.allowAlways)) {
        _remember(token.version, call.name);
      }
      return accepted ? decision : ToolApproval.reject;
    } finally {
      expiryTimer?.cancel();
      _closed = true;
      if (!_closedSignal.isCompleted) _closedSignal.complete();
      await db.deletePendingApproval(requestId);
    }
  }
}
