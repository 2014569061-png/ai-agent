import 'package:dio/dio.dart' show CancelToken;
import 'package:drift/drift.dart' show Value;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import '../domain/tool_codes.dart';
import '../domain/tool_result.dart';
import '../domain/unique_id.dart';
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
import 'modules/agent_module.dart';
import 'modules/module_host.dart';
import 'modules/run_profile.dart';
import 'modules/session_log_module.dart';
import 'session_log/session_event_store.dart';
import 'file_baseline_store.dart';
import 'run_event_tracker.dart';
import 'tool_pipeline/run_event_interceptor.dart';
import 'knowledge_service.dart';
import 'memory_service.dart';
import 'project_kind_detector.dart';
import 'system_prompt_assembly.dart';
import 'task_template_service.dart';
import 'nexus_guard.dart';

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
    String? taskId,
    RunProfile profile = RunProfile.background,

    /// 本次运行挂载的模块；默认 [defaultModules]（会话日志）。
    ModuleHost? modules,
  }) async {
    final provider =
        config.isConfigured ? createLlmProvider(config) : DemoProvider();
    final model = config.isConfigured ? config.model : 'demo-model';
    final assembled = await assembleTools(
      db: db,
      config: config,
      taskType: taskType,
      workspacePath: workspacePath,
      allowedToolNames: allowedToolNames,
    );
    final registry = assembled.registry;
    final mcpProvider = assembled.mcpProvider;
    // 绑定任务的后台运行与聊天运行一样留下运行记录与工具审计（RunRecords /
    // RunEvents），并在改文件前保存原始内容，供任务变更集回退。
    final runStartedAt = DateTime.now();
    final runId = UniqueId.generate('run');
    final tracker = taskId == null
        ? null
        : await _startRunRecord(db,
            runId: runId, taskId: taskId, model: model, startedAt: runStartedAt);
    // 绑定任务的运行写入 task:<id> 会话日志：同一任务多次恢复依次追加。
    final moduleSession = await (modules ?? defaultModules(db)).open(RunScope(
      profile: profile,
      runId: runId,
      model: model,
      sessionId: taskId == null ? null : RunScope.taskSessionId(taskId),
      taskId: taskId,
      workspacePath: workspacePath,
    ));
    final executor = AgentExecutor(
      provider: provider,
      tools: registry,
      hooks: moduleSession.hooks,
      toolPipeline: buildToolPipeline(
        runEvents: tracker,
        baseline: taskId != null &&
                workspacePath != null &&
                workspacePath.trim().isNotEmpty
            ? FileBaselineStore(taskId: taskId, workspacePath: workspacePath)
            : null,
        // 保存失败不阻断工具；转交 NexusGuard 仅用于上报（若用户已授权）。
        onBaselineError: (error, stackTrace) => NexusGuard.silently<void>(
            'headless.fileBaseline',
            () => Error.throwWithStackTrace(error, stackTrace)),
      ),
    );
    var persona = systemPrompt ?? '你是一个有帮助的 AI Agent。';
    if (workspacePath != null && workspacePath.trim().isNotEmpty) {
      await NexusGuard.silentlyAsync<void>('headless.taskTemplateRules',
          () async {
        final project = await const ProjectKindDetector().detect(workspacePath);
        final templateRules = TaskTemplateService().promptBlock(
          taskType: taskType,
          project: project,
        );
        if (templateRules.isNotEmpty) {
          persona = '$persona\n\n$templateRules';
        }
      });
    }
    var memoryBlock = '';
    var knowledgeBlock = '';
    var skillBlock = '';
    try {
      memoryBlock = await MemoryService()
          .buildInjectionBlock(db, contextTokens: config.contextTokens);
      knowledgeBlock = await KnowledgeService().buildInjectionBlock(db, prompt);
      // 只有本轮真正注册了 skills_read，才注入可按需读取的 Skill 索引。
      // Agent 的 allow-list 可能明确关闭 Skill 工具。
      if (registry.findExecutor('skills_read') != null) {
        skillBlock = await SkillStore().buildInjectionBlock(db);
      }
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
    var outcome = const RunOutcome.finished();
    try {
      await for (final event in executor.run(
        history: history,
        model: model,
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
        moduleSession.observe(event);
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
      outcome = const RunOutcome.aborted('unexpected_error');
    }
    await moduleSession.finish(outcome);
    final text = answer.toString().trim();
    await mcpProvider.dispose();
    final finalStatus =
        status == RunStatus.created ? RunStatus.completed : status;
    if (tracker != null) {
      await _finishRunRecord(
        db,
        tracker,
        status: finalStatus,
        startedAt: runStartedAt,
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        cachedTokens: cachedTokens,
      );
    }
    return HeadlessRunResult(
      text: text.isEmpty && errorMessage != null ? errorMessage : text,
      status: finalStatus,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      cachedTokens: cachedTokens,
      context: checkpoint,
      error: errorMessage,
    );
  }

  /// 无 UI 运行默认挂载的第一方模块。模块失败只上报，不影响任务。
  static ModuleHost defaultModules(AppDatabase db) => ModuleHost(
        [
          SessionLogModule(
            store: () => DriftSessionEventStore(db),
            onError: (error, stackTrace) => NexusGuard.silently<void>(
                'headless.sessionLog',
                () => Error.throwWithStackTrace(error, stackTrace)),
          ),
        ],
        onError: (moduleId, error, stackTrace) => NexusGuard.silently<void>(
            'headless.module.$moduleId',
            () => Error.throwWithStackTrace(error, stackTrace)),
      );

  /// Inserts the run record; `null` (no auditing) when the database write
  /// fails, so observability never blocks the run.
  static Future<RunEventTracker?> _startRunRecord(
    AppDatabase db, {
    required String runId,
    required String taskId,
    required String model,
    required DateTime startedAt,
  }) async {
    try {
      await db.insertRunRecord(RunRecordsCompanion.insert(
        runId: runId,
        conversationId: 'headless',
        taskId: Value(taskId),
        model: Value(model),
        status: const Value('running'),
        startedAt: startedAt,
      ));
      return RunEventTracker(database: db, runId: runId);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _finishRunRecord(
    AppDatabase db,
    RunEventTracker tracker, {
    required RunStatus status,
    required DateTime startedAt,
    required int inputTokens,
    required int outputTokens,
    required int cachedTokens,
  }) async {
    try {
      await tracker.flush();
      final endedAt = DateTime.now();
      await db.updateRunRecord(
        tracker.runId,
        RunRecordsCompanion(
          // 与聊天路径相同的状态词：success / failed / paused / cancelled。
          status: Value(switch (status) {
            RunStatus.failed => 'failed',
            RunStatus.paused => 'paused',
            RunStatus.cancelled => 'cancelled',
            _ => 'success',
          }),
          endedAt: Value(endedAt),
          totalDurationMs: Value(endedAt.difference(startedAt).inMilliseconds),
          inputTokens: Value(inputTokens),
          outputTokens: Value(outputTokens),
          cachedTokens: Value(cachedTokens),
          eventCount: Value(tracker.nextSequence),
        ),
      );
    } catch (_) {
      // 运行记录收尾失败只影响统计与审计完整度，不改变任务结果。
    }
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

    // 插件工具加载失败会让「模型看不到我的插件工具」且毫无线索，因此接入上报
    // （NexusGuard.silently 只上报、不改控制流，无需 logger）。
    await NexusGuard.silentlyAsync<void>('headless.loadPluginTools', () async {
      final pluginTools = await PluginStore().loadDeclarativeTools(db);
      for (final tool in pluginTools) {
        registerIfAllowed(tool);
      }
    });

    final mcpProvider = McpToolProvider();
    await NexusGuard.silentlyAsync<void>('headless.loadMcpTools', () async {
      final servers =
          await McpService(database: Future.value(db)).loadEnabled();
      for (final server in servers) {
        // 单个 MCP 服务器连不上是常见情况（未启动、网络不通），不应影响其它
        // 服务器注册，但同样要留下痕迹。
        await NexusGuard.silentlyAsync<void>('headless.connectMcpServer',
            () async {
          final tools = await mcpProvider.connectAndListTools(server);
          for (final tool in tools) {
            registerIfAllowed(tool);
          }
        });
      }
    });

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

    await NexusGuard.silentlyAsync<void>('headless.registerSkillsTools',
        () async {
      registerIfAllowed(SkillsReadTool(database: db));
      registerIfAllowed(SkillsReadResourceTool(database: db));
    });
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
