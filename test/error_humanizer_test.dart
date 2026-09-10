import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/error_humanizer.dart';

void main() {
  group('humanizeError 规则映射', () {
    test('CORS / XMLHttpRequest → 浏览器拦截提示', () {
      final h = humanizeError(
          'The XMLHttpRequest onError callback was called. This typically '
          'indicates an error on the network layer. CORS preflight failed');
      expect(h.summary, contains('浏览器拦截'));
      expect(h.detail, contains('XMLHttpRequest'));
    });

    test('SocketException → 连不上服务', () {
      final h =
          humanizeError("SocketException: Failed host lookup: 'api.x.com'");
      expect(h.summary, contains('连不上模型服务'));
    });

    test('TimeoutException → 请求超时', () {
      final h = humanizeError('TimeoutException after 30s');
      expect(h.summary, contains('超时'));
    });

    test('401 / invalid_api_key → 密钥无效', () {
      expect(
          humanizeError('Error 401: invalid_api_key').summary, contains('密钥'));
      expect(humanizeError('403 permission denied').summary, contains('密钥'));
    });

    test('429 → 限流', () {
      expect(humanizeError('429 rate limit exceeded').summary, contains('限流'));
    });

    test('5xx → 服务不可用', () {
      expect(humanizeError('HTTP 502 bad gateway').summary, contains('不可用'));
    });

    test('未知错误 → 兜底文案且保留原文', () {
      final h = humanizeError('some totally unknown failure');
      expect(h.summary, contains('技术细节'));
      expect(h.detail, 'some totally unknown failure');
    });
  });

  group('formatErrorForMessage / splitErrorDetail 往返', () {
    test('写入后可拆回：主文本含人话，detail 为原文', () {
      final raw = 'CORS request blocked';
      final message = formatErrorForMessage(raw);
      expect(message.startsWith('错误：'), isTrue);

      final split = splitErrorDetail(message);
      expect(split.main, contains('浏览器拦截'));
      expect(split.main.contains('CORS request blocked'), isFalse);
      expect(split.detail, raw);
    });

    test('无标记的普通文本 → main 原样返回', () {
      const text = '你好，这是一个普通回答。';
      final split = splitErrorDetail(text);
      expect(split.main, text);
      expect(split.detail, isNull);
    });

    test('旧消息兜底：错误段超长且无标记时自动折叠', () {
      final legacy = '前面的回答内容\n\n错误：${'x' * 300}';
      final split = splitErrorDetail(legacy);
      expect(split.main, '前面的回答内容');
      expect(split.detail, '错误：${'x' * 300}');
    });

    test('旧消息兜底：短错误不折叠', () {
      const legacy = '错误：短错误';
      final split = splitErrorDetail(legacy);
      expect(split.detail, isNull);
    });
  });
}
