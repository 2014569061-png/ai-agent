import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mojibake_repair.dart';
import 'autonomous_delegation.dart';

import '../domain/models.dart';
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
import 'agent_executor.dart';
import 'context_window.dart';
import 'error_humanizer.dart';
import 'headless_executor.dart';
import 'knowledge_service.dart';
import 'memory_service.dart';
import 'providers.dart';
import 'log_service.dart';
import 'run_event_queue.dart';
import 'run_event_tracker.dart';
import 'task_service.dart';
import 'workspace_service.dart';
import '../infrastructure/plugins/plugin_store.dart';
import '../infrastructure/skills/skill_store.dart';
import '../infrastructure/notifications/notification_service.dart';

// ignore_for_file: curly_braces_in_flow_control_structures

/// 单次工具调用的运行时展示状态类
class ToolActivity {
  const ToolActivity(
      {required this.call,
      required this.risk,
      this.status = '等待执行',
      this.result});
  final ToolCall call;
  final ToolRisk risk;
  final String status;
  final String? result;

  ToolActivity copyWith({String? status, String? result}) => ToolActivity(
        call: call,
        risk: risk,
        status: status ?? this.status,
        result: result ?? this.result,
      );
}

/// 鑱婂ぉ椤电殑瀹屾暣涓嶅彲鍙樼姸鎬?
class ChatState {
  const ChatState({
    this.messages = const [],
    this.running = false,
    this.loading = true,
    this.conversationId,
    this.conversationTitle = '新会话',
    this.agentName = '通用助手',
    this.systemPrompt = '你是一个有帮助的 AI Agent。',
    this.agentId,
    this.toolActivities = const [],
    this.activityLog = const [],
    this.activeModel = '',
    this.activeProviderName = '',
    this.activeProviderId = '',
    this.contextTokens = 128000,
    this.liveContextTokens = 0,
    this.liveReply,
    this.activeReasoningEffort = ReasoningEffort.medium,
    this.providerConfigured = false,
    this.planMode = false,
    this.approvalMode = ApprovalMode.ask,
    this.planState,
    this.currentWorkspacePath,
  });

  final List<ChatMessage> messages;
  final bool running;
  final bool loading;
  final String? conversationId;
  final String conversationTitle;
  final String agentName;
  final String systemPrompt;
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
  final ReasoningEffort activeReasoningEffort;
  final bool providerConfigured;
  final bool planMode;
  final ApprovalMode approvalMode;
  final PlanState? planState;
  final String? currentWorkspacePath;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? running,
    bool? loading,
    String? conversationId,
    String? conversationTitle,
    String? agentName,
    String? systemPrompt,
    String? agentId,
    List<ToolActivity>? toolActivities,
    List<String>? activityLog,
    String? activeModel,
    String? activeProviderName,
    String? activeProviderId,
    int? contextTokens,
    int? liveContextTokens,
    LiveReply? liveReply,
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
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        running: running ?? this.running,
        loading: loading ?? this.loading,
        conversationId: clearConversationId
            ? null
            : (conversationId ?? this.conversationId),
        conversationTitle: conversationTitle ?? this.conversationTitle,
        agentName: agentName ?? this.agentName,
        systemPrompt: systemPrompt ?? this.systemPrompt,
        agentId: clearAgentId ? null : (agentId ?? this.agentId),
        toolActivities: toolActivities ?? this.toolActivities,
        activityLog: activityLog ?? this.activityLog,
        activeModel: activeModel ?? this.activeModel,
        activeProviderName: activeProviderName ?? this.activeProviderName,
        activeProviderId: activeProviderId ?? this.activeProviderId,
        contextTokens: contextTokens ?? this.contextTokens,
        liveContextTokens: liveContextTokens ?? this.liveContextTokens,
        liveReply: clearLiveReply ? null : (liveReply ?? this.liveReply),
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

  AgentCancellationToken? _cancellationToken;
  CancelToken? _dioCancelToken;
  DateTime? _cancelRequestedAt;
  int _runGeneration = 0;
  final Set<int> _cancelledRunGenerations = <int>{};
  int? _activePlanGeneration;

  /// 预算暂停时保存的 Agent 内部上下文；用于从断点续跑而非重提原始 prompt。
  List<ChatMessage>? _lastBudgetPauseContext;

  /// 最近一次预算暂停保存的续跑上下文（可能为空）。
  List<ChatMessage>? get budgetPauseContext => _lastBudgetPauseContext;

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
              activities[index].copyWith(result: message.content);
        }
      } else {
        messages.add(_toDomainMessage(message));
      }
    }
    return (messages, activities);
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

  Future<void> _persistMessage(ChatMessage message) async {
    final conversationId = state.conversationId;
    if (conversationId == null) return;
    final database = await ref.read(databaseProvider.future);
    await database.insertMessage(MessagesCompanion.insert(
      id: 'message-${DateTime.now().microsecondsSinceEpoch}-${_messageSeq++}',
      conversationId: conversationId,
      role: message.role.name,
      content: _contentForPersist(message),
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
          'arguments': call.arguments,
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

  ToolRegistry _buildRegistry(
    Set<String> enabledTools,
    String tavilyKey,
    ProviderConfig config,
    ToolRisk subAgentRisk,
  ) {
    final registry = ToolRegistry();
    if (enabledTools.contains('calculator')) {
      registry.register(CalculatorTool());
    }
    if (enabledTools.contains('get_time')) registry.register(GetTimeTool());
    if (enabledTools.contains('json_query')) registry.register(JsonQueryTool());
    if (enabledTools.contains('http_request')) {
      registry.register(HttpRequestTool());
    }
    if (enabledTools.contains('web_search')) {
      registry.register(WebSearchTool(apiKey: tavilyKey));
    }
    if (enabledTools.contains('generate_image')) {
      registry.register(ImageGenTool(config: config));
    }

    // 记忆写入：回调懒加载 DB，写入"手动来源"记忆。
    registry.register(RememberTool(onRemember: _onRemember));
    // 子 Agent：复用 HeadlessExecutor 无 UI 执行，safe 工具才放行。
    // 风险由自主委派开关决定：开启 → safe（自动放行），关闭 → requiresConfirmation（走审批）。
    registry.register(SubAgentTool(onRun: _runSubAgent, risk: subAgentRisk));
    // 计划模式：模型首轮调用 manage_plan 后由回调更新 planState。
    registry.register(ManagePlanTool(onPlanUpdated: _onPlanUpdated));

    final wsPath = state.currentWorkspacePath;
    if (wsPath != null && wsPath.isNotEmpty) {
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
        if (registry.find(tool.manifest.name) == null) {
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
    final config = await store.load();
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
    final registry =
        _buildRegistry(enabledTools, tavilyKey, config, subAgentRisk);
    await _mergeMcpTools(registry);
    await _mergePluginTools(registry);
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
    final runGeneration = ++_runGeneration;
    _cancelledRunGenerations.remove(runGeneration);

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
      final isTextAttachment = const {'txt', 'md', 'csv', 'json', 'pdf'}
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
      if (content.isEmpty && file.extension == 'pdf') {
        parts.add(MessagePart.text('\n\nPDF 文件 ${file.name} 未提取到可用文本'));
        continue;
      }
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
      conversationTitle: newTitle,
      toolActivities: const [],
      activityLog: const [],
      liveContextTokens: initialContextTokens,
      clearLiveReply: true,
    );

    // 持久化失败不阻断对话：吞掉异常，后续 _runAgent 内的兜底 catch 会恢复 running 状态。
    try {
      final database = await ref.read(databaseProvider.future);
      if (!_ownsRun(runGeneration, conversationId)) return;
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
      if (!_ownsRun(runGeneration, conversationId)) return;
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

      if (!_ownsRun(runGeneration, conversationId)) return;
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
      if (_ownsRun(runGeneration, conversationId)) {
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
    final runGeneration = ++_runGeneration;
    _cancelledRunGenerations.remove(runGeneration);
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
      toolActivities: const [],
      activityLog: const [],
      clearLiveReply: true,
    );

    final prep = await _prepareRun(database);
    if (!_ownsRun(runGeneration, conversationId)) return;
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
    final runGeneration = ++_runGeneration;
    _cancelledRunGenerations.remove(runGeneration);
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

    if (!_ownsRun(runGeneration, conversationId)) return;

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
      toolActivities: const [],
      activityLog: const [],
      clearLiveReply: true,
    );

    final prep = await _prepareRun(database);
    if (!_ownsRun(runGeneration, conversationId)) return;
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
    try {
      database = await ref.read(databaseProvider.future);
      final db = database!;
      task = await db.findTask(taskId);
      if (task == null) return;
      final taskData = task;
      _invalidateActiveRun();
      final linkedConversation = taskData.conversationId.isEmpty
          ? null
          : await db.findConversation(taskData.conversationId);
      if (linkedConversation != null) {
        await switchConversation(linkedConversation);
        uiConversationId = linkedConversation.id;
      }

      runGeneration = ++_runGeneration;
      _cancelledRunGenerations.remove(runGeneration);
      final runApprovalMode = state.approvalMode;
      if (uiConversationId != null) {
        state = state.copyWith(
          running: true,
          toolActivities: const [],
          activityLog: const [],
          clearPlanState: true,
          clearLiveReply: true,
        );
      }
      bool ownsRun() =>
          runGeneration == _runGeneration &&
          !_cancelledRunGenerations.contains(runGeneration) &&
          (uiConversationId == null ||
              state.conversationId == uiConversationId);
      cancellationToken = AgentCancellationToken();
      _cancellationToken = cancellationToken;
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

      final result = await HeadlessExecutor.runDetailed(
        db: db,
        config: config,
        prompt: request['prompt']?.toString() ?? '',
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
      await TaskService().complete(
        db,
        taskId,
        status: taskStatus,
        summary: resultText.isNotEmpty
            ? resultText
            : (result.error ?? 'Agent 执行未返回内容'),
      );

      if (ownsRun()) {
        state = state.copyWith(running: false, clearLiveReply: true);
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
          runGeneration == _runGeneration &&
          !_cancelledRunGenerations.contains(runGeneration) &&
          (uiConversationId == null ||
              state.conversationId == uiConversationId)) {
        state = state.copyWith(running: false, clearLiveReply: true);
      }
    } finally {
      if (cancellationToken != null &&
          identical(_cancellationToken, cancellationToken)) {
        _cancellationToken = null;
      }
      if (runGeneration != 0) {
        _cancelledRunGenerations.remove(runGeneration);
      }
    }
  }

  /// 预算暂停后从保存的 Agent 上下文续跑，而不是重新提交原始 prompt。
  Future<void> resumeFromBudgetPause({
    required Future<ToolApproval> Function(ToolCall call, ToolRisk risk)
        approveTool,
  }) async {
    final context = _lastBudgetPauseContext;
    if (context == null || context.isEmpty || state.running || state.loading) {
      return;
    }
    final database = await ref.read(databaseProvider.future);
    final conversationId = state.conversationId;
    final runGeneration = ++_runGeneration;
    _cancelledRunGenerations.remove(runGeneration);
    // 追加一个助手占位消息承载续跑输出；实际模型输入用保存的上下文。
    final assistantIndex = state.messages.length;
    state = state.copyWith(
      messages: [
        ...state.messages,
        ChatMessage(
            role: MessageRole.assistant, parts: const [MessagePart.text('')]),
      ],
      running: true,
      toolActivities: const [],
      activityLog: const [],
      clearLiveReply: true,
    );
    try {
      final prep = await _prepareRun(database);
      if (!_ownsRun(runGeneration, conversationId)) return;
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
      if (_ownsRun(runGeneration, conversationId)) {
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
    if (generation == null || generation != _runGeneration) return;
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
  }

  void respondToPlan(bool approved) {
    final completer = _planCompleter;
    _planCompleter = null;
    state = state.copyWith(
        planState: state.planState
            ?.copyWith(status: approved ? 'executing' : 'cancelled'),
        activityLog: [
          ...state.activityLog,
          approved ? '计划已确认，正在继续执行' : '计划已取消',
        ]);
    if (completer != null && !completer.isCompleted) {
      completer.complete(approved);
    }
  }

  Future<bool> _confirmPlan(List<ToolCall> calls, String planText) async {
    final generation = _activePlanGeneration;
    if (generation == null || generation != _runGeneration) return false;
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

  bool _ownsRun(int generation, String? conversationId) =>
      generation == _runGeneration &&
      state.conversationId == conversationId &&
      !_cancelledRunGenerations.contains(generation);

  void _invalidateActiveRun() {
    final generation = _runGeneration;
    _cancelledRunGenerations.add(generation);
    _lastBudgetPauseContext = null;
    _runGeneration++;
    _cancellationToken?.cancel();
    _dioCancelToken?.cancel();
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

  Future<void> _runAgent(
    int assistantIndex,
    String model,
    ProviderConfig config,
    ToolRegistry registry,
    int maxSteps,
    double temperature,
    int maxTokens,
    double topP,
    ReasoningEffort reasoningEffort,
    Future<ToolApproval> Function(ToolCall call, ToolRisk risk) approveTool,
    String? taskId,
    int runGeneration,
    String? runConversationId, {
    /// 预算暂停后从断点续跑时传入的 Agent 内部上下文；为空则沿用会话消息。
    List<ChatMessage>? resumeContext,
  }) async {
    if (!_ownsRun(runGeneration, runConversationId)) return;
    _activePlanGeneration = runGeneration;
    final runHistory = resumeContext ??
        List<ChatMessage>.of(state.messages.take(assistantIndex));
    final runPlanMode = state.planMode;
    final runApprovalMode = state.approvalMode;
    final runSystemPrompt = state.systemPrompt;
    bool ownsRun() => _ownsRun(runGeneration, runConversationId);
    final runId = 'run-${DateTime.now().microsecondsSinceEpoch}';
    final logService = ref.read(logServiceProvider);
    final runStartedAt = DateTime.now();
    var eventSequence = 0;
    var runStatus = 'running';
    var retryCount = 0;
    RunEventTracker? tracker;
    try {
      final database = await ref.read(databaseProvider.future);
      await database.insertRunRecord(RunRecordsCompanion.insert(
        runId: runId,
        conversationId: runConversationId ?? 'unknown',
        model: Value(model),
        status: const Value('running'),
        startedAt: runStartedAt,
      ));
      tracker = RunEventTracker(database: database, runId: runId);
    } catch (_) {}
    RunEventHandle? modelEvent;
    final toolEvents = <String, RunEventHandle?>{};
    RunEventHandle? activeNetworkEvent;
    var networkSequence = 0;
    void syncEventCount() {
      final currentTracker = tracker;
      if (currentTracker != null) eventSequence = currentTracker.nextSequence;
    }

    Future<void> recordRunEvent({
      required String type,
      required String name,
      required String status,
      String? outputSummary,
      Map<String, dynamic>? metadata,
    }) async {
      final currentTracker = tracker;
      if (currentTracker == null) return;
      if (type == 'model_request' && status == 'started') {
        modelEvent = await currentTracker.start(
            type: type, name: name, metadata: metadata);
      } else if (type == 'tool_call' && outputSummary != null) {
        // Tool calls are started on ToolRequestedEvent and completed on
        // ToolResultEvent so their duration covers the actual execution.
        return;
      } else {
        await currentTracker.record(
          type: type,
          name: name,
          status: status,
          outputSummary: outputSummary,
          metadata: metadata,
        );
      }
      eventSequence = currentTracker.nextSequence;
    }

    await logService.info('Agent 开始执行',
        runId: runId, category: 'system', detail: {'model': model});
    final provider =
        config.isConfigured ? _buildProvider(config) : DemoProvider();
    final executor = AgentExecutor(provider: provider, tools: registry);
    final cancellationToken = AgentCancellationToken();
    final dioCancelToken = CancelToken();
    _cancellationToken = cancellationToken;
    _dioCancelToken = dioCancelToken;
    final answer = StringBuffer();
    final reasoning = StringBuffer();
    var usage = const Usage();
    int? estimatedCostCents;
    int? savedCostCents;
    final stopwatch = Stopwatch()..start();
    Duration? ttft;
    int? firstTokenDurationMs;
    DateTime? firstOutputAt;
    DateTime? lastOutputAt;
    var maxStallDurationMs = 0;
    var stallCount = 0;
    // 流式节流：文本和 reasoning 共用一个刷新调度器，避免推理模型的
    // reasoning 增量绕过节流、频繁重建整个消息列表。
    const flushInterval = Duration(milliseconds: 70);
    const flushMinUnits = 24;
    const contextEstimateInterval = Duration(milliseconds: 250);
    var lastFlush = DateTime.now();
    var lastFlushedUnits = 0;
    var lastContextEstimate = DateTime.fromMillisecondsSinceEpoch(0);
    Timer? flushTimer;

    void flushAnswer({bool force = false}) {
      if (!ownsRun() || assistantIndex >= state.messages.length) return;
      final now = DateTime.now();
      lastFlush = now;
      lastFlushedUnits = answer.length + reasoning.length;
      final message = ChatMessage(
        role: MessageRole.assistant,
        parts: [MessagePart.text(answer.toString())],
        reasoning: reasoning.isEmpty ? null : reasoning.toString(),
      );
      final liveReply = LiveReply(
        messageIndex: assistantIndex,
        text: answer.toString(),
        reasoning: reasoning.isEmpty ? null : reasoning.toString(),
      );
      final estimateContext = force ||
          now.difference(lastContextEstimate) >= contextEstimateInterval;
      if (estimateContext) lastContextEstimate = now;
      state = state.copyWith(
        liveReply: liveReply,
        liveContextTokens: estimateContext
            ? _estimateLiveContextTokens(assistantIndex, message)
            : state.liveContextTokens,
      );
    }

    void requestFlush({bool force = false}) {
      if (!ownsRun()) return;
      final now = DateTime.now();
      final elapsed = now.difference(lastFlush);
      final pendingUnits = answer.length + reasoning.length - lastFlushedUnits;
      if (force ||
          (elapsed >= flushInterval && pendingUnits >= flushMinUnits)) {
        flushTimer?.cancel();
        flushTimer = null;
        flushAnswer(force: force);
        return;
      }
      if (flushTimer != null) return;
      final remaining =
          elapsed >= flushInterval ? Duration.zero : flushInterval - elapsed;
      flushTimer = Timer(remaining, () {
        flushTimer = null;
        if (ownsRun() && answer.length + reasoning.length > lastFlushedUnits) {
          flushAnswer();
        }
      });
    }

    // 注入长期记忆与知识库片段，让交互式聊天也能享受记忆/RAG 能力（与
    // HeadlessExecutor 的后台路径保持一致）。注入失败不阻断执行。
    String baseSystemPrompt = runSystemPrompt;
    try {
      final database = await ref.read(databaseProvider.future);
      final memoryBlock = await MemoryService().buildInjectionBlock(database);
      if (memoryBlock.isNotEmpty) {
        baseSystemPrompt = '$memoryBlock\n$baseSystemPrompt';
      }
      final userQuery = _lastUserText(assistantIndex);
      final knowledgeBlock =
          await KnowledgeService().buildInjectionBlock(database, userQuery);
      if (knowledgeBlock.isNotEmpty) {
        baseSystemPrompt = '$knowledgeBlock\n$baseSystemPrompt';
      }
      final skillBlock = await SkillStore().buildInjectionBlock(database);
      if (skillBlock.isNotEmpty) {
        baseSystemPrompt = '$skillBlock\n$baseSystemPrompt';
      }
    } catch (_) {}

    // 委派规则：向主 Agent 注入使用 sub_agent 的边界与预算约束。
    try {
      final autonomousDelegation =
          await AutonomousDelegationService().isEnabled();
      baseSystemPrompt =
          '$baseSystemPrompt\n\n${_delegationRules(autonomousDelegation)}';
    } catch (_) {}

    try {
      final trustStore = await ref.read(toolTrustStoreProvider.future);
      await for (final event in executor.run(
        history: runHistory,
        model: model,
        confirmPlan: runPlanMode ? _confirmPlan : null,
        approveTool: approveTool,
        approvalMode: runApprovalMode,
        isToolTrusted: trustStore.isTrusted,
        systemPrompt: runPlanMode
            ? '$baseSystemPrompt\n\n[计划模式] 你的首个回复必须调用 manage_plan 工具来生成详细的 JSON 分步执行计划。在用户确认计划之前，不要调用其他工具。'
            : baseSystemPrompt,
        capabilities: ModelCapabilities.infer(model),
        maxSteps: maxSteps,
        temperature: temperature,
        maxTokens: maxTokens,
        topP: topP,
        reasoningEffort: reasoningEffort,
        contextBudgetTokens: config.contextTokens,
        cancellationToken: cancellationToken,
        cancelToken: dioCancelToken,
      )) {
        if (event is AgentStatusEvent &&
            event.status == RunStatus.waitingModel) {
          await tracker?.finish(modelEvent, status: 'success');
          modelEvent = await tracker?.start(
            type: 'model_request',
            name: '模型请求',
            metadata: {'attempt': networkSequence + 1},
          );
          networkSequence++;
          activeNetworkEvent = await tracker?.start(
            type: 'network',
            name: '模型网络请求',
            metadata: {'attempt': networkSequence},
          );
          syncEventCount();
        } else if (event is TextEvent) {
          final firstTokenElapsed = stopwatch.elapsed;
          ttft ??= firstTokenElapsed;
          firstTokenDurationMs ??= firstTokenElapsed.inMilliseconds;
          final now = DateTime.now();
          firstOutputAt ??= now;
          if (lastOutputAt != null) {
            final stallMs = now.difference(lastOutputAt).inMilliseconds;
            if (stallMs > 300) {
              stallCount++;
              maxStallDurationMs = math.max(maxStallDurationMs, stallMs);
            }
          }
          lastOutputAt = now;
          answer.write(event.text);
          requestFlush();
        } else if (event is ReasoningEvent) {
          final firstTokenElapsed = stopwatch.elapsed;
          ttft ??= firstTokenElapsed;
          firstTokenDurationMs ??= firstTokenElapsed.inMilliseconds;
          final now = DateTime.now();
          firstOutputAt ??= now;
          if (lastOutputAt != null) {
            final stallMs = now.difference(lastOutputAt).inMilliseconds;
            if (stallMs > 300) {
              stallCount++;
              maxStallDurationMs = math.max(maxStallDurationMs, stallMs);
            }
          }
          lastOutputAt = now;
          reasoning.write(event.text);
          requestFlush();
        } else if (event is AgentUsageEvent) {
          usage = Usage(
              promptTokens: event.promptTokens,
              completionTokens: event.completionTokens,
              cachedTokens: event.cachedTokens);
          if (ownsRun() && assistantIndex < state.messages.length) {
            final current = state.messages[assistantIndex];
            state = _withMessageAt(
              state,
              assistantIndex,
              current.copyWith(usage: usage),
            ).copyWith(
                liveContextTokens: usage.promptTokens + usage.completionTokens);
          }
          final estimate = _estimateUsageCost(model, usage);
          estimatedCostCents = estimate.costCents;
          savedCostCents = estimate.savedCostCents;
        } else if (event is AgentErrorEvent) {
          runStatus = 'failed';
          await tracker?.finish(activeNetworkEvent,
              status: 'failed', outputSummary: event.message);
          await tracker?.finish(modelEvent,
              status: 'failed', outputSummary: event.message);
          activeNetworkEvent = null;
          modelEvent = null;
          for (final handle in toolEvents.values) {
            await tracker?.finish(handle,
                status: 'failed', outputSummary: event.message);
          }
          toolEvents.clear();
          answer.write('\n\n${formatErrorForMessage(event.message)}');
          await recordRunEvent(
              type: 'error',
              name: 'Agent 错误',
              status: 'failed',
              outputSummary: event.message);
          await logService.error('Agent 执行失败',
              runId: runId,
              category: 'model',
              errorCode: 'AGENT_EXECUTION_FAILED',
              retryable: true,
              detail: {'message': event.message});
        } else if (event is AgentBudgetExhaustedEvent) {
          // 达到 maxSteps：可恢复的预算暂停，不是失败。保存续跑上下文与原因。
          runStatus = 'paused';
          _lastBudgetPauseContext = List<ChatMessage>.of(event.context);
          await tracker?.finish(activeNetworkEvent,
              status: 'success', outputSummary: event.message);
          await tracker?.finish(modelEvent,
              status: 'success', outputSummary: event.message);
          activeNetworkEvent = null;
          modelEvent = null;
          answer.write('\n\n${formatErrorForMessage(event.message)}');
          await recordRunEvent(
              type: 'budget',
              name: '执行预算已耗尽',
              status: 'paused',
              outputSummary: event.message,
              metadata: {'maxSteps': event.maxSteps});
          await logService.warning('Agent 达到执行步数预算，已暂停可续跑',
              runId: runId,
              category: 'budget',
              detail: {'maxSteps': event.maxSteps});
        } else if (event is AgentRetryEvent) {
          retryCount = event.attempt;
          await tracker?.finish(activeNetworkEvent,
              status: 'failed', metadata: {'attempt': event.attempt});
          await tracker?.finish(modelEvent,
              status: 'failed', metadata: {'attempt': event.attempt});
          activeNetworkEvent = null;
          modelEvent = null;
          networkSequence++;
          modelEvent = await tracker?.start(
            type: 'model_request',
            name: '模型请求重试',
            metadata: {'attempt': event.attempt + 1},
          );
          activeNetworkEvent = await tracker?.start(
            type: 'network',
            name: '模型网络请求重试',
            metadata: {'attempt': event.attempt + 1},
          );
          syncEventCount();
          await logService.warning('模型请求将重试',
              runId: runId,
              category: 'network',
              detail: {'attempt': event.attempt});
        } else if (event is ToolRequestedEvent) {
          if (!ownsRun()) continue;
          final risk = _riskFor(registry, event.call.name);
          // The provider response is complete once tool calls are emitted;
          // keep network latency separate from the tool execution duration.
          await tracker?.finish(activeNetworkEvent, status: 'success');
          await tracker?.finish(modelEvent, status: 'success');
          activeNetworkEvent = null;
          modelEvent = null;
          toolEvents[event.call.id] = await tracker?.start(
            type: _isFileOperationTool(event.call.name)
                ? 'file_operation'
                : 'tool_call',
            name: event.call.name,
            inputSummary: jsonEncode(event.call.arguments),
            metadata: {
              'tool': event.call.name,
              'path': event.call.arguments['path'],
              if (event.call.arguments['newPath'] != null)
                'newPath': event.call.arguments['newPath'],
            },
          );
          syncEventCount();
          if (ownsRun()) await _persistToolCall(event.call, risk);
          if (!ownsRun()) continue;
          state = state.copyWith(
            activityLog: [...state.activityLog, '等待确认'],
            toolActivities: [
              ...state.toolActivities,
              ToolActivity(call: event.call, risk: risk)
            ],
          );
        } else if (event is AgentStatusEvent &&
            event.status == RunStatus.executingTool) {
          if (!ownsRun()) continue;
          if (state.toolActivities.isEmpty ||
              state.toolActivities.last.call.name != 'manage_plan') {
            _updatePlanStepStatus('running');
          }
          state = state.copyWith(
            activityLog: [...state.activityLog, '等待确认'],
            toolActivities:
                _updateLastToolActivity(state.toolActivities, status: '执行中'),
          );
        } else if (event is ApprovalRequiredEvent) {
          if (!ownsRun()) continue;
          state = state.copyWith(
            activityLog: [...state.activityLog, '等待确认'],
            toolActivities: _updateToolActivity(
                state.toolActivities, event.call.id,
                status: '等待确认'),
          );
          if (taskId != null) {
            final taskDb = await ref.read(databaseProvider.future);
            await TaskService()
                .updateStatus(taskDb, taskId, 'waiting_approval');
          }
          await NotificationService.instance.init();
          await NotificationService.instance.show(
            id: event.call.id.hashCode & 0x7fffffff,
            title: '开发任务等待审批',
            body: '需要确认工具：${event.call.name}',
            payload: 'conversation:${state.conversationId ?? ''}',
          );
        } else if (event is ToolResultEvent) {
          if (!ownsRun()) continue;
          if (taskId != null) {
            final taskDb = await ref.read(databaseProvider.future);
            await TaskService().updateStatus(taskDb, taskId, 'running');
          }
          final toolFailed = _isToolFailureResult(event.result);
          await tracker?.finish(
            toolEvents.remove(event.call.id),
            status: toolFailed ? 'failed' : 'success',
            outputSummary: event.result,
            metadata: event.metadata,
          );
          await recordRunEvent(
              type: 'tool_call',
              name: event.call.name,
              status: toolFailed ? 'failed' : 'success',
              outputSummary: event.result,
              metadata: {
                ...event.metadata,
                'fileOperation': _isFileOperationTool(event.call.name),
                if (event.call.arguments['path'] != null)
                  'path': event.call.arguments['path'],
                if (_isFileOperationTool(event.call.name) &&
                    !event.metadata.containsKey('operation'))
                  'operation': event.call.name,
              });
          await logService
              .info('工具执行完成', runId: runId, category: 'tool', detail: {
            'tool': event.call.name,
            'success': !toolFailed,
          });
          if (event.call.name != 'manage_plan') {
            _updatePlanStepStatus(toolFailed ? 'failed' : 'completed');
          }
          if (ownsRun()) {
            await _persistMessage(ChatMessage(
                role: MessageRole.tool,
                toolCallId: event.call.id,
                parts: [MessagePart.text(event.result)]));
          }
          state = state.copyWith(
            toolActivities: _updateToolActivity(
              state.toolActivities,
              event.call.id,
              status: toolFailed ? '执行失败' : '已完成',
              result: event.result,
            ),
          );
        }
        if (event is AgentStatusEvent) {
          if (event.status == RunStatus.cancelled) {
            runStatus = 'cancelled';
            await tracker?.finish(activeNetworkEvent, status: 'cancelled');
            await tracker?.finish(modelEvent, status: 'cancelled');
            activeNetworkEvent = null;
            modelEvent = null;
            for (final handle in toolEvents.values) {
              await tracker?.finish(handle, status: 'cancelled');
            }
            toolEvents.clear();
          }
          if (event.status == RunStatus.completed) {
            runStatus = 'success';
            final usageMetadata = {
              'promptTokens': usage.promptTokens,
              'completionTokens': usage.completionTokens,
              'cachedTokens': usage.cachedTokens,
              'cacheHit': usage.cachedTokens > 0,
              'cacheSource': usage.cachedTokens > 0 ? 'provider-usage' : null,
              'savedTokens': usage.cachedTokens,
              'savedCostCents': savedCostCents,
              'estimatedCostCents': estimatedCostCents,
            };
            await tracker?.finish(activeNetworkEvent,
                status: 'success', metadata: usageMetadata);
            await tracker?.finish(modelEvent,
                status: 'success', metadata: usageMetadata);
            activeNetworkEvent = null;
            modelEvent = null;
          }
        }
      }
    } catch (error) {
      // 兜底：任何未预期异常（DB 写入失败、附件解析、审批回调等）都不能让
      // UI 永久停留在"运行中"。写入错误信息并恢复可交互状态。
      runStatus = 'failed';
      await tracker?.finish(activeNetworkEvent,
          status: 'failed', outputSummary: error.toString());
      await tracker?.finish(modelEvent,
          status: 'failed', outputSummary: error.toString());
      for (final handle in toolEvents.values) {
        await tracker?.finish(handle,
            status: 'failed', outputSummary: error.toString());
      }
      activeNetworkEvent = null;
      modelEvent = null;
      toolEvents.clear();
      answer.write('\n\n${formatErrorForMessage(error.toString())}');
      await logService.error('Agent 未预期异常',
          runId: runId,
          category: 'system',
          errorCode: 'AGENT_UNEXPECTED_ERROR',
          error: error,
          stackTrace: StackTrace.current);
    } finally {
      flushTimer?.cancel();
      flushTimer = null;
      stopwatch.stop();
      try {
        final runDb = await ref.read(databaseProvider.future);
        if (_cancelledRunGenerations.contains(runGeneration)) {
          runStatus = 'cancelled';
        }
        if (runStatus == 'running') runStatus = 'failed';
        if (activeNetworkEvent != null) {
          await tracker?.finish(activeNetworkEvent,
              status: runStatus == 'cancelled' ? 'cancelled' : 'failed');
          activeNetworkEvent = null;
        }
        if (modelEvent != null) {
          await tracker?.finish(modelEvent,
              status: runStatus == 'cancelled' ? 'cancelled' : 'failed');
          modelEvent = null;
        }
        if (toolEvents.isNotEmpty) {
          final status = runStatus == 'cancelled' ? 'cancelled' : 'failed';
          for (final handle in toolEvents.values) {
            await tracker?.finish(handle, status: status);
          }
          toolEvents.clear();
        }
        // Event/log writes are queued so streaming stays responsive. Make the
        // run completion the durability boundary before reading/uploading.
        await tracker?.flush();
        await logService.flush();
        final cancelDurationMs =
            runStatus == 'cancelled' && _cancelRequestedAt != null
                ? DateTime.now().difference(_cancelRequestedAt!).inMilliseconds
                : null;
        final outputRateMilli =
            usage.completionTokens > 0 && firstOutputAt != null
                ? (usage.completionTokens *
                        1000000 /
                        math.max(
                            1,
                            DateTime.now()
                                .difference(firstOutputAt)
                                .inMilliseconds))
                    .round()
                : null;
        await runDb.updateRunRecord(
            runId,
            RunRecordsCompanion(
              status: Value(runStatus),
              endedAt: Value(DateTime.now()),
              inputTokens: Value(usage.promptTokens),
              outputTokens: Value(usage.completionTokens),
              cachedTokens: Value(usage.cachedTokens),
              estimatedCostCents: Value(estimatedCostCents),
              eventCount: Value(eventSequence),
              totalDurationMs: Value(stopwatch.elapsedMilliseconds),
              retryCount: Value(retryCount),
              firstTokenDurationMs: Value(firstTokenDurationMs),
              outputRateMilli: Value(outputRateMilli),
              maxStallDurationMs: Value(maxStallDurationMs),
              stallCount: Value(stallCount),
              cancelDurationMs: Value(cancelDurationMs),
            ));
        final session = await ref.read(accountServiceProvider).restoreSession();
        if (session != null && eventSequence > 0) {
          final events = await runDb.eventsForRun(runId);
          final payload = events
              .map((event) => {
                    'event_id': event.eventId,
                    'sequence': event.sequenceNo,
                    'type': event.type,
                    'status': event.status,
                    'name': event.name,
                    'started_at': event.startedAt.toIso8601String(),
                    'ended_at': event.endedAt?.toIso8601String(),
                    'duration_ms': event.durationMs,
                    'metadata': jsonDecode(event.metadataJson),
                  })
              .toList();
          final queue = RunEventQueue();
          await queue.flush(
              api: ref.read(billingApiProvider), access: session.access);
          try {
            await ref.read(billingApiProvider).uploadRunEvents(
                access: session.access,
                runId: runId,
                conversationId: runConversationId,
                events: payload);
          } catch (_) {
            await queue.enqueue(
                runId: runId,
                conversationId: runConversationId,
                events: payload);
          }
        }
        await runDb.pruneRunRecords();
      } catch (_) {}
    }
    final assistantMessage = ChatMessage(
      role: MessageRole.assistant,
      parts: [MessagePart.text(answer.toString())],
      reasoning: reasoning.isEmpty ? null : reasoning.toString(),
      modelName: config.isConfigured ? config.model : '演示模型',
      usage: usage.totalTokens > 0 ? usage : null,
      elapsed: stopwatch.elapsed,
      ttft: ttft,
    );
    final runCancelled = _cancelledRunGenerations.contains(runGeneration) ||
        runStatus == 'cancelled';
    if (ownsRun()) {
      if (assistantIndex < state.messages.length) {
        state =
            _withMessageAt(state, assistantIndex, assistantMessage).copyWith(
          running: false,
          clearLiveReply: true,
          liveContextTokens: usage.totalTokens > 0
              ? usage.totalTokens
              : _estimateLiveContextTokens(assistantIndex, assistantMessage),
        );
      } else {
        state = state.copyWith(running: false, clearLiveReply: true);
      }
      final plan = state.planState;
      if (plan != null && plan.status == 'executing') {
        state = state.copyWith(
          planState: plan.copyWith(
            status: runStatus == 'success'
                ? 'completed'
                : (runCancelled
                    ? 'cancelled'
                    : (runStatus == 'paused' ? 'paused' : 'failed')),
          ),
        );
      }
      try {
        await _persistMessage(assistantMessage);
      } catch (_) {
        // 持久化失败不阻断 UI 恢复。
      }
    }
    if (taskId != null) {
      try {
        final taskDb = await ref.read(databaseProvider.future);
        final taskService = TaskService();
        final status = runCancelled
            ? 'cancelled'
            : runStatus == 'success'
                ? 'completed'
                : runStatus == 'paused'
                    ? 'paused'
                    : 'failed';
        await taskService.complete(
          taskDb,
          taskId,
          status: status,
          summary: answer.toString(),
          runId: runId,
        );
        await NotificationService.instance.init();
        await NotificationService.instance.show(
          id: taskId.hashCode & 0x7fffffff,
          title: status == 'completed'
              ? '开发任务已完成'
              : (status == 'paused' ? '开发任务已暂停' : '开发任务未完成'),
          body: _notificationPreview(answer.toString(), status),
          payload: 'task:$taskId',
        );
      } catch (_) {}
    }
    if (_activePlanGeneration == runGeneration) {
      _activePlanGeneration = null;
    }
    if (identical(_cancellationToken, cancellationToken)) {
      _cancellationToken = null;
    }
    if (identical(_dioCancelToken, dioCancelToken)) {
      _dioCancelToken = null;
    }
    _cancelledRunGenerations.remove(runGeneration);
    _cancelRequestedAt = null;
    // 完成或取消后清除续跑上下文，避免残留一个旧的暂停快照。
    if (runStatus == 'success' || runStatus == 'cancelled') {
      _lastBudgetPauseContext = null;
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
      String model, Usage usage) {
    const rates = <String, (int, int)>{
      'gpt-4o-mini': (2, 9),
      'gpt-4o': (35, 140),
      'claude-sonnet-4-5': (45, 190),
      'deepseek-chat': (3, 11),
      'deepseek-reasoner': (6, 22),
    };
    final rate = rates[model];
    if (rate == null || usage.totalTokens == 0) {
      return (costCents: null, savedCostCents: null);
    }
    final cachedRate = rate.$1 / 10;
    final freshInput =
        (usage.promptTokens - usage.cachedTokens).clamp(0, 1 << 30);
    final cost = ((freshInput * rate.$1 +
                usage.cachedTokens * cachedRate +
                usage.completionTokens * rate.$2) /
            1000000)
        .ceil();
    final saved =
        ((usage.cachedTokens * (rate.$1 - cachedRate)) / 1000000).ceil();
    return (costCents: cost, savedCostCents: saved);
  }

  void stop() {
    _commitLiveReply();
    _cancelRequestedAt = DateTime.now();
    _invalidateActiveRun();
    // 真正中断底层 HTTP 流（Dio 层），避免连接与带宽继续被占用。
    _dioCancelToken?.cancel();
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

  // --- 浼氳瘽 / Agent / Provider 操作 ---

  Future<void> newConversation() async {
    _invalidateActiveRun();
    final newGeneration = _runGeneration;
    final database = await ref.read(databaseProvider.future);
    final conversation = await _createConversation(database);
    if (newGeneration != _runGeneration) return;
    state = state.copyWith(
      conversationId: conversation.id,
      conversationTitle: conversation.title,
      messages: const [],
      toolActivities: const [],
      activityLog: const [],
      liveContextTokens: 0,
      clearPlanState: true,
      clearLiveReply: true,
    );
  }

  Future<void> switchConversation(Conversation conversation) async {
    _invalidateActiveRun();
    final switchGeneration = _runGeneration;
    final database = await ref.read(databaseProvider.future);
    final stored = await database.messagesFor(conversation.id);
    if (switchGeneration != _runGeneration) return;
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
    if (switchGeneration != _runGeneration) return;
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
      clearAgentId: agentId == null,
      clearPlanState: true,
      clearLiveReply: true,
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

  // --- 鐘舵€佽緟'---

  ToolRisk _riskFor(ToolRegistry registry, String name) =>
      registry.find(name)?.manifest.risk ?? ToolRisk.safe;

  bool _isFileOperationTool(String name) =>
      name.endsWith('_file') ||
      const {'list_directory', 'search_files'}.contains(name);

  bool _isToolFailureResult(String result) =>
      RegExp(r'(失败|failed|error)', caseSensitive: false).hasMatch(result);

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
      List<ToolActivity> activities, String callId,
      {String? status, String? result}) {
    return activities
        .map((a) => a.call.id == callId
            ? a.copyWith(status: status, result: result)
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
