import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart' show CancelToken;

import '../../domain/models.dart';
import '../../domain/unique_id.dart';
import '../database/app_database.dart';
import '../database/cost_budget_ledger.dart';
import '../database/database_provider.dart';
import 'cost_budget_policy.dart';
import 'llm_provider.dart';
import 'provider_config.dart';

class CostBudgetProvider implements LlmProvider {
  CostBudgetProvider(
    this.delegate,
    this.config, {
    Future<AppDatabase> Function()? database,
    Future<CostBudgetPolicy> Function()? policy,
    DateTime Function()? now,
  })  : database = database ?? (() => DatabaseProvider.instance.database),
        policy = policy ?? const CostBudgetService().loadPolicy,
        now = now ?? DateTime.now;

  final LlmProvider delegate;
  final ProviderConfig config;
  final Future<AppDatabase> Function() database;
  final Future<CostBudgetPolicy> Function() policy;
  final DateTime Function() now;
  static const exhausted = 'COST_BUDGET_EXHAUSTED';
  static const pricingUnavailable = 'COST_PRICING_UNAVAILABLE';

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    if (cancelToken?.isCancelled ?? false) return;
    final limits = await policy();
    final inputRate = config.inputPricePerMillionCents;
    final outputRate = config.outputPricePerMillionCents;
    final hasPrice = inputRate != null &&
        outputRate != null &&
        inputRate >= 0 &&
        outputRate >= 0;
    final media =
        request.messages.any((m) => m.parts.any((p) => p.type != 'text'));
    if (limits.hardStopEnabled && (!hasPrice || media)) {
      yield const ProviderErrorEvent(
          '费用硬停已开启；请先配置模型输入/输出单价。图片或音频请求缺少可靠费用上界，未发送请求。',
          failureKind: pricingUnavailable);
      return;
    }
    final canPrice = hasPrice && !media;
    // Even explicitly permitted unpriced calls get a durable unknown-cost row.
    final input = utf8
            .encode(jsonEncode({
              'messages': [
                for (final m in request.messages)
                  {
                    'role': m.role.name,
                    'text': m.text,
                    'reasoning': m.reasoning,
                    'toolCallId': m.toolCallId,
                    'toolCalls': [
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
            }))
            .length +
        128 +
        request.messages.length * 32;
    int cost(int inputTokens, int outputTokens) =>
        ((math.max(0, inputTokens) * (inputRate ?? 0) +
                    math.max(0, outputTokens) * (outputRate ?? 0)) /
                1000000)
            .ceil();
    final reservation = canPrice ? cost(input, request.maxTokens) : 0;
    final ledger = CostBudgetLedger(await database());
    final admission = await ledger.reserve(limits, reservation,
        now: now(),
        runId: request.costRunId,
        requestId: request.costRequestId ?? UniqueId.generate('request'),
        providerId: config.id,
        model: request.model,
        purpose: request.costPurpose,
        priced: canPrice,
        inputRate: inputRate,
        outputRate: outputRate);
    if (admission.id == null) {
      yield ProviderErrorEvent(admission.evaluation.reason,
          failureKind: admission.evaluation.errorCode ?? exhausted);
      return;
    }
    var reported = false, completed = false, failed = false;
    var prompt = 0, completion = 0;
    try {
      // Cancellation before dispatch is the only known zero-cost outcome.
      if (cancelToken?.isCancelled ?? false) {
        await ledger.settle(admission.id!, 0,
            reason: 'cancelled_before_dispatch');
        return;
      }
      await for (final event
          in delegate.stream(request, cancelToken: cancelToken)) {
        if (event is UsageEvent && event.usageReported) {
          reported = true;
          prompt += math.max(0, event.promptTokens);
          completion += math.max(0, event.completionTokens);
        }
        if (event is CompletedEvent) completed = true;
        if (event is ProviderErrorEvent) failed = true;
        yield event;
      }
    } catch (_) {
      failed = true;
      rethrow;
    } finally {
      // Ambiguous cancellation, failures and missing usage retain the reservation
      // rather than granting retries free budget.
      if (canPrice &&
          reported &&
          completed &&
          !failed &&
          !(cancelToken?.isCancelled ?? false)) {
        await ledger.settle(admission.id!, cost(prompt, completion),
            promptTokens: prompt, completionTokens: completion);
      } else {
        await ledger.markPending(
            admission.id!,
            !canPrice
                ? 'unpriced'
                : (cancelToken?.isCancelled ?? false)
                    ? 'cancelled'
                    : failed
                        ? 'provider_failure'
                        : 'missing_usage',
            observedCents:
                canPrice && reported ? cost(prompt, completion) : null);
      }
    }
  }
}
