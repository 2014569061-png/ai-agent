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

  /// 所有会话中已有 turn/start、但没有 turn/end 的运行。
  Future<List<UnsealedRun>> unsealedRuns();

  /// 会话为空时原子地写入一批事件（seq 从 1 起依次分配）；会话已有事件
  /// 则什么都不写并返回 false。用于旧数据导入，避免与并发运行交错。
  Future<bool> appendAllIfEmpty(
      String conversationId, List<NewSessionEvent> events);
}

/// 待写入的事件（seq 由存储分配）。
typedef NewSessionEvent = ({
  String type,
  Map<String, dynamic> payload,
  String? runId,
  String? contentKey,
});

/// 未封口的运行（进程被杀、崩溃，或仍在其他 isolate 中运行）。
class UnsealedRun {
  const UnsealedRun({
    required this.conversationId,
    required this.runId,
    required this.lastActivity,
  });

  final String conversationId;
  final String runId;

  /// 该运行最后一条事件的写入时间。
  final DateTime lastActivity;
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

  @override
  Future<bool> appendAllIfEmpty(
      String conversationId, List<NewSessionEvent> events) async {
    if (_byConversation[conversationId]?.isNotEmpty ?? false) return false;
    for (final e in events) {
      await append(
        conversationId: conversationId,
        type: e.type,
        payload: e.payload,
        runId: e.runId,
        contentKey: e.contentKey,
      );
    }
    return true;
  }

  @override
  Future<List<UnsealedRun>> unsealedRuns() async {
    final result = <UnsealedRun>[];
    for (final MapEntry(key: conversationId, value: events)
        in _byConversation.entries) {
      final last = <String, DateTime>{};
      final started = <String>{};
      final ended = <String>{};
      for (final e in events) {
        final runId = e.runId;
        if (runId == null) continue;
        last[runId] = e.createdAt;
        if (e.type == SessionEventType.turnStart) started.add(runId);
        if (e.type == SessionEventType.turnEnd) ended.add(runId);
      }
      for (final runId in started.difference(ended)) {
        result.add(UnsealedRun(
          conversationId: conversationId,
          runId: runId,
          lastActivity: last[runId]!,
        ));
      }
    }
    return result;
  }
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

  @override
  Future<bool> appendAllIfEmpty(
      String conversationId, List<NewSessionEvent> events) {
    return _db.transaction(() async {
      final existing = await _db.customSelect(
        'SELECT 1 FROM session_events WHERE conversation_id = ? LIMIT 1',
        variables: [Variable<String>(conversationId)],
      ).getSingleOrNull();
      if (existing != null) return false;
      final now = DateTime.now();
      var seq = 0;
      for (final e in events) {
        seq++;
        final event = SessionEvent(
          conversationId: conversationId,
          seq: seq,
          type: e.type,
          runId: e.runId,
          contentKey: e.contentKey,
          payload: e.payload,
          createdAt: now,
        );
        await _db.customInsert(
          'INSERT INTO session_events (conversation_id, seq, type, run_id, '
          'content_key, payload_json, format_version, created_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          variables: [
            Variable<String>(conversationId),
            Variable<int>(seq),
            Variable<String>(e.type),
            Variable<String>(e.runId),
            Variable<String>(e.contentKey),
            Variable<String>(event.payloadJson),
            Variable<int>(event.formatVersion),
            Variable<String>(now.toUtc().toIso8601String()),
          ],
        );
      }
      return true;
    });
  }

  @override
  Future<List<UnsealedRun>> unsealedRuns() async {
    final rows = await _db.customSelect(
      'SELECT s.conversation_id AS conversation_id, s.run_id AS run_id, '
      'MAX(e.created_at) AS last_at '
      'FROM session_events s '
      'JOIN session_events e '
      'ON e.conversation_id = s.conversation_id AND e.run_id = s.run_id '
      "WHERE s.type = '${SessionEventType.turnStart}' AND NOT EXISTS ("
      'SELECT 1 FROM session_events t '
      'WHERE t.conversation_id = s.conversation_id AND t.run_id = s.run_id '
      "AND t.type = '${SessionEventType.turnEnd}') "
      'GROUP BY s.conversation_id, s.run_id',
    ).get();
    return [
      for (final row in rows)
        UnsealedRun(
          conversationId: row.read<String>('conversation_id'),
          runId: row.read<String>('run_id'),
          lastActivity: DateTime.parse(row.read<String>('last_at')),
        ),
    ];
  }
}
