// 整轮成功触感：计数只在成功时增加，UI 只在计数增加时触发。
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/presentation/chat/chat_page.dart';

void main() {
  test('successfulRunCount 默认 0，copyWith 不传时保持原值', () {
    const base = ChatState();
    expect(base.successfulRunCount, 0);
    final bumped = base.copyWith(successfulRunCount: 2);
    expect(bumped.successfulRunCount, 2);
    expect(bumped.copyWith(running: false).successfulRunCount, 2);
  });

  test('runSucceededBetween 只在计数增加时为真', () {
    const a = ChatState();
    final b = a.copyWith(successfulRunCount: 1);
    expect(runSucceededBetween(a, b), isTrue);
    expect(runSucceededBetween(b, b.copyWith(running: false)), isFalse);
    // 新会话重建状态、计数归零时不触发。
    expect(runSucceededBetween(b, a), isFalse);
  });
}
