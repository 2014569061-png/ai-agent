import 'package:dio/dio.dart' show CancelToken;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import '../domain/tool_codes.dart';
import '../domain/tool_result.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/providers/llm_provider.dart';
import '../infrastructure/providers/provider_config.dart';
import '../infrastructure/providers/provider_factory.dart';
import '../infrastructure/tools/core_tools.dart';
import '../infrastructure/tools/image_gen_tool.dart';
import '../infrastructure/tools/tool_registry.dart';
import '../infrastructure/tools/workspace_tools.dart';
import '../infrastructure/tools/command_tool.dart';
import '../infrastructure/tools/skill_tools.dart';
import 'agent_executor.dart';
import 'knowledge_service.dart';
import 'memory_service.dart';
import 'project_kind_detector.dart';
import 'system_prompt_assembly.dart';
import 'task_template_service.dart';

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

class HeadlessToolAssembly {
  const HeadlessToolAssembly({
    required this.registry,
    required this.mcpProvider,
  });

  final ToolRegistry registry;
  final McpToolProvider mcpProvider;
}

class HeadlessExecutor {
  static Future<String> run({
    required AppDatabase db,
    required ProviderConfig config,
    required String prompt,
    String? systemPrompt,
    String? taskType,
    String? workspacePath,
    Iterable<String>? allowedToolNames,
    int maxSteps = 4,
    double temperature = 0.7,
    int maxTokens = 1024,
    double topP = 1.0,
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
      taskType: taskType,
      workspacePath: workspacePath,
      allowedToolNames: allowedToolNames,
      maxSteps: maxSteps,
      temperature: temperature,
      maxTokens: maxTokens,
      topP: topP,
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
    String? taskType,
    String? workspacePath,
    Iterable<String>? allowedToolNames,
    int maxSteps = 4,
    double temperature = 0.7,
    int maxTokens = 1024,
    double topP = 1.0,
    List<ChatMessage>? initialHistory,
    AgentCancellationToken? cancellationToken,
    CancelToken? cancelToken,
    ToolApprovalCallback? approveTool,
    ApprovalMode approvalMode = ApprovalMode.ask,
  }) async {
    final provider =
        config.isConfigured ? createLlmProvider(config) : DemoProvider();
    final assembled = await assembleTools(
      db: db,
      config: config,
      taskType: taskType,
      workspacePath: workspacePath,
      allowedToolNames: allowedToolNames,
    );
    final registry = assembled.registry;
    final mcpProvider = assembled.mcpProvider;
    final executor = AgentExecutor(provider: provider, tools: registry);
    var persona = systemPrompt ?? '你是一个有帮助的 AI Agent。';
    if (workspacePath != null && workspacePath.trim().isNotEmpty) {
      try {
        final project = await const ProjectKindDetector().detect(workspacePath);
        final templateRules = TaskTemplateService().promptBlock(
          taskType: taskType,
          project: project,
        );
        if (templateRules.isNotEmpty) {
          persona = '$persona\n\n$templateRules';
        }
      } catch (_) {}
    }
    var memoryBlock = '';
    var knowledgeBlock = '';
    var skillBlock = '';
    try {
      memoryBlock = await MemoryService()
          .buildInjectionBlock(db, contextTokens: config.contextTokens);
      knowledgeBlock = await KnowledgeService().buildInjectionBlock(db, prompt);
      // 与聊天路径保持一致：后台任务同样注入已启用 Skill 的指令块。
      skillBlock = await SkillStore().buildInjectionBlock(db);
    } catch (_) {
      // 注入失败不阻断执行。
    }
    // 与聊天路径共用同一拼装顺序（assembleAgentSystemPrompt）：稳定段在前、
    // 按问题检索的动态内容垫底，否则后台任务每轮前缀都在变化，前缀缓存失效。
    final system = assembleAgentSystemPrompt(
      personaPrompt: persona,
      skillIndexBlock: skillBlock,
      memoryBlock: memoryBlock,
      knowledgeBlock: knowledgeBlock,
    );

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
        temperature: temperature,
        maxTokens: maxTokens,
        topP: topP,
        contextBudgetTokens: config.contextTokens,
        cancellationToken: cancellationToken,
        cancelToken: cancelToken,
        // 无 UI 的后台路径（子 Agent/定时任务）没有真人审批，敏感或非 safe 工具一律拒绝。
        // 恢复开发闭环时调用方必须传入 approveTool，把写文件/终端交给用户确认。
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

  static Future<HeadlessToolAssembly> assembleTools({
    required AppDatabase db,
    required ProviderConfig config,
    String? taskType,
    String? workspacePath,
    Iterable<String>? allowedToolNames,
  }) async {
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

    try {
      registerIfAllowed(SkillsReadTool(database: db));
      registerIfAllowed(SkillsReadResourceTool(database: db));
    } catch (_) {}
    bool workspaceFilesEnabled;
    bool terminalEnabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getBool('settings.tool.terminal_file') ?? true;
      workspaceFilesEnabled =
          prefs.getBool('settings.tool.workspace_files') ?? legacy;
      terminalEnabled = prefs.getBool('settings.tool.terminal') ?? legacy;
    } catch (_) {
      workspaceFilesEnabled = true;
      terminalEnabled = true;
    }
    if (workspacePath != null &&
        workspacePath.trim().isNotEmpty &&
        workspaceFilesEnabled) {
      final sandbox = WorkspaceSandbox(workspacePath);
      registerIfAllowed(ReadFileTool(sandbox: sandbox));
      registerIfAllowed(ListDirectoryTool(sandbox: sandbox));
      registerIfAllowed(SearchFilesTool(sandbox: sandbox));
      final template = TaskTemplateService().findByType(taskType);
      final allowWrites = template?.implementsChanges == true ||
          allowList == null && taskType == 'implement_and_verify' ||
          (allowList != null &&
              (allowList.contains('edit_file') ||
                  allowList.contains('write_file') ||
                  allowList.contains('terminal')));
      if (allowWrites) {
        registerIfAllowed(WriteFileTool(sandbox: sandbox));
        registerIfAllowed(EditFileTool(sandbox: sandbox));
        registerIfAllowed(DeleteFileTool(sandbox: sandbox));
        registerIfAllowed(MoveFileTool(sandbox: sandbox));
        if (terminalEnabled) {
          registerIfAllowed(TerminalCommandTool(
            service: TerminalCommandService(workspacePath: workspacePath),
          ));
        }
      }
    }
    return HeadlessToolAssembly(registry: registry, mcpProvider: mcpProvider);
  }
}
