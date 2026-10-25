import '../../domain/models.dart';
import '../../domain/tool_codes.dart';
import '../../domain/tool_result.dart';
import 'tool_registry.dart';

class IsolatedSubAgentTool implements AgentTool, ToolExecutionMetadata {
  IsolatedSubAgentTool({required this.onRun});
  final Future<Map<String, dynamic>> Function(String prompt, int budget) onRun;
  @override
  Map<String, dynamic> lastMetadata = const {};
  @override
  final manifest = const UnifiedTool(
    name: 'sub_agent_edit',
    risk: ToolRisk.requiresConfirmation,
    timeout: Duration(minutes: 10),
    description:
        '在当前 Git 工作区快照的独立 worktree 中委派文件编辑，返回待审阅提案，绝不自动合入父工作区。包括未提交和非忽略未跟踪文件。禁止终端、网络工具、Git 元数据写入及再次委派。需审批；单次输出500–8000 token，累计预算4倍。',
    parametersSchema: {
      'type': 'object',
      'properties': {
        'prompt': {'type': 'string'},
        'maxTokens': {'type': 'integer', 'minimum': 500, 'maximum': 8000},
      },
      'required': ['prompt']
    },
  );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    lastMetadata = const {};
    final prompt = arguments['prompt'];
    final budget = arguments['maxTokens'] ?? 4000;
    if (prompt is! String ||
        prompt.trim().isEmpty ||
        prompt.length > 12000 ||
        budget is! int ||
        budget < 500 ||
        budget > 8000) {
      return ToolResult.failure(
          code: ToolCodes.invalidArguments,
          message: '需要 1–12000 字符 prompt 和 500–8000 整数 maxTokens');
    }
    try {
      final result = await onRun(prompt, budget);
      lastMetadata = {
        'isolatedProposal': true,
        'status': result['status'],
        'workspace': result['workspace'],
        'reportPath': result['reportPath'],
        'changeCount': result['changeCount'],
      };
      final ok = result['status'] == 'review_required';
      return ToolResult(
          ok: ok,
          code: ok ? ToolCodes.ok : ToolCodes.toolError,
          message: ok ? '隔离编辑已产出待审阅提案，尚未应用或验证' : '隔离子任务未完成，检查保留的报告',
          effect: ToolEffect.applied,
          data: result);
    } catch (_) {
      return ToolResult.failure(
          code: ToolCodes.toolError,
          message:
              '无法建立隔离子任务，请检查 Git 仓库、快照限制与取消状态。可能留下工作区元数据，请先检查 .nexus/worktrees。',
          effect: ToolEffect.unknown);
    }
  }
}
