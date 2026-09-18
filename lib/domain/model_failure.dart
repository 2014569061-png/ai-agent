enum ModelServiceStatus {
  online,
  offline,
  authRequired,
  rateLimited,
  serverError,
  billing,
  unknown,
}

/// 模型请求失败的重试分类。
///
/// 分类优先使用服务端状态码，再结合错误正文兜底。计费、鉴权、协议和
/// TLS 错误即使带有 429，也不能自动重试；未知错误保留一次有限重试机会，
/// 避免把偶发的 Provider 文案变化直接升级成用户可见失败。
class ModelFailure {
  const ModelFailure({
    required this.retryable,
    required this.kind,
    required this.serviceStatus,
    this.statusCode,
    this.retryAfter,
  });

  final bool retryable;
  final String kind;
  final ModelServiceStatus serviceStatus;
  final int? statusCode;
  final Duration? retryAfter;

  static ModelFailure classify(
    String raw, {
    int? statusCode,
    String? failureKind,
    Duration? retryAfter,
  }) {
    final text = raw.toLowerCase();
    final source = _normalizeFailureKind(failureKind);

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
        serviceStatus: ModelServiceStatus.billing,
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
        serviceStatus: ModelServiceStatus.authRequired,
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
        serviceStatus: ModelServiceStatus.unknown,
        statusCode: statusCode,
      );
    }

    if (statusCode == 429) {
      return ModelFailure(
        retryable: true,
        kind: 'transient',
        serviceStatus: ModelServiceStatus.rateLimited,
        statusCode: statusCode,
        retryAfter: retryAfter,
      );
    }

    if (statusCode != null &&
        const {500, 502, 503, 504, 524, 529}.contains(statusCode)) {
      return ModelFailure(
        retryable: true,
        kind: 'transient',
        serviceStatus: ModelServiceStatus.serverError,
        statusCode: statusCode,
        retryAfter: retryAfter,
      );
    }

    if (statusCode == 408) {
      return ModelFailure(
        retryable: true,
        kind: 'transient',
        serviceStatus: ModelServiceStatus.offline,
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
        serviceStatus: _isRateLimited(text)
            ? ModelServiceStatus.rateLimited
            : _isServerError(text)
                ? ModelServiceStatus.serverError
                : ModelServiceStatus.offline,
        statusCode: statusCode,
        retryAfter: retryAfter,
      );
    }

    if (statusCode != null && statusCode >= 400 && statusCode < 500) {
      return ModelFailure(
        retryable: false,
        kind: 'permanent',
        serviceStatus: ModelServiceStatus.unknown,
        statusCode: statusCode,
      );
    }

    // ProviderErrorEvent 的正文不一定包含可识别状态，保留有限重试行为。
    return ModelFailure(
      retryable: true,
      kind: 'unknown',
      serviceStatus: ModelServiceStatus.unknown,
      statusCode: statusCode,
    );
  }

  static bool _isRateLimited(String text) =>
      _containsAny(text, const ['429', 'rate limit', 'rate_limit']);

  /// 把传输层异常类型归一为提示词。
  ///
  /// [failureKind] 来自 `DioExceptionType.name`（`connectionTimeout` /
  /// `sendTimeout` / `receiveTimeout` / `connectionError` / `badCertificate`
  /// / `badResponse` / `cancel` / `unknown`）。归一后的小写标记会参与下方
  /// 的 `source` 匹配。
  ///
  /// 为什么显式列举而不是直接用 `toLowerCase()`：
  /// `unknown` 是 Dio 的**兜底类型**，它既可能包着「连接被拒」，也可能包着
  /// 「服务端返回了畸形响应」。若不加区分地当作 transient，会把本该提示
  /// 用户检查配置的情况伪装成「稍后重试」。这里把它降级为空标记，交给
  /// 正文与 statusCode 决定，行为更保守。
  ///
  /// 保持向后兼容：无法识别的 kind 仍按原样小写返回，不丢信息。
  static String _normalizeFailureKind(String? failureKind) {
    if (failureKind == null || failureKind.isEmpty) return '';
    return switch (failureKind.toLowerCase()) {
      // 传输层可达性问题 → 归为连接类，映射到 offline。
      'connectiontimeout' => 'connectiontimeout',
      'sendtimeout' => 'sendtimeout',
      'receivetimeout' => 'receivetimeout',
      'connectionerror' => 'connectionerror',
      // 兜底类型不提供可达性证据，交由正文判断。
      'unknown' => '',
      // 其余类型（badCertificate / badResponse / cancel）保留原值，
      // 让上方的协议段与调用方按各自语义处理。
      final other => other,
    };
  }

  static bool _isServerError(String text) => _containsAny(
        text,
        const ['500', '502', '503', '504', '524', '529', 'server error'],
      );

  static bool _containsAny(String value, Iterable<String> markers) =>
      markers.any(value.contains);
}
