import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/tools/tool_humanizer.dart';

void main() {
  const humanizer = ToolHumanizer();

  ToolCall call(String name, Map<String, dynamic> arguments) => ToolCall(
        id: name,
        name: name,
        arguments: arguments,
      );

  test('humanizes memory and skills tools for the activity timeline', () {
    expect(
      humanizer.summaryOf(call('memory_get', {'query': '用户偏好'})),
      '检索记忆 “用户偏好”',
    );
    expect(
      humanizer.summaryOf(call('skills_read', {'skill': 'code-review'})),
      '读取 Skill code-review',
    );
  });

  test('humanizes delegated work using the actual prompt parameter', () {
    expect(
      humanizer.summaryOf(call('sub_agent', {'prompt': '核对测试覆盖'})),
      '委派子 Agent：核对测试覆盖',
    );
  });
}
