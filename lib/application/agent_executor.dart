import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;

import '../domain/models.dart';
import '../infrastructure/providers/llm_provider.dart';
import '../infrastructure/tools/tool_registry.dart';
import '../infrastructure/providers/provider_config.dart';

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
    AgentCancellationToken? cancellationToken,
    CancelToken? cancelToken,
    Future<bool> Function(ToolCall call, ToolRisk risk)? approveTool,
    String? systemPrompt,
    ModelCapabilities capabilities = const ModelCapabilities(),
  }) async* {
    var messages = List<ChatMessage>.of(history);
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty && !messages.any((m) => m.role == MessageRole.system)) {
      messages.insert(0, ChatMessage(role: MessageRole.system, parts: [MessagePart.text(systemPrompt.trim())]));
    }
    var totalPromptTokens = 0;
    var totalCompletionTokens = 0;
    for (var step = 0; step < maxSteps; step++) {
      if (cancellationToken?.isCancelled ?? false) {
        yield const AgentStatusEvent(RunStatus.cancelled);
        return;
      }
      yield const AgentStatusEvent(RunStatus.waitingModel);
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
      final pendingCalls = <ToolCall>[];
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
          } else if (event is ToolCallEvent) {
            pendingCalls.add(event.call);
            yield ToolRequestedEvent(event.call);
          } else if (event is UsageEvent) {
            totalPromptTokens += event.promptTokens;
            totalCompletionTokens += event.completionTokens;
          } else if (event is ProviderErrorEvent) {
            yield AgentErrorEvent(event.message);
            return;
          }
        }
      } on TimeoutException {
        yield AgentErrorEvent('模型请求超时（${requestTimeout.inSeconds} 秒）');
        return;
      }
      // 流被主动取消（底层 HTTP 已真正中断）时，不产出 completed。
      if (cancellationToken?.isCancelled ?? false) {
        yield const AgentStatusEvent(RunStatus.cancelled);
        return;
      }
      if (pendingCalls.isEmpty) {
        messages.add(ChatMessage(role: MessageRole.assistant, parts: [MessagePart.text(textBuffer.toString())]));
        yield AgentUsageEvent(promptTokens: totalPromptTokens, completionTokens: totalCompletionTokens);
        yield const AgentStatusEvent(RunStatus.completed);
        return;
      }
      messages.add(ChatMessage(
        role: MessageRole.assistant,
        parts: [MessagePart.text(textBuffer.toString())],
        toolCalls: List<ToolCall>.unmodifiable(pendingCalls),
      ));
      for (final pendingCall in pendingCalls) {
        final tool = tools.find(pendingCall.name);
        if (tool == null) {
          yield AgentErrorEvent('未注册工具：${pendingCall.name}');
          return;
        }
        if (tool.manifest.risk != ToolRisk.safe) {
          yield ApprovalRequiredEvent(pendingCall, tool.manifest.risk);
          final approved = await approveTool?.call(pendingCall, tool.manifest.risk) ?? false;
          if (!approved) {
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
        yield ToolResultEvent(pendingCall, result);
        messages.add(ChatMessage(role: MessageRole.tool, toolCallId: pendingCall.id, parts: [MessagePart.text(result)]));
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

sealed class AgentEvent { const AgentEvent(); }
class AgentStatusEvent extends AgentEvent { const AgentStatusEvent(this.status); final RunStatus status; }
class TextEvent extends AgentEvent { const TextEvent(this.text); final String text; }
class ToolRequestedEvent extends AgentEvent { const ToolRequestedEvent(this.call); final ToolCall call; }
class ApprovalRequiredEvent extends AgentEvent { const ApprovalRequiredEvent(this.call, this.risk); final ToolCall call; final ToolRisk risk; }
class AgentErrorEvent extends AgentEvent { const AgentErrorEvent(this.message); final String message; }
class AgentUsageEvent extends AgentEvent {
  const AgentUsageEvent({required this.promptTokens, required this.completionTokens});
  final int promptTokens;
  final int completionTokens;
}
class ToolResultEvent extends AgentEvent {
  const ToolResultEvent(this.call, this.result);
  final ToolCall call;
  final String result;
}
