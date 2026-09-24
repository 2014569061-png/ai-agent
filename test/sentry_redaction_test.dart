import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/observability/sentry_service.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  group('SentryService.redactSecrets', () {
    test('遮蔽 sk- 前缀的 Provider 密钥', () {
      const message = 'DioException: 401 {"error":"Invalid API key sk-proj-AbCdEf123456"}';

      final redacted = SentryService.redactSecrets(message);

      expect(redacted, isNot(contains('sk-proj-AbCdEf123456')));
      expect(redacted, contains('[已脱敏]'));
      // 非敏感上下文必须保留，否则崩溃报告失去定位价值。
      expect(redacted, contains('DioException'));
      expect(redacted, contains('401'));
    });

    test('遮蔽 Google 与 GitHub 形态的密钥', () {
      final redacted = SentryService.redactSecrets(
        'AIzaSyA1B2C3D4E5F6G7H8I9J0 and ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345',
      );

      expect(redacted, isNot(contains('AIzaSyA1B2C3D4E5F6G7H8I9J0')));
      expect(redacted, isNot(contains('ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345')));
      expect(redacted, contains('[已脱敏]'));
    });

    test('遮蔽 Authorization Bearer 头', () {
      final redacted =
          SentryService.redactSecrets('headers: {Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.payload}');

      expect(redacted, isNot(contains('eyJhbGciOiJIUzI1NiJ9.payload')));
      // 关键字保留，便于判断是哪一类凭据泄露。
      expect(redacted, contains('Bearer'));
    });

    test('保留字段名，只遮蔽取值', () {
      final redacted = SentryService.redactSecrets('{"api_key": "abcdef123456"}');

      expect(redacted, contains('api_key'));
      expect(redacted, isNot(contains('abcdef123456')));
      expect(redacted, contains('[已脱敏]'));
    });

    test('普通错误文本不被改动', () {
      const message = 'SocketException: Connection refused (port 8080)';

      expect(SentryService.redactSecrets(message), message);
    });

    test('空字符串安全返回', () {
      expect(SentryService.redactSecrets(''), '');
    });
  });

  // 这段逻辑原先内联在 init() 的 beforeSend 闭包里，只有真的初始化过 SDK 才可能
  // 跑到 —— 等于隐私承诺只写在注释里。抽出来之后它可以被直接断言。
  group('SentryService.sanitizeEvent', () {
    SentryEvent buildEvent({
      SentryRequest? request,
      List<SentryException>? exceptions,
      List<Breadcrumb>? breadcrumbs,
    }) =>
        SentryEvent(
          request: request,
          exceptions: exceptions,
          breadcrumbs: breadcrumbs,
        );

    test('请求 URL 丢掉查询串与 fragment', () {
      final event = SentryService.sanitizeEvent(buildEvent(
        request: SentryRequest(
          url: 'https://api.example.com/v1/chat?api_key=SECRET-123#frag',
          method: 'POST',
        ),
      ));

      final url = event.request!.url!;
      expect(url, isNot(contains('SECRET-123')));
      expect(url, isNot(contains('?')));
      expect(url, isNot(contains('#')));
      // 路径与主机保留，否则崩溃报告失去定位价值。
      expect(url, contains('https://api.example.com/v1/chat'));
      expect(event.request!.method, 'POST');
    });

    test('鉴权头被移除，普通头保留', () {
      final event = SentryService.sanitizeEvent(buildEvent(
        request: SentryRequest(
          url: 'https://api.example.com/v1/chat',
          headers: {
            'Authorization': 'Bearer sk-abcdefghijklmnop',
            'X-Api-Key': 'sk-abcdefghijklmnop',
            'Cookie': 'session=abc123',
            'Content-Type': 'application/json',
          },
        ),
      ));

      final keys =
          event.request!.headers.keys.map((k) => k.toLowerCase()).toSet();
      expect(keys, isNot(contains('authorization')));
      expect(keys, isNot(contains('x-api-key')));
      expect(keys, isNot(contains('cookie')));
      expect(event.request!.headers['Content-Type'], 'application/json');
    });

    test('异常消息里的凭据被兜底脱敏，类型仍保留', () {
      final event = SentryService.sanitizeEvent(buildEvent(
        exceptions: [
          SentryException(
            type: 'DioException',
            value: 'DioException: 401 {"error":"Invalid key sk-proj-AbCdEf123456"}',
          ),
        ],
      ));

      final exception = event.exceptions!.single;
      expect(exception.value, isNot(contains('sk-proj-AbCdEf123456')));
      expect(exception.value, contains('[已脱敏]'));
      expect(exception.type, 'DioException');
    });

    test('面包屑被整体丢弃（自动集成会塞进含查询串的 URL）', () {
      final event = SentryService.sanitizeEvent(buildEvent(
        breadcrumbs: [
          Breadcrumb(
            message: 'GET https://api.example.com/v1?api_key=SECRET-123',
          ),
        ],
      ));

      expect(event.breadcrumbs, isEmpty);
    });

    test('没有请求与异常时安全返回', () {
      final event = SentryService.sanitizeEvent(buildEvent());

      expect(event.request, isNull);
      expect(event.breadcrumbs, isEmpty);
    });
  });
}
