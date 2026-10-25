part of 'chat_controller.dart';

/// 单次工具调用的运行时展示状态类
class ToolActivity {
  const ToolActivity(
      {required this.call,
      required this.risk,
      this.sensitive = false,
      this.status = '等待执行',
      this.result,
      this.compressed = false,
      this.originalResult,
      this.ok,
      this.code,
      this.effect,
      this.executionMs = 0,
      this.runningSince});
  final ToolCall call;
  final ToolRisk risk;
  final bool sensitive;
  final String status;
  final String? result;
  final bool compressed;
  final String? originalResult;
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
    bool? sensitive,
    String? status,
    String? result,
    bool? compressed,
    String? originalResult,
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
      sensitive: sensitive ?? this.sensitive,
      status: nextStatus,
      result: result ?? this.result,
      compressed: compressed ?? this.compressed,
      originalResult: originalResult ?? this.originalResult,
      ok: ok ?? this.ok,
      code: code ?? this.code,
      effect: effect ?? this.effect,
      executionMs: ms,
      runningSince: running,
    );
  }
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
    this.restoringConversation = false,
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
    this.contextTokens = ContextWindow.defaultMaxTokens,
    this.contextReservedOutputTokens = 2048,
    this.liveContextTokens = 0,
    this.contextSnapshot,
    this.contextSteps = const [],
    this.contextRuns = const [],
    this.timingSnapshot = TimingSnapshot.empty,
    this.liveReply,
    this.runProgress,
    this.totalSteps = 0,
    this.activeReasoningEffort = ReasoningEffort.auto,
    this.reasoningMode = ReasoningMode.standard,
    this.webSearchEnabled = false,
    this.providerConfigured = false,
    this.modelServiceStatus = ModelServiceStatus.online,
    this.planMode = false,
    ChatMode? mode,
    this.approvalMode = ApprovalMode.ask,
    this.planState,
    this.currentWorkspacePath,
    this.currentProjectId,
    this.currentProjectName,
    this.currentTaskId,
    this.currentRunId,
    this.pendingCitations = const [],
    this.omittedContext = const [],
    this.successfulRunCount = 0,
  }) : mode = mode ?? (planMode ? ChatMode.plan : ChatMode.chat);

  final List<ChatMessage> messages;
  final bool running;
  final bool paused;
  final bool loading;
  final bool restoringConversation;
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

  /// Output tokens reserved for the next model request. This is kept separate
  /// from [contextTokens], which represents the provider's total window.
  final int contextReservedOutputTokens;

  /// 当前请求的实时上下文估算；流式输出期间也会持续刷新。
  final int liveContextTokens;

  /// The last request-shaped breakdown emitted by [AgentExecutor].
  final ContextSnapshot? contextSnapshot;

  /// Request snapshots from the currently visible Agent run.
  final List<ContextStepRecord> contextSteps;

  /// Telemetry recovered for recent historical runs in this conversation.
  final List<ContextRunHistory> contextRuns;

  /// Cumulative timing for the currently visible Agent run.
  final TimingSnapshot timingSnapshot;
  final LiveReply? liveReply;

  /// 当前可见运行的用户级进度摘要；运行结束后清空，历史消息仍保留结果。
  final ChatRunProgress? runProgress;

  /// 本次会话累计的 agent 循环步数（= 模型调用次数）。
  ///
  /// 由 [ChatController] 在每一次 `RunStatus.waitingModel` 时 +1 —— agent 循环
  /// 每迭代一步都会先进入 waitingModel，因此这个计数精确等于「带工具调用的
  /// agent 循环」的迭代次数，而不是消息条数（一轮对话只落一条最终 assistant 消息）。
  final int totalSteps;
  final ReasoningEffort activeReasoningEffort;
  final ReasoningMode reasoningMode;
  final bool webSearchEnabled;
  final bool providerConfigured;
  final ModelServiceStatus modelServiceStatus;
  final bool planMode;
  final ChatMode mode;
  final ApprovalMode approvalMode;
  final PlanState? planState;
  final String? currentWorkspacePath;
  final String? currentProjectId;
  final String? currentProjectName;
  final String? currentTaskId;
  final String? currentRunId;
  final List<FileCitation> pendingCitations;
  final List<String> omittedContext;

  /// 本会话内「整轮成功完成」的次数，只增不减。UI 据此给出一次成功触感，
  /// 不参与任何业务判断。失败、取消、暂停、异常都不计数。
  final int successfulRunCount;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? running,
    bool? paused,
    bool? loading,
    bool? restoringConversation,
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
    int? contextReservedOutputTokens,
    int? liveContextTokens,
    ContextSnapshot? contextSnapshot,
    List<ContextStepRecord>? contextSteps,
    List<ContextRunHistory>? contextRuns,
    TimingSnapshot? timingSnapshot,
    LiveReply? liveReply,
    ChatRunProgress? runProgress,
    int? totalSteps,
    ReasoningEffort? activeReasoningEffort,
    ReasoningMode? reasoningMode,
    bool? webSearchEnabled,
    bool? providerConfigured,
    ModelServiceStatus? modelServiceStatus,
    bool? planMode,
    ChatMode? mode,
    ApprovalMode? approvalMode,
    PlanState? planState,
    String? currentWorkspacePath,
    String? currentProjectId,
    String? currentProjectName,
    String? currentTaskId,
    String? currentRunId,
    List<FileCitation>? pendingCitations,
    List<String>? omittedContext,
    int? successfulRunCount,
    bool clearWorkspace = false,
    bool clearProject = false,
    bool clearTask = false,
    bool clearConversationId = false,
    bool clearAgentId = false,
    bool clearPlanState = false,
    bool clearLiveReply = false,
    bool clearRunProgress = false,
    bool clearContextSnapshot = false,
    bool clearContextSteps = false,
    bool clearContextRuns = false,
    bool clearSessionSkillInstructions = false,
  }) {
    // Keep the old planMode named argument source-compatible for callers that
    // still use the plan toggle, while making ChatMode the public source of
    // truth for the new three-way selector.
    final nextMode = mode ??
        (planMode == null
            ? this.mode
            : planMode
                ? ChatMode.plan
                : (this.mode == ChatMode.plan ? ChatMode.chat : this.mode));
    final nextPlanMode =
        mode == null ? (planMode ?? this.planMode) : mode == ChatMode.plan;
    return ChatState(
      messages: messages ?? this.messages,
      running: running ?? this.running,
      paused: paused ?? this.paused,
      loading: loading ?? this.loading,
      restoringConversation:
          restoringConversation ?? this.restoringConversation,
      conversationId:
          clearConversationId ? null : (conversationId ?? this.conversationId),
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
      contextReservedOutputTokens:
          contextReservedOutputTokens ?? this.contextReservedOutputTokens,
      liveContextTokens: liveContextTokens ?? this.liveContextTokens,
      contextSnapshot: clearContextSnapshot
          ? null
          : (contextSnapshot ?? this.contextSnapshot),
      contextSteps:
          clearContextSteps ? const [] : (contextSteps ?? this.contextSteps),
      contextRuns:
          clearContextRuns ? const [] : (contextRuns ?? this.contextRuns),
      timingSnapshot: timingSnapshot ?? this.timingSnapshot,
      liveReply: clearLiveReply ? null : (liveReply ?? this.liveReply),
      runProgress: clearRunProgress ? null : (runProgress ?? this.runProgress),
      totalSteps: totalSteps ?? this.totalSteps,
      activeReasoningEffort:
          activeReasoningEffort ?? this.activeReasoningEffort,
      reasoningMode: reasoningMode ?? this.reasoningMode,
      webSearchEnabled: webSearchEnabled ?? this.webSearchEnabled,
      providerConfigured: providerConfigured ?? this.providerConfigured,
      modelServiceStatus: modelServiceStatus ?? this.modelServiceStatus,
      planMode: nextPlanMode,
      mode: nextMode,
      approvalMode: approvalMode ?? this.approvalMode,
      planState: clearPlanState ? null : (planState ?? this.planState),
      currentWorkspacePath: clearWorkspace
          ? null
          : (currentWorkspacePath ?? this.currentWorkspacePath),
      currentProjectId:
          clearProject ? null : (currentProjectId ?? this.currentProjectId),
      currentProjectName:
          clearProject ? null : (currentProjectName ?? this.currentProjectName),
      currentTaskId: clearTask ? null : (currentTaskId ?? this.currentTaskId),
      currentRunId: clearTask ? null : (currentRunId ?? this.currentRunId),
      pendingCitations: pendingCitations ?? this.pendingCitations,
      omittedContext: omittedContext ?? this.omittedContext,
      successfulRunCount: successfulRunCount ?? this.successfulRunCount,
    );
  }
}

/// Chat orchestration controller.
