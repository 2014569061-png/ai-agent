import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;

import '../domain/models.dart';
import '../domain/tool_codes.dart';
import '../domain/tool_result.dart';
import '../infrastructure/providers/llm_provider.dart';
import '../infrastructure/tools/tool_registry.dart';
import '../infrastructure/tools/schema_validator.dart';
import '../infrastructure/providers/provider_config.dart';
import 'context_window.dart';
import 'approval_policy.dart';
import 'model_failure.dart';
import 'run_controller.dart';

class AgentExecutor {
  AgentExecutor({required this.provider, required this.tools});
  final LlmProvider provider;
  final ToolRegistry tools;

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
    Future<ToolApproval> Function(ToolCall call, ToolRisk risk)? approveTool,
    ApprovalMode approvalMode = ApprovalMode.ask,
    bool Function(String toolName, ToolRisk risk)? isToolTrusted,
    String? systemPrompt,
    ModelCapabilities capabilities = const ModelCapabilities(),
    Future<bool> Function(List<ToolCall> calls, String planText)? confirmPlan,
    AgentRunController? runController,
  }) async* {
    var messages = List<ChatMessage>.of(history);
    const schemaValidator = SchemaValidator();
    // 内置环境规则与业务 system prompt 分开构造，确保调用方未传 prompt 或
    // 历史已带 system 消息时，模型仍然知道当前设备的真实能力边界。
    final builtInRules = <String>[];
    if (Platform.isAndroid &&
        tools.manifests.any((t) => t.name == 'terminal')) {
      builtInRules.add(
        '[运行环境说明] 当前运行在 Android 手机上。terminal 工具优先使用内置 '
        'Alpine Linux（PRoot + ARM64 rootfs），不可用时回退到 Termux，再回退到 Android Shell。'
        '内置 Alpine 默认是精简 rootfs，提供 sh/ash/BusyBox 基础命令；Go/Git/Node/Python 等工具'
        '可能尚未安装，需要先在 Alpine 中执行 apk add，或使用已配置的 Termux 工具链。'
        '不要默认声称环境无法运行 Linux 命令；编译或测试报错时先检查当前 Runtime 和缺失工具，'
        '再安装依赖或切换备用 Runtime。',
      );
    }
    final builtInSystemText = builtInRules.join('\n\n');
    final requestedSystemText = systemPrompt?.trim() ?? '';
    final systemIndex =
        messages.indexWhere((m) => m.role == MessageRole.system);
    if (systemIndex >= 0) {
      final existing = messages[systemIndex];
      final additions = <String>[];
      if (requestedSystemText.isNotEmpty &&
          !existing.text.contains(requestedSystemText)) {
        additions.add(requestedSystemText);
      }
      if (builtInSystemText.isNotEmpty &&
          !existing.text.contains(builtInSystemText)) {
        additions.add(builtInSystemText);
      }
      if (additions.isNotEmpty) {
        final combined = [existing.text.trim(), ...additions]
            .where((value) => value.isNotEmpty)
            .join('\n\n');
        messages[systemIndex] = existing.copyWith(
          parts: [MessagePart.text(combined)],
        );
      }
    } else {
      final systemText = [requestedSystemText, builtInSystemText]
          .where((value) => value.isNotEmpty)
          .join('\n\n');
      if (systemText.isNotEmpty) {
        messages.insert(
          0,
          ChatMessage(
            role: MessageRole.system,
            parts: [MessagePart.text(systemText)],
          ),
        );
      }
    }
    // 上下文预算：每步请求前裁剪一次，同时约束初始历史与多步工具循环
    // 中持续追加的工具结果。
    final contextWindow = ContextWindow(maxTokens: contextBudgetTokens);
    var totalPromptTokens = 0;
    var totalCompletionTokens = 0;
    var totalCachedTokens = 0;
    bool isCancelled() =>
        (cancellationToken?.isCancelled ?? false) ||
        (runController?.isCancelled ?? false);

    Future<void> checkpoint() async {
      await runController?.checkpoint();
    }

    void appendSteering(Iterable<String> instructions) {
      for (final instruction in instructions) {
        messages.add(ChatMessage(
          role: MessageRole.user,
          parts: [
            MessagePart.text(
              '用户补充指令：$instruction\n请继续执行，不要从头重复已完成的步骤。',
            ),
          ],
        ));
      }
    }

    for (var step = 0; step < maxSteps; step++) {
      if (runController?.isPaused ?? false) {
        yield const AgentStatusEvent(RunStatus.paused);
      }
      await checkpoint();
      if (isCancelled()) {
        yield const AgentStatusEvent(RunStatus.cancelled);
        return;
      }
      yield const AgentStatusEvent(RunStatus.waitingModel);
      messages = contextWindow.apply(messages);
      final request = UnifiedRequest(
        model: model,
        messages: messages,
        tools: capabilities.tools ? tools.manifests : const [],
        temperature: temperature,
        maxTokens: maxTokens,
        topP: topP,
        reasoningEffort: reasoningEffort,
      );
      final textBuffer = StringBuffer();
      final reasoningBuffer = StringBuffer();
      final pendingCalls = <ToolCall>[];
      var stopReason = StopReason.unknown;
      // 失败自动重试：本轮尚未产出任何内容（无文本/推理/工具调用）且底层
      // 请求失败时，指数退避后整体重发；已产出内容则不重试，避免文本重复
      // 渲染与工具重复副作用。Dio 层 RetryInterceptor 对流式请求不重试，
      // 这里是 SSE 失败的唯一重试路径。
      var attempts = 0;
      while (true) {
        ProviderErrorEvent? failure;
        try {
          await for (final event in provider
              .stream(request, cancelToken: cancelToken)
              .timeout(requestTimeout)) {
            if (isCancelled()) {
              yield const AgentStatusEvent(RunStatus.cancelled);
              return;
            }
            if (event is TextDeltaEvent) {
              textBuffer.write(event.text);
              yield TextEvent(event.text);
            } else if (event is ReasoningDeltaEvent) {
              reasoningBuffer.write(event.text);
              yield ReasoningEvent(event.text);
            } else if (event is ToolCallEvent) {
              pendingCalls.add(event.call);
              yield ToolRequestedEvent(event.call);
            } else if (event is CompletedEvent) {
              stopReason = event.stopReason;
            } else if (event is UsageEvent) {
              totalPromptTokens += event.promptTokens;
              totalCompletionTokens += event.completionTokens;
              totalCachedTokens += event.cachedTokens;
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
        if (failure == null) break;
        final classified = ModelFailure.classify(
          failure.message,
          statusCode: failure.statusCode,
          failureKind: failure.failureKind,
        );
        if (!classified.retryable) {
          cancelToken?.cancel();
          yield AgentErrorEvent(
            failure.message,
            retryable: false,
            failureKind: classified.kind,
            statusCode: classified.statusCode,
          );
          return;
        }
        final hasContent = textBuffer.isNotEmpty ||
            reasoningBuffer.isNotEmpty ||
            pendingCalls.isNotEmpty;
        if (hasContent || attempts >= maxRetries) {
          cancelToken?.cancel();
          yield AgentErrorEvent(
            failure.message,
            retryable: true,
            failureKind: classified.kind,
            statusCode: classified.statusCode,
          );
          return;
        }
        attempts++;
        yield AgentRetryEvent(attempts);
        if (isCancelled()) {
          yield const AgentStatusEvent(RunStatus.cancelled);
          return;
        }
        // 指数退避：第 1/2/3 次重试分别等待 2/4/8 秒。退避只针对
        // 尚未产生任何模型输出的瞬态失败，避免把已有工具调用重复提交。
        final delay = retryBackoff * (1 << (attempts - 1));
        final cancelled =
            cancellationToken?.whenCancelled ?? runController?.whenCancelled;
        if (cancelled == null) {
          await Future<void>.delayed(delay);
        } else {
          await Future.any<void>([Future<void>.delayed(delay), cancelled]);
        }
        if (isCancelled()) {
          cancelToken?.cancel();
          yield const AgentStatusEvent(RunStatus.cancelled);
          return;
        }
      }
      // 流被主动取消（底层 HTTP 已真正中断）时，不产出 completed。
      if (isCancelled()) {
        cancelToken?.cancel();
        yield const AgentStatusEvent(RunStatus.cancelled);
        return;
      }
      if (pendingCalls.isEmpty) {
        final steering = runController?.pollSteeringOrSeal() ?? const [];
        if (steering.isNotEmpty) {
          appendSteering(steering);
          continue;
        }
        messages.add(ChatMessage(
          role: MessageRole.assistant,
          parts: [MessagePart.text(textBuffer.toString())],
          reasoning:
              reasoningBuffer.isEmpty ? null : reasoningBuffer.toString(),
        ));
        yield AgentUsageEvent(
            promptTokens: totalPromptTokens,
            completionTokens: totalCompletionTokens,
            cachedTokens: totalCachedTokens);
        yield const AgentStatusEvent(RunStatus.completed);
        return;
      }
      // C3 计划模式门禁：首轮有工具调用时，先产出计划等待用户确认，再执行工具。
      // 只有模型明确以 toolUse 结束本轮时，夹带的调用才具备可执行资格。
      // outputLimit 通常意味着参数可能被截断，其他停因则属于协议矛盾；两者都必须
      // 回灌结构化错误，让模型重新规划，而不是把不完整调用交给真实工具。
      if (stopReason != StopReason.toolUse) {
        messages.add(ChatMessage(
          role: MessageRole.assistant,
          parts: [MessagePart.text(textBuffer.toString())],
          toolCalls: List<ToolCall>.unmodifiable(pendingCalls),
          reasoning:
              reasoningBuffer.isEmpty ? null : reasoningBuffer.toString(),
        ));
        final code = stopReason == StopReason.outputLimit
            ? ToolCodes.truncatedToolCall
            : ToolCodes.unexpectedToolCall;
        final message = stopReason == StopReason.outputLimit
            ? '模型输出达到长度上限，工具参数可能不完整，本次未执行'
            : '模型停因不是工具调用，本次夹带的工具调用未执行';
        for (final pendingCall in pendingCalls) {
          final toolResult = ToolResult.failure(
            code: code,
            message: message,
          );
          yield ToolResultEvent(pendingCall, toolResult);
          messages.add(ChatMessage(
            role: MessageRole.tool,
            toolCallId: pendingCall.id,
            parts: [MessagePart.text(toolResult.encode())],
          ));
        }
        continue;
      }
      var planApproved = false;
      if (step == 0 && confirmPlan != null && pendingCalls.isNotEmpty) {
        final approved = await confirmPlan(pendingCalls, textBuffer.toString());
        if (!approved) {
          yield const AgentStatusEvent(RunStatus.cancelled);
          return;
        }
        planApproved = true;
      }
      messages.add(ChatMessage(
        role: MessageRole.assistant,
        parts: [MessagePart.text(textBuffer.toString())],
        toolCalls: List<ToolCall>.unmodifiable(pendingCalls),
        reasoning: reasoningBuffer.isEmpty ? null : reasoningBuffer.toString(),
      ));
      for (final pendingCall in pendingCalls) {
        final registration = tools.findRegistration(pendingCall.name);
        if (registration == null) {
          final toolResult = ToolResult.failure(
            code: ToolCodes.unknownTool,
            message: '工具未注册：${pendingCall.name}，请改用当前能力目录中的工具',
          );
          yield ToolResultEvent(pendingCall, toolResult);
          messages.add(ChatMessage(
            role: MessageRole.tool,
            toolCallId: pendingCall.id,
            parts: [MessagePart.text(toolResult.encode())],
          ));
          continue;
        }
        if (pendingCall.arguments.containsKey('_unparsed') ||
            pendingCall.arguments
                .containsKey(ContextWindow.truncatedArgumentMark)) {
          final toolResult = ToolResult.failure(
            code: ToolCodes.truncatedToolCall,
            message: '工具参数不完整或超过上下文上限，本次未执行，请重新生成完整参数',
          );
          yield ToolResultEvent(pendingCall, toolResult);
          messages.add(ChatMessage(
            role: MessageRole.tool,
            toolCallId: pendingCall.id,
            parts: [MessagePart.text(toolResult.encode())],
          ));
          continue;
        }
        final validation = schemaValidator.validate(
          pendingCall.arguments,
          registration.spec.parametersSchema,
        );
        if (!validation.isValid) {
          final toolResult = ToolResult.failure(
            code: ToolCodes.invalidArguments,
            message: '工具参数校验失败：${validation.error}',
          );
          yield ToolResultEvent(pendingCall, toolResult);
          messages.add(ChatMessage(
            role: MessageRole.tool,
            toolCallId: pendingCall.id,
            parts: [MessagePart.text(toolResult.encode())],
          ));
          continue;
        }
        final decision = const ApprovalPolicy().decide(
          mode: approvalMode,
          risk: registration.spec.risk,
          sensitive: registration.spec.sensitive,
          trusted: isToolTrusted?.call(
                registration.spec.name,
                registration.spec.risk,
              ) ??
              false,
        );
        if (decision.requiresUser) {
          yield ApprovalRequiredEvent(pendingCall, registration.spec.risk);
          final userDecision =
              await approveTool?.call(pendingCall, registration.spec.risk) ??
                  ToolApproval.reject;
          if (userDecision == ToolApproval.reject) {
            final toolResult = ToolResult.failure(
              code: ToolCodes.approvalRejected,
              message: '用户拒绝了该工具调用，请改用不需要该权限的方案继续',
            );
            yield ToolResultEvent(pendingCall, toolResult);
            messages.add(ChatMessage(
              role: MessageRole.tool,
              toolCallId: pendingCall.id,
              parts: [MessagePart.text(toolResult.encode())],
            ));
            continue;
          }
        }
        if (isCancelled()) {
          yield const AgentStatusEvent(RunStatus.cancelled);
          return;
        }
        await checkpoint();
        if (isCancelled()) {
          yield const AgentStatusEvent(RunStatus.cancelled);
          return;
        }
        yield const AgentStatusEvent(RunStatus.executingTool);
        ToolResult toolResult;
        try {
          // 强制超时：一个卡死的终端命令或网络工具若不设上限，会无限期挂住
          // 整个 Agent 回合。这里只停止"等待"，**不保证中断底层进程/连接**——
          // 现有工具没有统一的取消通道，因此结果按 effect=unknown 上报，让模型
          // 先读取确认而不是盲目重试。
          toolResult = await registration.executor
              .execute(pendingCall.arguments)
              .timeout(
            registration.spec.timeout,
            onTimeout: () => ToolResult.failure(
              code: ToolCodes.timeout,
              message:
                  '工具执行超时（${registration.spec.timeout.inSeconds}s），已中止等待；'
                  '副作用无法确认，请先检查目标状态',
              effect: ToolEffect.unknown,
            ),
          );
        } catch (error) {
          // 异常发生在工具边界内，无法证明副作用是否发生；先让模型确认状态。
          toolResult = ToolResult.failure(
            code: ToolCodes.toolError,
            message: '工具执行异常：$error；副作用无法确认，请先检查目标状态',
            effect: ToolEffect.unknown,
          );
        }
        final metadata = registration.executor is ToolExecutionMetadata
            ? (registration.executor as ToolExecutionMetadata).lastMetadata
            : const <String, dynamic>{};
        yield ToolResultEvent(pendingCall, toolResult, metadata: metadata);
        messages.add(ChatMessage(
            role: MessageRole.tool,
            toolCallId: pendingCall.id,
            parts: [MessagePart.text(toolResult.encode())]));
      }
      // 计划审批只负责放行首轮工具调用。工具返回后必须显式告诉模型继续
      // 执行已批准的计划，否则模型可能把“计划已提交”误判为本轮任务结束。
      if (planApproved) {
        messages.add(ChatMessage(
          role: MessageRole.user,
          parts: [
            MessagePart.text(
              '[计划已确认] 用户已批准执行以上计划。请继续按照计划执行剩余步骤；需要工具时直接调用工具，不要只输出计划或提前结束。完成全部步骤后再总结结果。',
            )
          ],
        ));
      }
      appendSteering(runController?.drainSteering() ?? const []);
    }
    // 达到 maxSteps 不是业务失败：将其区分为可恢复的"预算暂停"状态，并把
    // 当前完整上下文（含工具结果与已批准的续跑指令）一并交给调用方，便于
    // 从断点续跑，而不是重新提交原始 prompt。
    yield const AgentStatusEvent(RunStatus.paused);
    yield AgentBudgetExhaustedEvent(
      context: messages,
      maxSteps: maxSteps,
    );
  }
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
  });
  final List<ChatMessage> context;
  final int maxSteps;
  final String message;
}

class AgentRetryEvent extends AgentEvent {
  const AgentRetryEvent(this.attempt);
  final int attempt;
}

class AgentUsageEvent extends AgentEvent {
  const AgentUsageEvent(
      {required this.promptTokens,
      required this.completionTokens,
      this.cachedTokens = 0});
  final int promptTokens;
  final int completionTokens;
  final int cachedTokens;
}

class ToolResultEvent extends AgentEvent {
  const ToolResultEvent(this.call, this.result,
      {this.metadata = const <String, dynamic>{}});
  final ToolCall call;
  final ToolResult result;
  final Map<String, dynamic> metadata;
}
