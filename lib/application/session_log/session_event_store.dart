import 'dart:convert';

import 'package:drift/drift.dart';

import '../../infrastructure/database/app_database.dart';
import 'session_event.dart';

/// 会话日志存储。实现必须保证：同一会话内 seq 从 1 开始连续递增，
/// 已写入的事件不再修改。
abstract interface class SessionEventStore {
  Future<SessionEvent> append({
    required String conversationId,
    required String type,
    required Map<String, dynamic> payload,
    String? runId,
    String? contentKey,
  });

  /// 会话内已记录消息的 contentKey → seq（每个 key 取最早的一条）。
  Future<Map<String, int>> messageKeys(String conversationId);

  /// 会话全部事件，按 seq 升序。
  Future<List<SessionEvent>> events(String conversationId);
}

/// 测试与无数据库场景使用的内存实现。
class InMemorySessionEventStore implements SessionEventStore {
  final Map<String, List<SessionEvent>> _byConversation = {};

  @override
  Future<SessionEvent> append({
    required String conversationId,
    required String type,
    required Map<String, dynamic> payload,
    String? runId,
    String? contentKey,
  }) async {
    final list = _byConversation.putIfAbsent(conversationId, () => []);
    final event = SessionEvent(
      conversationId: conversationId,
      seq: list.length + 1,
      type: type,
      runId: runId,
      contentKey: contentKey,
      // 与持久化实现一致：payload 以 JSON 往返，避免调用方后续修改原对象。
      payload: Map<String, dynamic>.from(
          jsonDecode(jsonEncode(payload)) as Map),
      createdAt: DateTime.now(),
    );
    list.add(event);
    return event;
  }

  @override
  Future<Map<String, int>> messageKeys(String conversationId) async {
    final result = <String, int>{};
    for (final event in _byConversation[conversationId] ?? const []) {
      final key = event.contentKey;
      if (key != null) result.putIfAbsent(key, () => event.seq);
    }
    return result;
  }

  @override
  Future<List<SessionEvent>> events(String conversationId) async =>
      List.unmodifiable(_byConversation[conversationId] ?? const []);
}

/// 基于 `session_events` 裸 SQL 表的持久化实现（建表见
/// AppDatabase.ensureSessionEventsTable）。
class DriftSessionEventStore implements SessionEventStore {
  DriftSessionEventStore(this._db);

  final AppDatabase _db;

  @override
  Future<SessionEvent> append({
    required String conversationId,
    required String type,
    required Map<String, dynamic> payload,
    String? runId,
    String? contentKey,
  }) {
    return _db.transaction(() async {
      final row = await _db.customSelect(
        'SELECT COALESCE(MAX(seq), 0) + 1 AS next '
        'FROM session_events WHERE conversation_id = ?',
        variables: [Variable<String>(conversationId)],
      ).getSingle();
      final seq = row.read<int>('next');
      final now = DateTime.now();
      final event = SessionEvent(
        conversationId: conversationId,
        seq: seq,
        type: type,
        runId: runId,
        contentKey: contentKey,
        payload: payload,
        createdAt: now,
      );
      await _db.customInsert(
        'INSERT INTO session_events (conversation_id, seq, type, run_id, '
        'content_key, payload_json, format_version, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        variables: [
          Variable<String>(conversationId),
          Variable<int>(seq),
          Variable<String>(type),
          Variable<String>(runId),
          Variable<String>(contentKey),
          Variable<String>(event.payloadJson),
          Variable<int>(event.formatVersion),
          Variable<String>(now.toUtc().toIso8601String()),
        ],
      );
      return event;
    });
  }

  @override
  Future<Map<String, int>> messageKeys(String conversationId) async {
    final rows = await _db.customSelect(
      'SELECT content_key, MIN(seq) AS seq FROM session_events '
      'WHERE conversation_id = ? AND content_key IS NOT NULL '
      'GROUP BY content_key',
      variables: [Variable<String>(conversationId)],
    ).get();
    return {
      for (final row in rows)
        row.read<String>('content_key'): row.read<int>('seq'),
    };
  }

  @override
  Future<List<SessionEvent>> events(String conversationId) async {
    final rows = await _db.customSelect(
      'SELECT * FROM session_events WHERE conversation_id = ? ORDER BY seq',
      variables: [Variable<String>(conversationId)],
    ).get();
    return [
      for (final row in rows)
        SessionEvent(
          conversationId: row.read<String>('conversation_id'),
          seq: row.read<int>('seq'),
          type: row.read<String>('type'),
          runId: row.readNullable<String>('run_id'),
          contentKey: row.readNullable<String>('content_key'),
          payload: Map<String, dynamic>.from(
              jsonDecode(row.read<String>('payload_json')) as Map),
          formatVersion: row.read<int>('format_version'),
          createdAt: DateTime.parse(row.read<String>('created_at')),
        ),
    ];
  }
}
