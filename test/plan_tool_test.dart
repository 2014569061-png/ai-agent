import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/infrastructure/tools/plan_tool.dart';

void main() {
  test('ManagePlanTool submits valid steps via callback', () async {
    List<PlanStep>? submitted;
    final tool = ManagePlanTool(
      onPlanUpdated: (steps) async {
        submitted = steps;
      },
    );

    final result = await tool.execute({
      'steps': [
        {'id': 's1', 'description': '查询天气'},
        {'id': 's2', 'description': '写总结'},
      ],
    });

    expect(result.ok, isTrue);
    expect(result.code, ToolCodes.ok);
    expect(result.message, contains('计划已成功提交'));
    expect(result.effect.name, 'applied');
    expect(submitted, hasLength(2));
    expect(submitted!.first.id, 's1');
    expect(submitted!.first.description, '查询天气');
  });

  test('ManagePlanTool returns friendly error on malformed input', () async {
    final tool = ManagePlanTool(onPlanUpdated: (_) async {});

    final result = await tool.execute({'steps': 'not-a-list'});

    expect(result.ok, isFalse);
    expect(result.code, ToolCodes.invalidArguments);
    expect(result.message, contains('steps'));
  });
}
