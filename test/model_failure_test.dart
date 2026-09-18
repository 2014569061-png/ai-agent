import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/domain/model_failure.dart';

void main() {
  test('billing markers win over a transient 429 status', () {
    final failure = ModelFailure.classify(
      'HTTP 429: insufficient_quota',
      statusCode: 429,
    );

    expect(failure.retryable, isFalse);
    expect(failure.kind, 'billing');
    expect(failure.serviceStatus, ModelServiceStatus.billing);
    expect(failure.statusCode, 429);
  });

  test('authentication and protocol failures are permanent', () {
    final authentication = ModelFailure.classify(
      'HTTP 401 unauthorized',
      statusCode: 401,
    );
    final protocol = ModelFailure.classify(
      'certificate verify failed',
      failureKind: 'badCertificate',
    );

    expect(authentication.retryable, isFalse);
    expect(authentication.kind, 'authentication');
    expect(authentication.serviceStatus, ModelServiceStatus.authRequired);
    expect(protocol.retryable, isFalse);
    expect(protocol.kind, 'protocol');
  });

  test('transient statuses and interrupted IO are retryable', () {
    final serviceUnavailable = ModelFailure.classify(
      'upstream unavailable',
      statusCode: 503,
    );
    final interrupted = ModelFailure.classify(
      'interrupted io',
      failureKind: 'InterruptedIOException',
    );

    expect(serviceUnavailable.retryable, isTrue);
    expect(serviceUnavailable.kind, 'transient');
    expect(serviceUnavailable.serviceStatus, ModelServiceStatus.serverError);
    expect(interrupted.retryable, isTrue);
    expect(interrupted.kind, 'transient');
    expect(interrupted.serviceStatus, ModelServiceStatus.offline);
  });

  test('rate limits retain retry-after metadata', () {
    final failure = ModelFailure.classify(
      'rate limit exceeded',
      statusCode: 429,
      retryAfter: const Duration(seconds: 12),
    );

    expect(failure.serviceStatus, ModelServiceStatus.rateLimited);
    expect(failure.retryAfter, const Duration(seconds: 12));
  });

  test('unknown failures retain bounded retry behavior', () {
    final failure = ModelFailure.classify('provider returned an odd error');

    expect(failure.retryable, isTrue);
    expect(failure.kind, 'unknown');
  });

  // P2-C：传输层异常类型必须映射到用户可理解的服务状态。
  // 这些 kind 来自 DioExceptionType.name，之前只有字符串正文兜底，
  // 没有针对 kind 本身的回归守护。
  group('传输层失败类型映射（P2-C）', () {
    test('三种 timeout 都映射为 offline（而非 serverError）', () {
      for (final kind in const [
        'connectionTimeout',
        'sendTimeout',
        'receiveTimeout',
      ]) {
        final failure = ModelFailure.classify('', failureKind: kind);
        expect(
          failure.serviceStatus,
          ModelServiceStatus.offline,
          reason: '$kind 应提示用户检查网络，而不是「服务端异常」',
        );
        expect(failure.retryable, isTrue, reason: '$kind 应可重试');
      }
    });

    test('connectionError 映射为 offline', () {
      final failure =
          ModelFailure.classify('', failureKind: 'connectionError');
      expect(failure.serviceStatus, ModelServiceStatus.offline);
      expect(failure.retryable, isTrue);
    });

    test('401 映射为 authRequired 且不自动重试', () {
      final failure =
          ModelFailure.classify('unauthorized', statusCode: 401);
      expect(failure.serviceStatus, ModelServiceStatus.authRequired);
      expect(failure.retryable, isFalse);
      // 鉴权失败不能自动重放：重试只会重复失败并可能触发风控。
    });

    test('403 同样归为 authRequired', () {
      final failure = ModelFailure.classify('forbidden', statusCode: 403);
      expect(failure.serviceStatus, ModelServiceStatus.authRequired);
      expect(failure.retryable, isFalse);
    });

    test('429 映射为 rateLimited 并可重试', () {
      final failure = ModelFailure.classify('', statusCode: 429);
      expect(failure.serviceStatus, ModelServiceStatus.rateLimited);
      expect(failure.retryable, isTrue);
    });

    test('5xx 映射为 serverError 并可重试', () {
      for (final status in const [500, 502, 503, 504, 524, 529]) {
        final failure =
            ModelFailure.classify('upstream failed', statusCode: status);
        expect(
          failure.serviceStatus,
          ModelServiceStatus.serverError,
          reason: 'HTTP $status 应提示服务端异常',
        );
        expect(failure.retryable, isTrue);
      }
    });

    test('Dio 的 unknown 兜底类型不冒充可达性结论', () {
      // unknown 既可能是「连接被拒」也可能是「响应畸形」，不应仅凭类型
      // 就下 offline 结论。无正文时可重试，但状态保持 unknown。
      final failure = ModelFailure.classify('', failureKind: 'unknown');
      expect(failure.retryable, isTrue);
      expect(failure.serviceStatus, ModelServiceStatus.unknown);
    });

    test('unknown 类型 + 明确正文仍能正确归类', () {
      expect(
        ModelFailure.classify('connection refused', failureKind: 'unknown')
            .serviceStatus,
        ModelServiceStatus.offline,
      );
      expect(
        ModelFailure.classify('rate limit exceeded', failureKind: 'unknown')
            .serviceStatus,
        ModelServiceStatus.rateLimited,
      );
    });

    test('badCertificate 归为不可重试的协议错误', () {
      final failure = ModelFailure.classify(
        'certificate verify failed',
        failureKind: 'badCertificate',
      );
      expect(failure.kind, 'protocol');
      expect(failure.retryable, isFalse);
    });

    test('无法识别的 kind 不丢失信息（向后兼容）', () {
      final failure = ModelFailure.classify(
        'interrupted io',
        failureKind: 'InterruptedIOException',
      );
      expect(failure.serviceStatus, ModelServiceStatus.offline);
      expect(failure.retryable, isTrue);
    });

    test('失败类型映射不改变原有状态码优先级', () {
      // 计费优先于 429：即使传输层报 timeout，正文已表明额度耗尽。
      final failure = ModelFailure.classify(
        'insufficient_quota',
        statusCode: 429,
        failureKind: 'connectionTimeout',
      );
      expect(failure.serviceStatus, ModelServiceStatus.billing);
      expect(failure.retryable, isFalse);
    });
  });
}
