import '../domain/models.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/providers/anthropic_provider.dart';
import '../infrastructure/providers/gemini_provider.dart';
import '../infrastructure/providers/llm_provider.dart';
import '../infrastructure/providers/openai_compatible_provider.dart';
import '../infrastructure/providers/proxy_provider.dart';
import '../infrastructure/providers/provider_config.dart';
import '../infrastructure/tools/core_tools.dart';
import '../infrastructure/tools/image_gen_tool.dart';
import '../infrastructure/tools/tool_registry.dart';
import 'agent_executor.dart';
import 'knowledge_service.dart';
import 'memory_service.dart';

import '../infrastructure/skills/skill_store.dart';

/// 无 UI 运行 Agent（C5 定时任务 + C2 后台任务复用）。
/// 危险工具在后台自动拒绝（无用户可审批），只放行 safe 工具。
class HeadlessExecutor {
  static Future<String> run({
    required AppDatabase db,
    required ProviderConfig config,
    required String prompt,
    String? systemPrompt,
  }) async {
    final provider =
        config.isConfigured ? _buildProvider(config) : DemoProvider();
    final registry = ToolRegistry()
      ..register(CalculatorTool())
      ..register(GetTimeTool())
      ..register(JsonQueryTool())
      ..register(ImageGenTool(config: config));
    final executor = AgentExecutor(provider: provider, tools: registry);

    var system = systemPrompt ?? '你是一个有帮助的 AI Agent。';
    try {
      final memoryBlock = await MemoryService().buildInjectionBlock(db);
      if (memoryBlock.isNotEmpty) system = '$memoryBlock\n$system';
      final knowledgeBlock =
          await KnowledgeService().buildInjectionBlock(db, prompt);
      if (knowledgeBlock.isNotEmpty) system = '$knowledgeBlock\n$system';
      // 与聊天路径保持一致：后台任务同样注入已启用 Skill 的指令块。
      final skillBlock = await SkillStore().buildInjectionBlock(db);
      if (skillBlock.isNotEmpty) system = '$skillBlock\n$system';
    } catch (_) {
      // 注入失败不阻断执行。
    }

    final history = [
      ChatMessage(role: MessageRole.user, parts: [MessagePart.text(prompt)])
    ];
    final answer = StringBuffer();
    try {
      await for (final event in executor.run(
        history: history,
        model: config.isConfigured ? config.model : 'demo-model',
        systemPrompt: system,
        capabilities: ModelCapabilities.infer(config.model),
        maxSteps: 4,
        contextBudgetTokens: config.contextTokens,
        // 无 UI 的后台路径（子 Agent/定时任务）没有真人审批，非 safe 工具一律拒绝。
        approveTool: (call, risk) async => risk == ToolRisk.safe
            ? ToolApproval.allowOnce
            : ToolApproval.reject,
      )) {
        if (event is TextEvent) answer.write(event.text);
      }
    } catch (error) {
      answer.write('\n\n错误：$error');
    }
    return answer.toString().trim();
  }

  static LlmProvider _buildProvider(ProviderConfig config) {
    switch (config.type) {
      case ProviderType.anthropic:
        return AnthropicProvider(config: config);
      case ProviderType.gemini:
        return GeminiProvider(config: config);
      case ProviderType.openaiCompatible:
        return OpenAiCompatibleProvider(config: config);
      case ProviderType.proxy:
        return ProxyProvider(
            backendBaseUrl: config.baseUrl,
            managedKey: config.apiKey,
            model: config.model);
    }
  }
}
