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

  test('shows the reviewed Android operation details in approval summaries',
      () {
    final lines = humanizer.paramLines(call('android_device', {
      'action': 'delete_root_file',
      '_approvalDetails': {
        'target': '/data/local/tmp/report.txt',
        'scope': 'single file',
        'impact': 'permanent deletion',
        'command': 'su -c rm',
        'executionPlan': 'delete only the listed file',
        'reversible': false,
        'rollback': 'restore from a backup',
      },
    }));

    expect(
        lines.map((line) => line.$1),
        containsAll([
          '目标',
          '影响范围',
          '影响',
          'Root 命令',
          '执行计划',
          '可撤销',
        ]));
    expect(lines.first.$2, '/data/local/tmp/report.txt');
  });
}
