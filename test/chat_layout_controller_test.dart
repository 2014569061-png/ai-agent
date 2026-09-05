import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/presentation/chat/chat_layout_controller.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ChatLayoutController.widthFactor.value = ChatLayoutController.adaptive;
  });

  test('persists a custom bubble width', () async {
    await ChatLayoutController.setWidthFactor(.8);

    expect(ChatLayoutController.widthFactor.value, .8);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getDouble('chat.bubble_width'), .8);
  });

  test('clamps invalid custom widths to the supported range', () async {
    await ChatLayoutController.setWidthFactor(2);
    expect(
        ChatLayoutController.widthFactor.value, ChatLayoutController.customMax);

    await ChatLayoutController.setWidthFactor(double.nan);
    expect(
        ChatLayoutController.widthFactor.value, ChatLayoutController.adaptive);
  });
}
