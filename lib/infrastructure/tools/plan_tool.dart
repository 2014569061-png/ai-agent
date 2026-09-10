import '../../domain/models.dart';
import '../../domain/tool_codes.dart';
import '../../domain/tool_result.dart';
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
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final stepsList = arguments['steps'];
    if (stepsList is! List) {
      return ToolResult.failure(
        code: ToolCodes.invalidArguments,
        message: 'steps 必须是数组',
      );
    }
    final steps = <PlanStep>[];
    for (var i = 0; i < stepsList.length; i++) {
      final item = stepsList[i];
      if (item is! Map) {
        return ToolResult.failure(
          code: ToolCodes.invalidArguments,
          message: 'steps[$i] 必须是对象',
        );
      }
      final id = item['id']?.toString() ?? '';
      final description = item['description']?.toString() ?? '';
      if (id.isEmpty || description.isEmpty) {
        return ToolResult.failure(
          code: ToolCodes.invalidArguments,
          message: 'steps[$i] 缺少 id 或 description',
        );
      }
      steps.add(PlanStep(id: id, description: description));
    }

    try {
      await onPlanUpdated(steps);
    } catch (e) {
      return ToolResult.failure(
        // 原实现把真实异常吞掉只回一句“格式错误”，模型无法判断该修参数还是重试。
        code: ToolCodes.toolError,
        message: '计划提交失败：$e',
        // 回调可能已部分更新计划状态，无法确定是否生效。
        effect: ToolEffect.unknown,
      );
    }
    return ToolResult.success(
      message: '计划已成功提交（${steps.length} 步）',
      data: {'stepCount': steps.length},
      effect: ToolEffect.applied,
    );
  }
}
