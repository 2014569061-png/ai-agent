import '../../domain/models.dart';
import 'chat_message_codec.dart';
import 'session_event.dart';

/// 从会话日志推导模型历史（Harness 的 deriveMessages 对应物）。
class SessionLogReader {
  SessionLogReader(List<SessionEvent> events)
      : _events = List.unmodifiable(events),
        _messages = {
          for (final e in events)
            if (e.type == SessionEventType.message) e.seq: e,
        };

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
