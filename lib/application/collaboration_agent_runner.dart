import 'package:crypto/crypto.dart';

import 'agent_executor.dart';
import 'headless_executor.dart';
import '../domain/collaboration_models.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/providers/provider_config.dart';

abstract interface class CollaborationAgentRunner {
  Future<CollaborationAgentOutput> run({
    required CollaborationAgentRole role,
    required String taskPrompt,
    required String context,
    required ProviderConfig config,
    required AppDatabase db,
    String? workspacePath,
    required int maxTokens,
    required AgentCancellationToken cancellationToken,
  });
}

/// Adapter that reuses the existing headless executor while keeping the
/// collaboration module independent from provider and tool implementations.
class HeadlessCollaborationAgentRunner implements CollaborationAgentRunner {
  const HeadlessCollaborationAgentRunner();

  static const _readOnlyTools = <String>{
    'calculator',
    'get_time',
    'json_query',
    'read_file',
    'list_directory',
    'search_files',
    'memory_get',
    'skills_read',
    'skills_read_resource',
  };

  @override
  Future<CollaborationAgentOutput> run({
    required CollaborationAgentRole role,
    required String taskPrompt,
    required String context,
    required ProviderConfig config,
    required AppDatabase db,
    String? workspacePath,
    required int maxTokens,
    required AgentCancellationToken cancellationToken,
  }) async {
    final systemPrompt = '''
你是${role.label}，职责是：${role.responsibility}。
这是 v0.9 协作分析。你是只读子 Agent，不得写文件、执行命令、提交 Git、联网提交或继续派生子 Agent。
只使用分配给你的工具：${role.allowedTools.join('、')}。
请只输出 JSON，字段必须包含：summary、findings、actions、evidence、nextSteps、risks、confidence。
findings 是对象数组，每项包含 title、detail、severity、evidence、recommendation。
如果证据不足，明确写入 risks，不要把猜测当成事实。
''';
    final prompt = '''
【主任务】
$taskPrompt

【授权上下文】
$context

请围绕你的职责提交结构化结论。不要输出 Markdown 代码围栏。
''';
    final result = await HeadlessExecutor.runDetailed(
      db: db,
      config: config,
      prompt: prompt,
      systemPrompt: systemPrompt,
      workspacePath: workspacePath,
      // 角色清单只是候选声明，最终再与只读投影求交，防止未来新增角色
      // 时误把 write/edit/terminal 等有副作用工具带入交叉验证。
      allowedToolNames:
          role.allowedTools.where(_readOnlyTools.contains).toSet().toList(),
      // 只读协作至少需要一轮“调用工具 -> 回灌结果 -> 输出结论”；
      // maxSteps=1 会把工具调用结果永远截断在模型之外。
      maxSteps: 3,
      maxTokens: maxTokens,
      cancellationToken: cancellationToken,
    );
    return CollaborationAgentOutput(
      role: role,
      text: result.text,
      inputTokens: result.inputTokens,
      outputTokens: result.outputTokens,
      cachedTokens: result.cachedTokens,
      failed: !result.succeeded,
      error: result.error,
    );
  }

  static String digest(String value) {
    return sha256.convert(value.codeUnits).toString();
  }
}
