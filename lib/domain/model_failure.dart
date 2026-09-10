/// 模型请求失败的重试分类。
///
/// 分类优先使用服务端状态码，再结合错误正文兜底。计费、鉴权、协议和
/// TLS 错误即使带有 429，也不能自动重试；未知错误保留一次有限重试机会，
/// 避免把偶发的 Provider 文案变化直接升级成用户可见失败。
class ModelFailure {
  const ModelFailure({
    required this.retryable,
    required this.kind,
    this.statusCode,
  });

  final bool retryable;
  final String kind;
  final int? statusCode;

  static ModelFailure classify(
    String raw, {
    int? statusCode,
    String? failureKind,
  }) {
    final text = raw.toLowerCase();
    final source = failureKind?.toLowerCase() ?? '';

    if (_containsAny(text, const [
      'insufficient_quota',
      'quota_exceeded',
      'billing_error',
      'usage_limit_reached',
      'payment_required',
      'credit balance',
      'billing hard limit',
      'insufficient credits',
    ])) {
      return ModelFailure(
        retryable: false,
        kind: 'billing',
        statusCode: statusCode,
      );
    }

    if (_containsAny(text, const [
          'invalid_api_key',
          'invalid api key',
          'unauthorized',
          'authentication',
          'forbidden',
          'permission denied',
          'access denied',
        ]) ||
        statusCode == 401 ||
        statusCode == 403) {
      return ModelFailure(
        retryable: false,
        kind: 'authentication',
        statusCode: statusCode,
      );
    }

    if (_containsAny(text, const [
          'protocol error',
          'invalid json',
          'malformed',
          'unexpected end',
          'bad certificate',
          'certificate verify failed',
          'ssl_error',
          'ssl error',
          'tls',
        ]) ||
        source.contains('badcertificate') ||
        statusCode == 400 ||
        statusCode == 422) {
      return ModelFailure(
        retryable: false,
        kind: 'protocol',
        statusCode: statusCode,
      );
    }

    if (statusCode != null &&
        const {408, 429, 500, 502, 503, 504, 524, 529}.contains(statusCode)) {
      return ModelFailure(
        retryable: true,
        kind: 'transient',
        statusCode: statusCode,
      );
    }

    if (_containsAny(text, const [
          '408',
          '429',
          '500',
          '502',
          '503',
          '504',
          '524',
          '529',
          'rate limit',
          'rate_limit',
          'timeout',
          'timed out',
          'socketexception',
          'failed host lookup',
          'connection refused',
          'connection reset',
          'connection error',
          'network is unreachable',
          'temporarily unavailable',
          'interruptedioexception',
          'interrupted io',
          'interrupted',
        ]) ||
        _containsAny(source, const [
          'connectiontimeout',
          'receivetimeout',
          'sendtimeout',
          'connectionerror',
          'unknown',
        ])) {
      return ModelFailure(
        retryable: true,
        kind: 'transient',
        statusCode: statusCode,
      );
    }

    if (statusCode != null && statusCode >= 400 && statusCode < 500) {
      return ModelFailure(
        retryable: false,
        kind: 'permanent',
        statusCode: statusCode,
      );
    }

    // ProviderErrorEvent 的正文不一定包含可识别状态，保留有限重试行为。
    return ModelFailure(
      retryable: true,
      kind: 'unknown',
      statusCode: statusCode,
    );
  }

  static bool _containsAny(String value, Iterable<String> markers) =>
      markers.any(value.contains);
}
