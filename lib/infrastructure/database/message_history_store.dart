import 'package:drift/drift.dart';
import 'app_database.dart';

/// Message-range operations share the same (created_at, rowid) ordering.
class MessageHistoryStore {
  MessageHistoryStore(this.db);
  final AppDatabase db;

  Future<QueryRow> _anchor(String conversationId, String id) async {
    final rows = await db.customSelect(
      'SELECT created_at, rowid AS anchor_rowid FROM messages '
      'WHERE conversation_id = ? AND id = ?',
      variables: [Variable<String>(conversationId), Variable<String>(id)],
      readsFrom: {db.messages},
    ).get();
    if (rows.isEmpty) throw StateError('消息不存在或已被删除');
    return rows.single;
  }

  List<Variable> _range(String conversationId, QueryRow anchor) => [
        Variable<String>(conversationId),
        Variable<int>(anchor.read<int>('created_at')),
        Variable<int>(anchor.read<int>('created_at')),
        Variable<int>(anchor.read<int>('anchor_rowid')),
      ];

  Future<void> editAndTruncate(
          String conversationId, String id, String content) =>
      db.transaction(() async {
        final anchor = await _anchor(conversationId, id);
        await (db.update(db.messages)
              ..where((m) =>
                  m.conversationId.equals(conversationId) & m.id.equals(id)))
            .write(MessagesCompanion(content: Value(content)));
        await db.customUpdate(
          'DELETE FROM messages WHERE conversation_id = ? '
          'AND (created_at > ? OR (created_at = ? AND rowid > ?))',
          variables: _range(conversationId, anchor),
          updates: {db.messages},
          updateKind: UpdateKind.delete,
        );
      });

  Future<void> deleteTrailing(String conversationId) =>
      db.transaction(() async {
        final last = await db.customSelect(
          "SELECT id FROM messages WHERE conversation_id = ? AND role = 'user' "
          'ORDER BY created_at DESC, rowid DESC LIMIT 1',
          variables: [Variable<String>(conversationId)],
          readsFrom: {db.messages},
        ).get();
        if (last.isEmpty) return;
        final anchor =
            await _anchor(conversationId, last.single.read<String>('id'));
        await db.customUpdate(
          "DELETE FROM messages WHERE conversation_id = ? AND role IN ('assistant','tool') "
          'AND (created_at > ? OR (created_at = ? AND rowid > ?))',
          variables: _range(conversationId, anchor),
          updates: {db.messages},
          updateKind: UpdateKind.delete,
        );
      });

  Future<void> copyThrough(
      String sourceId, String messageId, String branchId) async {
    final anchor = await _anchor(sourceId, messageId);
    await db.customInsert(
      'INSERT INTO messages (id, conversation_id, role, content, tool_call_id, '
      'tool_calls_json, reasoning_content, display_metadata_json, created_at) '
      'SELECT ? || id, ?, role, content, tool_call_id, tool_calls_json, '
      'reasoning_content, display_metadata_json, created_at FROM messages WHERE conversation_id = ? '
      'AND (created_at < ? OR (created_at = ? AND rowid <= ?)) '
      'ORDER BY created_at ASC, rowid ASC',
      variables: [
        Variable<String>('$branchId:'),
        Variable<String>(branchId),
        ..._range(sourceId, anchor)
      ],
      updates: {db.messages},
    );
  }
}
