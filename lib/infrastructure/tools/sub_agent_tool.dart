import '../../domain/models.dart';
import '../../domain/tool_codes.dart';
import '../../domain/tool_result.dart';
import 'tool_registry.dart';

class SubAgentFailure implements Exception {
  const SubAgentFailure(this.code,
      {this.partialText, this.inputTokens = 0, this.outputTokens = 0});
  final String code;
  final String? partialText;
  final int inputTokens;
  final int outputTokens;
}

/// 子 Agent 工具（C7）：主 Agent 可派生子 Agent（不同系统提示词）执行子任务并返回摘要。
/// 危险工具在子 Agent 内部递归走父级审批（由 HeadlessExecutor 仅放行 safe 工具兜底，嵌套受限）。
///
/// 默认采用"自主安全策略"：sub_agent 调用本身视为 safe（自动放行），子 Agent 内部
/// 仍只放行安全工具；可通过 [risk] 配置为 requiresConfirmation 以回退到审批模式。
/// 可通过可选的 `maxTokens` 字段为子任务分配受限 token 预算，越界值会被钳制到
/// [minBudget]~[maxBudget] 之间。
class SubAgentTool implements AgentTool {
  SubAgentTool({required this.onRun, this.risk = ToolRisk.safe});

  /// 回调注入（由 ChatController 连接 HeadlessExecutor 与 DB）。
  /// [budget] 为主 Agent 申请的受限 token 预算（可能为 null，由 ChatController 钳制）。
  final Future<String> Function(String? agentId, String prompt, int? budget)
      onRun;

  /// sub_agent 调用自身的风险等级。默认 safe（自主），可配置为
  /// requiresConfirmation 以兼容审批模式。
  final ToolRisk risk;

  /// 受限预算钳制上下限（与协作预算 maxTokens 对齐）。
  static const int minBudget = 500;
  static const int maxBudget = 8000;

  /// 钳制主 Agent 申请的预算：缺省返回上限，越界收敛到 [minBudget, maxBudget]。
  static int clampBudget(int? budget) {
    if (budget == null) return maxBudget;
    return budget.clamp(minBudget, maxBudget);
  }

  @override
  UnifiedTool get manifest => UnifiedTool(
        name: 'sub_agent',
        description: '派生子 Agent（不同系统提示词）执行子任务并返回摘要。',
        parametersSchema: {
          'type': 'object',
          'properties': {
            'agentId': {
              'type': 'string',
              'description': '子 Agent 的 id（可省略，取第一个）'
            },
            'prompt': {'type': 'string', 'description': '子任务描述'},
            'maxTokens': {
              'type': 'integer',
              'minimum': minBudget,
              'maximum': maxBudget,
              'description':
                  '单次输出上限（$minBudget~$maxBudget），累计输入+输出预算为该值的4倍，含重试与摘要',
            },
          },
          'required': ['prompt'],
        },
        risk: risk,
      );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    if ((arguments['agentId'] != null && arguments['agentId'] is! String) ||
        arguments['prompt'] is! String ||
        (arguments['maxTokens'] != null && arguments['maxTokens'] is! int)) {
      return ToolResult.failure(
          code: ToolCodes.invalidArguments,
          message: 'prompt/agentId 必须是字符串，maxTokens 必须是整数');
    }
    final agentId = arguments['agentId'] as String?;
    final prompt = (arguments['prompt'] as String).trim();
    if (prompt.isEmpty) {
      return ToolResult.failure(
        code: ToolCodes.invalidArguments,
        message: '请提供子任务描述（prompt 不能为空）',
      );
    }
    final budget = (arguments['maxTokens'] as num?)?.toInt();
    final String summary;
    try {
      summary = await onRun(agentId, prompt, clampBudget(budget));
    } on SubAgentFailure catch (error) {
      return ToolResult.failure(
          code: error.code,
          data: error.code == ToolCodes.tokenBudgetExhausted
              ? {
                  'partialSummary': error.partialText ?? '',
                  'inputTokens': error.inputTokens,
                  'outputTokens': error.outputTokens,
                  'stopReason': 'cumulative_token_budget',
                }
              : null,
          message: error.code == ToolCodes.tokenBudgetExhausted
              ? '子任务累计 token 预算不足，已保留进度。请汇总已有结果，不要自动重派相同任务重置预算。'
              : '子任务未成功完成，请检查任务状态后调整方案。');
    } catch (_) {
      return ToolResult.failure(
          code: ToolCodes.toolError, message: '子任务执行失败，内部异常已隐藏；请检查运行日志。');
    }
    return ToolResult.text(
      summary,
      extra: {
        if (agentId != null) 'agentId': agentId,
        'budget': clampBudget(budget),
        'totalTokenBudget': clampBudget(budget) * 4,
      },
    );
  }
}
