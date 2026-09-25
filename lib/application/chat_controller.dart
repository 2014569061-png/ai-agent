import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform, visibleForTesting;
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'attachment_policy.dart';
import 'mojibake_repair.dart';
import 'autonomous_delegation.dart';

import '../domain/attachment_file.dart';
import '../domain/context_insights.dart';
import '../domain/models.dart';
import '../domain/message_display_metadata.dart';
import '../domain/model_failure.dart';
import '../domain/tool_codes.dart';
import '../domain/tool_result.dart';
import '../domain/unique_id.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/files/document_extractor.dart';
import '../infrastructure/providers/llm_provider.dart';
import '../infrastructure/providers/provider_config.dart';
import '../infrastructure/providers/provider_factory.dart';
import '../infrastructure/tools/core_tools.dart';
import '../infrastructure/tools/android_device_tool.dart';
import '../infrastructure/tools/tool_registry.dart';
import '../infrastructure/tools/sub_agent_tool.dart';
import '../infrastructure/tools/plan_tool.dart';
import '../infrastructure/tools/image_gen_tool.dart';
import '../infrastructure/tools/workspace_tools.dart';
import '../infrastructure/tools/command_tool.dart';
import '../infrastructure/tools/skill_tools.dart';
import 'agent_executor.dart';
import 'audit_service.dart';
import 'android_automation_tool.dart';
import 'device_automation_service.dart';
import '../domain/device_automation.dart';
import 'run_coordinator.dart';
import 'context_insights_history.dart';
import 'context_compression_planner.dart';
import 'context_window.dart';
import 'error_humanizer.dart';
import 'reasoning_policy.dart';
import 'system_prompt_assembly.dart';
import 'knowledge_service.dart';
import 'memory_service.dart';
import 'providers.dart';
import 'log_service.dart';
import 'nexus_guard.dart';
import 'run_event_tracker.dart';
import 'run_controller.dart';
import '../domain/sensitive_tool_policy.dart';
import 'task_service.dart';
import 'task_template_service.dart';
import 'workspace_service.dart';
import 'workspace_snapshot.dart';
import 'project_kind.dart';
import 'project_kind_detector.dart';
import 'conversation_fork_service.dart';
import 'conversation_history_pager.dart';
import '../domain/history_load_result.dart';
import 'file_citation.dart';
import 'project_context_service.dart';
import 'project_service.dart';
import 'project_settings.dart';
import 'project_template_service.dart';
import 'prompt_budget.dart';
import 'task_summary.dart';
import 'background_execution_gateway.dart';
import 'development_execution_service.dart';
import 'development_loop_finalizer.dart';
import '../infrastructure/plugins/plugin_store.dart';
import '../infrastructure/skills/skill_store.dart';
import '../infrastructure/notifications/notification_service.dart';
import '../infrastructure/background/foreground_service.dart';

part 'chat_run_execution.dart';
part 'chat_state.dart';

// ignore_for_file: curly_braces_in_flow_control_structures

class ChatController extends Notifier<ChatState> {
  static const _maxAttachmentBytes = maxAttachmentBytes;
  static const _maxTextAttachmentChars = 100000;
  static const _documentExtractor = DocumentExtractor();

  DateTime? _cancelRequestedAt;
  final Set<String> _resumingTaskIds = <String>{};
  final Set<String> _inflightRequestIds = <String>{};
  String? _contextRunsLoadedConversationId;
  String? _contextRunsLoadingConversationId;
  int? _contextRunsLoadingRevision;
  Future<List<ContextRunHistory>>? _contextRunsLoading;
  var _contextRunsRevision = 0;
  var _conversationSwitchGeneration = 0;
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

  /// 容器读写入口。Riverpod 3 把 `Notifier.ref` 也标记为 protected，而
  /// [ChatRunExecution] 是 extension（不在子类继承链上），直接访问会触发
  /// `invalid_use_of_protected_member`。与其在 11 处调用点各加忽略，不如像
  /// `_currentState` 一样提供一个库内转发器，语义与可读性都保持一致。
  Ref get _ref => ref;

  /// 容器是否仍然挂载。
  ///
  /// Riverpod 3 起，对已销毁的容器读写 ref / state 会抛 `UnmountedRefException`
  /// （2.x 只是静默忽略）。因此任何在 `build()` 之后分离执行、且跨越 await 的
  /// 异步工作（见 [_initialize]），在每次触达 ref / 提交状态之前都必须先确认容器
  /// 还在——否则用户离开页面或 scope 被销毁的瞬间，一次迟到的初始化写入就会从
  /// 「静默无效」升级成「未捕获异常」。
  bool get _mounted => ref.mounted;

  /// 写入面向用户的运行摘要。只在真实阶段变化或服务端流量到达时触发，
  /// 不靠伪造的循环文案制造“模型正在工作”的错觉。
  void _setRunProgress({
    required int runGeneration,
    required String? conversationId,
    required ChatRunStage stage,
    required String label,
    int? completedTools,
    int? generatedCharacters,
    bool touch = true,
  }) {
    if (!_runs.ownsRun(runGeneration, conversationId) ||
        !_runs.isVisible(conversationId)) {
      return;
    }
    final now = DateTime.now();
    final current = state.runProgress ?? ChatRunProgress.started(now: now);
    final nextStage = stage;
    final nextLabel = label;
    final nextTools = completedTools ?? current.completedTools;
    final nextCharacters = generatedCharacters ?? current.generatedCharacters;
    final meaningfulChange = nextStage != current.stage ||
        nextLabel != current.label ||
        nextTools != current.completedTools ||
        nextCharacters != current.generatedCharacters;
    // 流式 token 可能每几十毫秒到达一次；进度心跳最多每秒写一次，避免
    // 为了更新“最后活动时间”而让顶栏和工具面板跟着每个 token 重建。
    final shouldTouch = touch &&
        (meaningfulChange ||
            now.difference(current.lastActivityAt) >=
                const Duration(seconds: 1));
    if (!meaningfulChange && !shouldTouch && state.runProgress != null) return;
    final next = current.copyWith(
      stage: nextStage,
      label: nextLabel,
      lastActivityAt: shouldTouch ? now : current.lastActivityAt,
      completedTools: nextTools,
      generatedCharacters: nextCharacters,
    );
    state = state.copyWith(runProgress: next);
  }

  @override
  ChatState build() {
    Future.microtask(_initialize);
    return const ChatState();
  }

  // --- 初始化 ---

  Future<void> _initialize() async {
    // build() 把初始化拆到 microtask 执行，因此这里可能在容器已销毁后才开始或
    // 恢复；第一步就要确认还挂载着，否则下面的 ref.read 本身就会抛。
    if (!_mounted) return;
    try {
      // 四路互不依赖的读取并发执行（F-5），替代逐个串行等待。
      // Workspace is managed via state.currentWorkspacePath
      final database = await ref.read(databaseProvider.future);
      final results = await Future.wait([
        ref
            .read(workspaceServiceProvider)
            .getActiveWorkspace()
            .catchError((_) => null),
        ref.read(providerConfigStoreProvider).load(),
        database.recentConversations(limit: 200),
        database.allAgents(limit: 200),
      ]);
      final activeWorkspace = results[0] as String?;
      final config = results[1] as ProviderConfig;
      final conversations = results[2] as List<Conversation>;
      var agents = results[3] as List<Agent>;
      ReasoningMode reasoningMode = ReasoningMode.standard;
      var webSearchEnabled = false;
      try {
        final preferences = await SharedPreferences.getInstance();
        reasoningMode = ReasoningModeX.parse(
          preferences.getString('settings.llm.reasoning_mode'),
          legacyDeepEnabled:
              preferences.getBool('settings.llm.deep_reasoning') ?? false,
        );
        webSearchEnabled =
            preferences.getBool('settings.tool.web_browsing') ?? false;
      } catch (error, stackTrace) {
        // 读取失败会静默退回默认设置：用户看到的「深度思考/联网」开关状态
        // 可能与上次保存的不一致，必须留痕。
        NexusGuard.degradeCaught('chat.loadSettings', error, stackTrace,
            logger: _logDegrade);
      }
      // 历史脏数据修复：统一修复早期版本遗留的乱码文本。
      // F-5：版本位短路 —— 完整跑过一次后不再每次启动全表扫描。
      await _healMojibakeAgents(database);
      // 内置技能由数据库打开后的维护队列异步安装，不阻塞首屏初始化。

      final conversation = conversations.isNotEmpty
          ? conversations.first
          : await _createConversation(database);
      final storedPage = await _loadConversationPage(database, conversation.id);
      _trackLoadedWindow(storedPage);
      final storedMessages = storedPage.map((e) => e.$1).toList();
      final contextSteps = await ContextInsightsHistory.latestForConversation(
        database,
        conversation.id,
      );
      if (agents.isEmpty) {
        final now = DateTime.now();
        await database.insertAgent(AgentsCompanion.insert(
          id: 'agent-default',
          name: '通用助手',
          modelProfileId: 'default',
          updatedAt: now,
        ));
        agents = await database.allAgents(limit: 200);
      }
      Agent? activeAgent;
      if (conversation.agentId != null) {
        for (final agent in agents) {
          if (agent.id == conversation.agentId) {
            activeAgent = agent;
            break;
          }
        }
      }
      final restored = _restoreFromMessages(storedMessages);
      final latestSnapshot =
          contextSteps.isEmpty ? null : contextSteps.last.snapshot;
      final restoredMessageTokens = restored.$1.fold<int>(
          0, (sum, message) => sum + ContextWindow.estimateTokens(message));
      // 上面每个 await 都可能让容器在该点已被销毁，写状态前必须再确认一次。
      if (!_mounted) return;
      state = state.copyWith(
        loading: false,
        conversationId: conversation.id,
        conversationTitle: MojibakeRepair.repair(conversation.title),
        agentName: activeAgent == null
            ? '通用助手'
            : MojibakeRepair.repair(activeAgent.name),
        systemPrompt: activeAgent?.systemPrompt ?? '你是一个有帮助的 AI Agent。',
        agentId: activeAgent?.id,
        clearAgentId: activeAgent == null,
        messages: restored.$1,
        toolActivities: restored.$2,
        activeModel: config.model,
        activeProviderName: config.name,
        activeProviderId: config.id,
        contextTokens: config.contextTokens,
        contextReservedOutputTokens: activeAgent?.maxTokens ?? 2048,
        activeReasoningEffort: config.reasoningEffort,
        reasoningMode: reasoningMode,
        webSearchEnabled: webSearchEnabled,
        providerConfigured: config.isConfigured,
        currentWorkspacePath: activeWorkspace,
        liveContextTokens: latestSnapshot?.usedTokens ?? restoredMessageTokens,
        contextSteps: contextSteps,
        contextSnapshot: latestSnapshot,
      );
      unawaited(_hydrateActiveProject(database, conversation));
    } catch (_) {
      // 初始化失败时降级为空会话，避免首屏永久显示加载状态。
      //
      // 容器销毁后 state 的 setter 会抛 UnmountedRefException；这里若再写一次，
      // 就会把一个「早退」变成未捕获异常（Riverpod 3 起不再静默容忍）。
      if (!_mounted) return;
      state = state.copyWith(loading: false);
    }
  }

  /// 历史脏数据修复：早期版本源代码里中文被错误编码，数据库里残留了
  /// 形如 "閫氱敤鍔╂墜" 的 agent 名字，每次启动检测并就地改回正确名字。
  static const _nameRepairs = <String, String>{
    '閫氱敤鍔╂墜': '通用助手',
    '鏂颁細': '新会话',
  };

  static const _mojibakeHealedFlag = 'settings.mojibakeHealed.v1';

  Future<void> _healMojibakeAgents(AppDatabase database) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_mojibakeHealedFlag) == true) return;
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
      await prefs.setBool(_mojibakeHealedFlag, true);
    } catch (_) {
      // 读不到 prefs（单测/插件缺失）时退回每次扫描，不阻断初始化。
    }
  }

  Future<Conversation> _createConversation(
    AppDatabase database, {
    ChatMode? modeOverride,
  }) async {
    final now = DateTime.now();
    final conversation = Conversation(
      id: UniqueId.generate('conversation', now: now),
      title: '新会话',
      agentId: null,
      projectId: state.currentProjectId,
      mode: (modeOverride ?? state.mode).name,
      providerProfileId:
          state.activeProviderId.isEmpty ? null : state.activeProviderId,
      isPinned: false,
      isFavorite: false,
      tagsJson: '[]',
      createdAt: now,
      updatedAt: now,
    );
    await database.saveConversation(conversation);
    return conversation;
  }

  ChatMessage _toDomainMessage(Message message) =>
      MessageDisplayMetadata.restore(
          ChatMessage(
            id: message.id,
            role: MessageRole.values.firstWhere(
                (role) => role.name == message.role,
                orElse: () => MessageRole.assistant),
            toolCallId: message.toolCallId,
            parts: [MessagePart.text(MojibakeRepair.repair(message.content))],
            reasoning: message.reasoningContent == null
                ? null
                : MojibakeRepair.repair(message.reasoningContent!),
          ),
          message.displayMetadataJson);

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
          final compressed =
              message.content.contains(ContextWindow.compressedToolResultMark);
          final original = compressed
              ? message.content
                  .replaceFirst(ContextWindow.compressedToolResultMark, '')
                  .trimLeft()
              : message.content;
          activities[index] = _restoreToolActivityResult(
            activities[index],
            original,
            compressed: compressed,
          );
        }
      } else {
        messages.add(_toDomainMessage(message));
      }
    }
    return (messages, activities);
  }

  /// 会话恢复也保留 ToolResult 的结构化语义，避免历史工具卡退化成文本输出。
  ToolActivity _restoreToolActivityResult(
    ToolActivity activity,
    String value, {
    bool compressed = false,
  }) {
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
          compressed: compressed,
          originalResult:
              compressed ? decoded['message']?.toString() ?? value : null,
          ok: decoded['ok'] == true,
          code: decoded['code']?.toString(),
          effect: effect,
        );
      }
    } catch (_) {
      // 兼容 ToolResult 迁移前保存的纯文本工具结果。
    }
    return activity.copyWith(
      result: value,
      compressed: compressed,
      originalResult: compressed ? value : null,
    );
  }

  Future<void> _persistCompressionMarkers(
    String? conversationId,
    Iterable<String> toolCallIds,
  ) async {
    if (conversationId == null) return;
    final ids = toolCallIds.toSet();
    if (ids.isEmpty) return;
    final database = await ref.read(databaseProvider.future);
    final stored = await database.messagesFor(conversationId);
    for (final message in stored) {
      if (message.role != 'tool' ||
          message.toolCallId == null ||
          !ids.contains(message.toolCallId) ||
          message.content.contains(ContextWindow.compressedToolResultMark)) {
        continue;
      }
      await database.saveMessage(message.copyWith(
        content:
            '${ContextWindow.compressedToolResultMark}\n${message.content}',
      ));
    }
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
          providerMetadata: item['providerMetadata'] is Map
              ? Map<String, dynamic>.from(item['providerMetadata'] as Map)
              : const {},
        );
        final risk = ToolRisk.values.firstWhere((r) => r.name == item['risk'],
            orElse: () => ToolRisk.safe);
        return (call, risk);
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// 降级日志出口。走 LogService 而不是 print：日志才会进诊断页、可导出。
  ///
  /// `LogService.warning` 自身把写库包在 try/catch 里并立即返回，因此它不会把
  /// 「已吞掉的失败」重新变成抛出的异常。
  void _logDegrade(String message, {Map<String, dynamic>? detail}) {
    // 容器销毁后 ref 会抛；降级日志绝不能反过来造成新的异常。
    if (!_mounted) return;
    unawaited(_ref
        .read(logServiceProvider)
        .warning(message, category: 'chat', detail: detail));
  }

  Future<void> _persistMessage(ChatMessage message,
      {String? toolName,
      ToolResult? toolResult,
      String? conversationId}) async {
    final targetId = conversationId ?? state.conversationId;
    if (targetId == null) return;
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
      id: message.id ?? UniqueId.generate('message'),
      conversationId: targetId,
      role: message.role.name,
      content: content,
      toolCallId: Value(message.toolCallId),
      reasoningContent: Value(message.reasoning),
      displayMetadataJson: Value(MessageDisplayMetadata.encode(message)),
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
  Future<void> _persistToolCall(ToolCall call, ToolRisk risk,
      {String? conversationId}) async {
    final targetId = conversationId ?? state.conversationId;
    if (targetId == null) return;
    final database = await ref.read(databaseProvider.future);
    await database.insertMessage(MessagesCompanion.insert(
      id: UniqueId.generate('message'),
      conversationId: targetId,
      role: 'assistant',
      content: '',
      toolCallsJson: Value(jsonEncode([
        {
          'id': call.id,
          'name': call.name,
          'arguments':
              SensitiveToolPolicy.redactArguments(call.name, call.arguments),
          if (call.providerMetadata.isNotEmpty)
            'providerMetadata': call.providerMetadata,
          'risk': risk.name
        },
      ])),
      createdAt: DateTime.now(),
    ));
  }

  // --- Provider 与工具构建 ---

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
    if (defaultTargetPlatform == TargetPlatform.android && !kIsWeb) {
      registry.register(AndroidDevicePreviewTool());
      registry.register(AndroidDeviceTool());
      registry.register(AndroidAppPrivateDataPreviewTool());
      registry.register(AndroidAppPrivateDataTool());
      registry.register(AndroidAutomationTool(
        service: ref.read(deviceAutomationServiceProvider),
      ));
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
    if (enabledTools.contains('skills_read') ||
        enabledTools.contains('skills_read_resource')) {
      try {
        final database = await ref.read(databaseProvider.future);
        if (enabledTools.contains('skills_read')) {
          registry.register(SkillsReadTool(database: database));
        }
        if (enabledTools.contains('skills_read_resource')) {
          registry.register(SkillsReadResourceTool(database: database));
        }
      } catch (_) {
        // 数据库尚未就绪时，当前回合不暴露 Skill 读取工具。
      }
    }
    // 子 Agent：走统一后台入口，safe 工具才放行。
    // 风险由自主委派开关决定：开启 → safe（自动放行），关闭 → requiresConfirmation（走审批）。
    registry.register(SubAgentTool(onRun: _runSubAgent, risk: subAgentRisk));
    // 计划模式：模型首轮调用 manage_plan 后由回调更新 planState。
    registry.register(ManagePlanTool(onPlanUpdated: _onPlanUpdated));

    final wsPath = state.currentWorkspacePath;
    if (settings.workspaceFiles && wsPath != null && wsPath.isNotEmpty) {
      final sandbox = WorkspaceSandbox(wsPath);
      registry.register(ReadFileTool(sandbox: sandbox));
      registry.register(WriteFileTool(sandbox: sandbox));
      registry.register(EditFileTool(sandbox: sandbox));
      registry.register(ListDirectoryTool(sandbox: sandbox));
      registry.register(SearchFilesTool(sandbox: sandbox));
      registry.register(DeleteFileTool(sandbox: sandbox));
      registry.register(MoveFileTool(sandbox: sandbox));
      if (settings.terminal && !kIsWeb) {
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
  Future<ToolSettings> _loadToolSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return ToolSettings(
        webBrowsing: state.webSearchEnabled,
        // Keep the former combined key as a migration fallback. New installs
        // and the settings page use separate permissions from this point on.
        workspaceFiles: prefs.getBool('settings.tool.workspace_files') ??
            prefs.getBool('settings.tool.terminal_file') ??
            true,
        terminal: prefs.getBool('settings.tool.terminal') ??
            prefs.getBool('settings.tool.terminal_file') ??
            true,
      );
    } catch (_) {
      return ToolSettings(webBrowsing: state.webSearchEnabled);
    }
  }

  /// 把已启用的 MCP 服务器工具并入 registry。
  /// 单个服务器连接失败不影响其余工具（失败静默跳过）。
  Future<void> _mergeMcpTools(ToolRegistry registry,
      {Set<String>? allowedToolNames}) async {
    try {
      final servers = await ref.read(mcpServiceProvider).loadEnabled();
      if (servers.isEmpty) return;
      final mcp = ref.read(mcpToolProvider);
      await mcp.syncServers(servers);
      for (final server in servers) {
        final tools = await mcp.connectAndListTools(server);
        for (final tool in tools) {
          if (allowedToolNames == null ||
              allowedToolNames.contains(tool.manifest.name)) {
            registry.register(tool);
          }
        }
      }
    } catch (_) {
      // MCP 服务不可达时静默降级，保留内置工具。
    }
  }

  /// 把已启用插件里的声明式 HTTP 工具并入 registry（与内置/MCP 工具重名时跳过）。
  Future<void> _mergePluginTools(ToolRegistry registry,
      {Set<String>? allowedToolNames}) async {
    try {
      final database = await ref.read(databaseProvider.future);
      final tools = await PluginStore().loadDeclarativeTools(database);
      for (final tool in tools) {
        if ((allowedToolNames == null ||
                allowedToolNames.contains(tool.manifest.name)) &&
            registry.findRegistration(tool.manifest.name) == null) {
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
      _prepareRun(AppDatabase database, {String taskType = 'general'}) async {
    final store = ref.read(providerConfigStoreProvider);
    var config = await store.load();
    config = config.copyWith(
      reasoningEffort: switch (state.reasoningMode) {
        ReasoningMode.standard => ReasoningEffort.off,
        ReasoningMode.deep => ReasoningEffort.high,
        ReasoningMode.auto => ReasoningPolicy.resolve(
            taskType: taskType,
            configured: config.reasoningEffort,
            planMode: state.planMode,
          ),
      },
    );
    final tavilyKey = await store.readToolKey('tavily');
    var enabledTools = <String>{'calculator', 'get_time', 'json_query'};
    // 前台单次预算默认 40 轮；最近有进展时执行器还会自动续跑 2 次（见
    // chat_run_execution 的 autoContinueLimit）。预算耗尽是可恢复的暂停。
    var maxSteps = 40;
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
        try {
          final decoded = jsonDecode(agent.enabledToolsJson);
          if (decoded is List) {
            // An empty list is an explicit per-Agent permission choice.
            enabledTools = decoded.whereType<String>().toSet();
          }
        } catch (_) {
          // Corrupt legacy metadata must not abort an otherwise valid run.
          enabledTools = <String>{};
        }
      }
    }
    // 聊天模式只发送普通对话请求，不装配工具/MCP/插件，避免模型在简单问答
    // 中主动执行工具。Agent 与计划模式沿用完整工具链。
    var registry = ToolRegistry();
    if (state.mode != ChatMode.chat) {
      // 自主委派开关决定 sub_agent 工具的风险等级：开启 → 自动放行（safe），
      // 关闭 → requiresConfirmation（与审批模式兼容）。
      final autonomousDelegation =
          await AutonomousDelegationService().isEnabled();
      final subAgentRisk =
          autonomousDelegation ? ToolRisk.safe : ToolRisk.requiresConfirmation;
      final toolSettings = await _loadToolSettings();
      registry = await _buildRegistry(
          enabledTools, tavilyKey, config, subAgentRisk, toolSettings);
      // A selected Agent owns the allow-list for user-selectable extension
      // tools.  Without an Agent, retain the workspace-wide enabled MCP and
      // plugin tools for backwards-compatible Agent/plan mode behavior.
      final extensionAllowList = agentId == null ? null : enabledTools;
      await _mergeMcpTools(registry, allowedToolNames: extensionAllowList);
      await _mergePluginTools(registry, allowedToolNames: extensionAllowList);
    }
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
      'implement_and_verify': '实现并验证',
    };
    final label = labels[taskType] ?? '开发任务';
    final shortPrompt = prompt.trim();
    if (shortPrompt.isEmpty) return label;
    return '$label：${shortPrompt.length > 28 ? '${shortPrompt.substring(0, 28)}…' : shortPrompt}';
  }

  Future<void> addFileCitation(FileCitation citation) async {
    if (citation.relativePath.isEmpty) return;
    final next = [
      ...state.pendingCitations.where((item) =>
          item.relativePath != citation.relativePath ||
          item.startLine != citation.startLine ||
          item.endLine != citation.endLine),
      citation,
    ];
    state = state.copyWith(pendingCitations: next);
  }

  void removeFileCitation(FileCitation citation) {
    state = state.copyWith(
      pendingCitations: state.pendingCitations
          .where((item) =>
              item.relativePath != citation.relativePath ||
              item.startLine != citation.startLine ||
              item.endLine != citation.endLine)
          .toList(growable: false),
    );
  }

  /// Keeps ordinary questions in chat mode while routing explicit project work
  /// through Agent mode, where workspace tools can be registered.
  static bool requiresAgentModeForRequest(
    String text, {
    String taskType = 'general',
  }) {
    if (taskType != 'general') return true;
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    final hasAction = RegExp(
      r'创建|新建|生成|制作|做|开发|实现|修改|编辑|修复|构建|编译|写一个|create|build|implement|edit|fix',
    ).hasMatch(normalized);
    final hasDevelopmentTarget = RegExp(
      r'html|网页|网站|页面|项目|代码|程序|应用|文件|exe|flutter|react|vue|python|go|node|file|app',
    ).hasMatch(normalized);
    final isDeviceAction = RegExp(
      r'打开.{0,12}(应用|软件|微信|支付宝|相机|设置|浏览器)|'
      r'(搜索|查找|找一下|找找).{0,16}(本地|手机|文件|照片|图片|pdf)|'
      r'(本地|手机).{0,10}(搜索|查找|找一下|找找).{0,12}(文件|照片|图片|pdf)|'
      r'找.{0,10}(本地|手机)?(文件|照片|图片)',
    ).hasMatch(normalized);
    return (hasAction && hasDevelopmentTarget) || isDeviceAction;
  }

  Future<void> send({
    required String text,
    required List<AttachmentFile> attachments,
    required ToolApprovalCallback approveTool,
    String taskType = 'general',
    String sourceType = 'manual',
    String? clientRequestId,
  }) async {
    final trimmed = text.trim();
    if ((trimmed.isEmpty && attachments.isEmpty) ||
        state.running ||
        state.loading) return;
    final requestId = (clientRequestId == null || clientRequestId.isEmpty)
        ? UniqueId.generate('req')
        : clientRequestId;
    if (!_inflightRequestIds.add(requestId)) return;
    if (state.mode == ChatMode.chat &&
        requiresAgentModeForRequest(trimmed, taskType: taskType)) {
      setMode(ChatMode.agent);
    }
    final conversationId = state.conversationId;
    final workspacePath = state.currentWorkspacePath;
    final runGeneration = _runs.beginRun();
    _invalidateContextRuns(clearState: true);

    final parts = <MessagePart>[MessagePart.text(trimmed)];
    for (final file in attachments) {
      final bytes = file.bytes;
      // 类型判定与选择器共用 attachment_policy.dart 的名单，避免「能选不能发」。
      final mime = imageMimeForExtension(file.extension);
      if (bytes != null && bytes.length > _maxAttachmentBytes) {
        parts.add(MessagePart.text('\n\n附件 ${file.name} 超过 8MB，已跳过'));
        continue;
      }
      final isTextAttachment = isTextAttachmentExtension(file.extension);
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

    final userMessage = ChatMessage(
      id: UniqueId.generate('message'),
      role: MessageRole.user,
      parts: parts,
    );
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
          id: UniqueId.generate('message'),
          role: MessageRole.assistant,
          parts: [const MessagePart.text('')],
        )
      ],
      running: true,
      paused: false,
      runProgress: ChatRunProgress.started(),
      conversationTitle: newTitle,
      currentTaskId: null,
      currentRunId: null,
      toolActivities: const [],
      activityLog: const [],
      liveContextTokens: initialContextTokens,
      timingSnapshot: TimingSnapshot.empty,
      clearContextSnapshot: true,
      clearContextSteps: true,
      clearContextRuns: true,
      clearLiveReply: true,
    );

    // 持久化失败不阻断对话：吞掉异常，后续 _runAgent 内的兜底 catch 会恢复 running 状态。
    try {
      final database = await ref.read(databaseProvider.future);
      if (!_runs.ownsRun(runGeneration, conversationId)) return;
      // 用户消息没落库才是真正的数据丢失：仍然不阻断对话（外层 catch 继续兜住），
      // 但必须留下可导出、可统计的痕迹。
      await NexusGuard.degradeAsync<void>(
        'chat.persistUserMessage',
        () async {
          await _persistMessage(userMessage);
          if (conversationId != null) {
            final current = await database.findConversation(conversationId);
            if (current != null) {
              await database.saveConversation(
                  current.copyWith(title: newTitle, updatedAt: DateTime.now()));
            }
          }
        },
        logger: _logDegrade,
      );

      final prep = await _prepareRun(database, taskType: taskType);
      if (!_runs.ownsRun(runGeneration, conversationId)) return;
      // C2 断点恢复：注册一个"运行中"任务，App 被杀后可在启动时提示继续执行。
      String? runningTaskId;
      ProjectKindDetection? project;
      try {
        if (workspacePath != null && workspacePath.trim().isNotEmpty) {
          project = await const ProjectKindDetector().detect(workspacePath);
        }
      } catch (error, stackTrace) {
        // 探测失败只让任务快照少一个 projectKind，不影响本次执行。
        NexusGuard.degradeCaught('chat.detectProjectKind', error, stackTrace,
            logger: _logDegrade);
      }
      try {
        final existing =
            await TaskService().findByRequestId(database, requestId);
        if (existing != null) {
          runningTaskId = existing.id;
          _runs.activeTaskId = existing.id;
          _runs.boundConversationId = conversationId;
          state = state.copyWith(
            currentTaskId: existing.id,
            pendingCitations: const [],
          );
        }
      } catch (error, stackTrace) {
        // 断点恢复登记失败：App 被杀后无法提示继续，属于可降级但需可查。
        NexusGuard.degradeCaught('chat.restoreRunningTask', error, stackTrace,
            logger: _logDegrade);
      }
      try {
        if (runningTaskId != null) {
          // clientRequestId 已创建过任务，不再插入第二条。
        } else {
          final task = await TaskService().create(
            db: database,
            conversationId: conversationId ?? '',
            type: 'development:$taskType',
            requestJson: jsonEncode({
              'prompt': trimmed,
              'conversationId': conversationId,
              'model': prep.model,
              'maxSteps': prep.maxSteps,
              'requestId': requestId,
            }),
            metadata: {
              'taskType': taskType,
              'sourceType': sourceType,
              'workspacePath': workspacePath,
              if (state.currentProjectId != null)
                'projectId': state.currentProjectId,
              'title': _taskTitle(taskType, trimmed),
              'attachments': attachments.map((file) => file.name).toList(),
              'requestId': requestId,
              if (project != null) 'projectKind': project.kind.id,
              if (state.pendingCitations.isNotEmpty)
                'citations': [
                  for (final citation in state.pendingCitations)
                    citation.toJson()
                ],
            },
          );
          runningTaskId = task.id;
          _runs.activeTaskId = task.id;
          _runs.boundConversationId = conversationId;
          state = state.copyWith(currentTaskId: task.id);
          Map<String, dynamic>? snapshotJson;
          if (workspacePath != null && workspacePath.trim().isNotEmpty) {
            try {
              snapshotJson = (await const WorkspaceSnapshotService()
                      .capture(workspacePath))
                  .toJson();
            } catch (error, stackTrace) {
              // 快照缺失只让「断点恢复」的信息变少，不该影响本次执行。
              NexusGuard.degradeCaught(
                  'chat.captureWorkspaceSnapshot', error, stackTrace,
                  logger: _logDegrade);
            }
          }
          await TaskService().updateProgress(
            database,
            task.id,
            phase: 'running',
            extra: {
              if (project != null) 'projectKind': project.kind.id,
              'workspaceAccessible':
                  workspacePath != null && workspacePath.trim().isNotEmpty,
              if (snapshotJson != null) 'workspaceSnapshot': snapshotJson,
            },
          );
        }
        state = state.copyWith(pendingCitations: const []);
      } catch (error, stackTrace) {
        // 任务登记失败不阻断执行，但必须留痕。
        NexusGuard.degradeCaught('chat.registerRunningTask', error, stackTrace,
            logger: _logDegrade);
      }

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
          id: UniqueId.generate('message'),
          role: MessageRole.assistant,
          parts: [MessagePart.text(formatErrorForMessage(error.toString()))],
        );
        state = _withMessageAt(state, assistantIndex, failed).copyWith(
          running: false,
          clearLiveReply: true,
          clearRunProgress: true,
        );
        // 会话历史是用户数据：写库失败必须留痕，否则这条失败消息会静默消失。
        await NexusGuard.degradeAsync<void>(
          'chat.persistFailedReply',
          () => _persistMessage(failed),
          logger: _logDegrade,
        );
      }
    } finally {
      _inflightRequestIds.remove(requestId);
    }
  }

  Future<void> regenerate({required ToolApprovalCallback approveTool}) async {
    if (state.running || state.loading || state.restoringConversation) return;
    if (state.messages.isEmpty ||
        state.messages.last.role != MessageRole.assistant) {
      return;
    }

    final conversationId = state.conversationId;
    final switchGeneration = _conversationSwitchGeneration;
    bool current() =>
        _mounted &&
        switchGeneration == _conversationSwitchGeneration &&
        state.conversationId == conversationId;
    final database = await ref.read(databaseProvider.future);
    if (!_mounted ||
        switchGeneration != _conversationSwitchGeneration ||
        state.conversationId != conversationId ||
        state.running) return;
    final runGeneration = _runs.beginRun();
    state = state.copyWith(running: true);
    try {
      if (conversationId != null) {
        await database.deleteTrailingAssistantAndTool(conversationId);
      }
    } catch (error) {
      if (current() && _runs.ownsRun(runGeneration, conversationId)) {
        state = state.copyWith(
            running: false,
            activityLog: [...state.activityLog, '重新生成未能保存，已取消：$error']);
      }
      return;
    }
    if (!current() || !_runs.ownsRun(runGeneration, conversationId)) return;
    _invalidateContextRuns(clearState: true);
    // 库侧会删掉最后一条用户消息之后的整段 assistant/tool。内存也要切整段，
    // 不能只替换最后一条，否则同一秒写入的 tool 记录会留在新回复前面。
    var cut = state.messages.length;
    while (cut > 0) {
      final role = state.messages[cut - 1].role;
      if (role != MessageRole.assistant && role != MessageRole.tool) break;
      cut--;
    }
    final assistantIndex = cut;
    state = state.copyWith(
      messages: [
        ...state.messages.sublist(0, cut),
        ChatMessage(
            id: UniqueId.generate('message'),
            role: MessageRole.assistant,
            parts: [const MessagePart.text('')])
      ],
      running: true,
      paused: false,
      runProgress: ChatRunProgress.started(),
      toolActivities: const [],
      activityLog: const [],
      clearLiveReply: true,
    );

    try {
      final prep = await _prepareRun(database);
      if (!current() || !_runs.ownsRun(runGeneration, conversationId)) return;
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
    } catch (error) {
      if (current() && _runs.ownsRun(runGeneration, conversationId)) {
        final failed = ChatMessage(
          id: UniqueId.generate('message'),
          role: MessageRole.assistant,
          parts: [MessagePart.text(formatErrorForMessage(error.toString()))],
        );
        state = _withMessageAt(state, assistantIndex, failed).copyWith(
          running: false,
          clearLiveReply: true,
          clearRunProgress: true,
        );
        // 会话历史是用户数据：写库失败必须留痕，否则这条失败消息会静默消失。
        await NexusGuard.degradeAsync<void>(
          'chat.persistFailedReply',
          () => _persistMessage(failed),
          logger: _logDegrade,
        );
      }
    }
  }

  /// 编辑历史用户消息并重发：替换该条内容，删除其后的所有回复与工具记录，
  /// 再基于编辑后的消息重新运行 Agent。
  Future<void> editAndResend({
    required int messageIndex,
    String? messageId,
    String? expectedConversationId,
    required String newText,
    required ToolApprovalCallback approveTool,
  }) async {
    if (state.running || state.loading || state.restoringConversation) return;
    final conversationId = state.conversationId;
    final switchGeneration = _conversationSwitchGeneration;
    bool current() =>
        _mounted &&
        switchGeneration == _conversationSwitchGeneration &&
        state.conversationId == conversationId;
    if (expectedConversationId != null &&
        expectedConversationId != conversationId) return;
    if (messageId != null) {
      messageIndex =
          state.messages.indexWhere((message) => message.id == messageId);
    }
    if (messageIndex < 0 || messageIndex >= state.messages.length) return;
    final target = state.messages[messageIndex];
    if (target.id == null) return;
    if (target.role != MessageRole.user) return;
    final trimmed = newText.trim();
    if (trimmed.isEmpty) return;

    final imageParts =
        target.parts.where((part) => part.type != 'text').toList();
    final editedMessage = ChatMessage(
        id: target.id,
        role: MessageRole.user,
        parts: [MessagePart.text(trimmed), ...imageParts]);

    final database = await ref.read(databaseProvider.future);
    if (!_mounted ||
        switchGeneration != _conversationSwitchGeneration ||
        state.conversationId != conversationId ||
        state.running) return;
    // A pending page may have prepended rows while awaiting the database.
    messageIndex =
        state.messages.indexWhere((message) => message.id == target.id);
    if (messageIndex < 0) return;
    final runGeneration = _runs.beginRun();
    state = state.copyWith(running: true);
    if (conversationId != null) {
      try {
        await database.editMessageAndTruncate(
            conversationId, target.id!, _contentForPersist(editedMessage));
      } catch (_) {
        if (current() && _runs.ownsRun(runGeneration, conversationId)) {
          state = state.copyWith(
            running: false,
            activityLog: [
              ...state.activityLog,
              '编辑未能保存，已取消重发',
            ],
          );
        }
        return;
      }
    }

    if (!current() || !_runs.ownsRun(runGeneration, conversationId)) return;
    _invalidateContextRuns(clearState: true);

    final assistantIndex = messageIndex + 1;
    state = state.copyWith(
      messages: [
        ...state.messages.sublist(0, messageIndex),
        editedMessage,
        // 与 send/regenerate 一致：占位助手消息由 _runAgent 按 assistantIndex 就地更新。
        ChatMessage(
            id: UniqueId.generate('message'),
            role: MessageRole.assistant,
            parts: [const MessagePart.text('')])
      ],
      running: true,
      paused: false,
      runProgress: ChatRunProgress.started(),
      toolActivities: const [],
      activityLog: const [],
      clearLiveReply: true,
    );

    try {
      final prep = await _prepareRun(database);
      if (!current() || !_runs.ownsRun(runGeneration, conversationId)) return;
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
    } catch (error) {
      if (current() && _runs.ownsRun(runGeneration, conversationId)) {
        final failed = ChatMessage(
          id: UniqueId.generate('message'),
          role: MessageRole.assistant,
          parts: [MessagePart.text(formatErrorForMessage(error.toString()))],
        );
        state = _withMessageAt(state, assistantIndex, failed).copyWith(
          running: false,
          clearLiveReply: true,
          clearRunProgress: true,
        );
        // 会话历史是用户数据：写库失败必须留痕，否则这条失败消息会静默消失。
        await NexusGuard.degradeAsync<void>(
          'chat.persistFailedReply',
          () => _persistMessage(failed),
          logger: _logDegrade,
        );
      }
    }
  }

  Completer<bool>? _planCompleter;

  /// C2 断点恢复：列出可续跑的后台任务（被杀遗留的 running + 预算暂停的 paused）。
  Future<List<Task>> recoverableTasks() async {
    try {
      final database = await ref.read(databaseProvider.future);
      return await TaskService().resumableTasks(database);
    } catch (_) {
      return const [];
    }
  }

  /// C2 断点恢复：重新执行一个被中断的后台任务，并把结果写回会话。
  Future<void> resumeTask(String taskId,
      {required ToolApprovalCallback approveTool}) async {
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
          runProgress: ChatRunProgress.started(),
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
      final workspaceValue = request['workspacePath']?.toString().trim();
      final workspacePath = workspaceValue == null || workspaceValue.isEmpty
          ? null
          : workspaceValue;
      final systemPrompt = request['systemPrompt']?.toString();
      if (workspacePath != null) {
        await ref
            .read(workspaceServiceProvider)
            .setActiveWorkspace(workspacePath);
        if (ownsRun()) {
          state = state.copyWith(currentWorkspacePath: workspacePath);
        }
      }

      final progress = _decodeTaskProgress(taskData.progressJson);
      final checkpoint = progress['checkpoint'];
      final checkpointContext = checkpoint is Map
          ? decodeChatContext(checkpoint['context'])
          : const <ChatMessage>[];
      final executionRunId = UniqueId.generate('run');
      _runs.activeTaskId = taskId;
      _runs.activeRunId = executionRunId;
      _runs.boundConversationId = uiConversationId ?? taskData.conversationId;
      final result = await BackgroundExecutionGateway().run(
        db: db,
        config: config,
        prompt: request['prompt']?.toString() ?? '',
        taskId: taskId,
        initialHistory: checkpointContext.isEmpty ? null : checkpointContext,
        systemPrompt: systemPrompt,
        taskType: request['taskType']?.toString(),
        workspacePath: workspacePath,
        maxSteps: maxSteps,
        cancellationToken: cancellationToken,
        approveTool: approveTool,
        approvalMode: runApprovalMode,
        keepAlive: true,
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
      if (workspacePath != null &&
          workspacePath.trim().isNotEmpty &&
          taskStatus != 'cancelled') {
        try {
          await DevelopmentLoopFinalizer().finalize(
            db: db,
            taskId: taskId,
            runId: executionRunId,
            workspacePath: workspacePath,
            terminal: null,
            runVerification: false,
          );
        } catch (error, stackTrace) {
          NexusGuard.degradeCaught(
              'chat.finalizeDevelopmentLoop', error, stackTrace,
              logger: _logDegrade);
        }
      }

      if (ownsRun()) {
        state = state.copyWith(
          running: false,
          paused: false,
          clearLiveReply: true,
          clearRunProgress: true,
          successfulRunCount:
              taskStatus == 'completed' ? state.successfulRunCount + 1 : null,
        );
        final assistantMessage = ChatMessage(
          id: UniqueId.generate('message'),
          role: MessageRole.assistant,
          parts: [MessagePart.text(resultText)],
          modelName: config.isConfigured ? config.model : '演示模型',
        );
        if (uiConversationId != null && resultText.isNotEmpty) {
          state = state.copyWith(
            messages: [...state.messages, assistantMessage],
            clearLiveReply: true,
          );
          // 助手回复是用户数据：写库失败必须留痕，否则刷新后回复会凭空消失。
          await NexusGuard.degradeAsync<void>(
            'chat.persistAssistantReply',
            () => _persistMessage(assistantMessage,
                conversationId: uiConversationId),
            logger: _logDegrade,
          );
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
        } catch (error, stackTrace) {
          // 在错误处理里标记任务失败又失败：任务会停在「运行中」，必须留痕。
          NexusGuard.degradeCaught('chat.markTaskFailed', error, stackTrace,
              logger: _logDegrade);
        }
      }
      if (runGeneration != 0 &&
          _runs.ownsRunUnbound(runGeneration, uiConversationId)) {
        state = state.copyWith(
          running: false,
          paused: false,
          clearLiveReply: true,
          clearRunProgress: true,
        );
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
    required ToolApprovalCallback approveTool,
  }) async {
    final context = _runs.budgetPauseContext;
    if (context == null || context.isEmpty || state.running || state.loading) {
      return;
    }
    final database = await ref.read(databaseProvider.future);
    final conversationId = state.conversationId;
    final runGeneration = _runs.beginRun();
    _invalidateContextRuns(clearState: true);
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
            id: UniqueId.generate('message'),
            role: MessageRole.assistant,
            parts: const [MessagePart.text('')]),
      ],
      running: true,
      paused: false,
      runProgress: ChatRunProgress.started(),
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
          id: UniqueId.generate('message'),
          role: MessageRole.assistant,
          parts: [MessagePart.text(formatErrorForMessage(error.toString()))],
        );
        state = _withMessageAt(state, assistantIndex, failed).copyWith(
          running: false,
          clearLiveReply: true,
          clearRunProgress: true,
        );
        // 会话历史是用户数据：写库失败必须留痕，否则这条失败消息会静默消失。
        await NexusGuard.degradeAsync<void>(
          'chat.persistFailedReply',
          () => _persistMessage(failed),
          logger: _logDegrade,
        );
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

  Future<String?> pickWorkspace() async {
    final service = ref.read(workspaceServiceProvider);
    final path = await service.pickDirectory();
    if (path != null) {
      await bindDirectoryAsProject(path);
    }
    return path;
  }

  Future<void> setWorkspace(String? path) async {
    final service = ref.read(workspaceServiceProvider);
    await service.setActiveWorkspace(path);
    state = state.copyWith(
      currentWorkspacePath: path,
      clearWorkspace: path == null,
      clearProject: path == null,
    );
  }

  Future<void> bindDirectoryAsProject(String path) async {
    final database = await ref.read(databaseProvider.future);
    final projectService = ProjectService(
      db: database,
      workspace: ref.read(workspaceServiceProvider),
    );
    final project = await projectService.importDirectory(
      ImportDirectoryRequest(directoryPath: path),
    );
    await openProject(project);
  }

  Future<void> openProject(Project project) async {
    final database = await ref.read(databaseProvider.future);
    final projectService = ProjectService(
      db: database,
      workspace: ref.read(workspaceServiceProvider),
    );
    final opened = await projectService.open(project.id);
    await _applyOpenedProject(opened.project, bindConversation: true);
    if (!opened.accessible) {
      throw ProjectException(opened.missingReason ?? '原目录不可访问，请重新定位项目路径');
    }
  }

  Future<void> clearProjectBinding() async {
    await setWorkspace(null);
  }

  Future<void> _hydrateActiveProject(
      AppDatabase database, Conversation conversation) async {
    // 由 _initialize 以 unawaited 分离调用，启动早期就可能撞上容器销毁。
    if (!_mounted) return;
    try {
      final projectService = ProjectService(
        db: database,
        workspace: _ref.read(workspaceServiceProvider),
      );
      await projectService.migrateLegacyWorkspaces();
      if (!_mounted) return;
      Project? project;
      if (conversation.projectId != null &&
          conversation.projectId!.isNotEmpty) {
        project = await database.findProject(conversation.projectId!);
      }
      project ??= await projectService.activeProject();
      if (project == null) return;
      if (!_mounted) return;
      await _applyOpenedProject(project, bindConversation: false);
    } catch (error, stackTrace) {
      // 启动时恢复项目失败：界面退化为「未选择项目」，原因要可查。
      NexusGuard.degradeCaught('chat.openActiveProject', error, stackTrace,
          logger: _logDegrade);
    }
  }

  Future<void> _applyOpenedProject(
    Project project, {
    required bool bindConversation,
  }) async {
    if (!_mounted) return;
    state = state.copyWith(
      currentWorkspacePath: project.canonicalRootPath,
      currentProjectId: project.id,
      currentProjectName: project.name,
    );
    if (!bindConversation) return;
    final conversationId = state.conversationId;
    if (conversationId == null) return;
    try {
      final database = await _ref.read(databaseProvider.future);
      final conversation = await database.findConversation(conversationId);
      if (conversation == null) return;
      await database.saveConversation(conversation.copyWith(
        projectId: Value(project.id),
        updatedAt: DateTime.now(),
      ));
    } catch (error, stackTrace) {
      NexusGuard.degradeCaught(
          'chat.bindConversationProject', error, stackTrace,
          logger: _logDegrade);
    }
  }

  void setPlanMode(bool value) {
    setMode(value
        ? ChatMode.plan
        : (state.mode == ChatMode.plan ? ChatMode.chat : state.mode));
  }

  /// Switches the user-facing execution mode. Mode changes are intentionally
  /// blocked while a run is active so a request keeps one stable tool policy.
  void setMode(ChatMode mode) {
    if (state.running) return;
    state = state.copyWith(
      mode: mode,
      planMode: mode == ChatMode.plan,
      clearPlanState: true,
    );
  }

  void setApprovalMode(ApprovalMode mode) {
    state = state.copyWith(approvalMode: mode);
  }

  Future<void> setReasoningMode(ReasoningMode mode) async {
    state = state.copyWith(reasoningMode: mode);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('settings.llm.reasoning_mode', mode.name);
      // Retain a compatible value for older settings/export paths.
      await preferences.setBool(
          'settings.llm.deep_reasoning', mode != ReasoningMode.standard);
    } catch (error, stackTrace) {
      // state 已更新但没落盘：界面显示已切换，重启后会退回旧值。
      NexusGuard.degradeCaught('chat.saveReasoningMode', error, stackTrace,
          logger: _logDegrade);
    }
  }

  Future<void> setWebSearchEnabled(bool value) async {
    state = state.copyWith(webSearchEnabled: value);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool('settings.tool.web_browsing', value);
    } catch (error, stackTrace) {
      // 同 saveReasoningMode：开关看起来生效了，重启后却会回退。
      NexusGuard.degradeCaught('chat.saveWebSearchEnabled', error, stackTrace,
          logger: _logDegrade);
    }
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

  /// sub_agent 工具回调：走统一后台入口执行一个子任务。
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
    } catch (error, stackTrace) {
      // 取不到 Agent 的自定义系统提示词：会用默认提示词，回答风格会不一致。
      NexusGuard.degradeCaught('chat.loadAgentPrompt', error, stackTrace,
          logger: _logDegrade);
    }
    try {
      final database = await ref.read(databaseProvider.future);
      final store = ref.read(providerConfigStoreProvider);
      final config = await store.load();
      return (await BackgroundExecutionGateway().run(
        db: database,
        config: config,
        prompt: prompt,
        systemPrompt: systemPrompt,
        maxTokens: SubAgentTool.clampBudget(budget),
      ))
          .text;
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
        '- 通过 maxTokens 为每个子任务分配受限预算（上限 ${SubAgentTool.maxBudget}），不要超预算；委派后应核实并汇总结果。';
  }

  /// 工作区与工具可用性注入：注册表里文件/终端工具是否存在由工作区绑定和
  /// 「设置 → 工具」开关共同决定。没有这些工具时模型倾向于回答“设备没有
  /// 终端/无法编译”——必须显式告知真实原因并引导用户开启，而不是让模型
  /// 替设备下“无能力”的结论（真实案例：模型因未选工作区而拒做手机开发任务）。
  static String workspaceToolRules({
    String? workspacePath,
    required bool fileToolsAvailable,
    required bool terminalAvailable,
    ChatMode mode = ChatMode.agent,
  }) {
    final ws = workspacePath?.trim() ?? '';
    if (mode == ChatMode.chat) {
      return '[工作区环境]\n'
          '- 当前会话为“聊天”模式，未装配文件或终端工具；这不是设置或设备能力问题。\n'
          '- 用户要求创建、修改、保存文件或执行构建时，请引导其切换到 Agent 模式并选择项目目录后重试。\n'
          '- 不要要求用户寻找不存在的“文件/终端开关”，也不要编造文件已创建。';
    }
    if (ws.isEmpty) {
      return '[工作区环境]\n'
          '- 当前未选择工作区，文件读写与终端工具未启用。这是应用内配置，不是设备能力缺失。\n'
          '- 若任务需要读写文件或执行命令（编译、脚本、构建等），请先简短告诉用户：'
          '点击聊天页顶栏的工作区入口选择一个项目目录，然后重发任务。\n'
          '- 不要声称设备无法完成，也不要在无工具时编造执行结果。';
    }
    if (!fileToolsAvailable) {
      return '[工作区环境]\n'
          '- 工作区：$ws，但工作区文件工具未启用，相关文件操作不可用。\n'
          '- 若任务需要读写文件，请提示用户到“设置 → 扩展与环境 → 工具列表”开启“允许 Agent 读写当前工作区文件”后再试。';
    }
    if (!terminalAvailable) {
      return '[工作区环境]\n'
          '- 工作区目录：$ws，文件工具可用，可创建、读取和编辑项目文件。\n'
          '- 终端命令当前不可用。静态 HTML/CSS/JS、Markdown 等文件任务仍应直接完成；仅安装依赖、构建或运行命令需要用户开启终端或配置运行环境。';
    }
    return '[工作区环境]\n'
        '- 工作区目录：$ws（文件工具与终端的默认工作目录；仅默认目录，不是完整文件系统沙箱）。\n'
        '- 可用工具：read_file / write_file / edit_file / list_directory / search_files / '
        'move_file / delete_file / terminal。\n'
        '- 终端命令运行在 Android Linux 运行时中（优先内置 Alpine PRoot 环境，回落 Termux 或系统 '
        'shell），可在环境内用 apk 等包管理器安装工具链（需网络）；单条命令默认 120s 超时，'
        '可用 timeoutSeconds 参数放宽。\n'
        '- 手机开发任务（编译、构建、运行脚本）必须基于真实命令输出汇报结果，禁止伪造成功。';
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

  void _detachVisibleRun() {
    if (state.running ||
        state.planState != null ||
        state.toolActivities.isNotEmpty) {
      state = state.copyWith(
        running: false,
        paused: false,
        toolActivities: const [],
        activityLog: const [],
        clearPlanState: true,
        clearLiveReply: true,
        clearRunProgress: true,
      );
    }
  }

  bool get hasBoundDevelopmentRun =>
      _runs.runController != null && !_runs.runController!.isSealed;

  bool get isBoundRunVisible =>
      hasBoundDevelopmentRun && _runs.isVisible(_runs.currentConversationId());

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
        clearRunProgress: true,
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

  /// 任务真正发起前申请通知权限（任务跑完要通知用户），失败静默降级。
  /// 放在控制器里，展示层就不必直接依赖通知基础设施（见 layering_test）。
  Future<void> ensureNotificationPermissionOnce() =>
      NotificationService.instance.ensurePermissionOnce();

  /// 暂停：正在流式输出的模型回复会被立即中断；正在执行的工具先跑完当前
  /// 命令，再停在下一个检查点。这里立刻把 UI 切到暂停态（露出继续/停止），
  /// 避免以前「点了暂停没反应、再点也没用」的问题。
  bool pause() {
    final controller = _runs.runController;
    if (controller == null || !controller.pause()) return false;
    unawaited(_persistControl(TaskControlKind.pause));
    if (_runs.isVisible(state.conversationId)) {
      state = state.copyWith(
        paused: true,
        activityLog: [...state.activityLog, '正在暂停：当前步骤结束后停下'],
      );
    }
    return true;
  }

  /// 恢复已暂停的 Agent；重复恢复保持幂等。
  bool resume() {
    final controller = _runs.runController;
    if (controller == null || !controller.resume()) return false;
    unawaited(_persistControl(TaskControlKind.resume));
    if (_runs.isVisible(state.conversationId)) {
      state = state.copyWith(
        paused: false,
        activityLog: [...state.activityLog, '运行已恢复'],
      );
    }
    return true;
  }

  /// 把补充指令排入当前 turn 边界，不打断正在执行的工具批次。
  bool steer(String text) {
    final controller = _runs.runController;
    if (controller == null || !controller.steer(text)) return false;
    unawaited(_persistControl(
      TaskControlKind.followUp,
      payload: {'text': text},
    ));
    if (_runs.isVisible(state.conversationId)) {
      state = state.copyWith(
        activityLog: [...state.activityLog, '已接收，将在下一检查点生效'],
      );
    }
    return true;
  }

  Future<void> _persistControl(
    TaskControlKind kind, {
    Map<String, dynamic> payload = const {},
  }) async {
    final taskId = _runs.activeTaskId;
    if (taskId == null || taskId.isEmpty) return;
    try {
      final db = await ref.read(databaseProvider.future);
      await DevelopmentExecutionService(db: db).submitControl(
        TaskControlRequest(
          taskId: taskId,
          kind: kind,
          clientControlId: UniqueId.generate('client'),
          runId: _runs.activeRunId,
          payload: payload,
        ),
      );
    } catch (error, stackTrace) {
      // 控制请求没入库：后台执行者收不到这条指令，属于必须留痕的降级。
      NexusGuard.degradeCaught('chat.sendControlRequest', error, stackTrace,
          logger: _logDegrade);
    }
  }

  void stop() {
    _commitLiveReply();
    _cancelRequestedAt = DateTime.now();
    unawaited(_persistControl(TaskControlKind.cancel));
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

  bool approveContextCompression(ContextCompressionPlan plan) {
    if (!state.running || state.loading || !plan.shouldSuggest) return false;
    final runController = _runs.runController;
    if (runController == null) return false;
    final toolCallIds = <String>{};
    for (final candidate in plan.candidates) {
      final toolCallId = candidate.toolCallId;
      if (toolCallId == null || toolCallId.isEmpty) return false;
      toolCallIds.add(toolCallId);
    }
    return runController.queueCompression(toolCallIds);
  }

  // --- 浼氳瘽 / Agent / Provider 操作 ---

  Future<void> newConversation() async {
    _detachVisibleRun();
    _invalidateContextRuns(clearState: true);
    final switchGeneration = ++_conversationSwitchGeneration;
    final newGeneration = _runs.generation;
    state = state.copyWith(restoringConversation: true);
    try {
      final database = await ref.read(databaseProvider.future);
      final conversation = await _createConversation(
        database,
        modeOverride: ChatMode.chat,
      );
      if (newGeneration != _runs.generation) return;
      state = state.copyWith(
        conversationId: conversation.id,
        conversationTitle: conversation.title,
        agentName: '通用助手',
        systemPrompt: '你是一个有帮助的 AI Agent。',
        clearAgentId: true,
        contextReservedOutputTokens: 2048,
        messages: const [],
        toolActivities: const [],
        activityLog: const [],
        liveContextTokens: 0,
        timingSnapshot: TimingSnapshot.empty,
        clearContextSnapshot: true,
        clearContextSteps: true,
        clearContextRuns: true,
        // 步数不落库，新会话即归零。
        totalSteps: 0,
        mode: ChatMode.chat,
        planMode: false,
        clearPlanState: true,
        clearLiveReply: true,
        clearSessionSkillInstructions: true,
      );
      _historyPager.track(const []);
    } finally {
      if (switchGeneration == _conversationSwitchGeneration) {
        state = state.copyWith(restoringConversation: false);
      }
    }
  }

  final _historyPager = ConversationHistoryPager();
  int? _loadingHistoryGeneration;

  Future<List<(Message, int)>> _loadConversationPage(
          AppDatabase database, String conversationId) =>
      database.messagesPage(conversationId,
          limit: ConversationHistoryPager.initialSize);

  void _trackLoadedWindow(List<(Message, int)> page) =>
      _historyPager.track(page);

  // Compatibility for existing callers; the UI consumes the explicit result.
  Future<bool> loadOlderMessages() async =>
      await loadOlderHistory() == HistoryLoadResult.loaded;

  Future<HistoryLoadResult> loadOlderHistory() async {
    final conversationId = state.conversationId;
    final generation = _conversationSwitchGeneration;
    if (conversationId == null ||
        state.running ||
        state.restoringConversation ||
        _loadingHistoryGeneration == generation) return HistoryLoadResult.busy;
    _loadingHistoryGeneration = generation;
    bool current() =>
        _mounted &&
        generation == _conversationSwitchGeneration &&
        state.conversationId == conversationId &&
        !state.running &&
        !state.restoringConversation;
    try {
      final database = await ref.read(databaseProvider.future);
      if (!current()) return HistoryLoadResult.stale;
      final (result, older) =
          await _historyPager.load(database, conversationId, current);
      if (!current()) return HistoryLoadResult.stale;
      if (result != HistoryLoadResult.loaded) return result;
      final restored = _restoreFromMessages(older);
      state = state.copyWith(
        messages: [...restored.$1, ...state.messages],
        toolActivities: [...restored.$2, ...state.toolActivities],
      );
      return HistoryLoadResult.loaded;
    } finally {
      if (_loadingHistoryGeneration == generation)
        _loadingHistoryGeneration = null;
    }
  }

  /// Loads historical context telemetry only when the metrics sheet needs it.
  ///
  /// Switching conversations restores the latest snapshot because that is all
  /// the chat HUD needs. The full run list is comparatively expensive: each run
  /// may contain up to 2,000 events and its metadata must be decoded. Keep that
  /// work off the conversation-switch path and cache it for the current session.
  Future<List<ContextRunHistory>> loadContextRuns() async {
    while (true) {
      final conversationId = state.conversationId;
      if (conversationId == null || conversationId.isEmpty) return const [];
      if (_contextRunsLoadedConversationId == conversationId) {
        return state.contextRuns;
      }

      final revision = _contextRunsRevision;
      final loading = _contextRunsLoading;
      if (_contextRunsLoadingConversationId == conversationId &&
          _contextRunsLoadingRevision == revision &&
          loading != null) {
        await loading;
        if (state.conversationId != conversationId) return const [];
        if (_contextRunsLoadedConversationId == conversationId) {
          return state.contextRuns;
        }
        // The request was invalidated while it was in flight. Retry against
        // the current revision instead of returning stale telemetry.
        continue;
      }

      final request = () async {
        final database = await ref.read(databaseProvider.future);
        final histories = await ContextInsightsHistory.recentForConversation(
          database,
          conversationId,
        );
        if (state.conversationId == conversationId &&
            revision == _contextRunsRevision) {
          _contextRunsLoadedConversationId = conversationId;
          state = state.copyWith(contextRuns: histories);
        }
        return histories;
      }();
      _contextRunsLoadingConversationId = conversationId;
      _contextRunsLoadingRevision = revision;
      _contextRunsLoading = request;
      try {
        await request;
      } finally {
        if (identical(_contextRunsLoading, request)) {
          _contextRunsLoading = null;
          _contextRunsLoadingConversationId = null;
          _contextRunsLoadingRevision = null;
        }
      }
      if (state.conversationId != conversationId) return const [];
      if (_contextRunsLoadedConversationId == conversationId) {
        return state.contextRuns;
      }
      // A new run or conversation switch invalidated this request. Loop once
      // more so callers never receive the obsolete result from this attempt.
    }
  }

  void _invalidateContextRuns({bool clearState = false}) {
    _contextRunsRevision++;
    _contextRunsLoadedConversationId = null;
    if (clearState) {
      state = state.copyWith(clearContextRuns: true);
    }
  }

  Future<void> switchConversation(Conversation conversation) async {
    _detachVisibleRun();
    _invalidateContextRuns(clearState: true);
    final switchGeneration = ++_conversationSwitchGeneration;
    final runGeneration = _runs.generation;
    state = state.copyWith(restoringConversation: true);
    try {
      final database = await ref.read(databaseProvider.future);
      final storedPage = await _loadConversationPage(database, conversation.id);
      final stored = storedPage.map((e) => e.$1).toList();
      if (switchGeneration != _conversationSwitchGeneration ||
          runGeneration != _runs.generation) return;
      _trackLoadedWindow(storedPage);
      var agentName = '通用助手';
      var systemPrompt = '你是一个有帮助的 AI Agent。';
      final agentId = conversation.agentId;
      var reservedOutputTokens = 2048;
      if (agentId != null) {
        final agent = await database.findAgent(agentId);
        if (agent != null) {
          agentName = agent.name;
          systemPrompt = agent.systemPrompt;
          reservedOutputTokens = agent.maxTokens;
        }
      }
      if (switchGeneration != _conversationSwitchGeneration ||
          runGeneration != _runs.generation) return;
      final restored = _restoreFromMessages(stored);
      // 会话切换只需要恢复最新一轮的上下文快照；完整历史由上下文面板按需加载。
      // 不要在这里读取最近 12 个 run 的全部事件，否则一次切换最坏会解码约
      // 24,000 条事件，拖慢中低端设备上的首屏恢复。
      final contextSteps = await ContextInsightsHistory.latestForConversation(
        database,
        conversation.id,
      );
      if (switchGeneration != _conversationSwitchGeneration ||
          runGeneration != _runs.generation) return;
      final latestSnapshot =
          contextSteps.isEmpty ? null : contextSteps.last.snapshot;
      final restoredMessageTokens = restored.$1.fold<int>(
          0, (sum, message) => sum + ContextWindow.estimateTokens(message));
      String? workspacePath = state.currentWorkspacePath;
      String? projectId = conversation.projectId ?? state.currentProjectId;
      String? projectName = state.currentProjectName;
      if (conversation.projectId != null &&
          conversation.projectId!.isNotEmpty) {
        try {
          final project = await database.findProject(conversation.projectId!);
          if (project != null) {
            projectId = project.id;
            projectName = project.name;
            workspacePath = project.canonicalRootPath;
          }
        } catch (error, stackTrace) {
          NexusGuard.degradeCaught(
              'chat.resolveConversationProject', error, stackTrace,
              logger: _logDegrade);
        }
      }
      state = state.copyWith(
        conversationId: conversation.id,
        conversationTitle: conversation.title,
        agentId: agentId,
        currentProjectId: projectId,
        currentProjectName: projectName,
        currentWorkspacePath: workspacePath,
        agentName: agentName,
        systemPrompt: systemPrompt,
        messages: restored.$1,
        toolActivities: restored.$2,
        activityLog: const [],
        contextReservedOutputTokens: reservedOutputTokens,
        liveContextTokens: latestSnapshot?.usedTokens ?? restoredMessageTokens,
        timingSnapshot: TimingSnapshot.empty,
        contextSteps: contextSteps,
        clearContextRuns: true,
        contextSnapshot: latestSnapshot,
        // 步数（agent 循环迭代数）未持久化，切回历史会话时从 0 重新累计。
        totalSteps: 0,
        mode: conversation.agentId == null ? ChatMode.chat : ChatMode.agent,
        planMode: false,
        clearAgentId: agentId == null,
        clearPlanState: true,
        clearLiveReply: true,
        clearSessionSkillInstructions: true,
      );
      _restoreVisibleRunIfNeeded(conversation.id);
    } finally {
      if (switchGeneration == _conversationSwitchGeneration) {
        state = state.copyWith(restoringConversation: false);
      }
    }
  }

  Future<TaskHandle> enqueueRepairFollowUp({
    required String prompt,
    String taskType = 'bug_fix',
    String? requestId,
  }) async {
    final database = await ref.read(databaseProvider.future);
    final conversationId =
        state.conversationId ?? (await _createConversation(database)).id;
    final handle = await DevelopmentExecutionService(db: database).enqueue(
      DevelopmentTaskRequest(
        prompt: prompt,
        conversationId: conversationId,
        projectId: state.currentProjectId,
        workspacePath: state.currentWorkspacePath,
        taskType: taskType,
        sourceType: 'verification_repair',
        requestId: requestId,
      ),
    );
    state = state.copyWith(currentTaskId: handle.taskId);
    return handle;
  }

  Future<Conversation> forkFromMessage(int messageIndex,
      {String? messageId, String? expectedConversationId}) async {
    final conversationId = state.conversationId;
    final generation = _conversationSwitchGeneration;
    if (conversationId == null ||
        state.running ||
        state.restoringConversation ||
        (expectedConversationId != null &&
            expectedConversationId != conversationId)) {
      throw StateError('会话已变化或正在运行');
    }
    if (messageId != null) {
      messageIndex =
          state.messages.indexWhere((message) => message.id == messageId);
    }
    if (messageIndex < 0 || messageIndex >= state.messages.length) {
      throw StateError('找不到分叉消息');
    }
    final anchor = state.messages[messageIndex].id;
    if (anchor == null) throw StateError('消息尚未保存');
    final database = await ref.read(databaseProvider.future);
    if (!_mounted ||
        generation != _conversationSwitchGeneration ||
        state.running) {
      throw StateError('会话已变化或正在运行');
    }
    final branch = await const ConversationForkService().fork(
        db: database,
        sourceConversationId: conversationId,
        forkMessageId: anchor);
    if (_mounted &&
        generation == _conversationSwitchGeneration &&
        !state.running) {
      await switchConversation(branch);
    }
    return branch;
  }

  void _restoreVisibleRunIfNeeded(String conversationId) {
    if (!hasBoundDevelopmentRun) return;
    if (_runs.boundConversationId != conversationId) return;
    if (!_runs.isVisible(conversationId)) return;
    state = state.copyWith(
      running: true,
      paused: _runs.runController?.isPaused ?? false,
      currentTaskId: _runs.activeTaskId,
      currentRunId: _runs.activeRunId,
    );
  }

  Future<void> selectAgent(Agent agent) async {
    state = state.copyWith(
        agentId: agent.id,
        agentName: agent.name,
        systemPrompt: agent.systemPrompt,
        contextReservedOutputTokens: agent.maxTokens,
        mode: ChatMode.agent,
        planMode: false,
        clearPlanState: true);
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
    } catch (error, stackTrace) {
      // 读不到当前工作区：切换 Provider 后工作区规则会退化为「未选择工作区」。
      NexusGuard.degradeCaught('chat.readActiveWorkspace', error, stackTrace,
          logger: _logDegrade);
    }
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
    messages[index] =
        message.id == null ? message.copyWith(id: messages[index].id) : message;
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
    bool? compressed,
    String? originalResult,
    bool? ok,
    String? code,
    ToolEffect? effect,
  }) {
    return activities
        .map((a) => a.call.id == callId
            ? a.copyWith(
                status: status,
                result: result,
                compressed: compressed,
                originalResult: originalResult,
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
