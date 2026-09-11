import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/chat_controller.dart';

void main() {
  test('session skill instructions are cleared explicitly', () {
    const state = ChatState(
      sessionSkillInstructions: [
        SessionSkillInstruction(id: 'skill-1', name: 'build', content: 'body'),
      ],
    );

    final cleared = state.copyWith(clearSessionSkillInstructions: true);

    expect(cleared.sessionSkillInstructions, isEmpty);
    expect(state.sessionSkillInstructions, hasLength(1));
  });

  test('session skill instructions retain identity for removal', () {
    const first = SessionSkillInstruction(id: 'one', name: 'one', content: 'a');
    const second =
        SessionSkillInstruction(id: 'two', name: 'two', content: 'b');
    const state = ChatState(sessionSkillInstructions: [first, second]);

    final remaining = state.sessionSkillInstructions
        .where((item) => item.id != 'one')
        .toList(growable: false);

    expect(remaining.single.id, 'two');
  });
}
