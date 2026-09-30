part of 'chat_page.dart';

/// 底部面板：聊天模式、推理模式、会话指标、会话配置、模型切换、头像菜单、审批模式与智能体选择。
extension _ChatSheets on _ChatPageState {
  Future<void> _showChatModeSheet() async {
    final state = ref.read(chatControllerProvider);
    if (state.running) {
      FloatingToast.show(context, '运行中不能切换模式', tone: ToastTone.warning);
      return;
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selected = await showNexusSheet<ChatMode>(
      context: context,
      maxHeightRatio: 0.32,
      builder: (sheetContext) {
        final activeColor = AppPalette.brand;
        final surface =
            isDark ? AppPalette.darkSurface : AppPalette.lightSurface;
        final hairline =
            isDark ? AppPalette.darkHairline : AppPalette.lightHairline;
        final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
        final textMuted =
            isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    '切换模式 (Mode)',
                    style: TextStyle(
                      fontSize: AppTokens.fontSizeBody,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: activeColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    state.mode.label,
                    style: TextStyle(
                      fontSize: AppTokens.fontSizeFootnote,
                      fontWeight: FontWeight.w500,
                      color: activeColor,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '关闭',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: AppTokens.kMinTouchTarget,
                      minHeight: AppTokens.kMinTouchTarget,
                    ),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: textMuted,
                    ),
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final mode in ChatMode.values) ...[
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.pop(sheetContext, mode),
                        child: AnimatedContainer(
                          duration: NexusMotion.durationFast(sheetContext),
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 8),
                          decoration: BoxDecoration(
                            color: mode == state.mode
                                ? activeColor.withValues(
                                    alpha: isDark ? 0.2 : 0.12)
                                : surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color:
                                  mode == state.mode ? activeColor : hairline,
                              width: mode == state.mode ? 1.5 : 1.0,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _ChatPageState._chatModeIcon(mode),
                                size: 20,
                                color: mode == state.mode
                                    ? activeColor
                                    : textColor,
                              ),
                              const SizedBox(height: 5),
                              Text(
                                mode.label,
                                style: TextStyle(
                                  fontSize: AppTokens.fontSizeCaption,
                                  fontWeight: mode == state.mode
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: mode == state.mode
                                      ? activeColor
                                      : textColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (mode != ChatMode.values.last) const SizedBox(width: 8),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || selected == null || selected == state.mode) return;
    _chat.setMode(selected);
    unawaited(HapticFeedback.selectionClick());
    FloatingToast.show(context, '已切换到${selected.label}模式');
  }

  Future<void> _showReasoningModeSheet() async {
    final state = ref.read(chatControllerProvider);
    final selected = await showNexusActionSheet<ReasoningMode>(
      context: context,
      title: '思考模式',
      subtitle: '标准适合普通对话；深度适合复杂任务；自动按任务调整',
      items: [
        for (final mode in ReasoningMode.values)
          ActionSheetItem<ReasoningMode>(
            icon: switch (mode) {
              ReasoningMode.standard => Icons.bolt_outlined,
              ReasoningMode.deep => Icons.psychology_outlined,
              ReasoningMode.auto => Icons.auto_awesome_outlined,
            },
            title: mode.label,
            subtitle: mode.description,
            value: mode,
            selected: mode == state.reasoningMode,
          ),
      ],
    );
    if (selected == null || !mounted || selected == state.reasoningMode) return;
    await _chat.setReasoningMode(selected);
    if (mounted) FloatingToast.show(context, '思考模式已设为「${selected.label}」');
  }

  Future<void> _openSessionMetricsSheet() async {
    final requestedConversationId =
        ref.read(chatControllerProvider).conversationId;
    if (requestedConversationId == null) return;
    try {
      await _chat.loadContextRuns();
    } catch (_) {
      // 历史遥测只是诊断增强；加载失败不应阻断指标面板。
    }
    if (!mounted) return;
    final current = ref.read(chatControllerProvider);
    if (current.conversationId != requestedConversationId) return;
    final metrics = SessionMetrics.from(
      messages: current.messages,
      steps: current.totalSteps,
      toolExecutionMs: current.toolActivities.fold<int>(
        0,
        (sum, activity) => sum + activity.executionMs,
      ),
    );
    if (metrics.isEmpty) return;
    await showSessionMetricsSheet(
      context,
      metrics: metrics,
      messages: current.messages,
      onCompress: current.running
          ? (plan) {
              Navigator.of(context).pop();
              final accepted = _chat.approveContextCompression(plan);
              if (mounted) {
                FloatingToast.show(
                  context,
                  accepted ? '已确认压缩，将在下一次模型请求前应用' : '当前运行状态不允许压缩',
                  tone: accepted ? ToastTone.success : ToastTone.warning,
                );
              }
            }
          : null,
      liveContextTokens: current.liveContextTokens,
      contextLimit: current.contextTokens,
      reservedOutputTokens: current.contextReservedOutputTokens,
      contextSnapshot: current.contextSnapshot,
      contextSteps: current.contextSteps,
      contextRuns: current.contextRuns,
      timing: current.timingSnapshot,
      toolActivities: current.toolActivities,
      runLabel: current.runProgress?.label ??
          (current.running ? '运行中' : '空闲 · 结果见消息'),
      onJumpToMessage: (messageId) {
        Navigator.of(context).pop();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _messageListKey.currentState?.scrollToMessageId(messageId);
        });
      },
    );
  }

  /// HUD 快捷压缩入口。
  ///
  /// 与指标面板共用同一套候选规划（[ContextCompressionPlanner.planForConversation]），
  /// 只把「打开面板 → 切页签 → 找到建议 → 确认」四步压成一次确认。
  ///
  /// 压缩只作用于发给模型的上下文，用户可见的会话记录保持不变；批准后由当前
  /// 运行在**下一次模型请求前**应用，因此不在运行中时直接拒绝并提示。
  Future<void> _requestContextCompression() async {
    final current = ref.read(chatControllerProvider);
    if (!current.running) {
      FloatingToast.show(
        context,
        '当前运行状态不允许压缩',
        tone: ToastTone.warning,
      );
      return;
    }
    final snapshot = current.contextSnapshot;
    final plan = const ContextCompressionPlanner().planForConversation(
      messages: current.messages,
      liveToolResults: [
        for (final activity in current.toolActivities)
          if (activity.result != null)
            ToolResultRef(
              toolCallId: activity.call.id,
              result: activity.result!,
            ),
      ],
      contextWindow: snapshot?.contextWindow ?? current.contextTokens,
      fixedTokens: snapshot?.tokensFor(ContextPartType.tools) ?? 0,
      reservedOutputTokens:
          snapshot?.reservedOutputTokens ?? current.contextReservedOutputTokens,
    );
    if (!plan.shouldSuggest) {
      FloatingToast.show(
        context,
        '暂无可压缩的工具结果',
        tone: ToastTone.warning,
      );
      return;
    }
    final confirmed = await showConfirmAction(
      context,
      title: '压缩上下文',
      message: '将较早的 ${plan.candidates.length} 条工具结果替换为占位摘要。'
          '只影响发给模型的上下文，聊天记录保持不变。',
      bulletItems: [
        '当前输入 ≈${formatCompact(plan.currentTokens)} tok',
        '预计节省 ≈${formatCompact(plan.estimatedSavings)} tok',
        '压缩后 ≈${formatCompact(plan.projectedTokens)} tok'
            '（目标 ≈${formatCompact(plan.targetTokens)} tok）',
        '将在下一次模型请求前生效',
      ],
      confirmLabel: '压缩',
      cancelLabel: '取消',
      isDanger: false,
    );
    if (!confirmed || !mounted) return;
    final accepted = _chat.approveContextCompression(plan);
    if (!mounted) return;
    FloatingToast.show(
      context,
      accepted ? '已确认压缩，将在下一次模型请求前应用' : '当前运行状态不允许压缩',
      tone: accepted ? ToastTone.success : ToastTone.warning,
    );
  }

  /// 统一会话上下文面板：模型/Agent/工作区/思考程度/计划模式一处调整。
  void _showSessionConfiguration() {
    showNexusSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) => SessionConfigurationSheet(
          state: ref.watch(chatControllerProvider),
          onSelectModel: () {
            Navigator.pop(sheetContext);
            _switchProvider();
          },
          onSelectAgent: () {
            Navigator.pop(sheetContext);
            _selectAgent();
          },
          onPickWorkspace: () {
            Navigator.pop(sheetContext);
            _pickWorkspace();
          },
          onClearWorkspace: () {
            ref.read(chatControllerProvider.notifier).setWorkspace(null);
            Navigator.pop(sheetContext);
            FloatingToast.show(context, '已解绑工作区', tone: ToastTone.success);
          },
          onSelectReasoningMode: () {
            Navigator.pop(sheetContext);
            _showReasoningModeSheet();
          },
          onToggleWebSearch: (enabled) {
            _chat.setWebSearchEnabled(enabled);
          },
          onTogglePlanMode: () {
            ref
                .read(chatControllerProvider.notifier)
                .setPlanMode(!ref.read(chatControllerProvider).planMode);
          },
          onSelectMode: () {
            Navigator.pop(sheetContext);
            _showChatModeSheet();
          },
        ),
      ),
    );
  }

  Future<void> _switchProvider() async {
    final store = ref.read(providerConfigStoreProvider);
    final state = ref.read(chatControllerProvider);
    final currentId = state.activeProviderId;
    final profiles = await store.loadAll();
    if (!mounted) return;
    final selected = await showNexusSheet<ModelPickerSelection>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ModelPickerSheet(
        profiles: profiles,
        selectedId: currentId,
        reasoningEffort: state.activeReasoningEffort,
        planMode: state.planMode,
        mode: state.mode,
        onOpenSettings: () {
          Navigator.of(context).pop();
          _openModelConfig();
        },
        onOpenTools: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(
              NexusPageRoute.detail(builder: (_) => const McpServersPage()));
        },
      ),
    );
    if (selected == null || !mounted) return;
    await _chat.switchProvider(selected.profile);
    if (selected.mode != state.mode) {
      _chat.setMode(selected.mode);
    }
    if (mounted) {
      FloatingToast.show(
          context, '已切换到 ${selected.profile.name} / ${selected.profile.model}');
    }
  }

  void _showAvatarMenu() {
    final state = ref.read(chatControllerProvider);
    showNexusActionSheet<void>(
      context: context,
      title: '更多操作',
      scrollable: true,
      items: [
        const ActionSheetItem.section('当前会话'),
        ActionSheetItem(
          icon: Icons.tune_rounded,
          title: '会话上下文',
          onTap: _showSessionConfiguration,
        ),
        ActionSheetItem(
          icon: Icons.tune,
          title: AppStrings.switchModel,
          onTap: _switchProvider,
        ),
        ActionSheetItem(
          icon: Icons.refresh,
          title: AppStrings.regenerate,
          enabled: !state.running &&
              state.messages.isNotEmpty &&
              state.messages.last.role == MessageRole.assistant,
          onTap: _regenerate,
        ),
        ActionSheetItem(
          icon: Icons.content_copy_outlined,
          title: AppStrings.copyConversation,
          enabled: state.messages.isNotEmpty,
          onTap: _copyConversation,
        ),
        ActionSheetItem(
          icon: Icons.ios_share,
          title: AppStrings.exportMarkdown,
          enabled: state.messages.isNotEmpty,
          onTap: _exportConversation,
        ),
        ActionSheetItem(
          icon: Icons.share_outlined,
          title: '分享会话',
          enabled: state.messages.isNotEmpty,
          onTap: _shareConversation,
        ),
        const ActionSheetItem.section('工作台'),
        ActionSheetItem(
          icon: Icons.space_dashboard_outlined,
          title: '会话工作台',
          subtitle: '本会话改动的文件、每轮结果与运行状态',
          enabled: state.messages.isNotEmpty || state.toolActivities.isNotEmpty,
          onTap: () => Navigator.of(context).push(
            NexusPageRoute.detail(builder: (_) => const SessionWorkbenchPage()),
          ),
        ),
        ActionSheetItem(
          icon: Icons.task_alt_outlined,
          title: '开发任务',
          subtitle: '查看任务状态、结果与恢复记录',
          onTap: () {
            Navigator.of(context).push(
              NexusPageRoute.detail(
                builder: (_) => DevelopmentTasksPage(
                  onConversationSelected: (conversation) async {
                    Navigator.of(context).pop();
                    await _switchConversation(conversation);
                  },
                ),
              ),
            );
          },
        ),
        ActionSheetItem(
          icon: Icons.account_tree_outlined,
          title: '项目',
          subtitle: '新建、导入或打开开发项目',
          onTap: _openProjectPicker,
        ),
        ActionSheetItem(
          icon: Icons.build_circle_outlined,
          title: '开发工作台',
          subtitle: '一键执行构建模板并查看产物校验和',
          onTap: () async {
            final chat = ref.read(chatControllerProvider);
            final workspace = chat.currentWorkspacePath;
            if (workspace == null || workspace.isEmpty) {
              if (mounted) {
                FloatingToast.show(context, '请先选择项目', tone: ToastTone.warning);
              }
              return;
            }
            await Navigator.of(context).push(NexusPageRoute.workspace(
              builder: (_) => DevelopmentWorkbenchPage(
                workspacePath: workspace,
                projectId: chat.currentProjectId,
              ),
            ));
          },
        ),
        ActionSheetItem(
          icon: Icons.dashboard_outlined,
          title: '仪表盘',
          subtitle: 'Token 消耗、费用指标与运行态',
          onTap: () {
            Navigator.of(context).push(
              NexusPageRoute.detail(builder: (_) => const DashboardPage()),
            );
          },
        ),
      ],
    );
  }

  Future<void> _selectApprovalMode() async {
    final currentMode = ref.read(chatControllerProvider).approvalMode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selected = await showNexusSheet<ApprovalMode>(
      context: context,
      maxHeightRatio: 0.32,
      builder: (sheetContext) {
        final activeColor = AppPalette.brand;
        final surface =
            isDark ? AppPalette.darkSurface : AppPalette.lightSurface;
        final hairline =
            isDark ? AppPalette.darkHairline : AppPalette.lightHairline;
        final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
        final textMuted =
            isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.shield_outlined, size: 18, color: activeColor),
                  const SizedBox(width: 6),
                  Text(
                    '操作权限与安全',
                    style: TextStyle(
                      fontSize: AppTokens.fontSizeBody,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '关闭',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: AppTokens.kMinTouchTarget,
                      minHeight: AppTokens.kMinTouchTarget,
                    ),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: textMuted,
                    ),
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final mode in ApprovalMode.values) ...[
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.pop(sheetContext, mode),
                        child: AnimatedContainer(
                          duration: NexusMotion.durationFast(sheetContext),
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 6),
                          decoration: BoxDecoration(
                            color: mode == currentMode
                                ? activeColor.withValues(
                                    alpha: isDark ? 0.2 : 0.12)
                                : surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color:
                                  mode == currentMode ? activeColor : hairline,
                              width: mode == currentMode ? 1.5 : 1.0,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                mode == ApprovalMode.fullAccess
                                    ? Icons.shield_rounded
                                    : (mode == ApprovalMode.autoSafe
                                        ? Icons.verified_user_rounded
                                        : Icons.help_outline_rounded),
                                size: 20,
                                color: mode == currentMode
                                    ? activeColor
                                    : (mode == ApprovalMode.autoSafe
                                        ? AppPalette.success
                                        : textColor),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                _approvalModeTitle(mode),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: AppTokens.fontSizeFootnote,
                                  fontWeight: mode == currentMode
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: mode == currentMode
                                      ? activeColor
                                      : textColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (mode != ApprovalMode.values.last)
                      const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _approvalModeDescription(currentMode),
                  style: TextStyle(
                    fontSize: AppTokens.fontSizeBadge,
                    color: textMuted,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (selected != null && mounted) {
      ref.read(chatControllerProvider.notifier).setApprovalMode(selected);
      unawaited(HapticFeedback.selectionClick());
    }
  }

  String _approvalModeTitle(ApprovalMode mode) => switch (mode) {
        ApprovalMode.ask => '每次询问',
        ApprovalMode.autoSafe => '自动批准低风险',
        ApprovalMode.fullAccess => '完全访问',
      };

  String _approvalModeDescription(ApprovalMode mode) => switch (mode) {
        ApprovalMode.ask => '敏感操作执行前都需要确认',
        ApprovalMode.autoSafe => '低风险工具自动执行，其余操作按风险确认',
        ApprovalMode.fullAccess => '可授权工具自动执行，危险操作仍需确认',
      };

  /// 把「始终允许 / 本会话允许」的授予写入审计，溯源决策链路。
  /// 注：审批弹窗已收敛到 tool_approval_helper.dart，此处保留审计记录
  /// 供聊天页独有场景（如直接授权后回执）扩展；当前未引用时勿删审计约定。

  Future<void> _selectAgent() async {
    final state = ref.read(chatControllerProvider);
    final database = await ref.read(databaseProvider.future);
    final agents = await database.allAgents(limit: 200);
    if (!mounted) return;
    final selected = await showNexusSheet<Agent>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
                title: Text(AppStrings.selectAgent),
                leading: Icon(Icons.smart_toy_outlined)),
            ...agents.map((agent) => ListTile(
                  leading: CircleAvatar(
                      child: Icon(agent.id == state.agentId
                          ? Icons.check
                          : Icons.smart_toy_outlined)),
                  title: Text(agent.name),
                  subtitle: Text(agent.systemPrompt,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  selected: agent.id == state.agentId,
                  onTap: () => Navigator.pop(context, agent),
                )),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await _chat.selectAgent(selected);
  }
}
