import 'package:shared_preferences/shared_preferences.dart';

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
import '../infrastructure/tools/workspace_tools.dart';
import 'agent_executor.dart';
import 'knowledge_service.dart';
import 'memory_service.dart';

import '../infrastructure/skills/skill_store.dart';

/// 无 UI 运行 Agent（C5 定时任务 + C2 后台任务复用）。
/// 危险工具在后台自动拒绝（无用户可审批），只放行 safe 工具。
class HeadlessRunResult {
  const HeadlessRunResult({
    required this.text,
    required this.status,
    required this.inputTokens,
    required this.outputTokens,
    required this.cachedTokens,
    this.error,
  });

  final String text;
  final RunStatus status;
  final int inputTokens;
  final int outputTokens;
  final int cachedTokens;
  final String? error;

  bool get succeeded => status == RunStatus.completed && error == null;
}

class HeadlessExecutor {
  static Future<String> run({
    required AppDatabase db,
    required ProviderConfig config,
    required String prompt,
    String? systemPrompt,
    String? workspacePath,
    Iterable<String>? allowedToolNames,
    int maxSteps = 4,
    int maxTokens = 1024,
    AgentCancellationToken? cancellationToken,
    Future<ToolApproval> Function(ToolCall call, ToolRisk risk)? approveTool,
    ApprovalMode approvalMode = ApprovalMode.ask,
  }) async {
    final result = await runDetailed(
      db: db,
      config: config,
      prompt: prompt,
      systemPrompt: systemPrompt,
      workspacePath: workspacePath,
      allowedToolNames: allowedToolNames,
      maxSteps: maxSteps,
      maxTokens: maxTokens,
      cancellationToken: cancellationToken,
      approveTool: approveTool,
      approvalMode: approvalMode,
    );
    return result.text;
  }

  static Future<HeadlessRunResult> runDetailed({
    required AppDatabase db,
    required ProviderConfig config,
    required String prompt,
    String? systemPrompt,
    String? workspacePath,
    Iterable<String>? allowedToolNames,
    int maxSteps = 4,
    int maxTokens = 1024,
    AgentCancellationToken? cancellationToken,
    Future<ToolApproval> Function(ToolCall call, ToolRisk risk)? approveTool,
    ApprovalMode approvalMode = ApprovalMode.ask,
  }) async {
    final provider =
        config.isConfigured ? _buildProvider(config) : DemoProvider();
    final allowList = allowedToolNames?.toSet();
    final registry = ToolRegistry();
    void registerIfAllowed(AgentTool tool) {
      if (allowList == null || allowList.contains(tool.manifest.name)) {
        registry.register(tool);
      }
    }

    registerIfAllowed(CalculatorTool());
    registerIfAllowed(GetTimeTool());
    registerIfAllowed(JsonQueryTool());
    registerIfAllowed(ImageGenTool(config: config));
    final terminalFileEnabled = (await SharedPreferences.getInstance())
            .getBool('settings.tool.terminal_file') ??
        true;
    if (workspacePath != null &&
        workspacePath.trim().isNotEmpty &&
        terminalFileEnabled) {
      final sandbox = WorkspaceSandbox(workspacePath);
      registerIfAllowed(ReadFileTool(sandbox: sandbox));
      registerIfAllowed(ListDirectoryTool(sandbox: sandbox));
      registerIfAllowed(SearchFilesTool(sandbox: sandbox));
    }
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
    var status = RunStatus.created;
    var inputTokens = 0;
    var outputTokens = 0;
    var cachedTokens = 0;
    String? errorMessage;
    try {
      await for (final event in executor.run(
        history: history,
        model: config.isConfigured ? config.model : 'demo-model',
        systemPrompt: system,
        capabilities: ModelCapabilities.infer(config.model),
        maxSteps: maxSteps,
        maxTokens: maxTokens,
        contextBudgetTokens: config.contextTokens,
        cancellationToken: cancellationToken,
        // 无 UI 的后台路径（子 Agent/定时任务）没有真人审批，非 safe 工具一律拒绝。
        approveTool: approveTool ??
            (call, risk) async => risk == ToolRisk.safe
                ? ToolApproval.allowOnce
                : ToolApproval.reject,
        approvalMode: approvalMode,
      )) {
        if (event is TextEvent) answer.write(event.text);
        if (event is AgentUsageEvent) {
          inputTokens += event.promptTokens;
          outputTokens += event.completionTokens;
          cachedTokens += event.cachedTokens;
        } else if (event is AgentStatusEvent) {
          status = event.status;
        } else if (event is AgentErrorEvent) {
          status = RunStatus.failed;
          errorMessage = event.message;
        } else if (event is AgentBudgetExhaustedEvent) {
          // 预算耗尽可恢复，不归类为真实失败。
          status = RunStatus.paused;
          errorMessage = event.message;
        }
      }
    } catch (error) {
      status = RunStatus.failed;
      errorMessage = error.toString();
    }
    final text = answer.toString().trim();
    return HeadlessRunResult(
      text: text.isEmpty && errorMessage != null ? errorMessage : text,
      status: status == RunStatus.created ? RunStatus.completed : status,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      cachedTokens: cachedTokens,
      error: errorMessage,
    );
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
