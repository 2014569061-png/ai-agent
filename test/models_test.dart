import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/models.dart';

void main() {
  group('ChatMessage.text', () {
    test('image part 以占位符呈现，不泄漏 base64 字符串', () {
      final message = ChatMessage(
        role: MessageRole.user,
        parts: [
          const MessagePart.text('看这张图'),
          const MessagePart.image('data:image/png;base64,aGVsbG8='),
          const MessagePart.text('顺便分析'),
          const MessagePart.file('data:text/plain;base64,aGVsbG8=', mimeType: 'text/plain'),
        ],
      );

      expect(message.text, contains('看这张图'));
      expect(message.text, contains('顺便分析'));
      expect(message.text, contains('[图片]'));
      expect(message.text, contains('[文件]'));
      expect(message.text, isNot(contains('base64')));
      expect(message.text, isNot(contains('aGVsbG8')));
      expect(message.text, isNot(contains('data:image')));
    });

    test('纯文本消息不受影响', () {
      final message = ChatMessage(role: MessageRole.assistant, parts: [const MessagePart.text('你好，世界')]);
      expect(message.text, '你好，世界');
    });

    test('空 parts 返回空串', () {
      final message = ChatMessage(role: MessageRole.user, parts: const []);
      expect(message.text, '');
    });
  });
}
