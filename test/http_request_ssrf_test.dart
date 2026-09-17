import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/tools/core_tools.dart';

/// SSRF 回归测试。
///
/// 背景：`HttpRequestTool` 此前自带一套私有黑名单（`_blockedUrl`），只拦
/// `0.0.0.0` / `169.254.*` / `.internal` / `.local`，**漏掉全部 RFC1918 私网段**。
/// 统一策略 `NetworkAccessPolicy` 早已存在且实现完整，但这个全应用最高频的
/// 网络出口没用它——同一策略两处实现，弱的那处必然被绕过。
///
/// 本文件锁定两件事：
/// 1. 私网地址一律拒绝（防止弱黑名单被改回来）；
/// 2. 重定向不再被自动跟随，避免「校验原始 URL 却被 302 绕开」。
void main() {
  /// 记录实际发出的请求，用于判定"是否真的发出去过"。
  late List<String> requestedUrls;

  /// 构造一个不触网的 Dio：拦截器直接给出响应，不发真实请求。
  Dio buildDio({
    int statusCode = 200,
    Map<String, List<String>>? headers,
    Object? data,
  }) {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 1),
      receiveTimeout: const Duration(seconds: 1),
      followRedirects: false,
    ));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        requestedUrls.add(options.uri.toString());
        handler.resolve(Response<dynamic>(
          requestOptions: options,
          statusCode: statusCode,
          headers: headers == null
              ? null
              : Headers.fromMap(headers),
          data: data,
        ));
      },
    ));
    return dio;
  }

  setUp(() => requestedUrls = <String>[]);

  group('http_request 私网地址拦截（SSRF 回归）', () {
    // 这些正是旧私有黑名单漏掉的地址。
    const privateUrls = <String>[
      'http://10.0.0.1/admin',
      'http://10.255.255.254/',
      'http://172.16.0.1/',
      'http://172.31.255.254/',
      'http://192.168.1.1/admin',
      'http://192.168.100.200:8080/status',
    ];

    for (final url in privateUrls) {
      test('拒绝私网地址 $url', () async {
        final dio = buildDio();
        final tool = HttpRequestTool(dio: dio);
        final result = await tool.execute({'url': url, 'method': 'GET'});

        expect(result.ok, isFalse, reason: '私网地址必须被拒绝：$url');
        expect(requestedUrls, isEmpty, reason: '被拒绝的地址不得发出请求：$url');
      });
    }

    test('拒绝云元数据与链路本地地址', () async {
      for (final url in [
        'http://169.254.169.254/latest/meta-data/',
        'http://0.0.0.0/',
      ]) {
        final dio = buildDio();
        final tool = HttpRequestTool(dio: dio);
        final result = await tool.execute({'url': url, 'method': 'GET'});
        expect(result.ok, isFalse, reason: '必须拒绝：$url');
        expect(requestedUrls, isEmpty);
      }
    });

    test('拒绝本机回环地址', () async {
      for (final url in ['http://localhost:8080/', 'http://127.0.0.1/']) {
        final dio = buildDio();
        final tool = HttpRequestTool(dio: dio);
        final result = await tool.execute({'url': url, 'method': 'GET'});
        expect(result.ok, isFalse, reason: '必须拒绝：$url');
      }
    });

    test('拒绝非 http/https 协议', () async {
      final dio = buildDio();
      final tool = HttpRequestTool(dio: dio);
      final result =
          await tool.execute({'url': 'file:///etc/passwd', 'method': 'GET'});
      expect(result.ok, isFalse);
      expect(requestedUrls, isEmpty);
    });

    test('公网地址仍可正常请求（防止修得过头）', () async {
      final dio = buildDio(data: {'ok': true});
      final tool = HttpRequestTool(dio: dio);
      final result = await tool
          .execute({'url': 'https://api.example.com/v1/data', 'method': 'GET'});

      expect(result.ok, isTrue);
      expect(requestedUrls, ['https://api.example.com/v1/data']);
    });
  });

  group('重定向不得绕过地址校验', () {
    test('公网地址 302 指向私网时，不跟随且不放行', () async {
      // 第一跳是公网（校验通过），响应要求重定向到内网。
      final dio = buildDio(
        statusCode: 302,
        headers: {'location': ['http://192.168.1.1/admin']},
      );
      final tool = HttpRequestTool(dio: dio);
      final result = await tool
          .execute({'url': 'https://evil.example.com/redirect', 'method': 'GET'});

      // 关键断言：内网地址**从未被请求**。
      expect(
        requestedUrls,
        isNot(contains('http://192.168.1.1/admin')),
        reason: '重定向目标若是私网，绝不能被请求',
      );
      expect(result.ok, isFalse);
    });

    test('重定向到云元数据同样被拦截', () async {
      final dio = buildDio(
        statusCode: 307,
        headers: {'location': ['http://169.254.169.254/latest/meta-data/']},
      );
      final tool = HttpRequestTool(dio: dio);
      await tool
          .execute({'url': 'https://evil.example.com/r', 'method': 'GET'});
      expect(requestedUrls, isNot(contains('http://169.254.169.254/latest/meta-data/')));
    });

    test('链式重定向到公网可完成，且每跳都被校验', () async {
      var hop = 0;
      final dio = Dio(BaseOptions(followRedirects: false));
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          requestedUrls.add(options.uri.toString());
          hop++;
          if (hop == 1) {
            handler.resolve(Response<dynamic>(
              requestOptions: options,
              statusCode: 302,
              headers: Headers.fromMap({
                'location': ['https://cdn.example.com/final'],
              }),
            ));
          } else {
            handler.resolve(Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {'done': true},
            ));
          }
        },
      ));

      final tool = HttpRequestTool(dio: dio);
      final result = await tool
          .execute({'url': 'https://start.example.com/a', 'method': 'GET'});

      expect(result.ok, isTrue);
      expect(requestedUrls, [
        'https://start.example.com/a',
        'https://cdn.example.com/final',
      ]);
    });

    test('重定向次数过多时中止（防循环）', () async {
      // 永远 302 到自己，验证有跳数上限。
      final dio = Dio(BaseOptions(followRedirects: false));
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          requestedUrls.add(options.uri.toString());
          handler.resolve(Response<dynamic>(
            requestOptions: options,
            statusCode: 302,
            headers: Headers.fromMap({
              'location': ['https://loop.example.com/'],
            }),
          ));
        },
      ));

      final tool = HttpRequestTool(dio: dio);
      final result = await tool
          .execute({'url': 'https://loop.example.com/', 'method': 'GET'});

      expect(result.ok, isFalse);
      // 上限 5 跳：首次 + 至多 5 次跟随，不应无限增长。
      expect(requestedUrls.length, lessThanOrEqualTo(6));
    });
  });
}
