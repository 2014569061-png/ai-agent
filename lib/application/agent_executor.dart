import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;

import '../domain/models.dart';
import '../infrastructure/providers/llm_provider.dart';
import '../infrastructure/tools/tool_registry.dart';
import '../infrastructure/providers/provider_config.dart';
import 'context_window.dart';
import 'approval_policy.dart';

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
    Duration requestTimeout = const Duration(seconds: 90),
    int contextBudgetTokens = ContextWindow.defaultMaxTokens,
    int maxRetries = 2,
    Duration retryBackoff = const Duration(seconds: 1),
    AgentCancellationToken? cancellationToken,
    CancelToken? cancelToken,
    Future<ToolApproval> Function(ToolCall call, ToolRisk risk)? approveTool,
    ApprovalMode approvalMode = ApprovalMode.ask,
    bool Function(String toolName, ToolRisk risk)? isToolTrusted,
    String? systemPrompt,
    ModelCapabilities capabilities = const ModelCapabilities(),
    Future<bool> Function(List<ToolCall> calls, String planText)? confirmPlan,
  }) async* {
    var messages = List<ChatMessage>.of(history);
    // Android 上 terminal 优先使用内置 Alpine Linux，必要时回退到 Termux。
    // 显式告知模型本机有 Linux shell，避免其基于常识让用户"去 Windows 编译"。
    var systemText = systemPrompt?.trim() ?? '';
    if (systemText.isNotEmpty &&
        Platform.isAndroid &&
        tools.manifests.any((t) => t.name == 'terminal')) {
      systemText += '\n\n[运行环境说明] 当前运行在 Android 手机上。terminal 工具优先使用内置 '
          'Alpine Linux（PRoot + ARM64 rootfs），不可用时回退到 Termux，再回退到 Android Shell。'
          '内置 Alpine 默认是精简 rootfs，提供 sh/ash/BusyBox 基础命令；Go/Git/Node/Python 等工具'
          '可能尚未安装，需要先在 Alpine 中执行 apk add，或使用已配置的 Termux 工具链。'
          '因此不要默认声称环境无法运行 Linux 命令；编译或测试报错时先检查当前 Runtime 和缺失工具，'
          '再安装依赖或切换备用 Runtime。';
    }
    if (systemText.isNotEmpty &&
        !messages.any((m) => m.role == MessageRole.system)) {
      messages.insert(
          0,
          ChatMessage(
              role: MessageRole.system, parts: [MessagePart.text(systemText)]));
    }
    // 上下文预算：每步请求前裁剪一次，同时约束初始历史与多步工具循环
    // 中持续追加的工具结果。
    final contextWindow = ContextWindow(maxTokens: contextBudgetTokens);
    var totalPromptTokens = 0;
    var totalCompletionTokens = 0;
    var totalCachedTokens = 0;
    for (var step = 0; step < maxSteps; step++) {
      if (cancellationToken?.isCancelled ?? false) {
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
            if (cancellationToken?.isCancelled ?? false) {
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
          // 超时也要真正中断底层 HTTP 流，避免连接泄漏/随后读取到陈旧流。
          cancelToken?.cancel();
          yield AgentErrorEvent('模型请求超时（${requestTimeout.inSeconds} 秒）');
          return;
        }
        if (failure == null) break;
        final hasContent = textBuffer.isNotEmpty ||
            reasoningBuffer.isNotEmpty ||
            pendingCalls.isNotEmpty;
        if (hasContent || attempts >= maxRetries) {
          yield AgentErrorEvent(failure.message);
          return;
        }
        attempts++;
        yield AgentRetryEvent(attempts);
        if (cancellationToken?.isCancelled ?? false) {
          yield const AgentStatusEvent(RunStatus.cancelled);
          return;
        }
        var remaining = retryBackoff * attempts;
        while (remaining > Duration.zero &&
            !(cancellationToken?.isCancelled ?? false)) {
          final slice = remaining < const Duration(milliseconds: 100)
              ? remaining
              : const Duration(milliseconds: 100);
          await Future<void>.delayed(slice);
          remaining -= slice;
        }
      }
      // 流被主动取消（底层 HTTP 已真正中断）时，不产出 completed。
      if (cancellationToken?.isCancelled ?? false) {
        cancelToken?.cancel();
        yield const AgentStatusEvent(RunStatus.cancelled);
        return;
      }
      if (pendingCalls.isEmpty) {
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
        final tool = tools.find(pendingCall.name);
        if (tool == null) {
          yield AgentErrorEvent('未注册工具：${pendingCall.name}');
          return;
        }
        final decision = const ApprovalPolicy().decide(
          mode: approvalMode,
          risk: tool.manifest.risk,
          sensitive: tool.manifest.sensitive,
          trusted:
              isToolTrusted?.call(tool.manifest.name, tool.manifest.risk) ??
                  false,
        );
        if (decision.requiresUser) {
          yield ApprovalRequiredEvent(pendingCall, tool.manifest.risk);
          final userDecision =
              await approveTool?.call(pendingCall, tool.manifest.risk) ??
                  ToolApproval.reject;
          if (userDecision == ToolApproval.reject) {
            yield const AgentStatusEvent(RunStatus.cancelled);
            return;
          }
        }
        if (cancellationToken?.isCancelled ?? false) {
          yield const AgentStatusEvent(RunStatus.cancelled);
          return;
        }
        yield const AgentStatusEvent(RunStatus.executingTool);
        String result;
        try {
          result = await tool.execute(pendingCall.arguments);
        } catch (error) {
          result = '工具执行失败：$error';
        }
        final metadata = tool is ToolExecutionMetadata
            ? (tool as ToolExecutionMetadata).lastMetadata
            : const <String, dynamic>{};
        yield ToolResultEvent(pendingCall, result, metadata: metadata);
        messages.add(ChatMessage(
            role: MessageRole.tool,
            toolCallId: pendingCall.id,
            parts: [MessagePart.text(result)]));
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
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
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
  const AgentErrorEvent(this.message);
  final String message;
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
  final String result;
  final Map<String, dynamic> metadata;
}
