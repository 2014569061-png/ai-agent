import '../../domain/models.dart';
import 'tool_registry.dart';

class ManagePlanTool implements AgentTool {
  ManagePlanTool({required this.onPlanUpdated});

  final Future<void> Function(List<PlanStep> steps) onPlanUpdated;

  @override
  final manifest = const UnifiedTool(
    name: 'manage_plan',
    description: '创建或更新分步执行计划。必须在计划模式的首步调用此工具，传入严格的 JSON 步骤数组。',
    risk: ToolRisk.safe,
    parametersSchema: {
      'type': 'object',
      'properties': {
        'steps': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string', 'description': '步骤唯一标识符（如 s1, s2）'},
              'description': {'type': 'string', 'description': '步骤的详细描述'},
            },
            'required': ['id', 'description'],
          },
          'description': '执行计划的步骤数组',
        },
      },
      'required': ['steps'],
    },
  );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    try {
      final stepsList = arguments['steps'] as List;
      final steps = stepsList.map((s) {
        final map = s as Map<String, dynamic>;
        return PlanStep(
          id: map['id']?.toString() ?? '',
          description: map['description']?.toString() ?? '',
        );
      }).toList();

      await onPlanUpdated(steps);
      return '计划已成功提交。';
    } catch (e) {
      return '计划提交失败：格式错误 ';
    }
  }
}
