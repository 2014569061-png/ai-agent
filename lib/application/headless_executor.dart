import 'package:dio/dio.dart' show CancelToken;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import '../domain/tool_codes.dart';
import '../domain/tool_result.dart';
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
import '../infrastructure/tools/skill_tools.dart';
import 'agent_executor.dart';
import 'knowledge_service.dart';
import 'memory_service.dart';

import '../infrastructure/skills/skill_store.dart';
import '../infrastructure/mcp/mcp_tool_provider.dart';
import '../infrastructure/plugins/plugin_store.dart';
import 'mcp_service.dart';

/// 无 UI 运行 Agent（C5 定时任务 + C2 后台任务复用）。
/// 危险工具在后台自动拒绝（无用户可审批），只放行 safe 工具。
class HeadlessRunResult {
  const HeadlessRunResult({
    required this.text,
    required this.status,
    required this.inputTokens,
    required this.outputTokens,
    required this.cachedTokens,
    this.context,
    this.error,
  });

  final String text;
  final RunStatus status;
  final int inputTokens;
  final int outputTokens;
  final int cachedTokens;

  /// 预算暂停时的完整 Agent 上下文。恢复只使用这份 checkpoint，绝不从
  /// 原始 prompt 重放已经完成的工具调用。
  final List<ChatMessage>? context;
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
    List<ChatMessage>? initialHistory,
    AgentCancellationToken? cancellationToken,
    CancelToken? cancelToken,
    ToolApprovalCallback? approveTool,
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
      initialHistory: initialHistory,
      cancellationToken: cancellationToken,
      cancelToken: cancelToken,
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
    List<ChatMessage>? initialHistory,
    AgentCancellationToken? cancellationToken,
    CancelToken? cancelToken,
    ToolApprovalCallback? approveTool,
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

    // Headless runs must expose the same user-installed tools as the
    // foreground chat path. Failures are isolated per source so a broken
    // plugin or unavailable MCP server cannot remove built-in tools.
    try {
      final pluginTools = await PluginStore().loadDeclarativeTools(db);
      for (final tool in pluginTools) {
        registerIfAllowed(tool);
      }
    } catch (_) {}

    final mcpProvider = McpToolProvider();
    try {
      final servers =
          await McpService(database: Future.value(db)).loadEnabled();
      for (final server in servers) {
        try {
          final tools = await mcpProvider.connectAndListTools(server);
          for (final tool in tools) {
            registerIfAllowed(tool);
          }
        } catch (_) {}
      }
    } catch (_) {}

    // 后台/协作路径也必须提供与主 Agent 一致的只读记忆和 Skill 读取能力。
    // 这里只注册读取工具；memory_write 属于持久化副作用，除非调用方明确
    // 把它放进 allow-list，否则不能因为“safe”标签而被后台自动执行。
    final memoryService = MemoryService();
    registerIfAllowed(MemoryGetTool(onGet: (query, offset, limit) async {
      final rows = await memoryService.search(db, query,
          offset: offset, limit: limit + 1);
      final hasMore = rows.length > limit;
      final visible = hasMore ? rows.take(limit).toList() : rows;
      return ToolResult.success(
        message: visible.isEmpty ? '没有找到匹配的记忆' : '已读取 ${visible.length} 条记忆',
        data: {
          'revision': await memoryService.currentRevision(db),
          'items': visible
              .map((item) => {
                    'id': item.id,
                    'content': item.content,
                    'category': item.category,
                    'importance': item.importance,
                    'updatedAt': item.updatedAt.toIso8601String(),
                  })
              .toList(growable: false),
          'hasMore': hasMore,
          if (hasMore) 'nextOffset': offset + visible.length,
        },
      );
    }));
    if (allowList?.contains('memory_write') == true) {
      registerIfAllowed(MemoryWriteTool(onWrite: ({
        required String? id,
        required String content,
        required String mode,
        required int? startLine,
        required int? endLine,
        required String? expectedRevision,
      }) async {
        try {
          final memory = await memoryService.write(
            database: db,
            id: id,
            content: content,
            mode: mode,
            startLine: startLine,
            endLine: endLine,
            expectedRevision: expectedRevision,
          );
          return ToolResult.success(
            message: '记忆已写入',
            data: {
              'id': memory.id,
              'revision': await memoryService.currentRevision(db),
              'mode': mode,
            },
            effect: ToolEffect.applied,
          );
        } on MemoryConflictException catch (error) {
          return ToolResult.failure(
            code: ToolCodes.revisionConflict,
            message: '记忆已被其他操作更新，请先重新调用 memory_get 获取最新 revision',
            data: {'revision': error.currentRevision},
          );
        } on FormatException catch (error) {
          return ToolResult.failure(
            code: ToolCodes.invalidArguments,
            message: error.message,
          );
        } catch (error) {
          return ToolResult.failure(
            code: ToolCodes.toolError,
            message: '记忆写入失败：$error',
          );
        }
      }));
    }

    // Skill 正文与资源都按需读取，索引由系统提示词渐进披露。
    try {
      registerIfAllowed(SkillsReadTool(database: db));
      registerIfAllowed(SkillsReadResourceTool(database: db));
    } catch (_) {
      // 单测或旧数据库不可用时不阻断其余只读工具。
    }
    // 注意：这里的 prefs 读取必须自带兜底。此前直接 await getInstance()，
    // 在单测 / 插件缺失环境下抛 MissingPluginException，会把**整轮后台执行**
    // 判为失败（与紧邻 188-193 行"不阻断其余只读工具"的本意相矛盾）。
    bool terminalFileEnabled;
    try {
      terminalFileEnabled = (await SharedPreferences.getInstance())
              .getBool('settings.tool.terminal_file') ??
          true;
    } catch (_) {
      terminalFileEnabled = true;
    }
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
      final memoryBlock = await MemoryService()
          .buildInjectionBlock(db, contextTokens: config.contextTokens);
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

    final history = initialHistory == null || initialHistory.isEmpty
        ? <ChatMessage>[
            ChatMessage(
                role: MessageRole.user, parts: [MessagePart.text(prompt)])
          ]
        : List<ChatMessage>.of(initialHistory);
    final answer = StringBuffer();
    var status = RunStatus.created;
    var inputTokens = 0;
    var outputTokens = 0;
    var cachedTokens = 0;
    String? errorMessage;
    List<ChatMessage>? checkpoint;
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
        cancelToken: cancelToken,
        // 无 UI 的后台路径（子 Agent/定时任务）没有真人审批，敏感或非 safe 工具一律拒绝。
        approveTool: approveTool ??
            (call, risk, sensitive) async => !sensitive && risk == ToolRisk.safe
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
          checkpoint = List<ChatMessage>.of(event.context);
        }
      }
    } catch (error) {
      status = RunStatus.failed;
      errorMessage = error.toString();
    }
    final text = answer.toString().trim();
    await mcpProvider.dispose();
    return HeadlessRunResult(
      text: text.isEmpty && errorMessage != null ? errorMessage : text,
      status: status == RunStatus.created ? RunStatus.completed : status,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      cachedTokens: cachedTokens,
      context: checkpoint,
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
