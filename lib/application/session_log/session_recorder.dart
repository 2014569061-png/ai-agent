import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/models.dart';
import '../agent_executor.dart';
import 'chat_message_codec.dart';
import 'session_event.dart';
import 'session_event_store.dart';

/// 把一次 AgentExecutor.run() 记录进会话日志（阶段 1：与 Messages 表双写）。
///
/// 用法：
/// ```dart
/// final recorder = SessionRecorder(store: s, conversationId: c, runId: r, model: m)..start();
/// await for (final e in executor.run(..., onRequest: recorder.onRequest)) {
///   recorder.observe(e);
///   ...
/// }
/// await recorder.flush();
/// ```
///
/// 记录器**永远不影响运行**：所有写入在后台串行队列里执行，任何存储错误
/// 只计数并交给 [onError]，不会抛回执行器或 UI。
class SessionRecorder {
  SessionRecorder({
    required this.store,
    required this.conversationId,
    required this.runId,
    required this.model,
    this.onError,
  });

  final SessionEventStore store;
  final String conversationId;
  final String runId;
  final String model;
  final void Function(Object error, StackTrace stack)? onError;

  Future<void> _queue = Future<void>.value();
  Map<String, int>? _known;
  List<int> _lastRequestRefs = const [];
  final _text = StringBuffer();
  final _reasoning = StringBuffer();
  var _ended = false;
  var _failures = 0;

  /// 写入失败次数（用于诊断，不影响运行）。
  int get failures => _failures;
  bool get ended => _ended;

  void start() => _enqueue(() => _append(
        SessionEventType.turnStart,
        {'runId': runId, 'model': model},
      ));

  /// 执行器在每次发送模型请求前调用；[request.messages] 必须是快照。
  void onRequest(int step, UnifiedRequest request) {
    if (_ended) return;
    _text.clear();
    _reasoning.clear();
    final messages = List<ChatMessage>.of(request.messages);
    _enqueue(() async {
      final refs = await _refsFor(messages);
      _lastRequestRefs = refs;
      await _append(SessionEventType.requestSent, {
        'step': step,
        'refs': refs,
        'model': request.model,
        'toolsHash': _toolsHash(request.tools),
        'toolCount': request.tools.length,
        'maxTokens': request.maxTokens,
        'temperature': request.temperature,
        'topP': request.topP,
        'reasoningEffort': request.reasoningEffort.name,
      });
    });
  }

  /// 消费执行器事件，识别运行结束。
  void observe(AgentEvent event) {
    if (_ended) return;
    switch (event) {
      case TextEvent(:final text):
        _text.write(text);
      case ReasoningEvent(:final text):
        _reasoning.write(text);
      case AgentStatusEvent(status: RunStatus.completed):
        // 与执行器完成时追加的 assistant 消息构造方式保持一致。
        final finalMessage = ChatMessage(
          role: MessageRole.assistant,
          parts: [MessagePart.text(_text.toString())],
          reasoning: _reasoning.isEmpty ? null : _reasoning.toString(),
        );
        _end('completed', tail: [finalMessage]);
      case AgentStatusEvent(status: RunStatus.cancelled):
        _end('cancelled');
      case AgentBudgetExhaustedEvent(:final context, :final reason):
        _end('paused', context: context, extra: {'reason': reason.name});
      case AgentErrorEvent(:final message, :final failureKind):
        _end('failed', extra: {
          'error': message,
          if (failureKind != null) 'failureKind': failureKind,
        });
      default:
        break;
    }
  }

  /// 事件流以异常结束或被外部中止时调用。
  void abort(String reason) => _end('interrupted', extra: {'reason': reason});

  /// 等待所有已排队的写入完成。
  Future<void> flush() => _queue;

  void _end(
    String status, {
    List<ChatMessage>? context,
    List<ChatMessage> tail = const [],
    Map<String, dynamic> extra = const {},
  }) {
    if (_ended) return;
    _ended = true;
    final snapshot = context == null ? null : List<ChatMessage>.of(context);
    _enqueue(() async {
      final refs = snapshot != null
          ? await _refsFor(snapshot)
          : [..._lastRequestRefs, ...await _refsFor(tail)];
      await _append(SessionEventType.turnEnd, {
        'status': status,
        'refs': refs,
        ...extra,
      });
    });
  }

  Future<List<int>> _refsFor(List<ChatMessage> messages) async {
    final known = _known ??= await store.messageKeys(conversationId);
    final refs = <int>[];
    for (final message in messages) {
      final key = ChatMessageCodec.contentKey(message);
      var seq = known[key];
      if (seq == null) {
        final event = await store.append(
          conversationId: conversationId,
          type: SessionEventType.message,
          payload: ChatMessageCodec.encode(message),
          runId: runId,
          contentKey: key,
        );
        seq = event.seq;
        known[key] = seq;
      }
      refs.add(seq);
    }
    return refs;
  }

  Future<void> _append(String type, Map<String, dynamic> payload) =>
      store.append(
        conversationId: conversationId,
        type: type,
        payload: payload,
        runId: runId,
      );

  void _enqueue(Future<void> Function() op) {
    _queue = _queue.then((_) => op()).catchError((Object e, StackTrace s) {
      _failures++;
      onError?.call(e, s);
    });
  }

  static String _toolsHash(List<UnifiedTool> tools) {
    final names = tools.map((t) => t.name).join('\n');
    return sha256.convert(utf8.encode(names)).toString().substring(0, 16);
  }
}
