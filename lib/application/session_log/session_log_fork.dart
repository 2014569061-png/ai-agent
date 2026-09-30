import '../../domain/models.dart';
import '../../infrastructure/database/app_database.dart';
import 'chat_message_codec.dart';
import 'legacy_import.dart';
import 'session_event.dart';
import 'session_event_store.dart';
import 'session_log_reader.dart';

/// 分支日志是怎么建立的。
enum SessionLogForkKind {
  /// 在原会话某个 turn/end 处分叉：复制模型当时可见的完整历史（含 system、附件）。
  boundary,

  /// 分叉点不在 turn 边界（或原会话没有日志）：从分支已复制的 Messages 行导入。
  imported,

  /// 分支已有日志，什么都没做。
  skipped,
}

/// 会话分叉时为分支建立会话日志。
///
/// Messages 表仍是分叉的依据：先由 ConversationForkService 复制行，再在原日志中
/// 找历史与这些行逐条对应（[SessionLogShadowCheck.sameMessage]）的 turn/end；找不到就退回导入。
class SessionLogForker {
  SessionLogForker(this.db, this.store);

  final AppDatabase db;
  final SessionEventStore store;

  static String forkRunId(String branchId) => 'fork:$branchId';

  Future<SessionLogForkKind> fork({
    required String sourceConversationId,
    required String branchConversationId,
  }) async {
    if ((await store.events(branchConversationId)).isNotEmpty) {
      return SessionLogForkKind.skipped;
    }
    final copied = [
      for (final row in await db.messagesFor(branchConversationId))
        chatMessageFromRow(row),
    ];
    final source = await SessionLogReader.load(store, sourceConversationId);
    for (final end in source.events.reversed) {
      if (end.type != SessionEventType.turnEnd) continue;
      final history = source.resolve(end.refs);
      final visible = [
        for (final m in history)
          if (m.role != MessageRole.system) m,
      ];
      if (SessionLogShadowCheck.firstMismatch(visible, copied) != null) {
        continue;
      }
      await _writeBoundaryFork(
        branchConversationId,
        history,
        parentConversationId: sourceConversationId,
        parentSeq: end.seq,
        parentRunId: end.runId,
      );
      return SessionLogForkKind.boundary;
    }
    final imported =
        await LegacySessionImporter(db, store).importConversation(branchConversationId);
    return imported ? SessionLogForkKind.imported : SessionLogForkKind.skipped;
  }

  Future<void> _writeBoundaryFork(
    String branchId,
    List<ChatMessage> history, {
    required String parentConversationId,
    required int parentSeq,
    required String? parentRunId,
  }) async {
    final runId = forkRunId(branchId);
    final events = <NewSessionEvent>[
      (
        type: SessionEventType.turnStart,
        payload: {
          'runId': runId,
          'model': 'fork',
          'forked': true,
          'parentConversationId': parentConversationId,
          'parentSeq': parentSeq,
          if (parentRunId != null) 'parentRunId': parentRunId,
        },
        runId: runId,
        contentKey: null,
      ),
    ];
    final blobs = <String, SessionBlobData>{};
    final seqByKey = <String, int>{};
    final refs = <int>[];
    for (final message in history) {
      final key = ChatMessageCodec.contentKey(message);
      final known = seqByKey[key];
      if (known != null) {
        refs.add(known);
        continue;
      }
      final encoded = ChatMessageCodec.encodeForLog(message);
      blobs.addAll(encoded.blobs);
      events.add((
        type: SessionEventType.message,
        payload: encoded.payload,
        runId: runId,
        contentKey: key,
      ));
      seqByKey[key] = events.length;
      refs.add(events.length);
    }
    events.add((
      type: SessionEventType.turnEnd,
      payload: {'status': 'forked', 'refs': refs},
      runId: runId,
      contentKey: null,
    ));
    // 附件先登记到分支名下：原会话删除后分支仍保有引用。
    if (blobs.isNotEmpty) await store.putBlobs(branchId, blobs);
    await store.appendAllIfEmpty(branchId, events);
  }
}
