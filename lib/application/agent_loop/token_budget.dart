import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart' show CancelToken;

import '../../domain/models.dart';
import '../../infrastructure/providers/llm_provider.dart';

/// A per-run ledger shared by main requests, retries and summarization.
/// Reserve UTF-8 bytes as a conservative text input bound before dispatch;
/// settle from provider usage when available, otherwise keep the reservation.
class TokenBudgetProvider implements LlmProvider {
  TokenBudgetProvider(this.delegate, this.limit, {this.onDispatch});
  final LlmProvider delegate;
  final int limit;
  final void Function(UnifiedRequest request)? onDispatch;
  int spent = 0;
  static const exhausted = 'token_budget_exhausted';

  static int inputReservation(UnifiedRequest request) {
    if (request.messages.any((m) => m.parts.any((p) => p.type != 'text'))) {
      // No local upper bound for provider-specific image/audio tokenization.
      return 1 << 30;
    }
    final data = {
      'messages': [
        for (final m in request.messages)
          {
            'role': m.role.name,
            'content': m.text,
            if (m.reasoning != null) 'reasoning': m.reasoning,
            if (m.toolCallId != null) 'tool_call_id': m.toolCallId,
            if (m.toolCalls.isNotEmpty)
              'tool_calls': [
                for (final c in m.toolCalls)
                  {'id': c.id, 'name': c.name, 'arguments': c.arguments}
              ],
          }
      ],
      'tools': [
        for (final t in request.tools)
          {
            'name': t.name,
            'description': t.description,
            'parameters': t.parametersSchema
          }
      ],
    };
    return utf8.encode(jsonEncode(data)).length +
        128 +
        request.messages.length * 32;
  }

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    final input = inputReservation(request);
    final output = math.min(request.maxTokens, limit - spent - input);
    if (output < 1) {
      yield ProviderErrorEvent('累计 token 预算不足（已结算 $spent / $limit），已停止后续请求',
          failureKind: exhausted);
      return;
    }
    final reserved = input + output;
    spent += reserved;
    var reported = false;
    var actual = 0;
    var completed = false;
    var failed = false;
    final bounded = UnifiedRequest(
        model: request.model,
        costRunId: request.costRunId,
        costRequestId: request.costRequestId,
        costPurpose: request.costPurpose,
        messages: request.messages,
        tools: request.tools,
        temperature: request.temperature,
        maxTokens: output,
        topP: request.topP,
        reasoningEffort: request.reasoningEffort);
    try {
      onDispatch?.call(bounded);
      await for (final event
          in delegate.stream(bounded, cancelToken: cancelToken)) {
        if (event is CompletedEvent) completed = true;
        if (event is ProviderErrorEvent) failed = true;
        if (event is UsageEvent && event.usageReported) {
          reported = true;
          actual += math.max(0, event.promptTokens) +
              math.max(0, event.completionTokens);
        }
        yield event;
      }
    } finally {
      // Missing usage, errors and cancellation cannot grant free retries.
      if (reported &&
          completed &&
          !failed &&
          !(cancelToken?.isCancelled ?? false) &&
          actual > 0) {
        spent += actual - reserved;
      } else if (actual > reserved) {
        spent += actual - reserved;
      }
    }
  }
}
