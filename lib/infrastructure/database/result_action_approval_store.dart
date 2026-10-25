import 'dart:convert';

import 'package:drift/drift.dart' show Variable;

import '../../domain/approval_action_codec.dart';
import '../../domain/result_card.dart';
import '../../domain/unique_id.dart';
import 'app_database.dart';
import 'result_action_store.dart';

// Per-isolate owner: approval DTOs from a previous app process/isolate are not
// resumable execution permission. Notification callbacks only decide the row.
final _owner = UniqueId.generate('result-approval-owner');

class ResultActionApprovalTicket {
  const ResultActionApprovalTicket(this.requestId, this.actionId, this.callType,
      this.risk, this.card, this.expiresAt);
  final String requestId;
  final String actionId;
  final String callType;
  final ResultActionRisk risk;
  final ResultCard card;
  final DateTime expiresAt;
}

/// Uses the existing pending_approvals channel, with a strict structured binding
/// in its private summary field. No new schema, no global or session grants.
class ResultActionApprovalStore implements ResultActionApprovalVerifier {
  ResultActionApprovalStore(this.db,
      {String? ownerId, DateTime Function()? now})
      : ownerId = ownerId ?? _owner,
        _now = now ?? DateTime.now;
  final AppDatabase db;
  final String ownerId;
  final DateTime Function() _now;

  Future<ResultActionApprovalTicket?> open(String actionId,
      {Duration timeout = const Duration(minutes: 5)}) async {
    if (timeout <= Duration.zero || timeout > const Duration(minutes: 5)) {
      return null;
    }
    return db.transaction(() async {
      final repo = SqlResultActionRepository(db);
      final action = await repo.findAction(actionId);
      if (action == null ||
          action.status != ResultActionStatus.pendingConfirm ||
          (action.approvalId ?? '').isNotEmpty ||
          action.everExecuted) {
        return null;
      }
      final spec = ResultActionRegistry.find(action.actionType);
      final card = await repo.findCard(action.cardId);
      if (spec == null ||
          !spec.requiresConfirmation ||
          spec.risk != action.risk ||
          card == null ||
          card.kind != spec.kind ||
          !card.referencesRealResource ||
          card.status != ResultCardStatus.active ||
          card.revision != action.cardRevision) {
        return null;
      }
      final requestId = UniqueId.generate('result-appr');
      await db.insertPendingApproval(
          requestId: requestId,
          toolName: action.actionType,
          risk: action.risk.wireName,
          ttl: timeout,
          summary: jsonEncode({
            'type': 'result_action',
            'schema': 1,
            'owner': ownerId,
            'actionId': action.id,
            'actionRevision': action.revision,
            'cardId': card.id,
            'cardRevision': card.revision,
            'resourceType': card.resourceType,
            'resourceId': card.resourceId,
            'resourceVersion': card.resourceVersion,
            'actionType': spec.actionType,
          }));
      final row = await _row(requestId);
      return ResultActionApprovalTicket(
          requestId,
          actionId,
          action.actionType,
          action.risk,
          card,
          DateTime.parse(row!['expires_at'] as String).toUtc());
    });
  }

  Future<Map<String, dynamic>?> _row(String id) async {
    final row = await db.customSelect(
        'SELECT * FROM pending_approvals WHERE request_id=?',
        variables: [Variable(id)]).getSingleOrNull();
    return row?.data;
  }

  bool _matches(
      Map<String, dynamic> row, ResultActionRecord action, ResultCard card,
      {bool forExecution = false}) {
    try {
      final binding = jsonDecode(row['summary'] as String);
      final deadline = DateTime.parse(row['expires_at'] as String).toUtc();
      final approvedRevision = action.approvalId == row['request_id'];
      final revision = binding['actionRevision'];
      return binding is Map &&
          binding['type'] == 'result_action' &&
          binding['schema'] == 1 &&
          binding['owner'] == ownerId &&
          revision is int &&
          binding['actionId'] == action.id &&
          binding['cardId'] == card.id &&
          action.cardId == card.id &&
          binding['cardRevision'] == card.revision &&
          action.cardRevision == card.revision &&
          card.status == ResultCardStatus.active &&
          binding['resourceType'] == card.resourceType &&
          binding['resourceId'] == card.resourceId &&
          binding['resourceVersion'] == card.resourceVersion &&
          binding['actionType'] == action.actionType &&
          row['tool_name'] == action.actionType &&
          row['risk'] == action.risk.wireName &&
          (forExecution
              ? action.status == ResultActionStatus.running &&
                  action.attempts == 1 &&
                  approvedRevision &&
                  action.revision == revision + 2
              : action.status == ResultActionStatus.pendingConfirm &&
                  !action.everExecuted &&
                  action.revision == revision + (approvedRevision ? 1 : 0)) &&
          ((action.approvalId ?? '').isEmpty || approvedRevision) &&
          _now().toUtc().isBefore(deadline);
    } catch (_) {
      // Corrupt/missing/tampered binding is not approval authority.
      return false;
    }
  }

  Future<bool> isCurrent(ResultActionApprovalTicket ticket) async {
    final repo = SqlResultActionRepository(db);
    final action = await repo.findAction(ticket.actionId);
    final card = action == null ? null : await repo.findCard(action.cardId);
    final row = await _row(ticket.requestId);
    return action != null &&
        card != null &&
        row != null &&
        _matches(row, action, card);
  }

  @override
  Future<bool> verify(
      {required ResultActionRecord action,
      required ResultCard card,
      required String approvalId,
      required DateTime expiresAt,
      bool forExecution = false}) async {
    final row = await _row(approvalId);
    return row != null &&
        row['decision'] == approvalApproveAction &&
        _matches(row, action, card, forExecution: forExecution) &&
        DateTime.tryParse(row['expires_at'] as String)?.toUtc() ==
            expiresAt.toUtc();
  }
}
