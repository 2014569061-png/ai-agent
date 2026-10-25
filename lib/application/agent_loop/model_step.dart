import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;

import '../../domain/models.dart';
import '../../infrastructure/providers/llm_provider.dart';
import '../agent_executor.dart';
import '../run_controller.dart';
import 'model_retry_policy.dart';
import 'usage_tally.dart';
import 'token_budget.dart';

/// 一次模型流式请求（含重试）的累积结果。
class ModelStepResult {
  final text = StringBuffer();
  final reasoning = StringBuffer();
  final pendingCalls = <ToolCall>[];
  var stopReason = StopReason.unknown;

  /// 本轮被用户暂停中断（流已掐断，不算失败）。
  var pauseInterrupted = false;

  /// 运行已终止（取消或不可恢复的错误）；终止事件已由 [ModelStepRunner] 产出，
  /// 调用方应直接结束运行。
  var terminated = false;
  var tokenBudgetExhausted = false;

  bool get hasContent =>
      text.isNotEmpty || reasoning.isNotEmpty || pendingCalls.isNotEmpty;

  /// 本轮 assistant 消息；[withToolCalls] 时附带本轮全部工具调用。
  ChatMessage assistantMessage({bool withToolCalls = false}) => withToolCalls
      ? ChatMessage(
          role: MessageRole.assistant,
          parts: [MessagePart.text(text.toString())],
          toolCalls: List<ToolCall>.unmodifiable(pendingCalls),
          reasoning: reasoning.isEmpty ? null : reasoning.toString(),
        )
      : ChatMessage(
          role: MessageRole.assistant,
          parts: [MessagePart.text(text.toString())],
          reasoning: reasoning.isEmpty ? null : reasoning.toString(),
        );
}

/// 流式执行单步模型请求：转发文本/推理/工具调用事件、累计用量、
/// 失败按 [ModelRetryPolicy] 重试，并处理暂停中断与取消。
class ModelStepRunner {
  ModelStepRunner({
    required this.provider,
    required this.requestTimeout,
    required this.retryPolicy,
    required this.usage,
    required this.isCancelled,
    this.cancellationToken,
    this.runController,
    this.cancelToken,
  });

  final LlmProvider provider;
  final Duration requestTimeout;
  final ModelRetryPolicy retryPolicy;
  final UsageTally usage;
  final bool Function() isCancelled;
  final AgentCancellationToken? cancellationToken;
  final AgentRunController? runController;

  /// 调用方持有的运行级 HTTP token；最终失败或取消时一并取消。
  final CancelToken? cancelToken;

  Stream<AgentEvent> run(UnifiedRequest request, ModelStepResult out) async* {
    usage.beginStep();
    // 暂停即中断：本轮模型请求使用独立的 CancelToken，并与运行级 token 联动
    // （停止时一并取消）。用户点暂停时，若本轮还没产出工具调用，就立即掐断
    // 流式输出；已输出的半截文字留作上下文，恢复后让模型从中断处接着写。
    final stepCancelToken = CancelToken();
    final cancellation = cancellationToken?.whenCancelled;
    if (cancellation != null) {
      unawaited(cancellation.then((_) => stepCancelToken.cancel('cancelled')));
    }
    final controllerCancellation = runController?.whenCancelled;
    if (controllerCancellation != null) {
      unawaited(controllerCancellation
          .then((_) => stepCancelToken.cancel('cancelled')));
    }
    final runCancelToken = cancelToken;
    if (runCancelToken != null) {
      unawaited(runCancelToken.whenCancel.then<void>((_) {
        if (!stepCancelToken.isCancelled) stepCancelToken.cancel();
      }));
    }
    runController?.onPauseInterrupt = () {
      if (out.pendingCalls.isNotEmpty || stepCancelToken.isCancelled) return;
      out.pauseInterrupted = true;
      stepCancelToken.cancel('paused');
    };
    // 失败自动重试：本轮尚未产出任何内容（无文本/推理/工具调用）且底层
    // 请求失败时，指数退避后整体重发；已产出内容则不重试，避免文本重复
    // 渲染与工具重复副作用。Dio 层 RetryInterceptor 对流式请求不重试，
    // 这里是 SSE 失败的唯一重试路径。
    var attempts = 0;
    while (true) {
      ProviderErrorEvent? failure;
      try {
        await for (final event in provider
            .stream(request, cancelToken: stepCancelToken)
            .timeout(requestTimeout)) {
          if (isCancelled()) {
            out.terminated = true;
            yield const AgentStatusEvent(RunStatus.cancelled);
            return;
          }
          if (out.pauseInterrupted) break;
          if (event is TextDeltaEvent) {
            out.text.write(event.text);
            yield TextEvent(event.text);
          } else if (event is ReasoningDeltaEvent) {
            out.reasoning.write(event.text);
            yield ReasoningEvent(event.text);
          } else if (event is ToolCallEvent) {
            out.pendingCalls.add(event.call);
            yield ToolRequestedEvent(event.call);
          } else if (event is CompletedEvent) {
            out.stopReason = event.stopReason;
          } else if (event is UsageEvent) {
            usage.add(event);
          } else if (event is ProviderErrorEvent) {
            failure = event;
            break;
          }
        }
      } on TimeoutException {
        // 空闲超时属于 transient failure，先让统一重试分类决定是否重试。
        // 只有最终失败时才取消调用方持有的底层 HTTP token。
        failure = ProviderErrorEvent(
          '模型请求超时（${requestTimeout.inSeconds} 秒）',
          failureKind: 'receiveTimeout',
        );
      }
      // 暂停中断时 provider 按约定会静默结束；即便个别实现仍产出错误，也按
      // 中断处理：不重试，也不当作失败。
      if (failure == null || (out.pauseInterrupted && !isCancelled())) break;
      if (failure.failureKind == TokenBudgetProvider.exhausted) {
        out.tokenBudgetExhausted = true;
        return;
      }
      final decision = retryPolicy.decide(
        failure,
        hasContent: out.hasContent,
        attempts: attempts,
      );
      if (decision is! RetryAfter) {
        cancelToken?.cancel();
        out.terminated = true;
        yield AgentErrorEvent(
          failure.message,
          retryable: decision is RetryGiveUp,
          failureKind: decision.failure.kind,
          statusCode: decision.failure.statusCode,
        );
        return;
      }
      attempts = decision.attempt;
      yield AgentRetryEvent(attempts);
      if (isCancelled()) {
        out.terminated = true;
        yield const AgentStatusEvent(RunStatus.cancelled);
        return;
      }
      // 指数退避只针对尚未产生任何模型输出的瞬态失败，避免把已有工具调用
      // 重复提交。
      final delay = decision.delay;
      final cancelled =
          cancellationToken?.whenCancelled ?? runController?.whenCancelled;
      if (cancelled == null) {
        await Future<void>.delayed(delay);
      } else {
        await Future.any<void>([Future<void>.delayed(delay), cancelled]);
      }
      if (isCancelled()) {
        cancelToken?.cancel();
        out.terminated = true;
        yield const AgentStatusEvent(RunStatus.cancelled);
        return;
      }
    }
    runController?.onPauseInterrupt = null;
    // 流被主动取消（底层 HTTP 已真正中断）时，不产出 completed。
    if (isCancelled()) {
      cancelToken?.cancel();
      out.terminated = true;
      yield const AgentStatusEvent(RunStatus.cancelled);
    }
  }
}
