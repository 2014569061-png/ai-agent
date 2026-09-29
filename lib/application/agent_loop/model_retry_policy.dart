import '../../domain/model_failure.dart';
import '../../domain/models.dart';

/// 模型请求失败后的处理决定。
sealed class RetryDecision {
  const RetryDecision(this.failure);
  final ModelFailure failure;
}

/// 不可重试（鉴权、计费、协议等），立即失败。
final class RetryFatal extends RetryDecision {
  const RetryFatal(super.failure);
}

/// 可重试但不能再试：本轮已产出内容（重发会重复渲染或重复副作用），
/// 或次数已用完。以 retryable=true 的错误结束。
final class RetryGiveUp extends RetryDecision {
  const RetryGiveUp(super.failure);
}

/// 等待 [delay] 后整体重发。
final class RetryAfter extends RetryDecision {
  const RetryAfter(super.failure, {required this.attempt, required this.delay});
  final int attempt;
  final Duration delay;
}

/// 模型流式请求的失败重试策略（原先内联在 AgentExecutor.run 中）。
///
/// 只在本轮尚未产出任何内容时重试；指数退避 backoff × 2^(n-1)。
/// Dio 层 RetryInterceptor 对流式请求不重试，这里是 SSE 失败唯一的重试路径。
class ModelRetryPolicy {
  const ModelRetryPolicy({
    this.maxRetries = 3,
    this.backoff = const Duration(seconds: 2),
  });

  final int maxRetries;
  final Duration backoff;

  /// [attempts] 为已经重试过的次数。
  RetryDecision decide(
    ProviderErrorEvent error, {
    required bool hasContent,
    required int attempts,
  }) {
    final classified = ModelFailure.classify(
      error.message,
      statusCode: error.statusCode,
      failureKind: error.failureKind,
    );
    if (!classified.retryable) return RetryFatal(classified);
    if (hasContent || attempts >= maxRetries) return RetryGiveUp(classified);
    final attempt = attempts + 1;
    return RetryAfter(
      classified,
      attempt: attempt,
      delay: backoff * (1 << (attempt - 1)),
    );
  }
}
