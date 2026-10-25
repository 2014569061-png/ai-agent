import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;

import '../domain/model_failure.dart';
import '../domain/models.dart';
import '../infrastructure/providers/llm_provider.dart';
import 'run_event_tracker.dart';

LlmProvider withModelTrace(LlmProvider provider, RunEventTracker? tracker) =>
    tracker == null ? provider : TracedModelProvider(provider, tracker);

/// One span per subscription/attempt, including retries and summaries.
/// Never records prompts, generated text, arguments, URLs or raw error bodies.
class TracedModelProvider implements LlmProvider {
  TracedModelProvider(this.delegate, this.tracker);
  final LlmProvider delegate;
  final RunEventTracker tracker;

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    if (cancelToken?.isCancelled ?? false) return;
    tracker.currentRequestId = request.costRequestId;
    tracker.currentModelSpanId = null;
    final handle = await tracker
        .start(type: 'model_attempt', name: 'provider_attempt', metadata: {
      'model': request.model,
      'purpose': request.costPurpose,
    });
    tracker.currentModelSpanId = handle?.eventId;
    final watch = Stopwatch()..start();
    int? firstTokenMs, firstTextMs;
    var completed = false, failed = false, usageReported = false;
    var prompt = 0, completion = 0;
    String? category;
    int? statusCode;
    try {
      await for (final event
          in delegate.stream(request, cancelToken: cancelToken)) {
        if ((event is TextDeltaEvent && event.text.isNotEmpty) ||
            (event is ReasoningDeltaEvent && event.text.isNotEmpty)) {
          firstTokenMs ??= watch.elapsedMilliseconds;
        }
        if (event is TextDeltaEvent && event.text.isNotEmpty) {
          firstTextMs ??= watch.elapsedMilliseconds;
        }
        if (event is CompletedEvent) completed = true;
        if (event is UsageEvent && event.usageReported) {
          usageReported = true;
          prompt += event.promptTokens < 0 ? 0 : event.promptTokens;
          completion += event.completionTokens < 0 ? 0 : event.completionTokens;
        }
        if (event is ProviderErrorEvent) {
          failed = true;
          category = ModelFailure.classify('',
                  failureKind: event.failureKind, statusCode: event.statusCode)
              .kind;
          statusCode = event.statusCode;
        }
        yield event;
      }
    } on TimeoutException {
      failed = true;
      category = 'timeout';
      rethrow;
    } catch (_) {
      failed = true;
      category = 'provider_exception';
      rethrow;
    } finally {
      watch.stop();
      final cancelled = cancelToken?.isCancelled ?? false;
      final status = cancelled
          ? 'cancelled'
          : failed
              ? 'failed'
              : completed
                  ? 'success'
                  : 'unknown';
      await tracker.finish(handle, status: status, metadata: {
        'outcome': status,
        'failureCategory': cancelled
            ? 'cancelled'
            : category ?? (completed ? null : 'stream_incomplete'),
        'httpStatus': statusCode,
        'firstTokenMs': firstTokenMs,
        'firstTextMs': firstTextMs,
        'usageReported': usageReported,
        'reportedPromptTokens': usageReported ? prompt : null,
        'reportedCompletionTokens': usageReported ? completion : null,
        'timingScope': 'subscription_to_stream_end_including_backpressure',
      });
    }
  }
}
