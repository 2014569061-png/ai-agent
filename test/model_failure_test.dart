import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/model_failure.dart';

void main() {
  test('billing markers win over a transient 429 status', () {
    final failure = ModelFailure.classify(
      'HTTP 429: insufficient_quota',
      statusCode: 429,
    );

    expect(failure.retryable, isFalse);
    expect(failure.kind, 'billing');
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
    expect(interrupted.retryable, isTrue);
    expect(interrupted.kind, 'transient');
  });

  test('unknown failures retain bounded retry behavior', () {
    final failure = ModelFailure.classify('provider returned an odd error');

    expect(failure.retryable, isTrue);
    expect(failure.kind, 'unknown');
  });
}
