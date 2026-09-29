import '../../domain/models.dart';
import '../agent_executor.dart' show AgentContextCompressionEvent;
import '../context_compression_applier.dart';
import '../context_window.dart';
import '../run_controller.dart';
import 'agent_loop_hooks.dart';
import 'loop_messages.dart';

/// 应用用户在运行中批准的工具结果压缩（来自 AgentRunController 队列）。
class QueuedCompressionTransform implements RequestTransform {
  const QueuedCompressionTransform(this.controller);

  final AgentRunController? controller;

  @override
  String get id => 'builtin.queued-compression';

  @override
  RequestTransformResult apply(
      RequestContext context, List<ChatMessage> messages) {
    final ids = controller?.drainCompressionToolCallIds() ?? const <String>{};
    if (ids.isEmpty) return RequestTransformResult(messages);
    final compression =
        const ContextCompressionApplier().applyToolCallIds(messages, ids);
    final next = List<ChatMessage>.of(compression.messages);
    if (compression.appliedCandidates.isEmpty) {
      return RequestTransformResult(next);
    }
    return RequestTransformResult(next, [
      AgentContextCompressionEvent(
        toolCallIds: compression.appliedCandidates
            .map((candidate) => candidate.toolCallId)
            .whereType<String>()
            .toList(growable: false),
        candidateCount: compression.appliedCandidates.length,
        estimatedSavedTokens: compression.savedTokens,
        originalTokens: compression.originalTokens,
        compressedTokens: compression.compressedTokens,
      ),
    ]);
  }
}

/// 按上下文预算裁剪历史（每步请求前一次）。始终排在最后。
class ContextWindowTransform implements RequestTransform {
  const ContextWindowTransform(this.window);

  final ContextWindow window;

  @override
  String get id => 'builtin.context-window';

  @override
  RequestTransformResult apply(
          RequestContext context, List<ChatMessage> messages) =>
      RequestTransformResult(window.apply(messages));
}

/// 完成边界的用户插话：有排队指令则继续运行；没有则封存控制器。
///
/// 始终排在最后——封存之后到达的插话会被拒绝，所以必须让其他 handler 先
/// 表态，避免控制器被封存后运行仍继续。
class SteeringTurnStopping implements TurnStoppingHandler {
  const SteeringTurnStopping(this.controller);

  final AgentRunController? controller;

  @override
  String get id => 'builtin.steering';

  @override
  TurnContinuation? onTurnStopping(TurnStoppingContext context) {
    final steering = controller?.pollSteeringOrSeal() ?? const <String>[];
    if (steering.isEmpty) return null;
    return TurnContinuation(
      [for (final s in steering) LoopMessages.steering(s)],
      keepAssistantText: false,
    );
  }
}
