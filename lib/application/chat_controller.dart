import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform, visibleForTesting;
import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mojibake_repair.dart';
import 'autonomous_delegation.dart';

import '../domain/models.dart';
import '../domain/tool_codes.dart';
import '../domain/tool_result.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/files/document_extractor.dart';
import '../infrastructure/providers/anthropic_provider.dart';
import '../infrastructure/providers/gemini_provider.dart';
import '../infrastructure/providers/llm_provider.dart';
import '../infrastructure/providers/openai_compatible_provider.dart';
import '../infrastructure/providers/proxy_provider.dart';
import '../infrastructure/providers/provider_config.dart';
import '../infrastructure/tools/core_tools.dart';
import '../infrastructure/tools/tool_registry.dart';
import '../infrastructure/tools/sub_agent_tool.dart';
import '../infrastructure/tools/plan_tool.dart';
import '../infrastructure/tools/image_gen_tool.dart';
import '../infrastructure/tools/workspace_tools.dart';
import '../infrastructure/tools/command_tool.dart';
import '../infrastructure/tools/skill_tools.dart';
import 'agent_executor.dart';
import 'run_coordinator.dart';
import 'context_window.dart';
import 'error_humanizer.dart';
import 'headless_executor.dart';
import 'knowledge_service.dart';
import 'memory_service.dart';
import 'providers.dart';
import 'log_service.dart';
import 'run_event_tracker.dart';
import 'run_controller.dart';
import '../domain/sensitive_tool_policy.dart';
import 'task_service.dart';
import 'workspace_service.dart';
import '../infrastructure/plugins/plugin_store.dart';
import '../infrastructure/skills/skill_store.dart';
import '../infrastructure/notifications/notification_service.dart';
import '../infrastructure/background/foreground_service.dart';

part 'chat_run_execution.dart';

// ignore_for_file: curly_braces_in_flow_control_structures

/// 单次工具调用的运行时展示状态类
class ToolActivity {
  const ToolActivity(
      {required this.call,
      required this.risk,
      this.status = '等待执行',
      this.result,
      this.ok,
      this.code,
      this.effect,
      this.executionMs = 0,
      this.runningSince});
  final ToolCall call;
  final ToolRisk risk;
  final String status;
  final String? result;
  final bool? ok;
  final String? code;
  final ToolEffect? effect;

  /// 状态常量：只有落在「执行中」区间内的时长才计入 [executionMs]。
  static const statusRunning = '执行中';

  /// 已累计的「真实执行」时长（毫秒）。
  ///
  /// 只在 `status == '执行中'` 的区间内累计——工具调用从
  /// 「等待执行 → 等待确认 → 执行中 → 已完成」流转，审批停留期间不计时，
  /// 因此指标里的「工具调用耗时」不会混入用户自己的审批等待时间。
  final int executionMs;

  /// 当前执行区间的起算时刻；仅当处于「执行中」时非空。
  final DateTime? runningSince;

  Duration get duration => Duration(milliseconds: executionMs);

  ToolActivity copyWith({
    String? status,
    String? result,
    bool? ok,
    String? code,
    ToolEffect? effect,
    DateTime? now,
  }) {
    final nextStatus = status ?? this.status;
    final clock = now ?? DateTime.now();

    var ms = executionMs;
    DateTime? running = runningSince;

    if (nextStatus != this.status) {
      // 离开「执行中」：结算这一段，避免把审批等待算进去。
      if (this.status == statusRunning && running != null) {
        final delta = clock.difference(running).inMilliseconds;
        if (delta > 0) ms += delta;
        running = null;
      }
      // 进入「执行中」：开始计时（此前若有等待审批，天然被排除在外）。
      if (nextStatus == statusRunning) {
        running = clock;
      }
    }

    return ToolActivity(
      call: call,
      risk: risk,
      status: nextStatus,
      result: result ?? this.result,
      ok: ok ?? this.ok,
      code: code ?? this.code,
      effect: effect ?? this.effect,
      executionMs: ms,
      runningSince: running,
    );
  }
}

/// 「设置 → 工具」页面的全局工具开关快照，由 [_loadToolSettings] 从
/// SharedPreferences（settings.tool.*）读取并在此处统一消费。
/// 关闭的开关会对应地从工具注册表中剔除对应工具。
class ToolSettings {
  const ToolSettings({
    this.webBrowsing = true,
    this.terminalFile = true,
  });

  /// 网页浏览（web_search）。
  final bool webBrowsing;

  /// 终端 / 工作区文件工具。
  final bool terminalFile;
}

class SessionSkillInstruction {
  const SessionSkillInstruction({
    required this.id,
    required this.name,
    required this.content,
  });

  final String id;
  final String name;
  final String content;
}

/// 聊天页的完整不可变状态
class ChatState {
  const ChatState({
    this.messages = const [],
    this.running = false,
    this.paused = false,
    this.loading = true,
    this.conversationId,
    this.conversationTitle = '新会话',
    this.agentName = '通用助手',
    this.systemPrompt = '你是一个有帮助的 AI Agent。',
    this.sessionSkillInstructions = const [],
    this.agentId,
    this.toolActivities = const [],
    this.activityLog = const [],
    this.activeModel = '',
    this.activeProviderName = '',
    this.activeProviderId = '',
    this.contextTokens = 128000,
    this.liveContextTokens = 0,
    this.liveReply,
    this.totalSteps = 0,
    this.activeReasoningEffort = ReasoningEffort.medium,
    this.providerConfigured = false,
    this.planMode = false,
    this.approvalMode = ApprovalMode.ask,
    this.planState,
    this.currentWorkspacePath,
  });

  final List<ChatMessage> messages;
  final bool running;
  final bool paused;
  final bool loading;
  final String? conversationId;
  final String conversationTitle;
  final String agentName;
  final String systemPrompt;

  /// Explicitly loaded Skill bodies for the current in-memory conversation.
  /// They are intentionally never persisted or used as a global Skill switch.
  final List<SessionSkillInstruction> sessionSkillInstructions;
  final String? agentId;
  final List<ToolActivity> toolActivities;
  final List<String> activityLog;
  final String activeModel;
  final String activeProviderName;
  final String activeProviderId;

  /// G1 激活 Provider 的上下文窗口(供 HUD 与执行预算同源显示)。
  final int contextTokens;

  /// 当前请求的实时上下文估算；流式输出期间也会持续刷新。
  final int liveContextTokens;
  final LiveReply? liveReply;

  /// 本次会话累计的 agent 循环步数（= 模型调用次数）。
  ///
  /// 由 [ChatController] 在每一次 `RunStatus.waitingModel` 时 +1 —— agent 循环
  /// 每迭代一步都会先进入 waitingModel，因此这个计数精确等于「带工具调用的
  /// agent 循环」的迭代次数，而不是消息条数（一轮对话只落一条最终 assistant 消息）。
  final int totalSteps;
  final ReasoningEffort activeReasoningEffort;
  final bool providerConfigured;
  final bool planMode;
  final ApprovalMode approvalMode;
  final PlanState? planState;
  final String? currentWorkspacePath;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? running,
    bool? paused,
    bool? loading,
    String? conversationId,
    String? conversationTitle,
    String? agentName,
    String? systemPrompt,
    List<SessionSkillInstruction>? sessionSkillInstructions,
    String? agentId,
    List<ToolActivity>? toolActivities,
    List<String>? activityLog,
    String? activeModel,
    String? activeProviderName,
    String? activeProviderId,
    int? contextTokens,
    int? liveContextTokens,
    LiveReply? liveReply,
    int? totalSteps,
    ReasoningEffort? activeReasoningEffort,
    bool? providerConfigured,
    bool? planMode,
    ApprovalMode? approvalMode,
    PlanState? planState,
    String? currentWorkspacePath,
    bool clearWorkspace = false,
    bool clearConversationId = false,
    bool clearAgentId = false,
    bool clearPlanState = false,
    bool clearLiveReply = false,
    bool clearSessionSkillInstructions = false,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        running: running ?? this.running,
        paused: paused ?? this.paused,
        loading: loading ?? this.loading,
        conversationId: clearConversationId
            ? null
            : (conversationId ?? this.conversationId),
        conversationTitle: conversationTitle ?? this.conversationTitle,
        agentName: agentName ?? this.agentName,
        systemPrompt: systemPrompt ?? this.systemPrompt,
        sessionSkillInstructions: clearSessionSkillInstructions
            ? const []
            : (sessionSkillInstructions ?? this.sessionSkillInstructions),
        agentId: clearAgentId ? null : (agentId ?? this.agentId),
        toolActivities: toolActivities ?? this.toolActivities,
        activityLog: activityLog ?? this.activityLog,
        activeModel: activeModel ?? this.activeModel,
        activeProviderName: activeProviderName ?? this.activeProviderName,
        activeProviderId: activeProviderId ?? this.activeProviderId,
        contextTokens: contextTokens ?? this.contextTokens,
        liveContextTokens: liveContextTokens ?? this.liveContextTokens,
        liveReply: clearLiveReply ? null : (liveReply ?? this.liveReply),
        totalSteps: totalSteps ?? this.totalSteps,
        activeReasoningEffort:
            activeReasoningEffort ?? this.activeReasoningEffort,
        providerConfigured: providerConfigured ?? this.providerConfigured,
        planMode: planMode ?? this.planMode,
        approvalMode: approvalMode ?? this.approvalMode,
        planState: clearPlanState ? null : (planState ?? this.planState),
        currentWorkspacePath: clearWorkspace
            ? null
            : (currentWorkspacePath ?? this.currentWorkspacePath),
      );
}

/// Chat orchestration controller.
class ChatController extends Notifier<ChatState> {
  static int _messageSeq = 0;
  static const _maxAttachmentBytes = 8 * 1024 * 1024;
  static const _maxTextAttachmentChars = 100000;
  static const _documentExtractor = DocumentExtractor();

  DateTime? _cancelRequestedAt;
  final Set<String> _resumingTaskIds = <String>{};
  int? _activePlanGeneration;

  /// 单次运行的代次 / 取消 / 预算断点状态（见 RunCoordinator）。
  late final RunCoordinator _runs =
      RunCoordinator(currentConversationId: () => state.conversationId);

  /// 最近一次预算暂停保存的续跑上下文（可能为空）。
  List<ChatMessage>? get budgetPauseContext => _runs.budgetPauseContext;

  /// 状态读写入口：`Notifier.state` 是 protected 成员，同库的 part 文件扩展
  /// （chat_run_execution.dart）无法直接引用它，故提供仅库内可见的转发对。
  ChatState get _currentState => state;
  set _currentState(ChatState value) => state = value;

  @override
  ChatState build() {
    Future.microtask(_initialize);
    return const ChatState();
  }

  // --- 初始化 ---

  Future<void> _initialize() async {
    try {
      String? activeWorkspace;
      try {
        activeWorkspace =
            await ref.read(workspaceServiceProvider).getActiveWorkspace();
      } catch (_) {}
      final store = ref.read(providerConfigStoreProvider);
      final config = await store.load();
      // Workspace is managed via state.currentWorkspacePath
      final database = await ref.read(databaseProvider.future);
      // 历史脏数据修复：统一修复早期版本遗留的乱码文本。
      await _healMojibakeAgents(database);
      final conversations = await database.recentConversations();
      final conversation = conversations.isNotEmpty
          ? conversations.first
          : await _createConversation(database);
      final storedMessages = await database.messagesFor(conversation.id);
      var agents = await database.allAgents();
      if (agents.isEmpty) {
        final now = DateTime.now();
        await database.insertAgent(AgentsCompanion.insert(
          id: 'agent-default',
          name: '通用助手',
          modelProfileId: 'default',
          updatedAt: now,
        ));
        agents = await database.allAgents();
      }
      final activeAgent = agents.first;
      final restored = _restoreFromMessages(storedMessages);
      state = state.copyWith(
        loading: false,
        conversationId: conversation.id,
        conversationTitle: MojibakeRepair.repair(conversation.title),
        agentName: MojibakeRepair.repair(activeAgent.name),
        systemPrompt: activeAgent.systemPrompt,
        agentId: activeAgent.id,
        messages: restored.$1,
        toolActivities: restored.$2,
        activeModel: config.model,
        activeProviderName: config.name,
        activeProviderId: config.id,
        contextTokens: config.contextTokens,
        activeReasoningEffort: config.reasoningEffort,
        providerConfigured: config.isConfigured,
        currentWorkspacePath: activeWorkspace,
      );
    } catch (_) {
      // 初始化失败时降级为空会话，避免首屏永久显示加载状态。
      state = state.copyWith(loading: false);
    }
  }

  /// 历史脏数据修复：早期版本源代码里中文被错误编码，数据库里残留了
  /// 形如 "閫氱敤鍔╂墜" 的 agent 名字，每次启动检测并就地改回正确名字。
  static const _nameRepairs = <String, String>{
    '閫氱敤鍔╂墜': '通用助手',
    '鏂颁細': '新会话',
  };

  Future<void> _healMojibakeAgents(AppDatabase database) async {
    final agents = await database.allAgents();
    for (final agent in agents) {
      final repaired = _nameRepairs[agent.name];
      if (repaired != null) {
        await database.insertAgent(AgentsCompanion.insert(
          id: agent.id,
          name: repaired,
          systemPrompt: Value(agent.systemPrompt),
          modelProfileId: agent.modelProfileId,
          enabledToolsJson: Value(agent.enabledToolsJson),
          temperature: Value(agent.temperature),
          maxTokens: Value(agent.maxTokens),
          maxSteps: Value(agent.maxSteps),
          topP: Value(agent.topP),
          updatedAt: DateTime.now(),
        ));
      }
    }
  }

  Future<Conversation> _createConversation(AppDatabase database) async {
    final now = DateTime.now();
    final conversation = Conversation(
      id: 'conversation-${now.microsecondsSinceEpoch}',
      title: '新会话',
      agentId: null,
      isPinned: false,
      isFavorite: false,
      tagsJson: '[]',
      createdAt: now,
      updatedAt: now,
    );
    await database.saveConversation(conversation);
    return conversation;
  }

  ChatMessage _toDomainMessage(Message message) => ChatMessage(
        role: MessageRole.values.firstWhere((role) => role.name == message.role,
            orElse: () => MessageRole.assistant),
        toolCallId: message.toolCallId,
        parts: [MessagePart.text(MojibakeRepair.repair(message.content))],
        reasoning: message.reasoningContent == null
            ? null
            : MojibakeRepair.repair(message.reasoningContent!),
      );

  /// Restore persisted messages and tool cards.
  (List<ChatMessage>, List<ToolActivity>) _restoreFromMessages(
      List<Message> stored) {
    final messages = <ChatMessage>[];
    final activities = <ToolActivity>[];
    for (final message in stored) {
      final toolCallsJson = message.toolCallsJson;
      if (message.role == 'assistant' &&
          toolCallsJson != null &&
          toolCallsJson.isNotEmpty) {
        for (final (call, risk) in _decodeToolCalls(toolCallsJson)) {
          activities.add(ToolActivity(call: call, risk: risk, status: '已完成'));
        }
      } else if (message.role == 'tool') {
        final index =
            activities.lastIndexWhere((a) => a.call.id == message.toolCallId);
        if (index >= 0) {
          activities[index] =
              _restoreToolActivityResult(activities[index], message.content);
        }
      } else {
        messages.add(_toDomainMessage(message));
      }
    }
    return (messages, activities);
  }

  /// 会话恢复也保留 ToolResult 的结构化语义，避免历史工具卡退化成文本输出。
  ToolActivity _restoreToolActivityResult(ToolActivity activity, String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        final effect = switch (decoded['effect']?.toString()) {
          'applied' => ToolEffect.applied,
          'unknown' => ToolEffect.unknown,
          'none' => ToolEffect.none,
          _ => ToolEffect.none,
        };
        return activity.copyWith(
          result: decoded['message']?.toString() ?? value,
          ok: decoded['ok'] == true,
          code: decoded['code']?.toString(),
          effect: effect,
        );
      }
    } catch (_) {
      // 兼容 ToolResult 迁移前保存的纯文本工具结果。
    }
    return activity.copyWith(result: value);
  }

  List<(ToolCall, ToolRisk)> _decodeToolCalls(String json) {
    try {
      final list =
          (jsonDecode(json) as List<dynamic>).whereType<Map<String, dynamic>>();
      return list.map((item) {
        final call = ToolCall(
          id: item['id'] as String? ?? '',
          name: item['name'] as String? ?? '',
          arguments: item['arguments'] as Map<String, dynamic>? ?? const {},
        );
        final risk = ToolRisk.values.firstWhere((r) => r.name == item['risk'],
            orElse: () => ToolRisk.safe);
        return (call, risk);
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persistMessage(ChatMessage message,
      {String? toolName, ToolResult? toolResult}) async {
    final conversationId = state.conversationId;
    if (conversationId == null) return;
    final database = await ref.read(databaseProvider.future);
    var content = _contentForPersist(message);
    if (message.role == MessageRole.tool &&
        toolName != null &&
        toolResult != null) {
      // 模型回灌仍使用原始结果；进入 SQLite 时按工具名单替换为占位符。
      content = SensitiveToolPolicy.redactResult(toolName, toolResult).encode();
    } else if (message.role == MessageRole.tool && message.toolCallId != null) {
      final activity = state.toolActivities
          .where((item) => item.call.id == message.toolCallId)
          .firstOrNull;
      if (activity != null &&
          SensitiveToolPolicy.isResultSensitive(activity.call.name)) {
        content = '[敏感工具结果已脱敏]';
      }
    }
    await database.insertMessage(MessagesCompanion.insert(
      id: 'message-${DateTime.now().microsecondsSinceEpoch}-${_messageSeq++}',
      conversationId: conversationId,
      role: message.role.name,
      content: content,
      toolCallId: Value(message.toolCallId),
      reasoningContent: Value(message.reasoning),
      createdAt: DateTime.now(),
    ));
  }

  /// 把消息部件序列化为 DB content 字段（非文本部件用占位标记）。
  String _contentForPersist(ChatMessage message) => message.parts.map((part) {
        if (part.type == 'image') return '[图片附件]';
        if (part.type == 'file') return '[文件附件]';
        return part.value;
      }).join();

  /// Persist a tool call for restoring tool cards.
  Future<void> _persistToolCall(ToolCall call, ToolRisk risk) async {
    final conversationId = state.conversationId;
    if (conversationId == null) return;
    final database = await ref.read(databaseProvider.future);
    await database.insertMessage(MessagesCompanion.insert(
      id: 'message-${DateTime.now().microsecondsSinceEpoch}-${_messageSeq++}',
      conversationId: conversationId,
      role: 'assistant',
      content: '',
      toolCallsJson: Value(jsonEncode([
        {
          'id': call.id,
          'name': call.name,
          'arguments':
              SensitiveToolPolicy.redactArguments(call.name, call.arguments),
          'risk': risk.name
        },
      ])),
      createdAt: DateTime.now(),
    ));
  }

  // --- Provider 与工具构建 ---

  LlmProvider _buildProvider(ProviderConfig config) {
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

  Future<ToolRegistry> _buildRegistry(
    Set<String> enabledTools,
    String tavilyKey,
    ProviderConfig config,
    ToolRisk subAgentRisk,
    ToolSettings settings,
  ) async {
    final registry = ToolRegistry();
    if (enabledTools.contains('calculator')) {
      registry.register(CalculatorTool());
    }
    if (enabledTools.contains('get_time')) registry.register(GetTimeTool());
    if (enabledTools.contains('json_query')) registry.register(JsonQueryTool());
    if (enabledTools.contains('http_request')) {
      registry.register(HttpRequestTool());
    }
    if (settings.webBrowsing && enabledTools.contains('web_search')) {
      registry.register(WebSearchTool(apiKey: tavilyKey));
    }
    if (enabledTools.contains('generate_image')) {
      registry.register(ImageGenTool(config: config));
    }

    // 记忆写入：回调懒加载 DB，写入"手动来源"记忆。
    registry.register(RememberTool(
      onRemember: _onRemember,
      onRememberWithRevision: _onRememberWithRevision,
    ));
    registry.register(MemoryGetTool(onGet: _onMemoryGet));
    registry.register(MemoryWriteTool(onWrite: _onMemoryWrite));
    try {
      final database = await ref.read(databaseProvider.future);
      registry.register(SkillsReadTool(database: database));
      registry.register(SkillsReadResourceTool(database: database));
    } catch (_) {
      // 数据库尚未就绪时，当前回合不暴露 Skill 读取工具。
    }
    // 子 Agent：复用 HeadlessExecutor 无 UI 执行，safe 工具才放行。
    // 风险由自主委派开关决定：开启 → safe（自动放行），关闭 → requiresConfirmation（走审批）。
    registry.register(SubAgentTool(onRun: _runSubAgent, risk: subAgentRisk));
    // 计划模式：模型首轮调用 manage_plan 后由回调更新 planState。
    registry.register(ManagePlanTool(onPlanUpdated: _onPlanUpdated));

    final wsPath = state.currentWorkspacePath;
    if (settings.terminalFile && wsPath != null && wsPath.isNotEmpty) {
      final sandbox = WorkspaceSandbox(wsPath);
      registry.register(ReadFileTool(sandbox: sandbox));
      registry.register(WriteFileTool(sandbox: sandbox));
      registry.register(EditFileTool(sandbox: sandbox));
      registry.register(ListDirectoryTool(sandbox: sandbox));
      registry.register(SearchFilesTool(sandbox: sandbox));
      registry.register(DeleteFileTool(sandbox: sandbox));
      registry.register(MoveFileTool(sandbox: sandbox));
      if (!kIsWeb) {
        registry.register(TerminalCommandTool(
          service: TerminalCommandService(workspacePath: wsPath),
        ));
      }
    }

    return registry;
  }

  /// 读取「设置 → 工具」页面上各工具开关的当前值。开关写在
  /// SharedPreferences（settings.tool.*），由 [ToolSettings] 统一消费，
  /// 关闭的开关会对应地从工具注册表中剔除。
  static Future<ToolSettings> _loadToolSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return ToolSettings(
        webBrowsing: prefs.getBool('settings.tool.web_browsing') ?? true,
        terminalFile: prefs.getBool('settings.tool.terminal_file') ?? true,
      );
    } catch (_) {
      return const ToolSettings();
    }
  }

  /// 把已启用的 MCP 服务器工具并入 registry。
  /// 单个服务器连接失败不影响其余工具（失败静默跳过）。
  Future<void> _mergeMcpTools(ToolRegistry registry) async {
    try {
      final servers = await ref.read(mcpServiceProvider).loadEnabled();
      if (servers.isEmpty) return;
      final mcp = ref.read(mcpToolProvider);
      await mcp.syncServers(servers);
      for (final server in servers) {
        final tools = await mcp.connectAndListTools(server);
        for (final tool in tools) {
          registry.register(tool);
        }
      }
    } catch (_) {
      // MCP 服务不可达时静默降级，保留内置工具。
    }
  }

  /// 把已启用插件里的声明式 HTTP 工具并入 registry（与内置/MCP 工具重名时跳过）。
  Future<void> _mergePluginTools(ToolRegistry registry) async {
    try {
      final database = await ref.read(databaseProvider.future);
      final tools = await PluginStore().loadDeclarativeTools(database);
      for (final tool in tools) {
        if (registry.findRegistration(tool.manifest.name) == null) {
          registry.register(tool);
        }
      }
    } catch (_) {
      // 插件解析失败不影响内置与 MCP 工具。
    }
  }

  /// 加载 Provider/Agent 配置并构建工具注册表（发送 / 重新生成 / 编辑重发共用）。
  Future<
      ({
        ProviderConfig config,
        ToolRegistry registry,
        String model,
        int maxSteps,
        double temperature,
        int maxTokens,
        double topP
      })> _prepareRun(AppDatabase database) async {
    final store = ref.read(providerConfigStoreProvider);
    var config = await store.load();
    try {
      final prefs = await SharedPreferences.getInstance();
      final deepReasoning =
          prefs.getBool('settings.llm.deep_reasoning') ?? true;
      if (!deepReasoning) {
        config = config.copyWith(reasoningEffort: ReasoningEffort.off);
      }
    } catch (_) {
      // Keep the provider's configured reasoning level if preferences fail.
    }
    final tavilyKey = await store.readToolKey('tavily');
    var enabledTools = <String>{'calculator', 'get_time', 'json_query'};
    // 前台单次预算默认提高到 16，预算耗尽现在是可恢复的暂停而非失败。
    var maxSteps = 16;
    var temperature = 0.7;
    var maxTokens = 2048;
    var topP = 1.0;
    final agentId = state.agentId;
    if (agentId != null) {
      final agent = await database.findAgent(agentId);
      if (agent != null) {
        maxSteps = agent.maxSteps;
        temperature = agent.temperature;
        maxTokens = agent.maxTokens;
        topP = agent.topP;
        if (agent.enabledToolsJson.trim().isNotEmpty) {
          final decoded = jsonDecode(agent.enabledToolsJson);
          if (decoded is List) {
            enabledTools = decoded.whereType<String>().toSet();
          }
        }
      }
    }
    // 自主委派开关决定 sub_agent 工具的风险等级：开启 → 自动放行（safe），
    // 关闭 → requiresConfirmation（与审批模式兼容）。
    final autonomousDelegation =
        await AutonomousDelegationService().isEnabled();
    final subAgentRisk =
        autonomousDelegation ? ToolRisk.safe : ToolRisk.requiresConfirmation;
    final toolSettings = await _loadToolSettings();
    var registry = await _buildRegistry(
        enabledTools, tavilyKey, config, subAgentRisk, toolSettings);
    await _mergeMcpTools(registry);
    await _mergePluginTools(registry);
    final platform = kIsWeb
        ? 'web'
        : switch (defaultTargetPlatform) {
            TargetPlatform.android => 'android',
            TargetPlatform.iOS => 'ios',
            TargetPlatform.macOS => 'macos',
            TargetPlatform.windows => 'windows',
            TargetPlatform.linux => 'linux',
            TargetPlatform.fuchsia => 'fuchsia',
          };
    var linuxAvailable = false;
    final terminalExecutor = registry.findExecutor('terminal');
    if (terminalExecutor is TerminalCommandTool) {
      try {
        linuxAvailable =
            (await terminalExecutor.service.inspectRuntime()).available;
      } catch (_) {
        linuxAvailable = false;
      }
    }
    registry = registry.project(ToolCapabilitySnapshot(
      platform: platform,
      // 当前 terminal 注册即代表本轮已有可用 runtime；执行器仍会做最终兜底。
      linuxAvailable: linuxAvailable,
    ));
    final model = config.isConfigured ? config.model : 'demo-model';
    return (
      config: config,
      registry: registry,
      model: model,
      maxSteps: maxSteps,
      temperature: temperature,
      maxTokens: maxTokens,
      topP: topP,
    );
  }

  // --- 鍙戦€佷笌閲嶆柊生成 ---

  String _taskTitle(String taskType, String prompt) {
    const labels = <String, String>{
      'project_analysis': '项目解读',
      'bug_fix': '问题修复',
      'code_review': '代码审查',
      'release_check': '发布检查',
    };
    final label = labels[taskType] ?? '开发任务';
    final shortPrompt = prompt.trim();
    if (shortPrompt.isEmpty) return label;
    return '$label：${shortPrompt.length > 28 ? '${shortPrompt.substring(0, 28)}…' : shortPrompt}';
  }

  Future<void> send({
    required String text,
    required List<PlatformFile> attachments,
    required Future<ToolApproval> Function(ToolCall call, ToolRisk risk)
        approveTool,
    String taskType = 'general',
    String sourceType = 'manual',
  }) async {
    final trimmed = text.trim();
    if ((trimmed.isEmpty && attachments.isEmpty) ||
        state.running ||
        state.loading) return;
    final conversationId = state.conversationId;
    final workspacePath = state.currentWorkspacePath;
    final runGeneration = _runs.beginRun();

    final parts = <MessagePart>[MessagePart.text(trimmed)];
    for (final file in attachments) {
      final bytes = file.bytes;
      final mime = file.extension == 'png'
          ? 'image/png'
          : file.extension == 'jpg' || file.extension == 'jpeg'
              ? 'image/jpeg'
              : null;
      if (bytes != null && bytes.length > _maxAttachmentBytes) {
        parts.add(MessagePart.text('\n\n附件 ${file.name} 超过 8MB，已跳过'));
        continue;
      }
      final isTextAttachment = const {'txt', 'md', 'csv', 'json'}
          .contains(file.extension?.toLowerCase());
      if (bytes != null && mime != null) {
        parts.add(MessagePart.image('data:$mime;base64,${base64Encode(bytes)}',
            mimeType: mime));
        continue;
      }
      if (bytes == null || !isTextAttachment) {
        parts.add(MessagePart.text('\n\n附件 ${file.name} 类型暂不支持，已跳过'));
        continue;
      }
      final content =
          _documentExtractor.extractText(fileName: file.name, bytes: bytes) ??
              '';
      final truncated = content.length > _maxTextAttachmentChars;
      final visibleContent = truncated
          ? '${content.substring(0, _maxTextAttachmentChars)}\n[内容已截断'
          : content;
      parts.add(MessagePart.text('\n\n文件 ${file.name} 内容：\n$visibleContent'));
      continue;
    }

    final userMessage = ChatMessage(role: MessageRole.user, parts: parts);
    final initialContextTokens = [
      ...state.messages,
      userMessage,
    ].fold<int>(
        0, (sum, message) => sum + ContextWindow.estimateTokens(message));
    final assistantIndex = state.messages.length + 1;
    var newTitle = state.conversationTitle;
    if (newTitle == '新会话') {
      newTitle = trimmed.length > 24 ? trimmed.substring(0, 24) : trimmed;
    }

    state = state.copyWith(
      messages: [
        ...state.messages,
        userMessage,
        ChatMessage(
            role: MessageRole.assistant,
            parts: [const MessagePart.text('')],
            reasoning: '正在思考…')
      ],
      running: true,
      paused: false,
      conversationTitle: newTitle,
      toolActivities: const [],
      activityLog: const [],
      liveContextTokens: initialContextTokens,
      clearLiveReply: true,
    );

    // 持久化失败不阻断对话：吞掉异常，后续 _runAgent 内的兜底 catch 会恢复 running 状态。
    try {
      final database = await ref.read(databaseProvider.future);
      if (!_runs.ownsRun(runGeneration, conversationId)) return;
      try {
        await _persistMessage(userMessage);
        if (conversationId != null) {
          final current = await database.findConversation(conversationId);
          if (current != null) {
            await database.saveConversation(
                current.copyWith(title: newTitle, updatedAt: DateTime.now()));
          }
        }
      } catch (_) {}

      final prep = await _prepareRun(database);
      if (!_runs.ownsRun(runGeneration, conversationId)) return;
      // C2 断点恢复：注册一个"运行中"任务，App 被杀后可在启动时提示继续执行。
      String? runningTaskId;
      try {
        final task = await TaskService().create(
          db: database,
          conversationId: conversationId ?? '',
          type: 'development:$taskType',
          requestJson: jsonEncode({
            'prompt': trimmed,
            'conversationId': conversationId,
            'model': prep.model,
            'maxSteps': prep.maxSteps,
          }),
          metadata: {
            'taskType': taskType,
            'sourceType': sourceType,
            'workspacePath': workspacePath,
            'title': _taskTitle(taskType, trimmed),
            'attachments': attachments.map((file) => file.name).toList(),
          },
        );
        runningTaskId = task.id;
      } catch (_) {} // 任务登记失败不阻断执行。

      if (!_runs.ownsRun(runGeneration, conversationId)) return;
      await _runAgent(
          assistantIndex,
          prep.model,
          prep.config,
          prep.registry,
          prep.maxSteps,
          prep.temperature,
          prep.maxTokens,
          prep.topP,
          prep.config.reasoningEffort,
          approveTool,
          runningTaskId,
          runGeneration,
          conversationId);
    } catch (error) {
      if (_runs.ownsRun(runGeneration, conversationId)) {
        final failed = ChatMessage(
          role: MessageRole.assistant,
          parts: [MessagePart.text(formatErrorForMessage(error.toString()))],
        );
        state = _withMessageAt(state, assistantIndex, failed).copyWith(
          running: false,
          clearLiveReply: true,
        );
        try {
          await _persistMessage(failed);
        } catch (_) {}
      }
    }
  }

  Future<void> regenerate(
      {required Future<ToolApproval> Function(ToolCall call, ToolRisk risk)
          approveTool}) async {
    if (state.running || state.loading) return;
    if (state.messages.isEmpty ||
        state.messages.last.role != MessageRole.assistant) {
      return;
    }

    final database = await ref.read(databaseProvider.future);
    final conversationId = state.conversationId;
    final runGeneration = _runs.beginRun();
    if (conversationId != null) {
      await database.deleteTrailingAssistantAndTool(conversationId);
    }
    final assistantIndex = state.messages.length - 1;
    state = state.copyWith(
      messages: [
        ...state.messages.sublist(0, assistantIndex),
        ChatMessage(
            role: MessageRole.assistant,
            parts: [const MessagePart.text('')],
            reasoning: '正在思考…')
      ],
      running: true,
      paused: false,
      toolActivities: const [],
      activityLog: const [],
      clearLiveReply: true,
    );

    final prep = await _prepareRun(database);
    if (!_runs.ownsRun(runGeneration, conversationId)) return;
    await _runAgent(
        assistantIndex,
        prep.model,
        prep.config,
        prep.registry,
        prep.maxSteps,
        prep.temperature,
        prep.maxTokens,
        prep.topP,
        prep.config.reasoningEffort,
        approveTool,
        null,
        runGeneration,
        conversationId);
  }

  /// 编辑历史用户消息并重发：替换该条内容，删除其后的所有回复与工具记录，
  /// 再基于编辑后的消息重新运行 Agent。
  Future<void> editAndResend({
    required int messageIndex,
    required String newText,
    required Future<ToolApproval> Function(ToolCall call, ToolRisk risk)
        approveTool,
  }) async {
    if (state.running || state.loading) return;
    if (messageIndex < 0 || messageIndex >= state.messages.length) return;
    final target = state.messages[messageIndex];
    if (target.role != MessageRole.user) return;
    final trimmed = newText.trim();
    if (trimmed.isEmpty) return;

    final imageParts =
        target.parts.where((part) => part.type != 'text').toList();
    final editedMessage = ChatMessage(
        role: MessageRole.user,
        parts: [MessagePart.text(trimmed), ...imageParts]);

    // state 中的用户消息与库中 role=user 的行按出现顺序一一对应，
    // 以第 ordinal 条用户行作为锚点，更新内容并截断其后所有行。
    final database = await ref.read(databaseProvider.future);
    final conversationId = state.conversationId;
    final runGeneration = _runs.beginRun();
    if (conversationId != null) {
      var ordinal = 0;
      for (var i = 0; i <= messageIndex; i++) {
        if (state.messages[i].role == MessageRole.user) ordinal++;
      }
      final userRows = (await database.messagesFor(conversationId))
          .where((row) => row.role == 'user')
          .toList(growable: false);
      if (userRows.length < ordinal) return;
      final anchor = userRows[ordinal - 1];
      try {
        await database.editMessageAndTruncate(
            conversationId, anchor.id, _contentForPersist(editedMessage));
      } catch (_) {
        // 持久化失败不阻断重发。
      }
    }

    if (!_runs.ownsRun(runGeneration, conversationId)) return;

    final assistantIndex = messageIndex + 1;
    state = state.copyWith(
      messages: [
        ...state.messages.sublist(0, messageIndex),
        editedMessage,
        // 与 send/regenerate 一致：占位助手消息由 _runAgent 按 assistantIndex 就地更新。
        ChatMessage(
            role: MessageRole.assistant,
            parts: [const MessagePart.text('')],
            reasoning: '正在思考…')
      ],
      running: true,
      paused: false,
      toolActivities: const [],
      activityLog: const [],
      clearLiveReply: true,
    );

    final prep = await _prepareRun(database);
    if (!_runs.ownsRun(runGeneration, conversationId)) return;
    await _runAgent(
        assistantIndex,
        prep.model,
        prep.config,
        prep.registry,
        prep.maxSteps,
        prep.temperature,
        prep.maxTokens,
        prep.topP,
        prep.config.reasoningEffort,
        approveTool,
        null,
        runGeneration,
        conversationId);
  }

  Completer<bool>? _planCompleter;

  void setVoiceLoopMode(bool value) {
    // A3 连续语音对话：占位，后续接入 TTS/ASR 循环。
  }

  /// C2 断点恢复：列出上次被中断（仍为 running）的后台任务。
  Future<List<Task>> recoverableTasks() async {
    try {
      final database = await ref.read(databaseProvider.future);
      return await TaskService().runningTasks(database);
    } catch (_) {
      return const [];
    }
  }

  /// C2 断点恢复：重新执行一个被中断的后台任务，并把结果写回会话。
  Future<void> resumeTask(String taskId,
      {required Future<ToolApproval> Function(ToolCall call, ToolRisk risk)
          approveTool}) async {
    AppDatabase? database;
    Task? task;
    String? uiConversationId;
    var runGeneration = 0;
    AgentCancellationToken? cancellationToken;
    if (!_resumingTaskIds.add(taskId)) return;
    try {
      database = await ref.read(databaseProvider.future);
      final db = database!;
      task = await db.findTask(taskId);
      if (task == null) return;
      final taskData = task;
      if (taskData.status != 'running' && taskData.status != 'paused') return;
      final taskService = TaskService();
      final savedProgress = _decodeTaskProgress(taskData.progressJson);
      final savedCheckpoint = savedProgress['checkpoint'];
      final savedCheckpointRunId = savedCheckpoint is Map
          ? savedCheckpoint['runId']?.toString().trim()
          : null;
      // 终态结果已经按 runId 应用过时，恢复入口只清理遗留 checkpoint，
      // 不再把同一结果追加到会话，避免进程重启后的重复副作用/重复消息。
      if (savedCheckpointRunId != null &&
          savedCheckpointRunId.isNotEmpty &&
          taskService.isRunApplied(savedProgress, savedCheckpointRunId)) {
        await taskService.clearCheckpoint(db, taskId);
        if (taskData.status != 'completed') {
          await taskService.updateStatus(db, taskId, 'completed');
        }
        return;
      }
      _invalidateActiveRun();
      final linkedConversation = taskData.conversationId.isEmpty
          ? null
          : await db.findConversation(taskData.conversationId);
      if (linkedConversation != null) {
        await switchConversation(linkedConversation);
        uiConversationId = linkedConversation.id;
      }

      runGeneration = _runs.beginRun();
      final runApprovalMode = state.approvalMode;
      if (uiConversationId != null) {
        state = state.copyWith(
          running: true,
          paused: false,
          toolActivities: const [],
          activityLog: const [],
          clearPlanState: true,
          clearLiveReply: true,
        );
      }
      bool ownsRun() => _runs.ownsRunUnbound(runGeneration, uiConversationId);
      cancellationToken = AgentCancellationToken();
      _runs.cancellationToken = cancellationToken;
      await TaskService().markResumed(db, taskId);
      await TaskService().updateStatus(db, taskId, 'running');

      final request = _decodeTaskRequest(taskData.requestJson);
      final store = ref.read(providerConfigStoreProvider);
      final config = await store.load();
      final maxStepsValue = request['maxSteps'];
      final maxSteps = maxStepsValue is num
          ? maxStepsValue.toInt()
          : int.tryParse(maxStepsValue?.toString() ?? '') ?? 8;
      final workspacePath = request['workspacePath']?.toString();
      final systemPrompt = request['systemPrompt']?.toString();

      final progress = _decodeTaskProgress(taskData.progressJson);
      final checkpoint = progress['checkpoint'];
      final checkpointContext = checkpoint is Map
          ? decodeChatContext(checkpoint['context'])
          : const <ChatMessage>[];
      final executionRunId = 'run-${DateTime.now().microsecondsSinceEpoch}';
      final result = await HeadlessExecutor.runDetailed(
        db: db,
        config: config,
        prompt: request['prompt']?.toString() ?? '',
        initialHistory: checkpointContext.isEmpty ? null : checkpointContext,
        systemPrompt: systemPrompt,
        workspacePath: workspacePath,
        maxSteps: maxSteps,
        cancellationToken: cancellationToken,
        approveTool: approveTool,
        approvalMode: runApprovalMode,
      );

      final taskStatus = switch (result.status) {
        RunStatus.cancelled => 'cancelled',
        RunStatus.failed => 'failed',
        RunStatus.paused => 'paused',
        _ => result.succeeded ? 'completed' : 'failed',
      };
      final resultText = result.text.trim();
      await taskService.complete(
        db,
        taskId,
        status: taskStatus,
        summary: resultText.isNotEmpty
            ? resultText
            : (result.error ?? 'Agent 执行未返回内容'),
        checkpoint: result.status == RunStatus.paused && result.context != null
            ? {
                'version': 1,
                'runId': executionRunId,
                'context': encodeChatContextForPersistence(result.context!),
                'reason': result.error,
              }
            : null,
        runId: executionRunId,
      );

      if (ownsRun()) {
        state =
            state.copyWith(running: false, paused: false, clearLiveReply: true);
        final assistantMessage = ChatMessage(
          role: MessageRole.assistant,
          parts: [MessagePart.text(resultText)],
          modelName: config.isConfigured ? config.model : '演示模型',
        );
        if (uiConversationId != null && resultText.isNotEmpty) {
          state = state.copyWith(
            messages: [...state.messages, assistantMessage],
            clearLiveReply: true,
          );
          try {
            await _persistMessage(assistantMessage);
          } catch (_) {}
        }
      }
    } catch (error) {
      final dbForCatch = database;
      if (dbForCatch != null) {
        try {
          await TaskService().complete(
            dbForCatch,
            taskId,
            status: 'failed',
            summary: error.toString(),
          );
        } catch (_) {}
      }
      if (runGeneration != 0 &&
          _runs.ownsRunUnbound(runGeneration, uiConversationId)) {
        state =
            state.copyWith(running: false, paused: false, clearLiveReply: true);
      }
    } finally {
      _resumingTaskIds.remove(taskId);
      if (cancellationToken != null) {
        _runs.clearCancellationTokenIf(cancellationToken);
      }
      if (runGeneration != 0) {
        _runs.forget(runGeneration);
      }
    }
  }

  /// 预算暂停后从保存的 Agent 上下文续跑，而不是重新提交原始 prompt。
  Future<void> resumeFromBudgetPause({
    required Future<ToolApproval> Function(ToolCall call, ToolRisk risk)
        approveTool,
  }) async {
    final context = _runs.budgetPauseContext;
    if (context == null || context.isEmpty || state.running || state.loading) {
      return;
    }
    final database = await ref.read(databaseProvider.future);
    final conversationId = state.conversationId;
    final runGeneration = _runs.beginRun();
    // 追加一个助手占位消息承载续跑输出；实际模型输入用保存的上下文。
    final assistantIndex = state.messages.length;
    final pausedPlan = state.planState;
    state = state.copyWith(
      planState: pausedPlan?.status == 'paused'
          ? pausedPlan!.copyWith(status: 'executing')
          : pausedPlan,
      messages: [
        ...state.messages,
        ChatMessage(
            role: MessageRole.assistant, parts: const [MessagePart.text('')]),
      ],
      running: true,
      paused: false,
      toolActivities: const [],
      activityLog: const [],
      clearLiveReply: true,
    );
    try {
      final prep = await _prepareRun(database);
      if (!_runs.ownsRun(runGeneration, conversationId)) return;
      await _runAgent(
        assistantIndex,
        prep.model,
        prep.config,
        prep.registry,
        prep.maxSteps,
        prep.temperature,
        prep.maxTokens,
        prep.topP,
        prep.config.reasoningEffort,
        approveTool,
        null,
        runGeneration,
        conversationId,
        resumeContext: context,
      );
    } catch (error) {
      if (_runs.ownsRun(runGeneration, conversationId)) {
        final failed = ChatMessage(
          role: MessageRole.assistant,
          parts: [MessagePart.text(formatErrorForMessage(error.toString()))],
        );
        state = _withMessageAt(state, assistantIndex, failed).copyWith(
          running: false,
          clearLiveReply: true,
        );
        try {
          await _persistMessage(failed);
        } catch (_) {}
      }
    }
  }

  Map<String, dynamic> _decodeTaskRequest(String json) {
    try {
      final decoded = jsonDecode(json);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  Map<String, dynamic> _decodeTaskProgress(String json) {
    try {
      final decoded = jsonDecode(json);
      return decoded is Map<String, dynamic>
          ? Map<String, dynamic>.from(decoded)
          : const {};
    } catch (_) {
      return const {};
    }
  }

  Future<void> pickWorkspace() async {
    final service = ref.read(workspaceServiceProvider);
    final path = await service.pickDirectory();
    if (path != null) {
      state = state.copyWith(currentWorkspacePath: path);
    }
  }

  Future<void> setWorkspace(String? path) async {
    final service = ref.read(workspaceServiceProvider);
    await service.setActiveWorkspace(path);
    state = state.copyWith(
        currentWorkspacePath: path, clearWorkspace: path == null);
  }

  void setPlanMode(bool value) {
    state = state.copyWith(planMode: value, clearPlanState: true);
  }

  void setApprovalMode(ApprovalMode mode) {
    state = state.copyWith(approvalMode: mode);
  }

  /// remember 工具回调：异步懒加载 DB 并写入一条手动来源记忆。
  Future<void> _onRemember(String content) async {
    try {
      final database = await ref.read(databaseProvider.future);
      await MemoryService().add(
        database: database,
        content: content,
        sourceType: 'manual',
        importance: 2,
      );
    } catch (_) {
      // 记忆写入失败不阻断主流程。
    }
  }

  Future<ToolResult> _onRememberWithRevision(
      String content, String? expectedRevision) async {
    try {
      final database = await ref.read(databaseProvider.future);
      final memory = await MemoryService().add(
        database: database,
        content: content,
        sourceType: 'manual',
        importance: 2,
        expectedRevision: expectedRevision,
      );
      final revision = await MemoryService().currentRevision(database);
      return ToolResult.success(
        message: '已记住：${memory.content}',
        data: {'revision': revision, 'id': memory.id},
        effect: ToolEffect.applied,
      );
    } on MemoryConflictException catch (error) {
      return ToolResult.failure(
        code: ToolCodes.revisionConflict,
        message: '记忆已被其他操作更新，请先重新调用 memory_get 获取最新 revision',
        data: {'revision': error.currentRevision},
      );
    } catch (error) {
      return ToolResult.failure(
        code: ToolCodes.toolError,
        message: '记忆写入失败：$error',
      );
    }
  }

  Future<ToolResult> _onMemoryGet(String query, int offset, int limit) async {
    try {
      final database = await ref.read(databaseProvider.future);
      final service = MemoryService();
      // 多取一条用于告诉模型是否还有下一页，避免模型因静默截断而误以为
      // 当前结果就是完整记忆集合。
      final matched = await service.search(database, query,
          offset: offset, limit: limit + 1);
      final hasMore = matched.length > limit;
      final items = hasMore ? matched.take(limit).toList() : matched;
      final revision = await service.currentRevision(database);
      return ToolResult.success(
        message: items.isEmpty ? '未找到匹配记忆' : '已读取 ${items.length} 条记忆',
        data: {
          'revision': revision,
          'offset': offset,
          'limit': limit,
          'hasMore': hasMore,
          'nextOffset': hasMore ? offset + items.length : null,
          'items': items
              .map((item) => {
                    'id': item.id,
                    'content': item.content,
                    'category': item.category,
                    'importance': item.importance,
                    'updatedAt': item.updatedAt.toIso8601String(),
                  })
              .toList(growable: false),
        },
      );
    } catch (error) {
      return ToolResult.failure(
        code: ToolCodes.toolError,
        message: '读取记忆失败：$error',
      );
    }
  }

  Future<ToolResult> _onMemoryWrite({
    required String? id,
    required String content,
    required String mode,
    required int? startLine,
    required int? endLine,
    required String? expectedRevision,
  }) async {
    try {
      final database = await ref.read(databaseProvider.future);
      final service = MemoryService();
      final memory = await service.write(
        database: database,
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
          'revision': await service.currentRevision(database),
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
  }

  /// sub_agent 工具回调：复用 HeadlessExecutor 无 UI 执行一个子任务。
  /// [budget] 为可选的受限 token 预算，越界/缺省值会被钳制到
  /// [SubAgentTool.minBudget]~[SubAgentTool.maxBudget]。
  Future<String> _runSubAgent(
      String? agentId, String prompt, int? budget) async {
    String? systemPrompt;
    try {
      final database = await ref.read(databaseProvider.future);
      if (agentId != null && agentId.isNotEmpty) {
        final agent = await database.findAgent(agentId);
        if (agent != null && agent.systemPrompt.trim().isNotEmpty) {
          systemPrompt = agent.systemPrompt;
        }
      }
    } catch (_) {}
    try {
      final database = await ref.read(databaseProvider.future);
      final store = ref.read(providerConfigStoreProvider);
      final config = await store.load();
      return await HeadlessExecutor.run(
        db: database,
        config: config,
        prompt: prompt,
        systemPrompt: systemPrompt,
        maxTokens: SubAgentTool.clampBudget(budget),
      );
    } catch (error) {
      return '子任务执行失败：$error';
    }
  }

  /// manage_plan 工具回调：把模型产出的步骤写入 planState。
  Future<void> _onPlanUpdated(List<PlanStep> steps) async {
    if (steps.isEmpty) return;
    final generation = _activePlanGeneration;
    if (generation == null || generation != _runs.generation) return;
    state = state.copyWith(planState: PlanState(steps: steps));
  }

  /// 主 Agent 的 sub_agent 委派规则。开启自主委派时给出自主边界；关闭时
  /// 要求先获得用户确认（与审批模式兼容）。
  static String _delegationRules(bool autonomous) {
    if (autonomous) {
      return '[自主委派规则]\n'
          '- 可将可独立、并行推进的只读子任务委派给 sub_agent 执行以加快处理。\n'
          '- 通过 maxTokens 为每个子任务分配受限预算（上限 ${SubAgentTool.maxBudget}），不要超预算。\n'
          '- 子 Agent 仅放行安全工具；写文件、执行命令、提交、联网发布等危险操作必须由你亲自处理并走审批，不得委派。\n'
          '- 委派只是优化手段，你仍对最终结果负责，应核实并汇总子 Agent 返回。';
    }
    return '[委派规则]\n'
        '- 委派子任务前必须先获得用户确认（sub_agent 调用需审批）。\n'
        '- 仅可委派只读、安全的子任务；危险操作由你亲自处理并走审批。\n'
        '- 通过 maxTokens 为子任务分配受限预算（上限 ${SubAgentTool.maxBudget}），不要超预算；委派后应核实并汇总结果。';
  }

  void _updatePlanStepStatus(String status) {
    final plan = state.planState;
    if (plan == null || !plan.isConfirmed) return;

    final steps = List<PlanStep>.from(plan.steps);
    var targetIdx = -1;
    if (status == 'running') {
      targetIdx = steps.indexWhere((step) => step.status == 'pending');
    } else if (status == 'completed' || status == 'failed') {
      targetIdx = steps.indexWhere((step) => step.status == 'running');
      if (targetIdx == -1) {
        targetIdx = steps.indexWhere((step) => step.status == 'pending');
      }
    }

    if (targetIdx != -1) {
      steps[targetIdx] = steps[targetIdx].copyWith(status: status);
      state = state.copyWith(planState: plan.copyWith(steps: steps));
    }

    // 步骤全部走到终态后，顶层计划状态必须随之收敛，避免“所有步骤已完成
    // 但顶层仍显示 executing”。
    _reconcilePlanTopLevel();
  }

  /// 依据步骤终态收敛计划顶层状态：
  /// - 全部步骤 completed → 顶层 completed；
  /// - 任一步骤 failed 且无 pending/running → 顶层 failed；
  /// - 仅当步骤都还活跃时保持当前执行态。
  void _reconcilePlanTopLevel() {
    final plan = state.planState;
    if (plan == null ||
        !plan.isConfirmed ||
        plan.status == 'completed' ||
        plan.status == 'cancelled' ||
        plan.steps.isEmpty) {
      return;
    }
    final next = resolvePlanTerminalStatus(
        steps: plan.steps, currentStatus: plan.status);
    if (next != null && next != plan.status) {
      state = state.copyWith(planState: plan.copyWith(status: next));
    }
  }

  /// 运行收尾终态收敛 + 残留步骤归一化（独立于 ownsRun，防止代次失效时残留 executing）。
  /// - 终态 completed → 残留 running / pending 步骤置为 completed；
  /// - 终态 failed / cancelled → 残留 running / pending 步骤置为 failed；
  /// - 终态 paused → 步骤保持原样（供“继续执行”从断点续跑）。
  void _convergePlanToTerminal({
    required String? runStatus,
    required bool cancelled,
  }) {
    final plan = state.planState;
    if (plan == null ||
        plan.status == 'completed' ||
        plan.status == 'cancelled' ||
        plan.status == 'failed') {
      return;
    }
    final terminal = resolvePlanTerminalStatus(
      steps: plan.steps,
      currentStatus: plan.status,
      runStatus: runStatus,
      cancelled: cancelled,
    );
    if (terminal == null) return;
    state = state.copyWith(
      planState: plan.copyWith(
        status: terminal,
        steps: normalizePlanStepsForTerminal(plan.steps, terminal),
      ),
    );
  }

  /// 纯函数：按计划终态归一化残留步骤（@visibleForTesting 便于单测）。
  /// - completed → running / pending 置为 completed；
  /// - failed / cancelled → running / pending 置为 failed；
  /// - 其他（paused 等）保持不变。
  @visibleForTesting
  static List<PlanStep> normalizePlanStepsForTerminal(
      List<PlanStep> steps, String terminal) {
    final String? replacement;
    if (terminal == 'completed') {
      replacement = 'completed';
    } else if (terminal == 'failed' || terminal == 'cancelled') {
      replacement = 'failed';
    } else {
      replacement = null;
    }
    if (replacement == null) return steps;
    return [
      for (final step in steps)
        if (step.status == 'running' || step.status == 'pending')
          step.copyWith(status: replacement)
        else
          step,
    ];
  }

  /// 纯函数：依据步骤终态与运行结果，解析计划应进入的顶层状态。
  /// - [runStatus] 为 null 表示运行尚未结束，只依据步骤终态收敛；
  ///   否则按运行结果解析（含步骤全完成对 paused 的覆盖）。
  @visibleForTesting
  static String? resolvePlanTerminalStatus({
    required List<PlanStep> steps,
    required String currentStatus,
    String? runStatus,
    bool cancelled = false,
  }) {
    if (steps.isEmpty) return null;
    final allCompleted = steps.every((step) => step.status == 'completed');
    final allTerminal = steps
        .every((step) => step.status == 'completed' || step.status == 'failed');
    final anyFailed = steps.any((step) => step.status == 'failed');

    // 运行尚未结束：仅在步骤全部走到终态时收敛，避免提前改态。
    if (runStatus == null) {
      if (allCompleted) return 'completed';
      if (allTerminal && anyFailed) return 'failed';
      return null;
    }

    // 运行已结束：按运行结果解析。
    if (cancelled || runStatus == 'cancelled') return 'cancelled';
    if (runStatus == 'success') return 'completed';
    if (allCompleted) return 'completed';
    if (runStatus == 'paused') return 'paused';
    return 'failed';
  }

  void respondToPlan(bool approved) {
    final completer = _planCompleter;
    _planCompleter = null;
    final wasConfirmed = state.planState?.isConfirmed ?? false;
    state = state.copyWith(
        planState: state.planState
            ?.copyWith(status: approved ? 'executing' : 'cancelled'),
        activityLog: [
          ...state.activityLog,
          approved ? '计划已确认，正在继续执行' : '计划已取消',
        ]);
    if (completer != null && !completer.isCompleted) {
      completer.complete(approved);
    } else if (!approved && wasConfirmed) {
      // 计划已确认并正在执行，此时点击“停止执行计划”不仅要标记为取消，
      // 还必须真正中断底层运行，避免顶层残留 executing / 后台继续执行。
      _invalidateActiveRun();
    }
  }

  Future<bool> _confirmPlan(List<ToolCall> calls, String planText) async {
    final generation = _activePlanGeneration;
    if (generation == null || generation != _runs.generation) return false;
    _planCompleter?.complete(false);
    final completer = Completer<bool>();
    _planCompleter = completer;

    if (state.planState == null) {
      final steps = <PlanStep>[];
      for (final c in calls) {
        if (c.name == 'manage_plan') {
          final s = c.arguments['steps'] as List?;
          if (s != null) {
            for (final item in s) {
              steps.add(PlanStep(
                  id: item['id']?.toString() ?? '',
                  description: item['description']?.toString() ?? ''));
            }
          }
        }
      }
      if (steps.isEmpty) {
        steps.add(const PlanStep(id: 's1', description: '执行任务'));
      }
      state = state.copyWith(planState: PlanState(steps: steps));
    }

    return completer.future;
  }

  void _invalidateActiveRun() {
    // 代次、取消令牌与预算断点统一交给 RunCoordinator 处理。
    _runs.invalidateActiveRun();
    // 计划回调与计划代次属于计划状态机，暂留此处（A-1 第 3 步再抽 PlanStateMachine）。
    final completer = _planCompleter;
    _planCompleter = null;
    _activePlanGeneration = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(false);
    }
    if (state.running ||
        state.planState != null ||
        state.toolActivities.isNotEmpty) {
      state = state.copyWith(
        running: false,
        toolActivities: const [],
        activityLog: const [],
        clearPlanState: true,
        clearLiveReply: true,
      );
    }
  }

  String _notificationPreview(String value, String status) {
    final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) {
      return status == 'completed'
          ? '请打开任务查看结果'
          : (status == 'paused' ? '任务已暂停，可恢复继续执行' : '请打开任务查看失败原因');
    }
    return text.length > 90 ? '${text.substring(0, 90)}…' : text;
  }

  ({int? costCents, int? savedCostCents}) _estimateUsageCost(
      ProviderConfig config, Usage usage) {
    const rates = <String, (int, int)>{
      'gpt-4o-mini': (2, 9),
      'gpt-4o': (35, 140),
      'claude-sonnet-4-5': (45, 190),
      'deepseek-chat': (3, 11),
      'deepseek-reasoner': (6, 22),
    };
    final fallback = rates[config.model];
    final inputRate = config.inputPricePerMillionCents ?? fallback?.$1;
    final outputRate = config.outputPricePerMillionCents ?? fallback?.$2;
    final cachedRate = config.cachedPricePerMillionCents ??
        (inputRate == null ? null : (inputRate / 10).round());
    final effectiveCachedRate = cachedRate;
    if (inputRate == null ||
        outputRate == null ||
        effectiveCachedRate == null ||
        usage.totalTokens == 0) {
      return (costCents: null, savedCostCents: null);
    }
    final freshInput =
        (usage.promptTokens - usage.cachedTokens).clamp(0, 1 << 30);
    final cost = ((freshInput * inputRate +
                usage.cachedTokens * effectiveCachedRate +
                usage.completionTokens * outputRate) /
            1000000)
        .ceil();
    final saved =
        ((usage.cachedTokens * (inputRate - effectiveCachedRate)) / 1000000)
            .ceil();
    return (costCents: cost, savedCostCents: saved);
  }

  /// 暂停只在下一个 Agent 检查点生效，不打断当前模型流或工具调用。
  bool pause() {
    if (!state.running) return false;
    final controller = _runs.runController;
    if (controller == null || !controller.pause()) return false;
    state = state.copyWith(
      activityLog: [...state.activityLog, '运行已暂停，等待检查点'],
    );
    return true;
  }

  /// 恢复已暂停的 Agent；重复恢复保持幂等。
  bool resume() {
    final controller = _runs.runController;
    if (controller == null || !controller.resume()) return false;
    state = state.copyWith(
      paused: false,
      activityLog: [...state.activityLog, '运行已恢复'],
    );
    return true;
  }

  /// 把补充指令排入当前 turn 边界，不打断正在执行的工具批次。
  bool steer(String text) {
    if (!state.running) return false;
    final controller = _runs.runController;
    if (controller == null || !controller.steer(text)) return false;
    state = state.copyWith(
      activityLog: [...state.activityLog, '补充指令已排队，将在下一轮生效'],
    );
    return true;
  }

  void stop() {
    _commitLiveReply();
    _cancelRequestedAt = DateTime.now();
    _invalidateActiveRun();
    // 真正中断底层 HTTP 流（Dio 层），避免连接与带宽继续被占用。
    _runs.dioCancelToken?.cancel();
  }

  /// Preserve text already visible when the user explicitly stops generation.
  /// Navigation/session changes use the normal invalidation path and discard it.
  void _commitLiveReply() {
    final live = state.liveReply;
    if (live == null ||
        live.messageIndex < 0 ||
        live.messageIndex >= state.messages.length) {
      return;
    }
    final current = state.messages[live.messageIndex];
    final message = current.copyWith(
      parts: [MessagePart.text(live.text)],
      reasoning: live.reasoning,
    );
    state = _withMessageAt(state, live.messageIndex, message).copyWith(
      clearLiveReply: true,
    );
  }

  void setSystemPrompt(String prompt) =>
      state = state.copyWith(systemPrompt: prompt);

  void addSessionSkillInstruction({
    required String id,
    required String name,
    required String instruction,
  }) {
    final normalized = instruction.trim();
    if (id.isEmpty ||
        normalized.isEmpty ||
        state.sessionSkillInstructions.any((item) => item.id == id)) {
      return;
    }
    const maxSessionSkillChars = 16000;
    final current = state.sessionSkillInstructions;
    final used = current.fold<int>(0, (sum, item) => sum + item.content.length);
    if (used >= maxSessionSkillChars) return;
    final remaining = maxSessionSkillChars - used;
    state = state.copyWith(
      sessionSkillInstructions: [
        ...current,
        SessionSkillInstruction(
          id: id,
          name: name,
          content:
              normalized.substring(0, normalized.length.clamp(0, remaining)),
        ),
      ],
    );
  }

  void removeSessionSkillInstruction(String id) {
    state = state.copyWith(
      sessionSkillInstructions: state.sessionSkillInstructions
          .where((item) => item.id != id)
          .toList(growable: false),
    );
  }

  // --- 浼氳瘽 / Agent / Provider 操作 ---

  Future<void> newConversation() async {
    _invalidateActiveRun();
    final newGeneration = _runs.generation;
    final database = await ref.read(databaseProvider.future);
    final conversation = await _createConversation(database);
    if (newGeneration != _runs.generation) return;
    state = state.copyWith(
      conversationId: conversation.id,
      conversationTitle: conversation.title,
      messages: const [],
      toolActivities: const [],
      activityLog: const [],
      liveContextTokens: 0,
      // 步数不落库，新会话即归零。
      totalSteps: 0,
      clearPlanState: true,
      clearLiveReply: true,
      clearSessionSkillInstructions: true,
    );
  }

  Future<void> switchConversation(Conversation conversation) async {
    _invalidateActiveRun();
    final switchGeneration = _runs.generation;
    final database = await ref.read(databaseProvider.future);
    final stored = await database.messagesFor(conversation.id);
    if (switchGeneration != _runs.generation) return;
    var agentName = state.agentName;
    var systemPrompt = state.systemPrompt;
    var agentId = conversation.agentId;
    if (agentId != null) {
      final agent = await database.findAgent(agentId);
      if (agent != null) {
        agentName = agent.name;
        systemPrompt = agent.systemPrompt;
      }
    }
    if (switchGeneration != _runs.generation) return;
    final restored = _restoreFromMessages(stored);
    state = state.copyWith(
      conversationId: conversation.id,
      conversationTitle: conversation.title,
      agentId: agentId,
      agentName: agentName,
      systemPrompt: systemPrompt,
      messages: restored.$1,
      toolActivities: restored.$2,
      activityLog: const [],
      liveContextTokens: restored.$1.fold<int>(
          0, (sum, message) => sum + ContextWindow.estimateTokens(message)),
      // 步数（agent 循环迭代数）未持久化，切回历史会话时从 0 重新累计。
      totalSteps: 0,
      clearAgentId: agentId == null,
      clearPlanState: true,
      clearLiveReply: true,
      clearSessionSkillInstructions: true,
    );
  }

  Future<void> selectAgent(Agent agent) async {
    state = state.copyWith(
        agentId: agent.id,
        agentName: agent.name,
        systemPrompt: agent.systemPrompt);
    final database = await ref.read(databaseProvider.future);
    final conversationId = state.conversationId;
    if (conversationId != null) {
      final conversation = await database.findConversation(conversationId);
      if (conversation != null) {
        await database.saveConversation(conversation.copyWith(
            agentId: Value(agent.id), updatedAt: DateTime.now()));
      }
    }
  }

  Future<void> switchProvider(ProviderConfig profile) async {
    String? activeWorkspace;
    try {
      activeWorkspace =
          await ref.read(workspaceServiceProvider).getActiveWorkspace();
    } catch (_) {}
    final store = ref.read(providerConfigStoreProvider);
    await store.save(profile);
    final config = await store.load();
    // Workspace is managed via state.currentWorkspacePath
    state = state.copyWith(
      activeModel: config.model,
      activeProviderName: config.name,
      activeProviderId: config.id,
      contextTokens: config.contextTokens,
      activeReasoningEffort: config.reasoningEffort,
      providerConfigured: config.isConfigured,
      currentWorkspacePath: activeWorkspace,
    );
  }

  /// 切换"思考程度"档位（已保存到 ProviderConfig），更新 state 以便 UI 立即反映。
  void setReasoningEffort(ReasoningEffort effort) {
    state = state.copyWith(activeReasoningEffort: effort);
  }

  /// 重新加载当前生效的服务商配置（如用户从设置页配置 Key 返回后）。
  Future<void> reloadProviderConfig() async {
    final store = ref.read(providerConfigStoreProvider);
    final config = await store.load();
    state = state.copyWith(
      activeModel: config.model,
      activeProviderName: config.name,
      activeProviderId: config.id,
      contextTokens: config.contextTokens,
      activeReasoningEffort: config.reasoningEffort,
      providerConfigured: config.isConfigured,
    );
  }

  // --- 鐘舵€佽緟'---

  ToolRisk _riskFor(ToolRegistry registry, String name) =>
      registry.findRegistration(name)?.spec.risk ?? ToolRisk.safe;

  bool _isFileOperationTool(String name) =>
      name.endsWith('_file') ||
      const {'list_directory', 'search_files'}.contains(name);

  /// 取 assistantIndex 之前最近的一条用户文本，作为知识库检索的 query。
  String _lastUserText(int assistantIndex) {
    final messages = state.messages.sublist(0, assistantIndex);
    for (final message in messages.reversed) {
      if (message.role == MessageRole.user && message.text.trim().isNotEmpty) {
        return message.text.trim();
      }
    }
    return '';
  }

  ChatState _withMessageAt(ChatState s, int index, ChatMessage message) {
    final messages = List<ChatMessage>.of(s.messages);
    messages[index] = message;
    return s.copyWith(messages: messages);
  }

  int _estimateLiveContextTokens(
    int assistantIndex,
    ChatMessage assistantMessage, {
    List<ChatMessage> extraMessages = const [],
  }) {
    final messages = [
      ...state.messages.take(assistantIndex),
      assistantMessage,
      ...extraMessages,
    ];
    return messages.fold<int>(
        0, (sum, message) => sum + ContextWindow.estimateTokens(message));
  }

  List<ToolActivity> _updateToolActivity(
    List<ToolActivity> activities,
    String callId, {
    String? status,
    String? result,
    bool? ok,
    String? code,
    ToolEffect? effect,
  }) {
    return activities
        .map((a) => a.call.id == callId
            ? a.copyWith(
                status: status,
                result: result,
                ok: ok,
                code: code,
                effect: effect,
              )
            : a)
        .toList();
  }

  List<ToolActivity> _updateLastToolActivity(List<ToolActivity> activities,
      {String? status}) {
    if (activities.isEmpty) return activities;
    final updated = List<ToolActivity>.of(activities);
    updated[updated.length - 1] = updated.last.copyWith(status: status);
    return updated;
  }
}

final chatControllerProvider =
    NotifierProvider<ChatController, ChatState>(ChatController.new);

/// 流式实时回复的高频切片 Provider。
///
/// 流式期间 [ChatController] 以 ≤70ms 的节奏刷新 `liveReply`；把它单独暴露，
/// 使只有真正消费流式文本的子树（消息列表）随其重建，而输入胶囊、会话指标条
/// 与顶栏不会被每次增量刷新的整页重建波及。
///
/// 说明：此处直接放在 `chat_controller.dart` 末尾、与 [chatControllerProvider]
/// 并列，而非 `providers.dart`——后者已被本文件 import，若反向 import 本文件
/// 会形成循环依赖。
final liveReplyProvider = Provider<LiveReply?>(
  (ref) => ref.watch(chatControllerProvider).liveReply,
);

/// 运行态切片 Provider（低频标量）。
///
/// `Provider` 仅在返回值变化（`==`）时才通知监听者，因此订阅它等价于
/// `chatControllerProvider.select((s) => s.running)`，但语义更清晰。
final runningProvider = Provider<bool>(
  (ref) => ref.watch(chatControllerProvider).running,
);
