import '../../domain/models.dart';
import 'chat_message_codec.dart';
import 'session_event.dart';
import 'session_event_store.dart';

/// 从会话日志推导模型历史（Harness 的 deriveMessages 对应物）。
class SessionLogReader {
  /// [blobs]：附件哈希 → 内容，用 [load] 一并读取；缺失的附件解码为占位文本。
  SessionLogReader(List<SessionEvent> events,
      {Map<String, String> blobs = const {}})
      : _blobs = blobs,
        _events = List.unmodifiable(events),
        _messages = {
          for (final e in events)
            if (e.type == SessionEventType.message) e.seq: e,
        };

  /// 读取会话的全部事件及其引用的附件。
  static Future<SessionLogReader> load(
      SessionEventStore store, String conversationId) async {
    final events = await store.events(conversationId);
    final refs = {
      for (final e in events)
        if (e.type == SessionEventType.message)
          ...ChatMessageCodec.blobRefs(e.payload),
    };
    return SessionLogReader(events,
        blobs: refs.isEmpty ? const {} : await store.blobs(refs));
  }

  final Map<String, String> _blobs;
  final List<SessionEvent> _events;
  final Map<int, SessionEvent> _messages;

  List<SessionEvent> get events => _events;

  /// 把序号引用解析为消息。引用缺失说明日志损坏，直接抛出。
  List<ChatMessage> resolve(List<int> refs) => [
        for (final seq in refs)
          ChatMessageCodec.decode(
            (_messages[seq] ??
                    (throw StateError('会话日志缺少 message #$seq')))
                .payload,
            blobs: _blobs,
          ),
      ];

  /// 某次运行的全部模型请求（按发送顺序）。
  List<List<ChatMessage>> requestsFor(String runId) => [
        for (final e in _events)
          if (e.type == SessionEventType.requestSent && e.runId == runId)
            resolve(e.refs),
      ];

  /// 最近一次运行结束时的模型可见历史；没有已结束运行时返回 null。
  List<ChatMessage>? deriveMessages() {
    for (final e in _events.reversed) {
      if (e.type == SessionEventType.turnEnd) return resolve(e.refs);
    }
    return null;
  }

  /// 最近一次运行的结束状态（completed/paused/...），没有则为 null。
  String? get lastTurnStatus {
    for (final e in _events.reversed) {
      if (e.type == SessionEventType.turnEnd) {
        return e.payload['status'] as String?;
      }
    }
    return null;
  }

  /// 已开始但没有 turn/end 的运行（进程被杀、崩溃）。阶段 4 用它封口。
  List<String> get unsealedRuns {
    final started = <String>[];
    final ended = <String>{};
    for (final e in _events) {
      final runId = e.runId;
      if (runId == null) continue;
      if (e.type == SessionEventType.turnStart) started.add(runId);
      if (e.type == SessionEventType.turnEnd) ended.add(runId);
    }
    return [for (final r in started) if (!ended.contains(r)) r];
  }
}
