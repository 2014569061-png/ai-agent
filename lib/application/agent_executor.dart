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
    // G1:Android 上 terminal 工具的 go/bash 等经 Termux 桥在本机执行,具备完整
    // Go 工具链。显式告知模型本机可编译,避免其基于常识让用户"去 Windows 编译"。
    var systemText = systemPrompt?.trim() ?? '';
    if (systemText.isNotEmpty &&
        Platform.isAndroid &&
        tools.manifests.any((t) => t.name == 'terminal')) {
      systemText += '\n\n[运行环境说明] 当前运行在 Android 手机上,terminal 工具中的 '
          'go/gofmt/bash/sh/curl/jq/make/zig 会自动转交本机 Termux 沙箱执行(内置完整 Go '
          '工具链与网络)。因此:Go 程序可以直接在本机编写并运行 go vet / go test 验证,'
          '用 GOOS=windows GOARCH=amd64 go build -o <名字>.exe . 交叉编译出 Windows exe,'
          '产物直接落在工作区目录。编译或测试报错时直接修改代码重试;'
          '绝对不要让用户"到 Windows 电脑上手动编译",也不要声称本环境无法构建。';
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
        await Future<void>.delayed(retryBackoff * attempts);
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
      if (step == 0 && confirmPlan != null && pendingCalls.isNotEmpty) {
        final approved = await confirmPlan(pendingCalls, textBuffer.toString());
        if (!approved) {
          yield const AgentStatusEvent(RunStatus.cancelled);
          return;
        }
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
    }
    yield const AgentErrorEvent('Agent 已达到最大执行步数');
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
