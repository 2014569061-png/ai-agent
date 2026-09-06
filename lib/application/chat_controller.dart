import 'dart:convert';
import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mojibake_repair.dart';

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
import 'error_humanizer.dart';
import 'headless_executor.dart';
import 'knowledge_service.dart';
import 'memory_service.dart';
import 'providers.dart';
import 'task_service.dart';
import 'workspace_service.dart';
import '../infrastructure/plugins/plugin_store.dart';
import '../infrastructure/skills/skill_store.dart';

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
    this.activeReasoningEffort = ReasoningEffort.medium,
    this.providerConfigured = false,
    this.planMode = false,
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
  final ReasoningEffort activeReasoningEffort;
  final bool providerConfigured;
  final bool planMode;
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
    ReasoningEffort? activeReasoningEffort,
    bool? providerConfigured,
    bool? planMode,
    PlanState? planState,
    String? currentWorkspacePath,
    bool clearWorkspace = false,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        running: running ?? this.running,
        loading: loading ?? this.loading,
        conversationId: conversationId ?? this.conversationId,
        conversationTitle: conversationTitle ?? this.conversationTitle,
        agentName: agentName ?? this.agentName,
        systemPrompt: systemPrompt ?? this.systemPrompt,
        agentId: agentId ?? this.agentId,
        toolActivities: toolActivities ?? this.toolActivities,
        activityLog: activityLog ?? this.activityLog,
        activeModel: activeModel ?? this.activeModel,
        activeProviderName: activeProviderName ?? this.activeProviderName,
        activeProviderId: activeProviderId ?? this.activeProviderId,
        contextTokens: contextTokens ?? this.contextTokens,
        activeReasoningEffort:
            activeReasoningEffort ?? this.activeReasoningEffort,
        providerConfigured: providerConfigured ?? this.providerConfigured,
        planMode: planMode ?? this.planMode,
        planState: planState ?? this.planState,
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
  String _contentForPersist(ChatMessage message) =>
      message.parts.map((part) {
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
    registry.register(SubAgentTool(onRun: _runSubAgent));
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
          })>
      _prepareRun(AppDatabase database) async {
    final store = ref.read(providerConfigStoreProvider);
    final config = await store.load();
    final tavilyKey = await store.readToolKey('tavily');
    var enabledTools = <String>{'calculator', 'get_time', 'json_query'};
    var maxSteps = 8;
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
    final registry = _buildRegistry(enabledTools, tavilyKey, config);
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

  Future<void> send({
    required String text,
    required List<PlatformFile> attachments,
    required Future<ToolApproval> Function(ToolCall call, ToolRisk risk)
        approveTool,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.running || state.loading) return;

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
      if (bytes != null && mime != null) {
        parts.add(MessagePart.image('data:$mime;base64,${base64Encode(bytes)}',
            mimeType: mime));
      } else if (bytes != null &&
          (file.extension == 'txt' ||
              file.extension == 'md' ||
              file.extension == 'csv' ||
              file.extension == 'json' ||
              file.extension == 'pdf')) {
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
      } else {
        parts.add(MessagePart.text('\n\n附件 ${file.name} 类型暂不支持，已跳过'));
      }
    }

    final userMessage = ChatMessage(role: MessageRole.user, parts: parts);
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
            role: MessageRole.assistant, parts: [const MessagePart.text('')])
      ],
      running: true,
      conversationTitle: newTitle,
      toolActivities: const [],
      activityLog: const [],
    );

    // 持久化失败不阻断对话：吞掉异常，后续 _runAgent 内的兜底 catch 会恢复 running 状态。
    final database = await ref.read(databaseProvider.future);
    final conversationId = state.conversationId;
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
    _wasCancelled = false;
    // C2 断点恢复：注册一个"运行中"任务，App 被杀后可在启动时提示继续执行。
    String? runningTaskId;
    try {
      final task = await TaskService().create(
        db: database,
        conversationId: conversationId ?? '',
        requestJson: jsonEncode({
          'prompt': trimmed,
          'conversationId': conversationId,
          'model': prep.model,
          'maxSteps': prep.maxSteps,
        }),
      );
      runningTaskId = task.id;
    } catch (_) {} // 任务登记失败不阻断执行。

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
        runningTaskId);
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
    if (conversationId != null) {
      await database.deleteTrailingAssistantAndTool(conversationId);
    }
    final assistantIndex = state.messages.length - 1;
    state = state.copyWith(
      messages: [
        ...state.messages.sublist(0, assistantIndex),
        ChatMessage(
            role: MessageRole.assistant, parts: [const MessagePart.text('')])
      ],
      running: true,
      toolActivities: const [],
      activityLog: const [],
    );

    final prep = await _prepareRun(database);
    _wasCancelled = false;
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
        null);
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

    final assistantIndex = messageIndex + 1;
    state = state.copyWith(
      messages: [
        ...state.messages.sublist(0, messageIndex),
        editedMessage,
        // 与 send/regenerate 一致：占位助手消息由 _runAgent 按 assistantIndex 就地更新。
        ChatMessage(
            role: MessageRole.assistant, parts: [const MessagePart.text('')])
      ],
      running: true,
      toolActivities: const [],
      activityLog: const [],
    );

    final prep = await _prepareRun(database);
    _wasCancelled = false;
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
        null);
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
    try {
      final database = await ref.read(databaseProvider.future);
      final task = await database.findTask(taskId);
      if (task == null) return;
      await TaskService().markResumed(database, taskId);
      await TaskService().updateStatus(database, taskId, 'running');

      final request = _decodeTaskRequest(task.requestJson);
      final store = ref.read(providerConfigStoreProvider);
      final config = await store.load();

      final result = await HeadlessExecutor.run(
        db: database,
        config: config,
        prompt: request['prompt'] as String? ?? '',
      );

      await TaskService().updateStatus(database, taskId, 'completed');
      if (result.trim().isEmpty) return;

      final assistantMessage = ChatMessage(
        role: MessageRole.assistant,
        parts: [MessagePart.text(result)],
        modelName: config.isConfigured ? config.model : '演示模型',
      );
      state = state.copyWith(
        messages: [...state.messages, assistantMessage],
        running: false,
      );
      await _persistMessage(assistantMessage);
    } catch (_) {
      // 恢复失败静默，不阻断 UI。
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
    state = state.copyWith(planMode: value, planState: null);
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
  Future<String> _runSubAgent(String? agentId, String prompt) async {
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
      );
    } catch (error) {
      return '子任务执行失败：$error';
    }
  }

  /// manage_plan 工具回调：把模型产出的步骤写入 planState。
  Future<void> _onPlanUpdated(List<PlanStep> steps) async {
    if (steps.isEmpty) return;
    state = state.copyWith(planState: PlanState(steps: steps));
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
            ?.copyWith(status: approved ? 'confirmed' : 'cancelled'));
    if (completer != null && !completer.isCompleted) {
      completer.complete(approved);
    }
  }

  Future<bool> _confirmPlan(List<ToolCall> calls, String planText) async {
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
  ) async {
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
    final stopwatch = Stopwatch()..start();
    Duration? ttft;
    // 流式节流：token 级更新合并为每 50ms 一次，降低高频重建整个消息列表
    // 的主线程压力；流结束时会做最终完整刷新，不丢失文本。
    const flushInterval = Duration(milliseconds: 50);
    var lastFlush = DateTime.now();

    void flushAnswer() {
      lastFlush = DateTime.now();
      state = _withMessageAt(
          state,
          assistantIndex,
          ChatMessage(
              role: MessageRole.assistant,
              parts: [MessagePart.text(answer.toString())],
              reasoning: reasoning.isEmpty ? null : reasoning.toString()));
    }

    // 注入长期记忆与知识库片段，让交互式聊天也能享受记忆/RAG 能力（与
    // HeadlessExecutor 的后台路径保持一致）。注入失败不阻断执行。
    String baseSystemPrompt = state.systemPrompt;
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

    try {
      await for (final event in executor.run(
        history: state.messages.sublist(0, assistantIndex),
        model: model,
        confirmPlan: state.planMode ? _confirmPlan : null,
        approveTool: approveTool,
        systemPrompt: state.planMode
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
        if (event is TextEvent) {
          ttft ??= stopwatch.elapsed;
          answer.write(event.text);
          if (DateTime.now().difference(lastFlush) >= flushInterval) {
            flushAnswer();
          }
        } else if (event is ReasoningEvent) {
          ttft ??= stopwatch.elapsed;
          reasoning.write(event.text);
          flushAnswer();
        } else if (event is AgentUsageEvent) {
          usage = Usage(
              promptTokens: event.promptTokens,
              completionTokens: event.completionTokens);
        } else if (event is AgentErrorEvent) {
          answer.write('\n\n${formatErrorForMessage(event.message)}');
        } else if (event is ToolRequestedEvent) {
          final risk = _riskFor(registry, event.call.name);
          await _persistToolCall(event.call, risk);
          state = state.copyWith(
            activityLog: [...state.activityLog, '等待确认'],
            toolActivities: [
              ...state.toolActivities,
              ToolActivity(call: event.call, risk: risk)
            ],
          );
        } else if (event is AgentStatusEvent &&
            event.status == RunStatus.executingTool) {
          _updatePlanStepStatus('running');
          state = state.copyWith(
            activityLog: [...state.activityLog, '等待确认'],
            toolActivities:
                _updateLastToolActivity(state.toolActivities, status: '执行中'),
          );
        } else if (event is ApprovalRequiredEvent) {
          state = state.copyWith(
            activityLog: [...state.activityLog, '等待确认'],
            toolActivities: _updateToolActivity(
                state.toolActivities, event.call.id,
                status: '等待确认'),
          );
        } else if (event is ToolResultEvent) {
          _updatePlanStepStatus(
              event.result.startsWith('工具执行失败') ? 'failed' : 'completed');
          await _persistMessage(ChatMessage(
              role: MessageRole.tool,
              toolCallId: event.call.id,
              parts: [MessagePart.text(event.result)]));
          state = state.copyWith(
            toolActivities: _updateToolActivity(
              state.toolActivities,
              event.call.id,
              status: event.result.startsWith('工具执行失败') ? '执行失败' : '已完成',
              result: event.result,
            ),
          );
        }
      }
    } catch (error) {
      // 兜底：任何未预期异常（DB 写入失败、附件解析、审批回调等）都不能让
      // UI 永久停留在"运行中"。写入错误信息并恢复可交互状态。
      answer.write('\n\n${formatErrorForMessage(error.toString())}');
    } finally {
      stopwatch.stop();
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
    _cancellationToken = null;
    state = _withMessageAt(state, assistantIndex, assistantMessage)
        .copyWith(running: false);
    try {
      await _persistMessage(assistantMessage);
    } catch (_) {
      // 持久化失败不阻断 UI 恢复。
    }
    if (taskId != null) {
      try {
        final taskDb = await ref.read(databaseProvider.future);
        final taskService = TaskService();
        await taskService.updateStatus(
            taskDb, taskId, _wasCancelled ? 'cancelled' : 'completed');
      } catch (_) {}
    }
  }

  bool _wasCancelled = false;

  void stop() {
    _wasCancelled = true;
    _cancellationToken?.cancel();
    // 真正中断底层 HTTP 流（Dio 层），避免连接与带宽继续被占用。
    _dioCancelToken?.cancel();
  }

  void setSystemPrompt(String prompt) =>
      state = state.copyWith(systemPrompt: prompt);

  // --- 浼氳瘽 / Agent / Provider 操作 ---

  Future<void> newConversation() async {
    if (state.running) return;
    final database = await ref.read(databaseProvider.future);
    final conversation = await _createConversation(database);
    state = state.copyWith(
      conversationId: conversation.id,
      conversationTitle: conversation.title,
      messages: const [],
      toolActivities: const [],
      activityLog: const [],
    );
  }

  Future<void> switchConversation(Conversation conversation) async {
    final database = await ref.read(databaseProvider.future);
    final stored = await database.messagesFor(conversation.id);
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
