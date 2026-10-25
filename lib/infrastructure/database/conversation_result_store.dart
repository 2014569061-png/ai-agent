import 'dart:convert';

import 'package:drift/drift.dart' show Variable;

import '../../domain/result_card.dart';
import 'app_database.dart';
import 'result_action_store.dart';

/// A captured UI scope, never a model-provided grant. Empty project means the
/// non-project conversation only, not all projects. turnId is a run ID here.
class ConversationResultScope {
  ConversationResultScope(this.conversationId,
      {String? projectId, this.taskId, this.runId})
      : projectId = normalizeProject(projectId);
  final String conversationId;
  final String projectId;
  final String? taskId, runId;
  static String normalizeProject(String? value) => value?.trim() ?? '';
  String get key => jsonEncode([conversationId, projectId, taskId, runId]);
}

class ConversationResultCursor {
  const ConversationResultCursor(this.scopeKey, this.createdAt, this.id);
  final String scopeKey, createdAt, id;
}

class ConversationResultPage {
  const ConversationResultPage(this.items, this.next);
  final List<ResultCard> items;
  final ConversationResultCursor? next;
}

/// Scoped facade over the same durable result repository and CAS mechanism.
/// All reads AND writes recheck ownership; possession of a card/action ID alone
/// is insufficient. No second execution or approval engine is introduced.
class ConversationResultRepository
    implements ConditionalResultActionRepository {
  ConversationResultRepository(this.db, this.scope)
      : base = SqlResultActionRepository(db);
  @override
  final AppDatabase db;
  final ConversationResultScope scope;
  final SqlResultActionRepository base;

  String get _where => '''
r.task_id IN (SELECT t.id FROM tasks t JOIN conversations c ON c.id=t.conversation_id
 WHERE c.id=? AND COALESCE(TRIM(c.project_id),'')=?
 AND COALESCE(TRIM(t.project_id),'')=?)
${scope.taskId == null ? '' : 'AND r.task_id=?'}
${scope.runId == null ? '' : 'AND r.turn_id=?'}
AND (r.resource_type!='artifact' OR EXISTS (
 SELECT 1 FROM artifacts a WHERE a.id=r.resource_id AND a.task_id=r.task_id
 AND a.run_id=r.turn_id AND COALESCE(TRIM(a.project_id),'')=?))
''';
  List<Variable> get _variables => [
        Variable(scope.conversationId),
        Variable(scope.projectId),
        Variable(scope.projectId),
        if (scope.taskId != null) Variable(scope.taskId!),
        if (scope.runId != null) Variable(scope.runId!),
        Variable(scope.projectId),
      ];

  Future<ConversationResultPage> page(
      {ConversationResultCursor? after,
      int limit = 10,
      ResultCardKind? kind}) async {
    if (limit < 1 || limit > 50) throw ArgumentError('Page limit 1..50');
    final key = '${scope.key}:${kind?.wireName ?? '*'}';
    if (after != null && after.scopeKey != key) {
      throw ArgumentError('Cursor belongs to another result scope');
    }
    if (scope.conversationId.trim().isEmpty) {
      return const ConversationResultPage([], null);
    }
    return db.transaction(() async {
      final rows = await db.customSelect('''
SELECT r.id, COALESCE(r.created_at,'') AS stamp FROM result_cards r
WHERE $_where
${kind == null ? '' : 'AND r.kind=?'}
${after == null ? '' : "AND (COALESCE(r.created_at,'') < ? OR (COALESCE(r.created_at,'') = ? AND r.id < ?))"}
ORDER BY COALESCE(r.created_at,'') DESC, r.id DESC LIMIT ?
''', variables: [
        ..._variables,
        if (kind != null) Variable(kind.wireName),
        if (after != null) ...[
          Variable(after.createdAt),
          Variable(after.createdAt),
          Variable(after.id)
        ],
        Variable(limit + 1),
      ]).get();
      final visible = rows.take(limit).toList();
      final cards = <ResultCard>[];
      for (final row in visible) {
        final card = await base.findCard(row.read<String>('id'));
        if (card != null) cards.add(card);
      }
      final last = visible.lastOrNull;
      return ConversationResultPage(
          cards,
          rows.length > limit && last != null
              ? ConversationResultCursor(
                  key, last.read<String>('stamp'), last.read<String>('id'))
              : null);
    });
  }

  @override
  Future<ResultCard?> findCard(String cardId) => db.transaction(() async {
        if (scope.conversationId.trim().isEmpty) return null;
        final row = await db.customSelect(
            'SELECT r.id FROM result_cards r WHERE $_where AND r.id=?',
            variables: [..._variables, Variable(cardId)]).getSingleOrNull();
        return row == null ? null : base.findCard(cardId);
      });

  @override
  Future<List<ResultCard>> listCards(
          {ResultCardKind? kind, int limit = 50}) async =>
      (await page(kind: kind, limit: limit)).items;

  @override
  Future<ResultActionRecord?> findAction(String actionId) async {
    final action = await base.findAction(actionId);
    return action != null && await findCard(action.cardId) != null
        ? action
        : null;
  }

  @override
  Future<ResultActionRecord?> findActionByIdempotencyKey(String key) async {
    final action = await base.findActionByIdempotencyKey(key);
    return action != null && await findCard(action.cardId) != null
        ? action
        : null;
  }

  @override
  Future<List<ResultActionRecord>> listActions(String cardId) async =>
      await findCard(cardId) == null ? [] : base.listActions(cardId);

  @override
  Future<void> saveCard(ResultCard card) => db.transaction(() async {
        final existing = await findCard(card.id);
        if (existing == null ||
            existing.taskId != card.taskId ||
            existing.turnId != card.turnId ||
            existing.resourceType != card.resourceType ||
            existing.resourceId != card.resourceId) {
          throw StateError('Result no longer belongs to captured scope');
        }
        await base.saveCard(card);
      });
  @override
  Future<void> saveAction(ResultActionRecord action) =>
      db.transaction(() async {
        final card = await findCard(action.cardId);
        if (card == null || card.revision != action.cardRevision) {
          throw StateError('Result no longer belongs to captured scope');
        }
        await base.saveAction(action);
      });
  @override
  Future<bool> compareAndSaveAction(ResultActionRecord action,
          {required int expectedRevision,
          ResultCard? expectedCard,
          Future<bool> Function()? authorize}) =>
      base.compareAndSaveAction(action,
          expectedRevision: expectedRevision,
          expectedCard: expectedCard,
          authorize: () async =>
              await findCard(action.cardId) != null &&
              (authorize == null || await authorize()));
}
