import '../../domain/tool_result_truncation.dart';
import '../../domain/models.dart';
import '../../domain/tool_codes.dart';
import '../../domain/tool_result.dart';
import 'sub_agent_tool.dart';
import 'tool_registry.dart';

/// A single approved tool invocation with bounded, independently settled jobs.
/// This does not parallelize the general mutating-tool execution pipeline.
class ParallelSubAgentsTool implements AgentTool {
  ParallelSubAgentsTool({required this.onRun, this.risk = ToolRisk.safe});
  final Future<String> Function(String?, String, int?) onRun;
  final ToolRisk risk;
  @override
  UnifiedTool get manifest => UnifiedTool(
          name: 'sub_agents',
          risk: risk,
          timeout: const Duration(minutes: 5),
          description:
              '并行执行 1–3 个独立只读子任务；每项返回独立状态和摘要。没有写入或终端权限。每轮输出上限之和不超过12000；各项累计输入+输出预算为输出上限的4倍（整批≤48000），含重试和摘要。',
          parametersSchema: {
            'type': 'object',
            'properties': {
              'tasks': {
                'type': 'array',
                'minItems': 1,
                'maxItems': 3,
                'items': {
                  'type': 'object',
                  'properties': {
                    'id': {'type': 'string'},
                    'prompt': {'type': 'string'},
                    'agentId': {'type': 'string'},
                    'maxTokens': {
                      'type': 'integer',
                      'minimum': 500,
                      'maximum': 8000
                    },
                  },
                  'required': ['id', 'prompt'],
                }
              },
            },
            'required': ['tasks']
          });

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final tasks = arguments['tasks'];
    final ids = <String>{};
    var allocated = 0;
    if (tasks is! List || tasks.isEmpty || tasks.length > 3) return _invalid();
    for (final task in tasks) {
      if (task is! Map ||
          task['id'] is! String ||
          (task['id'] as String).trim().isEmpty ||
          (task['id'] as String).length > 100 ||
          !ids.add(task['id'] as String) ||
          task['prompt'] is! String ||
          (task['prompt'] as String).trim().isEmpty ||
          (task['prompt'] as String).length > 12000 ||
          (task['agentId'] != null && task['agentId'] is! String)) {
        return _invalid();
      }
      final budget = task['maxTokens'] ?? 4000;
      if (budget is! int || budget < 500 || budget > 8000) return _invalid();
      allocated += budget;
    }
    if (allocated > 12000) return _invalid();
    final results = await Future.wait(tasks.map((raw) async {
      final task = raw as Map;
      final result = await SubAgentTool(onRun: onRun).execute({
        'prompt': task['prompt'],
        'agentId': task['agentId'],
        'maxTokens': task['maxTokens'] ?? 4000,
      });
      final text = result.data?['partialSummary']?.toString() ??
          result.data?['text']?.toString() ??
          result.message;
      return {
        'id': task['id'],
        'ok': result.ok,
        'code': result.code,
        if (result.data?['stopReason'] != null)
          'stopReason': result.data!['stopReason'],
        if (result.data?['inputTokens'] != null)
          'inputTokens': result.data!['inputTokens'],
        if (result.data?['outputTokens'] != null)
          'outputTokens': result.data!['outputTokens'],
        'summary': ToolResultTruncation.truncate(text, 3500),
        'truncated': text.length > 3500,
        'totalTokenBudget': (task['maxTokens'] as int? ?? 4000) * 4,
        'budget': task['maxTokens'] ?? 4000
      };
    }));
    final failed = results.where((r) => r['ok'] != true).length;
    return ToolResult(
        ok: failed == 0,
        code: failed == 0 ? ToolCodes.ok : ToolCodes.toolError,
        message: '${results.length - failed} 个子任务成功，$failed 个失败；逐项检查 results',
        data: {
          'results': results,
          'allocatedBudget': allocated,
          'totalTokenBudget': allocated * 4,
          'isolation': 'separate-context-read-only'
        });
  }

  ToolResult _invalid() => ToolResult.failure(
      code: ToolCodes.invalidArguments,
      message: '需要1–3个唯一id与非空prompt；每项预算500–8000，总预算≤12000');
}
