import 'dart:convert';

/// 会话日志事件类型（阶段 1 词汇）。
///
/// 会话日志是追加式的：事件一经写入不再修改。模型看到的一切都必须能从日志
/// 重建——`message` 事件保存模型可见的消息内容（按内容去重，只写一次），
/// `request/sent` 以序号引用这些消息，精确描述每一次模型请求。
abstract final class SessionEventType {
  /// 一次 AgentExecutor.run() 开始。payload: {runId, model}
  static const turnStart = 'turn/start';

  /// 一条模型可见的消息首次出现。payload: ChatMessageCodec 编码结果。
  static const message = 'message';

  /// 一次模型请求。payload: {step, refs:[seq...], model, toolsHash, ...}
  static const requestSent = 'request/sent';

  /// 运行结束。payload: {status, refs?:[seq...], error?}
  ///
  /// status 取值：completed / paused / cancelled / failed / interrupted。
  /// paused 时 refs 为可续跑的完整上下文。
  static const turnEnd = 'turn/end';
}

/// 一条已持久化（或待持久化）的会话日志事件。
class SessionEvent {
  const SessionEvent({
    required this.conversationId,
    required this.seq,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.runId,
    this.contentKey,
    this.formatVersion = currentFormatVersion,
  });

  /// 事件 payload 的格式版本；将来调整格式时走相邻版本迁移链。
  static const currentFormatVersion = 1;

  final String conversationId;

  /// 会话内单调递增的序号，从 1 开始。
  final int seq;
  final String type;
  final String? runId;

  /// 仅 `message` 事件：模型可见内容的哈希，用于跨运行去重。
  final String? contentKey;
  final Map<String, dynamic> payload;
  final int formatVersion;
  final DateTime createdAt;

  String get payloadJson => jsonEncode(payload);

  List<int> get refs => switch (payload['refs']) {
        final List<dynamic> list => list.cast<num>().map((n) => n.toInt()).toList(),
        _ => const <int>[],
      };
}
