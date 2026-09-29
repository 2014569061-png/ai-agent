import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;

import '../domain/context_insights.dart';
import '../domain/models.dart';
import '../domain/tool_codes.dart';
import '../domain/tool_result.dart';
import '../infrastructure/providers/llm_provider.dart';
import '../infrastructure/tools/tool_registry.dart';
import '../infrastructure/providers/provider_config.dart';
import 'context_window.dart';
import 'run_controller.dart';
import 'tool_pipeline/execution_interceptors.dart';
import 'tool_pipeline/tool_invocation.dart';
import 'tool_pipeline/tool_pipeline.dart';
import 'tool_pipeline/tool_run_context.dart';
import 'agent_loop/agent_loop_hooks.dart';
import 'agent_loop/builtin_hooks.dart';
import 'agent_loop/context_reporter.dart';
import 'agent_loop/loop_messages.dart';
import 'agent_loop/model_retry_policy.dart';
import 'agent_loop/model_step.dart';
import 'agent_loop/request_shape.dart';
import 'agent_loop/step_budget_policy.dart';
import 'agent_loop/system_prompt_merge.dart';
import 'agent_loop/usage_tally.dart';

class AgentExecutor {
  AgentExecutor({
    required this.provider,
    required this.tools,
    ToolPipeline? toolPipeline,
    this.hooks = AgentLoopHooks.empty,
  }) : toolPipeline = toolPipeline ?? defaultToolPipeline;
  final LlmProvider provider;
  final ToolRegistry tools;

  /// 执行循环的阶段钩子（request / 请求观察 / 工具结果 / turn-stopping）。
  /// 内置行为（压缩、上下文裁剪、步数预算、插话）始终存在，外部钩子按
  /// [AgentLoopHooks] 文档描述的位置插入。
  final AgentLoopHooks hooks;

  /// 本执行器使用的工具调用管线。未指定时使用 [defaultToolPipeline]；
  /// 调用方可在默认拦截器基础上插入审计、网络策略等环节，
  /// 例如 `ToolPipeline([...defaultToolInterceptors(), myInterceptor])`。
  final ToolPipeline toolPipeline;

  /// 默认管线：前置守卫 → 审批 → 检查点 → 执行边界 → 授权 → 超时执行。
  /// 拦截器均为无状态实现，可在所有执行器间共享。
  static final ToolPipeline defaultToolPipeline =
      ToolPipeline(defaultToolInterceptors());

  Stream<AgentEvent> run({
    required List<ChatMessage> history,
    required String model,
    int maxSteps = 8,
    double temperature = 0.7,
    int maxTokens = 2048,
    double topP = 1.0,
    ReasoningEffort reasoningEffort = ReasoningEffort.off,

    /// 读取空闲超时，而非整个响应的总时长；长回答只要持续有新数据就不会被误杀。
    Duration requestTimeout = const Duration(minutes: 5),
    int contextBudgetTokens = ContextWindow.defaultMaxTokens,
    int maxRetries = 3,
    Duration retryBackoff = const Duration(seconds: 2),
    AgentCancellationToken? cancellationToken,
    CancelToken? cancelToken,
    ToolApprovalCallback? approveTool,
    ApprovalMode approvalMode = ApprovalMode.ask,
    bool Function(String toolName, ToolRisk risk)? isToolTrusted,
    String? systemPrompt,
    ModelCapabilities capabilities = const ModelCapabilities(),
    Future<bool> Function(List<ToolCall> calls, String planText)? confirmPlan,
    AgentRunController? runController,

    /// 到达 [maxSteps] 时若最近仍有进展（最近有工具成功、最后 4 次不全失败），
    /// 自动再追加一轮 [maxSteps] 预算的次数上限；0 表示不自动续跑。
    int autoContinueLimit = 0,

    /// 连续多少次工具失败（中间没有任何成功）后提前暂停；0 表示不熔断。
    int failurePauseThreshold = 4,

    /// 每次发送模型请求前回调一次，参数为**不可变快照**：`request.messages`
    /// 不会再被执行器修改（实际发送的请求与工作列表是同一对象，事后读取会
    /// 看到后续追加的消息）。用于会话日志记录模型真正看到的内容。
    /// 重试复用同一请求，不重复回调；回调抛出的异常被吞掉，不影响运行。
    void Function(int step, UnifiedRequest request)? onRequest,
  }) async* {
    var messages = List<ChatMessage>.of(history);

    // 结算一次工具调用：追加对应的 tool 消息并返回结果事件。
    // 每个调用必须恰好结算一次，且顺序与模型给出的调用顺序一致。
    ToolResultEvent settle(
      ToolCall call,
      ToolResult result, {
      Map<String, dynamic> metadata = const <String, dynamic>{},
    }) {
      messages.add(ChatMessage(
        role: MessageRole.tool,
        toolCallId: call.id,
        parts: [MessagePart.text(result.encode())],
      ));
      return ToolResultEvent(call, result, metadata: metadata);
    }
    mergeSystemPrompt(
      messages,
      requested: systemPrompt,
      builtInRules: builtInEnvironmentRules(
        isAndroid: Platform.isAndroid,
        hasTerminal: tools.manifests.any((t) => t.name == 'terminal'),
      ),
    );
    final shape = RequestShape.resolve(
      manifests: tools.manifests,
      toolsEnabled: capabilities.tools,
      contextBudgetTokens: contextBudgetTokens,
      requestedOutputTokens: maxTokens,
    );
    final requestTools = shape.tools;
    final reservedOutputTokens = shape.reservedOutputTokens;
    bool isCancelled() =>
        (cancellationToken?.isCancelled ?? false) ||
        (runController?.isCancelled ?? false);

    Future<void> checkpoint() async {
      await runController?.checkpoint();
    }

    // 统一的暂停检查点：已暂停时先发出 paused（UI 立即切到「已暂停」并露出
    // 继续/停止按钮），再等待恢复或取消。以前工具调用前的检查点只会静默阻塞，
    // UI 一直停在「运行中」，看起来就像暂停没有生效。
    Stream<AgentEvent> pausePoint() async* {
      if (!(runController?.isPaused ?? false)) return;
      yield const AgentStatusEvent(RunStatus.paused);
      await checkpoint();
    }

    void appendSteering(Iterable<String> instructions) {
      for (final instruction in instructions) {
        messages.add(LoopMessages.steering(instruction));
      }
    }

    // 步数预算、自动续跑与连续失败熔断；模型请求失败重试。
    final budgetPolicy = StepBudgetPolicy(
      maxSteps: maxSteps,
      autoContinueLimit: autoContinueLimit,
      failurePauseThreshold: failurePauseThreshold,
    );
    final retryPolicy =
        ModelRetryPolicy(maxRetries: maxRetries, backoff: retryBackoff);

    // 本次运行的阶段钩子：内置实现包在执行器级外部钩子两侧。顺序即语义——
    // 压缩先于外部 transform、裁剪最后；预算观察最先；steering 最后（它会封存
    // 控制器，之后外部 handler 无法再续跑）。
    final loop = AgentLoopHooks(
      requestTransforms: [QueuedCompressionTransform(runController)],
      toolOutcomeObservers: [budgetPolicy],
    ).merge(hooks).merge(AgentLoopHooks(
          requestTransforms: [ContextWindowTransform(shape.contextWindow)],
          requestObservers: [if (onRequest != null) onRequest],
          turnStopping: [SteeringTurnStopping(runController)],
        ));

    final usage = UsageTally();
    final contextReporter = ContextReporter(
      tools: requestTools,
      contextWindow: contextBudgetTokens,
      reservedOutputTokens: reservedOutputTokens,
    );
    final modelStep = ModelStepRunner(
      provider: provider,
      requestTimeout: requestTimeout,
      retryPolicy: retryPolicy,
      usage: usage,
      isCancelled: isCancelled,
      cancellationToken: cancellationToken,
      runController: runController,
      cancelToken: cancelToken,
    );
    UnifiedRequest buildRequest(List<ChatMessage> requestMessages) =>
        UnifiedRequest(
          model: model,
          messages: requestMessages,
          tools: requestTools,
          temperature: temperature,
          maxTokens: reservedOutputTokens,
          topP: topP,
          reasoningEffort: reasoningEffort,
        );

    for (var step = 0;; step++) {
      final budgetDecision = budgetPolicy.beforeStep(step);
      if (budgetDecision is BudgetExhausted) break;
      if (budgetDecision is BudgetExtended) {
        // 预算用完但最近仍有进展：自动再给一轮预算，不打断用户。
        yield AgentBudgetExtendedEvent(
          round: budgetDecision.round,
          limit: budgetDecision.limit,
          addedSteps: budgetDecision.addedSteps,
        );
      }
      yield* pausePoint();
      if (isCancelled()) {
        yield const AgentStatusEvent(RunStatus.cancelled);
        return;
      }
      yield const AgentStatusEvent(RunStatus.waitingModel);
      final requestContext = RequestContext(step: step + 1, model: model);
      for (final transform in loop.requestTransforms) {
        final result = transform.apply(requestContext, messages);
        if (!identical(result.messages, messages)) {
          messages = List<ChatMessage>.of(result.messages);
        }
        for (final event in result.events) {
          yield event;
        }
      }
      final request = buildRequest(messages);
      _notifyRequestObservers(loop.requestObservers, step + 1,
          () => buildRequest(List.unmodifiable(messages)));
      for (final event in contextReporter.report(step + 1, messages)) {
        yield event;
      }

      final out = ModelStepResult();
      yield* modelStep.run(request, out);
      if (out.terminated) return;
      final pendingCalls = out.pendingCalls;
      if (out.pauseInterrupted) {
        // 本轮被暂停中断：丢弃可能不完整的工具调用；已输出的半截文字作为
        // assistant 上下文保留，并提示模型恢复后从中断处接着写。回到循环
        // 顶部，由暂停检查点发出 paused，等待继续或停止。
        final partial = out.text.toString();
        if (partial.trim().isNotEmpty) {
          messages.add(ChatMessage(
            role: MessageRole.assistant,
            parts: [MessagePart.text(partial)],
          ));
          messages.add(LoopMessages.pauseInterrupted());
        }
        continue;
      }
      yield AgentStepUsageEvent(step: step + 1, usage: usage.stepUsage);
      if (pendingCalls.isEmpty) {
        // turn-stopping：任一 handler 可否决结束并让运行继续。
        final stopping = TurnStoppingContext(
          step: step + 1,
          finalText: out.text.toString(),
        );
        final continuation =
            _resolveContinuation(loop.turnStopping, stopping);
        if (continuation != null && continuation.messages.isNotEmpty) {
          if (continuation.keepAssistantText) {
            messages.add(out.assistantMessage());
          }
          messages.addAll(continuation.messages);
          continue;
        }
        messages.add(out.assistantMessage());
        yield usage.totalEvent;
        yield const AgentStatusEvent(RunStatus.completed);
        return;
      }
      // C3 计划模式门禁：首轮有工具调用时，先产出计划等待用户确认，再执行工具。
      // 只有模型明确以 toolUse 结束本轮时，夹带的调用才具备可执行资格。
      // outputLimit 通常意味着参数可能被截断，其他停因则属于协议矛盾；两者都必须
      // 回灌结构化错误，让模型重新规划，而不是把不完整调用交给真实工具。
      if (out.stopReason != StopReason.toolUse) {
        messages.add(out.assistantMessage(withToolCalls: true));
        final rejection = _rejectedCallResult(out.stopReason);
        for (final pendingCall in pendingCalls) {
          yield settle(pendingCall, rejection);
        }
        continue;
      }
      var planApproved = false;
      if (step == 0 && confirmPlan != null && pendingCalls.isNotEmpty) {
        final approved = await confirmPlan(pendingCalls, out.text.toString());
        if (!approved) {
          yield const AgentStatusEvent(RunStatus.cancelled);
          return;
        }
        planApproved = true;
      }
      messages.add(out.assistantMessage(withToolCalls: true));
      for (final pendingCall in pendingCalls) {
        final registration = tools.findRegistration(pendingCall.name);
        final outcome = _ToolCallOutcome();
        yield* _executeTool(
          pendingCall,
          registration,
          outcome,
          (emit) => ToolRunContext(
            approvalMode: approvalMode,
            approveTool: approveTool,
            isToolTrusted: isToolTrusted,
            isCancelled: isCancelled,
            isPaused: () => runController?.isPaused ?? false,
            waitForResume: checkpoint,
            emit: emit,
          ),
        );
        if (outcome.cancelled) return;
        final toolResult = outcome.result!;
        // 未进入执行边界（守卫短路或审批拒绝）：不附带元数据，也不计入熔断。
        if (!outcome.executionStarted) {
          yield settle(pendingCall, toolResult);
          continue;
        }
        yield settle(pendingCall, toolResult, metadata: outcome.metadata);
        for (final observer in loop.toolOutcomeObservers) {
          observer.onToolOutcome(pendingCall, toolResult);
        }
      }
      // 同一调用反复失败：在本步全部工具结果之后提醒模型换方法（不能插在
      // 工具结果中间，否则会破坏 assistant tool_calls → tool 的消息顺序）。
      final failureHints = budgetPolicy.drainFailureHints();
      if (failureHints.isNotEmpty) {
        messages.add(LoopMessages.failureHints(failureHints));
      }
      // 计划审批只负责放行首轮工具调用。工具返回后必须显式告诉模型继续
      // 执行已批准的计划，否则模型可能把“计划已提交”误判为本轮任务结束。
      if (planApproved) messages.add(LoopMessages.planConfirmed());
      appendSteering(runController?.drainSteering() ?? const []);
      // 连续失败熔断：多次失败且中间没有任何成功，提前暂停交给用户决定，
      // 避免模型在没有权限或环境缺失时空转到预算耗尽。
      if (budgetPolicy.shouldPauseForFailures) {
        yield const AgentStatusEvent(RunStatus.paused);
        yield AgentBudgetExhaustedEvent(
          context: messages,
          maxSteps: step + 1,
          reason: AgentPauseReason.repeatedFailures,
          message:
              '连续 ${budgetPolicy.consecutiveFailures} 次工具调用失败，任务已暂停，可继续执行',
        );
        return;
      }
    }
    // 达到 maxSteps 不是业务失败：将其区分为可恢复的"预算暂停"状态，并把
    // 当前完整上下文（含工具结果与已批准的续跑指令）一并交给调用方，便于
    // 从断点续跑，而不是重新提交原始 prompt。
    yield const AgentStatusEvent(RunStatus.paused);
    yield AgentBudgetExhaustedEvent(
      context: messages,
      maxSteps: budgetPolicy.budget,
    );
  }

  /// 请求观察者收到不可变快照；任何观察者（会话日志等）失败都不影响请求。
  static void _notifyRequestObservers(List<RequestObserver> observers,
      int step, UnifiedRequest Function() snapshot) {
    if (observers.isEmpty) return;
    final frozen = snapshot();
    for (final observer in observers) {
      try {
        observer(step, frozen);
      } on Object {
        // 忽略：观察失败不能影响模型请求。
      }
    }
  }

  /// 模型未以 toolUse 结束却夹带了工具调用时回灌的结构化错误。
  static ToolResult _rejectedCallResult(StopReason stopReason) =>
      stopReason == StopReason.outputLimit
          ? ToolResult.failure(
              code: ToolCodes.truncatedToolCall,
              message: LoopMessages.truncatedToolCallMessage)
          : ToolResult.failure(
              code: ToolCodes.unexpectedToolCall,
              message: LoopMessages.unexpectedToolCallMessage);

  /// turn-stopping：按顺序询问，第一个非空的续跑决定生效。
  static TurnContinuation? _resolveContinuation(
      List<TurnStoppingHandler> handlers, TurnStoppingContext context) {
    for (final handler in handlers) {
      final continuation = handler.onTurnStopping(context);
      if (continuation != null) return continuation;
    }
    return null;
  }

  /// 经工具管线执行单个调用，逐个转发管线事件（消费方处理完毕、恢复本
  /// 生成器后才确认送达，拦截器随后才继续——例如先落库「等待确认」，再调用
  /// approveTool）。结果写入 [outcome]；取消时产出 cancelled 并置
  /// [_ToolCallOutcome.cancelled]，其他异常原样抛出。
  Stream<AgentEvent> _executeTool(
    ToolCall call,
    ToolRegistration? registration,
    _ToolCallOutcome outcome,
    ToolRunContext Function(ToolEventEmitter emit) contextFor,
  ) async* {
    final channel = StreamController<_ToolEmission>();
    final context = contextFor((event) {
      final emission = _ToolEmission(event);
      channel.add(emission);
      return emission.delivered.future;
    });
    ToolResult? pipelineResult;
    Object? pipelineError;
    StackTrace? pipelineTrace;
    final settled = toolPipeline
        .run(
          ToolInvocation(
            call: call,
            registration: registration,
            context: context,
          ),
          executeWithTimeout,
        )
        .then<void>(
          (result) => pipelineResult = result,
          onError: (Object error, StackTrace trace) {
            pipelineError = error;
            pipelineTrace = trace;
          },
        )
        .whenComplete(channel.close);
    await for (final emission in channel.stream) {
      yield emission.event;
      emission.delivered.complete();
    }
    await settled;
    final error = pipelineError;
    if (error is ToolRunCancelled) {
      outcome.cancelled = true;
      yield const AgentStatusEvent(RunStatus.cancelled);
      return;
    }
    if (error != null) {
      Error.throwWithStackTrace(error, pipelineTrace ?? StackTrace.current);
    }
    final result = pipelineResult;
    if (result == null) {
      throw StateError('工具管线未产出结果：${call.name}');
    }
    outcome.result = result;
    outcome.executionStarted = context.executionStarted;
    if (context.executionStarted) {
      outcome.metadata = switch (registration?.executor) {
        final ToolExecutionMetadata source => source.lastMetadata,
        _ => const <String, dynamic>{},
      };
    }
  }
}

final class _ToolCallOutcome {
  ToolResult? result;
  bool cancelled = false;
  bool executionStarted = false;
  Map<String, dynamic> metadata = const <String, dynamic>{};
}

class AgentCancellationToken {
  bool _cancelled = false;
  final Completer<void> _cancelCompleter = Completer<void>();
  bool get isCancelled => _cancelled;
  Future<void> get whenCancelled => _cancelCompleter.future;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancelCompleter.complete();
  }
}

sealed class AgentEvent {
  const AgentEvent();
}

class ContextSnapshotEvent extends AgentEvent {
  const ContextSnapshotEvent({
    required this.step,
    required this.snapshot,
    this.anchorMessageId,
  });

  final int step;
  final ContextSnapshot snapshot;
  final String? anchorMessageId;
}

/// Emitted after the local pre-request estimate and before the provider stream
/// starts, so the caller can persist a visible budget warning without changing
/// the request or silently deleting user history.
class ContextBudgetWarningEvent extends AgentEvent {
  const ContextBudgetWarningEvent({
    required this.level,
    required this.usedTokens,
    required this.contextWindow,
    required this.remainingTokens,
    this.dominantPart,
  });

  final ContextBudgetLevel level;
  final int usedTokens;
  final int contextWindow;
  final int remainingTokens;
  final String? dominantPart;
}

class AgentContextCompressionEvent extends AgentEvent {
  const AgentContextCompressionEvent({
    required this.toolCallIds,
    required this.candidateCount,
    required this.estimatedSavedTokens,
    required this.originalTokens,
    required this.compressedTokens,
  });

  final List<String> toolCallIds;
  final int candidateCount;
  final int estimatedSavedTokens;
  final int originalTokens;
  final int compressedTokens;
}

class AgentContextChangeEvent extends AgentEvent {
  const AgentContextChangeEvent({
    required this.step,
    required this.kind,
    required this.category,
    required this.deltaTokens,
  });

  final int step;
  final String kind;
  final String category;
  final int deltaTokens;
}

class AgentStepUsageEvent extends AgentEvent {
  const AgentStepUsageEvent({required this.step, required this.usage});

  final int step;
  final Usage usage;
}

class AgentStatusEvent extends AgentEvent {
  const AgentStatusEvent(this.status);
  final RunStatus status;
}

class TextEvent extends AgentEvent {
  const TextEvent(this.text);
  final String text;
}

class ReasoningEvent extends AgentEvent {
  const ReasoningEvent(this.text);
  final String text;
}

class ToolRequestedEvent extends AgentEvent {
  const ToolRequestedEvent(this.call);
  final ToolCall call;
}

class ApprovalRequiredEvent extends AgentEvent {
  const ApprovalRequiredEvent(this.call, this.risk);
  final ToolCall call;
  final ToolRisk risk;
}

class AgentErrorEvent extends AgentEvent {
  const AgentErrorEvent(
    this.message, {
    this.retryable = false,
    this.failureKind,
    this.statusCode,
  });
  final String message;
  final bool retryable;
  final String? failureKind;
  final int? statusCode;
}

/// 达到 maxSteps 触发的可恢复预算暂停。携带当前完整上下文，调用方可用它
/// 作为下一次 [AgentExecutor.run] 的 history，从断点续跑而不重新执行工具。
class AgentBudgetExhaustedEvent extends AgentEvent {
  const AgentBudgetExhaustedEvent({
    required this.context,
    required this.maxSteps,
    this.message = '已达到单次执行步数预算，任务已暂停，可继续执行',
    this.reason = AgentPauseReason.budget,
  });
  final List<ChatMessage> context;
  final int maxSteps;
  final String message;
  final AgentPauseReason reason;
}

/// 可恢复暂停的原因。
enum AgentPauseReason {
  /// 达到轮数预算（含自动续跑追加的部分）。
  budget,

  /// 连续多次工具失败，提前熔断。
  repeatedFailures,
}

/// 预算用完但最近仍有进展时，执行器自动追加一轮预算（不打断用户）。
class AgentBudgetExtendedEvent extends AgentEvent {
  const AgentBudgetExtendedEvent({
    required this.round,
    required this.limit,
    required this.addedSteps,
  });

  /// 第几次自动续跑（从 1 开始）。
  final int round;
  final int limit;
  final int addedSteps;
}

class AgentRetryEvent extends AgentEvent {
  const AgentRetryEvent(this.attempt);
  final int attempt;
}

class AgentUsageEvent extends AgentEvent {
  const AgentUsageEvent({
    required this.promptTokens,
    required this.completionTokens,
    this.cachedTokens = 0,
    this.cacheWriteTokens = 0,
    this.reasoningTokens = 0,
    this.usageReported = false,
    this.cacheStatsReported = false,
  });
  final int promptTokens;
  final int completionTokens;
  final int cachedTokens;

  /// 缓存写入 token（Anthropic cache_creation_input_tokens）。
  final int cacheWriteTokens;

  /// 推理 token（已包含在 completionTokens 内）。
  final int reasoningTokens;

  /// 本轮是否收到过任何 provider usage 统计。
  final bool usageReported;

  /// usage 中是否出现过缓存统计字段（区别于“返回了 0 命中”）。
  final bool cacheStatsReported;
}

class ToolResultEvent extends AgentEvent {
  const ToolResultEvent(this.call, this.result,
      {this.metadata = const <String, dynamic>{}});
  final ToolCall call;
  final ToolResult result;
  final Map<String, dynamic> metadata;
}

/// 管线发往执行器事件流的一条事件；[delivered] 在消费方处理完毕后完成。
final class _ToolEmission {
  _ToolEmission(this.event);

  final AgentEvent event;
  final delivered = Completer<void>();
}
