import '../../domain/models.dart';
import 'tool_registry.dart';

/// 子 Agent 工具（C7）：主 Agent 可派生子 Agent（不同系统提示词）执行子任务并返回摘要。
/// 危险工具在子 Agent 内部递归走父级审批（由 HeadlessExecutor 仅放行 safe 工具兜底，嵌套受限）。
class SubAgentTool implements AgentTool {
  SubAgentTool({required this.onRun});

  /// 回调注入（由 ChatController 连接 HeadlessExecutor 与 DB）。
  final Future<String> Function(String? agentId, String prompt) onRun;

  @override
  final manifest = const UnifiedTool(
    name: 'sub_agent',
    description: '派生子 Agent（不同系统提示词）执行子任务并返回摘要。',
    parametersSchema: {
      'type': 'object',
      'properties': {
        'agentId': {'type': 'string', 'description': '子 Agent 的 id（可省略，取第一个）'},
        'prompt': {'type': 'string', 'description': '子任务描述'},
      },
      'required': ['prompt'],
    },
    risk: ToolRisk.requiresConfirmation,
  );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final agentId = arguments['agentId'] as String?;
    final prompt = (arguments['prompt'] as String? ?? '').trim();
    if (prompt.isEmpty) return '请提供子任务描述';
    return onRun(agentId, prompt);
  }
}
