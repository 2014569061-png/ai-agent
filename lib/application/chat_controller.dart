import 'dart:convert';

import 'package:dio/dio.dart' show CancelToken;
import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/files/document_extractor.dart';
import '../infrastructure/mcp/mcp_server_config.dart';
import '../infrastructure/providers/anthropic_provider.dart';
import '../infrastructure/providers/gemini_provider.dart';
import '../infrastructure/providers/llm_provider.dart';
import '../infrastructure/providers/openai_compatible_provider.dart';
import '../infrastructure/providers/provider_config.dart';
import '../infrastructure/tools/core_tools.dart';
import '../infrastructure/tools/tool_registry.dart';
import 'agent_executor.dart';
import 'providers.dart';

/// 单次工具调用的运行时展示状态类
class ToolActivity {
  const ToolActivity({required this.call, required this.risk, this.status = '等待执行', this.result});
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
    this.activeReasoningEffort = ReasoningEffort.medium,
    this.providerConfigured = false,
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
  final ReasoningEffort activeReasoningEffort;
  final bool providerConfigured;

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
    ReasoningEffort? activeReasoningEffort,
    bool? providerConfigured,
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
        activeReasoningEffort: activeReasoningEffort ?? this.activeReasoningEffort,
        providerConfigured: providerConfigured ?? this.providerConfigured,
      );
}
/// Chat orchestration controller.
class ChatController extends Notifier<ChatState> {
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
      final store = ref.read(providerConfigStoreProvider);
      final config = await store.load();
      final database = await ref.read(databaseProvider.future);
      // 历史脏数据修复：早期版本源码里中文被错误编码，
      // 已在 IndexedDB 里留下乱码 agent 名字，这里就地修复。
      await _healMojibakeAgents(database);
      final conversations = await database.recentConversations();
      final conversation = conversations.isNotEmpty ? conversations.first : await _createConversation(database);
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
        conversationTitle: conversation.title,
        agentName: activeAgent.name,
        systemPrompt: activeAgent.systemPrompt,
        agentId: activeAgent.id,
        messages: restored.$1,
        toolActivities: restored.$2,
        activeModel: config.model,
        activeProviderName: config.name,
        activeProviderId: config.id,
        activeReasoningEffort: config.reasoningEffort,
        providerConfigured: config.isConfigured,
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
        role: MessageRole.values.firstWhere((role) => role.name == message.role, orElse: () => MessageRole.assistant),
        toolCallId: message.toolCallId,
        parts: [MessagePart.text(message.content)],
      );

  /// Restore persisted messages and tool cards.
  (List<ChatMessage>, List<ToolActivity>) _restoreFromMessages(List<Message> stored) {
    final messages = <ChatMessage>[];
    final activities = <ToolActivity>[];
    for (final message in stored) {
      final toolCallsJson = message.toolCallsJson;
      if (message.role == 'assistant' && toolCallsJson != null && toolCallsJson.isNotEmpty) {
        for (final (call, risk) in _decodeToolCalls(toolCallsJson)) {
          activities.add(ToolActivity(call: call, risk: risk, status: '已完成'));
        }
      } else if (message.role == 'tool') {
        final index = activities.lastIndexWhere((a) => a.call.id == message.toolCallId);
        if (index >= 0) {
          activities[index] = activities[index].copyWith(result: message.content);
        }
      } else {
        messages.add(_toDomainMessage(message));
      }
    }
    return (messages, activities);
  }

  List<(ToolCall, ToolRisk)> _decodeToolCalls(String json) {
    try {
      final list = (jsonDecode(json) as List<dynamic>).whereType<Map<String, dynamic>>();
      return list.map((item) {
        final call = ToolCall(
          id: item['id'] as String? ?? '',
          name: item['name'] as String? ?? '',
          arguments: item['arguments'] as Map<String, dynamic>? ?? const {},
        );
        final risk = ToolRisk.values.firstWhere((r) => r.name == item['risk'], orElse: () => ToolRisk.safe);
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
      id: 'message-${DateTime.now().microsecondsSinceEpoch}',
      conversationId: conversationId,
      role: message.role.name,
      content: message.parts.map((part) {
        if (part.type == 'image') return '[图片附件]';
        if (part.type == 'file') return '[文件附件]';
        return part.value;
      }).join(),
      toolCallId: Value(message.toolCallId),
      createdAt: DateTime.now(),
    ));
  }
  /// Persist a tool call for restoring tool cards.
  Future<void> _persistToolCall(ToolCall call, ToolRisk risk) async {
    final conversationId = state.conversationId;
    if (conversationId == null) return;
    final database = await ref.read(databaseProvider.future);
    await database.insertMessage(MessagesCompanion.insert(
      id: 'message-${DateTime.now().microsecondsSinceEpoch}',
      conversationId: conversationId,
      role: 'assistant',
      content: '',
      toolCallsJson: Value(jsonEncode([
        {'id': call.id, 'name': call.name, 'arguments': call.arguments, 'risk': risk.name},
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
    }
  }

  ToolRegistry _buildRegistry(Set<String> enabledTools, String tavilyKey) {
    final registry = ToolRegistry();
    if (enabledTools.contains('calculator')) registry.register(CalculatorTool());
    if (enabledTools.contains('get_time')) registry.register(GetTimeTool());
    if (enabledTools.contains('json_query')) registry.register(JsonQueryTool());
    if (enabledTools.contains('http_request')) registry.register(HttpRequestTool());
    if (enabledTools.contains('web_search')) registry.register(WebSearchTool(apiKey: tavilyKey));
    return registry;
  }

  /// 把已启用的 MCP 服务器工具并入 registry。
  /// 单个服务器连接失败不影响其余工具（失败静默跳过）。
  Future<void> _mergeMcpTools(ToolRegistry registry) async {
    try {
      final servers = await McpServerStore().loadEnabled();
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

  // --- 鍙戦€佷笌閲嶆柊生成 ---

  Future<void> send({
    required String text,
    required List<PlatformFile> attachments,
    required Future<bool> Function(ToolCall call, ToolRisk risk) approveTool,
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
        parts.add(MessagePart.image('data:$mime;base64,${base64Encode(bytes)}', mimeType: mime));
      } else if (bytes != null &&
          (file.extension == 'txt' || file.extension == 'md' || file.extension == 'csv' || file.extension == 'json' || file.extension == 'pdf')) {
        final content = _documentExtractor.extractText(fileName: file.name, bytes: bytes) ?? '';
        if (content.isEmpty && file.extension == 'pdf') {
          parts.add(MessagePart.text('\n\nPDF 文件 ${file.name} 未提取到可用文本'));
          continue;
        }
        final truncated = content.length > _maxTextAttachmentChars;
        final visibleContent = truncated ? '${content.substring(0, _maxTextAttachmentChars)}\n[内容已截断' : content;
        parts.add(MessagePart.text('\n\n文件 ${file.name} 内容：\n$visibleContent'));
      } else {
        parts.add(MessagePart.text('\n\n附件 ${file.name} 类型暂不支持，已跳过'));
      }
    }

    final userMessage = ChatMessage(role: MessageRole.user, parts: parts);
    final assistantIndex = state.messages.length + 1;
    var newTitle = state.conversationTitle;
    if (newTitle == '新会话') newTitle = trimmed.length > 24 ? trimmed.substring(0, 24) : trimmed;

    state = state.copyWith(
      messages: [...state.messages, userMessage, ChatMessage(role: MessageRole.assistant, parts: [const MessagePart.text('')])],
      running: true,
      conversationTitle: newTitle,
      toolActivities: const [],
      activityLog: const [],
    );

    await _persistMessage(userMessage);
    final database = await ref.read(databaseProvider.future);
    final conversationId = state.conversationId;
    if (conversationId != null) {
      final current = await database.findConversation(conversationId);
      if (current != null) await database.saveConversation(current.copyWith(title: newTitle, updatedAt: DateTime.now()));
    }

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
          if (decoded is List) enabledTools = decoded.whereType<String>().toSet();
        }
      }
    }

    final registry = _buildRegistry(enabledTools, tavilyKey);
    await _mergeMcpTools(registry);
    final model = config.isConfigured ? config.model : 'demo-model';
    await _runAgent(assistantIndex, model, config, registry, maxSteps, temperature, maxTokens, topP, config.reasoningEffort, approveTool);
  }

  Future<void> regenerate({required Future<bool> Function(ToolCall call, ToolRisk risk) approveTool}) async {
    if (state.running || state.loading) return;
    if (state.messages.isEmpty || state.messages.last.role != MessageRole.assistant) return;

    final database = await ref.read(databaseProvider.future);
    final conversationId = state.conversationId;
    if (conversationId != null) {
      await database.deleteTrailingAssistantAndTool(conversationId);
    }
    final assistantIndex = state.messages.length - 1;
    state = state.copyWith(
      messages: [...state.messages.sublist(0, assistantIndex), ChatMessage(role: MessageRole.assistant, parts: [const MessagePart.text('')])],
      running: true,
      toolActivities: const [],
      activityLog: const [],
    );

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
          if (decoded is List) enabledTools = decoded.whereType<String>().toSet();
        }
      }
    }
    final registry = _buildRegistry(enabledTools, tavilyKey);
    await _mergeMcpTools(registry);
    final model = config.isConfigured ? config.model : 'demo-model';
    await _runAgent(assistantIndex, model, config, registry, maxSteps, temperature, maxTokens, topP, config.reasoningEffort, approveTool);
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
    Future<bool> Function(ToolCall call, ToolRisk risk) approveTool,
  ) async {
    final provider = config.isConfigured ? _buildProvider(config) : DemoProvider();
    final executor = AgentExecutor(provider: provider, tools: registry);
    final cancellationToken = AgentCancellationToken();
    final dioCancelToken = CancelToken();
    _cancellationToken = cancellationToken;
    _dioCancelToken = dioCancelToken;
    final answer = StringBuffer();
    var usage = const Usage();
    final stopwatch = Stopwatch()..start();
    // 流式节流：token 级更新合并为每 50ms 一次，降低高频重建整个消息列表
    // 的主线程压力；流结束时会做最终完整刷新，不丢失文本。
    const flushInterval = Duration(milliseconds: 50);
    var lastFlush = DateTime.now();

    void flushAnswer() {
      lastFlush = DateTime.now();
      state = _withMessageAt(state, assistantIndex, ChatMessage(role: MessageRole.assistant, parts: [MessagePart.text(answer.toString())]));
    }

    try {
      await for (final event in executor.run(
        history: state.messages.sublist(0, assistantIndex),
        model: model,
        approveTool: approveTool,
        systemPrompt: state.systemPrompt,
        capabilities: ModelCapabilities.infer(model),
        maxSteps: maxSteps,
        temperature: temperature,
        maxTokens: maxTokens,
        topP: topP,
        reasoningEffort: reasoningEffort,
        cancellationToken: cancellationToken,
        cancelToken: dioCancelToken,
      )) {
        if (event is TextEvent) {
          answer.write(event.text);
          if (DateTime.now().difference(lastFlush) >= flushInterval) {
            flushAnswer();
          }
        } else if (event is AgentUsageEvent) {
          usage = Usage(promptTokens: event.promptTokens, completionTokens: event.completionTokens);
        } else if (event is AgentErrorEvent) {
          answer.write('\n\n错误：${event.message}');
        } else if (event is ToolRequestedEvent) {
          final risk = _riskFor(registry, event.call.name);
          await _persistToolCall(event.call, risk);
          state = state.copyWith(
            activityLog: [...state.activityLog, '等待确认'],
            toolActivities: [...state.toolActivities, ToolActivity(call: event.call, risk: risk)],
          );
        } else if (event is AgentStatusEvent && event.status == RunStatus.executingTool) {
          state = state.copyWith(
            activityLog: [...state.activityLog, '等待确认'],
            toolActivities: _updateLastToolActivity(state.toolActivities, status: '执行中'),
          );
        } else if (event is ApprovalRequiredEvent) {
          state = state.copyWith(
            activityLog: [...state.activityLog, '等待确认'],
            toolActivities: _updateToolActivity(state.toolActivities, event.call.id, status: '等待确认'),
          );
        } else if (event is ToolResultEvent) {
          await _persistMessage(ChatMessage(role: MessageRole.tool, toolCallId: event.call.id, parts: [MessagePart.text(event.result)]));
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
      answer.write('\n\n错误：$error');
    } finally {
      stopwatch.stop();
    }
    final assistantMessage = ChatMessage(
      role: MessageRole.assistant,
      parts: [MessagePart.text(answer.toString())],
      modelName: config.isConfigured ? config.model : '演示模型',
      usage: usage.totalTokens > 0 ? usage : null,
      elapsed: stopwatch.elapsed,
    );
    _cancellationToken = null;
    state = _withMessageAt(state, assistantIndex, assistantMessage).copyWith(running: false);
    try {
      await _persistMessage(assistantMessage);
    } catch (_) {
      // 持久化失败不阻断 UI 恢复。
    }
  }

  void stop() {
    _cancellationToken?.cancel();
    // 真正中断底层 HTTP 流（Dio 层），避免连接与带宽继续被占用。
    _dioCancelToken?.cancel();
  }

  void setSystemPrompt(String prompt) => state = state.copyWith(systemPrompt: prompt);

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
    state = state.copyWith(agentId: agent.id, agentName: agent.name, systemPrompt: agent.systemPrompt);
    final database = await ref.read(databaseProvider.future);
    final conversationId = state.conversationId;
    if (conversationId != null) {
      final conversation = await database.findConversation(conversationId);
      if (conversation != null) {
        await database.saveConversation(conversation.copyWith(agentId: Value(agent.id), updatedAt: DateTime.now()));
      }
    }
  }

  Future<void> switchProvider(ProviderConfig profile) async {
    final store = ref.read(providerConfigStoreProvider);
    await store.save(profile);
    final config = await store.load();
    state = state.copyWith(
      activeModel: config.model,
      activeProviderName: config.name,
      activeProviderId: config.id,
      activeReasoningEffort: config.reasoningEffort,
      providerConfigured: config.isConfigured,
    );
  }

  /// 切换"思考程度"档位（已保存到 ProviderConfig），更新 state 以便 UI 立即反映。
  void setReasoningEffort(ReasoningEffort effort) {
    state = state.copyWith(activeReasoningEffort: effort);
  }

  // --- 鐘舵€佽緟'---

  ToolRisk _riskFor(ToolRegistry registry, String name) =>
      registry.find(name)?.manifest.risk ?? ToolRisk.safe;

  ChatState _withMessageAt(ChatState s, int index, ChatMessage message) {
    final messages = List<ChatMessage>.of(s.messages);
    messages[index] = message;
    return s.copyWith(messages: messages);
  }

  List<ToolActivity> _updateToolActivity(List<ToolActivity> activities, String callId, {String? status, String? result}) {
    return activities
        .map((a) => a.call.id == callId ? a.copyWith(status: status, result: result) : a)
        .toList();
  }

  List<ToolActivity> _updateLastToolActivity(List<ToolActivity> activities, {String? status}) {
    if (activities.isEmpty) return activities;
    final updated = List<ToolActivity>.of(activities);
    updated[updated.length - 1] = updated.last.copyWith(status: status);
    return updated;
  }
}

final chatControllerProvider = NotifierProvider<ChatController, ChatState>(ChatController.new);


