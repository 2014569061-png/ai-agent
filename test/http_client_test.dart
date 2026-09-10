import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/infrastructure/providers/http_client.dart';

void main() {
  test('buildHttpClient uses the layered request timeouts', () {
    final dio = buildHttpClient();

    expect(dio.options.connectTimeout, const Duration(seconds: 15));
    expect(dio.options.sendTimeout, const Duration(seconds: 30));
    expect(dio.options.receiveTimeout, const Duration(minutes: 5));
  });

  test('billing 429 is not retried by the Dio interceptor', () async {
    final adapter = _ErrorAdapter(
      statusCode: 429,
      body: const {
        'error': {'code': 'insufficient_quota'},
      },
    );
    final dio = Dio()..httpClientAdapter = adapter;
    dio.interceptors.add(
      RetryInterceptor(
        dio: dio,
        maxRetries: 3,
        baseDelay: Duration.zero,
      ),
    );

    await expectLater(
        dio.get<dynamic>('https://example.test'), throwsA(isA<DioException>()));
    expect(adapter.calls, 1);
  });

  test('transient 503 is retried up to maxRetries', () async {
    final adapter = _ErrorAdapter(statusCode: 503, body: 'unavailable');
    final dio = Dio()..httpClientAdapter = adapter;
    dio.interceptors.add(
      RetryInterceptor(
        dio: dio,
        maxRetries: 2,
        baseDelay: Duration.zero,
      ),
    );

    await expectLater(
        dio.get<dynamic>('https://example.test'), throwsA(isA<DioException>()));
    expect(adapter.calls, 3);
  });

  test('streaming requests bypass automatic retries', () async {
    final adapter = _ErrorAdapter(statusCode: 503, body: 'unavailable');
    final dio = Dio()..httpClientAdapter = adapter;
    dio.interceptors.add(
      RetryInterceptor(
        dio: dio,
        maxRetries: 3,
        baseDelay: Duration.zero,
      ),
    );

    await expectLater(
      dio.get<dynamic>(
        'https://example.test',
        options: Options(responseType: ResponseType.stream),
      ),
      throwsA(isA<DioException>()),
    );
    expect(adapter.calls, 1);
  });
}

class _ErrorAdapter implements HttpClientAdapter {
  _ErrorAdapter({required this.statusCode, required this.body});

  final int statusCode;
  final dynamic body;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    throw DioException(
      requestOptions: options,
      response: Response<dynamic>(
        requestOptions: options,
        statusCode: statusCode,
        data: body,
      ),
      type: DioExceptionType.badResponse,
    );
  }

  @override
  void close({bool force = false}) {}
}
