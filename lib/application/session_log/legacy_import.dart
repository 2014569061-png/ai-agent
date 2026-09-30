import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Variable;

import '../../domain/models.dart';
import '../../infrastructure/database/app_database.dart';
import '../mojibake_repair.dart';
import 'chat_message_codec.dart';
import 'session_event.dart';
import 'session_event_store.dart';
import 'session_log_reader.dart';

/// Messages 表的一行 → 模型可见的 ChatMessage（一行对应一条，含工具调用）。
///
/// 文本经 [MojibakeRepair] 修复，与聊天恢复历史时的处理一致。
ChatMessage chatMessageFromRow(Message row) => ChatMessage(
      id: row.id,
      role: MessageRole.values.firstWhere((role) => role.name == row.role,
          orElse: () => MessageRole.assistant),
      toolCallId: row.toolCallId,
      parts: [MessagePart.text(MojibakeRepair.repair(row.content))],
      toolCalls: _decodeToolCalls(row.toolCallsJson),
      reasoning: row.reasoningContent == null
          ? null
          : MojibakeRepair.repair(row.reasoningContent!),
    );

List<ToolCall> _decodeToolCalls(String? json) {
  if (json == null || json.isEmpty) return const [];
  try {
    return [
      for (final item
          in (jsonDecode(json) as List<dynamic>).whereType<Map<String, dynamic>>())
        ToolCall(
          id: item['id'] as String? ?? '',
          name: item['name'] as String? ?? '',
          arguments: item['arguments'] as Map<String, dynamic>? ?? const {},
          providerMetadata: item['providerMetadata'] is Map
              ? Map<String, dynamic>.from(item['providerMetadata'] as Map)
              : const {},
        ),
    ];
  } on Object {
    return const [];
  }
}

/// 把只存在于 Messages 表的旧会话导入会话日志：一次合成运行
/// （turn/start → message… → turn/end status=imported，refs 为全部消息）。
///
/// 幂等：会话已有任何日志事件时不做任何事。
class LegacySessionImporter {
  LegacySessionImporter(this.db, this.store);

  final AppDatabase db;
  final SessionEventStore store;

  static String importRunId(String conversationId) => 'import:$conversationId';

  /// 返回是否真的导入了。
  Future<bool> importConversation(String conversationId) async {
    final rows = await db.messagesFor(conversationId);
    if (rows.isEmpty) return false;
    final runId = importRunId(conversationId);
    final events = <NewSessionEvent>[
      (
        type: SessionEventType.turnStart,
        payload: {'runId': runId, 'model': 'legacy-import', 'imported': true},
        runId: runId,
        contentKey: null,
      ),
    ];
    final seqByKey = <String, int>{};
    final refs = <int>[];
    for (final row in rows) {
      final message = chatMessageFromRow(row);
      final key = ChatMessageCodec.contentKey(message);
      final known = seqByKey[key];
      if (known != null) {
        refs.add(known);
        continue;
      }
      events.add((
        type: SessionEventType.message,
        payload: ChatMessageCodec.encode(message),
        runId: runId,
        contentKey: key,
      ));
      seqByKey[key] = events.length;
      refs.add(events.length);
    }
    events.add((
      type: SessionEventType.turnEnd,
      payload: {'status': 'imported', 'refs': refs, 'rowCount': rows.length},
      runId: runId,
      contentKey: null,
    ));
    return store.appendAllIfEmpty(conversationId, events);
  }

  /// 导入最多 [limit] 个尚无日志的会话，返回导入数量。
  Future<int> importPending({int limit = 20}) async {
    final rows = await db.customSelect(
      'SELECT DISTINCT m.conversation_id AS id FROM messages m '
      'WHERE NOT EXISTS (SELECT 1 FROM session_events s '
      'WHERE s.conversation_id = m.conversation_id) LIMIT ?',
      variables: [Variable<int>(limit)],
    ).get();
    var imported = 0;
    for (final row in rows) {
      if (await importConversation(row.read<String>('id'))) imported++;
    }
    return imported;
  }
}

/// 影子比对结果：日志推导的历史（去掉 system）与 Messages 表逐条比较。
class ShadowComparison {
  const ShadowComparison({
    required this.conversationId,
    required this.loggedCount,
    required this.storedCount,
    this.firstMismatch,
    this.logged,
    this.stored,
  });

  final String conversationId;
  final int loggedCount;
  final int storedCount;

  /// 第一处不一致的下标；一致时为 null。
  final int? firstMismatch;

  /// 不一致处两边消息的描述（角色|工具调用 ID|长度|摘要），不含正文。
  final String? logged;
  final String? stored;

  bool get matches => firstMismatch == null;

  Map<String, dynamic> toJson() => {
        'conversationId': conversationId,
        'loggedCount': loggedCount,
        'storedCount': storedCount,
        if (firstMismatch != null) 'firstMismatch': firstMismatch,
        if (logged != null) 'logged': logged,
        if (stored != null) 'stored': stored,
      };
}

/// 阶段 4 切换读路径前的依据：持续确认日志与 Messages 表一致。
abstract final class SessionLogShadowCheck {
  /// 比较时每条消息的视图：角色、工具调用 ID、工具调用名与文本。
  static String view(ChatMessage m) => [
        m.role.name,
        m.toolCallId ?? '',
        m.toolCalls.map((c) => c.name).join(','),
        m.text,
      ].join('|');

  /// 会话还没有已结束的运行时返回 null。
  static Future<ShadowComparison?> compare(
      AppDatabase db, SessionEventStore store, String conversationId) async {
    final derived =
        SessionLogReader(await store.events(conversationId)).deriveMessages();
    if (derived == null) return null;
    final logged = [
      for (final m in derived)
        if (m.role != MessageRole.system) view(m),
    ];
    final stored = [
      for (final row in await db.messagesFor(conversationId))
        view(chatMessageFromRow(row)),
    ];
    final common =
        logged.length < stored.length ? logged.length : stored.length;
    int? mismatch;
    for (var i = 0; i < common; i++) {
      if (logged[i] != stored[i]) {
        mismatch = i;
        break;
      }
    }
    if (mismatch == null && logged.length != stored.length) mismatch = common;
    String? describe(List<String> list) =>
        mismatch != null && mismatch < list.length
            ? _describe(list[mismatch])
            : null;
    return ShadowComparison(
      conversationId: conversationId,
      loggedCount: logged.length,
      storedCount: stored.length,
      firstMismatch: mismatch,
      logged: describe(logged),
      stored: describe(stored),
    );
  }

  /// 比较最近更新的 [limit] 个有日志的会话，只返回不一致的。
  static Future<List<ShadowComparison>> compareRecent(
      AppDatabase db, SessionEventStore store,
      {int limit = 20}) async {
    final rows = await db.customSelect(
      'SELECT c.id AS id FROM conversations c WHERE EXISTS ('
      'SELECT 1 FROM session_events s WHERE s.conversation_id = c.id) '
      'ORDER BY c.updated_at DESC LIMIT ?',
      variables: [Variable<int>(limit)],
    ).get();
    final mismatches = <ShadowComparison>[];
    for (final row in rows) {
      final result = await compare(db, store, row.read<String>('id'));
      if (result != null && !result.matches) mismatches.add(result);
    }
    return mismatches;
  }

  // 诊断信息不含对话正文：只保留角色、工具调用 ID、长度与摘要。
  static String _describe(String view) {
    final parts = view.split('|');
    final digest = sha256.convert(utf8.encode(view)).toString().substring(0, 8);
    return '${parts[0]}|${parts[1]}|len=${view.length}|$digest';
  }
}
