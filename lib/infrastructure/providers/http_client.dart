import 'dart:math';

import 'package:dio/dio.dart';

import '../../domain/model_failure.dart';

/// 共享 HTTP 客户端工厂。
///
/// 统一为三个 LLM Provider 提供带重试能力的 [Dio] 实例，并设置默认连接与
/// 接收超时，避免无响应的上游让 Agent 卡在"运行中"。
Dio buildHttpClient({
  int maxRetries = 3,
  Duration connectTimeout = const Duration(seconds: 15),
  Duration sendTimeout = const Duration(seconds: 30),
  Duration receiveTimeout = const Duration(minutes: 5),
}) {
  final dio = Dio(BaseOptions(
    connectTimeout: connectTimeout,
    sendTimeout: sendTimeout,
    receiveTimeout: receiveTimeout,
  ));
  dio.interceptors.add(RetryInterceptor(dio: dio, maxRetries: maxRetries));
  return dio;
}

/// 5xx / 网络错误自动重试（指数退避）。
///
/// 规则：
/// - 4xx（除 429 外）不重试，直接透传错误；
/// - 5xx 与连接/超时错误最多重试 [maxRetries] 次，间隔 500ms·2^n；
/// - 主动取消（[DioExceptionType.cancel]）不重试。
class RetryInterceptor extends Interceptor {
  RetryInterceptor(
      {required this.dio,
      this.maxRetries = 3,
      this.baseDelay = const Duration(milliseconds: 500)});

  final Dio dio;
  final int maxRetries;
  final Duration baseDelay;

  static const _retryCountKey = 'nexus.retry_count';

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // 主动取消或证书问题：不重试。
    if (err.type == DioExceptionType.cancel ||
        err.type == DioExceptionType.badCertificate ||
        err.type == DioExceptionType.unknown &&
            err.message?.contains('cancelled') == true) {
      handler.next(err);
      return;
    }

    // 流式请求（SSE）不重试：流中段失败时整体重发会导致已输出的
    // 文本重复渲染、服务端重复计费。
    if (err.requestOptions.responseType == ResponseType.stream) {
      handler.next(err);
      return;
    }

    final status = err.response?.statusCode;
    final detail = err.response?.data?.toString() ?? err.message ?? '';
    final failure = ModelFailure.classify(
      detail,
      statusCode: status,
      failureKind: err.type.name,
    );
    // 计费、鉴权、协议和证书失败即使返回 429，也不能自动重放请求。
    if (!failure.retryable) {
      handler.next(err);
      return;
    }
    // 4xx（除 429 限流）不重试 —— 客户端错误重试无意义。
    if (status != null && status >= 400 && status < 500 && status != 429) {
      handler.next(err);
      return;
    }

    final retryable = failure.retryable &&
        (status == null ||
            (status >= 500) ||
            status == 429 ||
            err.type == DioExceptionType.connectionError ||
            err.type == DioExceptionType.connectionTimeout ||
            err.type == DioExceptionType.sendTimeout ||
            err.type == DioExceptionType.receiveTimeout);
    if (!retryable) {
      handler.next(err);
      return;
    }

    final attempts = (err.requestOptions.extra[_retryCountKey] as int?) ?? 0;
    if (attempts >= maxRetries) {
      handler.next(err);
      return;
    }

    // B-12：不原地修改 err.requestOptions.extra —— 复制一份再带计数重发，
    // 防御未来 RequestOptions 被复用时的计数串扰。
    final retryOptions = err.requestOptions.copyWith(
      extra: <String, Object?>{
        ...err.requestOptions.extra,
        _retryCountKey: attempts + 1,
      },
    );
    final delay = baseDelay * pow(2, attempts);
    final cancelToken = err.requestOptions.cancelToken;
    if (cancelToken != null) {
      await Future.any<void>([
        Future<void>.delayed(delay),
        cancelToken.whenCancel.then<void>((_) {}),
      ]);
      if (cancelToken.isCancelled) {
        handler.next(err);
        return;
      }
    } else {
      await Future<void>.delayed(delay);
    }

    try {
      final response = await dio.fetch<dynamic>(retryOptions);
      handler.resolve(response);
    } catch (retryError) {
      handler.next(err);
    }
  }
}
