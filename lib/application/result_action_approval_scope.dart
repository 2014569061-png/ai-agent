import 'dart:async';

import '../domain/approval_action_codec.dart';
import '../domain/models.dart';
import '../domain/result_card.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/database/result_action_approval_store.dart';
import 'approval_bridge.dart';
import 'approval_decision_scope.dart';
import 'audit_service.dart';

/// One pending action/version, owned by the requesting page. It shares the
/// decision transport with run approvals, never their plan/global trust grants.
class ResultActionApprovalScope implements ApprovalDecisionScope {
  ResultActionApprovalScope._(this.db, this.store, this.ticket, this.bridge);
  @override
  final AppDatabase db;
  final ResultActionApprovalStore store;
  final ResultActionApprovalTicket ticket;
  final ApprovalBridge bridge;
  final _invalidated = Completer<void>();
  bool _closed = false;
  Timer? _watcher;
  bool _checking = false;
  @override
  String get requestId => ticket.requestId;
  @override
  Future<void> get invalidated => _invalidated.future;

  static Future<ResultActionApprovalScope?> open(
      AppDatabase db, String actionId,
      {Duration timeout = const Duration(minutes: 5),
      ApprovalBridge bridge = const ApprovalBridge()}) async {
    final store = ResultActionApprovalStore(db);
    final ticket = await store.open(actionId, timeout: timeout);
    return ticket == null
        ? null
        : ResultActionApprovalScope._(db, store, ticket, bridge);
  }

  ToolRisk get risk => ticket.risk == ResultActionRisk.high
      ? ToolRisk.dangerous
      : ToolRisk.requiresConfirmation;
  ToolCall get call =>
      ToolCall(id: ticket.actionId, name: ticket.callType, arguments: {
        'cardTitle': ticket.card.title,
        'resource': '${ticket.card.resourceType}/${ticket.card.resourceId}',
        'resourceVersion': ticket.card.resourceVersion,
        'actionId': ticket.actionId,
        'boundary': '仅本次、仅此资源版本；系统交接不代表接收方已保存',
      });
  Duration get remaining => ticket.expiresAt.difference(DateTime.now().toUtc());
  ResultActionApproval get approval => ResultActionApproval(
      approvalId: requestId,
      cardId: ticket.card.id,
      actionType: ticket.callType,
      grantedAt: DateTime.now().toUtc(),
      expiresAt: ticket.expiresAt);

  @override
  Future<bool> isCurrent() async =>
      !_closed && !_invalidated.isCompleted && await store.isCurrent(ticket);

  Future<ToolApproval> invoke(Future<ToolApproval> Function() body) async {
    Timer? deadline;
    try {
      if (!await isCurrent()) return ToolApproval.reject;
      _watcher = Timer.periodic(const Duration(milliseconds: 200), (_) async {
        if (_checking || _closed) return;
        _checking = true;
        try {
          if (!await isCurrent() && !_invalidated.isCompleted) {
            _invalidated.complete();
          }
        } catch (_) {
          // Missing/closed/maintenance-replaced DB is never approval authority.
          if (!_invalidated.isCompleted) _invalidated.complete();
        } finally {
          _checking = false;
        }
      });
      final expiry = Completer<ToolApproval>();
      deadline = Timer(remaining.isNegative ? Duration.zero : remaining,
          () => expiry.complete(ToolApproval.reject));
      final decision = await Future.any<ToolApproval>([
        body(),
        expiry.future,
        invalidated.then((_) => ToolApproval.reject),
      ]);
      if (!await isCurrent()) return ToolApproval.reject;
      // No allowSession/allowAlways escalation, including from a buggy caller.
      await db.decidePendingApproval(
          requestId,
          decision == ToolApproval.allowOnce
              ? approvalApproveAction
              : approvalDenyAction);
      final accepted = decision == ToolApproval.allowOnce &&
          await db.findPendingApprovalDecision(requestId) ==
              approvalApproveAction &&
          await isCurrent();
      await AuditService().logSecurityEvent(db,
          type: 'result_action_approval',
          detail: '${ticket.callType} request=$requestId',
          risk: risk.name,
          decision: accepted ? 'allowOnce' : 'reject');
      return accepted ? ToolApproval.allowOnce : ToolApproval.reject;
    } finally {
      deadline?.cancel();
      _watcher?.cancel();
    }
  }

  Future<void> close() async {
    _closed = true;
    _watcher?.cancel();
    if (!_invalidated.isCompleted) _invalidated.complete();
    await db.deletePendingApproval(requestId);
  }
}
