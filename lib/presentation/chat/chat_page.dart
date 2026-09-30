import '../l10n/app_strings.dart';
import '../widgets/floating_toast.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../application/attachment_policy.dart';
import '../../application/chat_controller.dart';
import '../../application/context_compression_planner.dart';
import '../../application/draft_service.dart';
import '../../application/error_humanizer.dart';
import '../../application/file_citation.dart';
import '../../application/project_context_service.dart';
import '../../application/app_lock_service.dart';
import '../../application/providers.dart';
import '../../application/task_service.dart';
import '../../domain/attachment_file.dart';
import '../../domain/unique_id.dart';
import '../../domain/context_insights.dart';
import '../../application/workspace_service.dart';
import '../../application/skill_intent_matcher.dart';
import '../../application/skill_catalog.dart';
import '../../application/tts_text.dart';
import '../../domain/sensitive_tool_policy.dart';
import '../../domain/models.dart';
import '../../domain/session_metrics.dart';
import '../../domain/tool_result.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/skills/skill_parser.dart';
import '../../infrastructure/tts/tts_service.dart';
import '../../infrastructure/files/conversation_exporter.dart';
import '../../infrastructure/share/deep_link_service.dart';
import '../../infrastructure/share/sharing_service.dart';
import '../../infrastructure/notifications/notification_intent.dart';
import '../agents/agents_page.dart';
import '../dashboard/dashboard_page.dart';
import '../dashboard/widgets/token_numbers.dart';
import '../history/history_page.dart';
import '../tasks/development_tasks_page.dart';
import '../tasks/task_details_page.dart';
import '../memory/memory_page.dart';
import '../mcp/mcp_servers_page.dart';
import '../widgets/image_cache_policy.dart';
import '../prompts/prompt_library_page.dart';
import 'widgets/plan_panel.dart';
import '../settings/provider_list_page.dart';
import '../settings/device_automation_page.dart';
import '../settings/settings_page.dart';
import 'chat_layout_controller.dart';
import 'chat_scroll_coordinator.dart';
import 'composer_skill_slot.dart';
import 'skill_suggestion_rules.dart';
import 'slash_skill_query.dart';
import '../workspace/file_tree_sheet.dart';
import '../workspace/development_workbench_page.dart';
import '../projects/project_home_page.dart';
import '../projects/project_picker_page.dart';
import '../utils/keyboard_insets.dart';
import '../utils/keyboard_avoider.dart';

import 'widgets/floating_capsule_input.dart';
import 'widgets/chat_execution_stage.dart';
import 'widgets/attachment_drawer_panel.dart';
import 'widgets/session_metrics_bar.dart';
import 'widgets/provider_setup_hint.dart';
import 'widgets/composer_skill_slot.dart';
import 'widgets/session_metrics_sheet.dart';
import '../../../infrastructure/background_service.dart';
import 'widgets/session_configuration_sheet.dart';
import 'widgets/capsule_top_bar.dart';
import 'widgets/chat_empty_state.dart';
import 'widgets/chat_message_list.dart';
import 'widgets/conversation_restore_skeleton.dart';
import 'widgets/model_picker_sheet.dart';
import 'widgets/tool_activity_section.dart';
import 'widgets/skill_suggestion_bar.dart';
import 'widgets/chat_catalog_drawer.dart';
import '../widgets/nexus_sheet.dart';
import '../widgets/nexus_action_sheet.dart';
import '../widgets/confirm_action.dart';
import '../widgets/nexus_surface.dart';
import '../widgets/nexus_disclosure.dart';
import '../widgets/nexus_status_pill.dart';
import '../widgets/tool_approval_helper.dart';
import '../motion/motion_preferences.dart';
import '../motion/nexus_haptics.dart';
import '../motion/nexus_motion.dart';
import '../motion/nexus_page_route_factory.dart';
import '../widgets/nexus_loading_skeleton.dart';
import '../widgets/glass_surface_group.dart';
import '../widgets/glass_scroll_edge.dart';
import 'widgets/nexus_back_to_latest_button.dart';
import '../theme/app_appearance_controller.dart';
import '../widgets/liquid_glass.dart';

part 'chat_message_actions.dart';
part 'chat_page_attachments.dart';
part 'chat_page_conversation.dart';
part 'chat_page_intents.dart';
part 'chat_page_sheets.dart';
part 'chat_page_skills.dart';
part 'chat_page_tool_approvals.dart';

/// 两次状态之间是否有一整轮运行成功完成（用于成功触感）。
@visibleForTesting
bool runSucceededBetween(ChatState previous, ChatState next) =>
    next.successfulRunCount > previous.successfulRunCount;

/// 切换会话时是否应停止本页发起的朗读（离开会话后不再继续读上一段）。
@visibleForTesting
bool shouldStopSpeakingOnSwitch(
  ChatState previous,
  ChatState next, {
  required bool speakingHere,
}) =>
    speakingHere && previous.conversationId != next.conversationId;

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage>
    with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  Future<void> _pickWorkspace() async {
    // 与项目页保持一致：不把「所有文件访问权限」挡在目录选择器之前。
    // 只读目录同样允许导入（可浏览、可让模型读代码），授权引导挪到导入后真正
    // 需要写文件时（见 ProjectPickerPage._offerWriteAccess）。
    if (!mounted) return;
    await _openProjectPicker();
  }

  Future<void> _openProjectPicker() async {
    await Navigator.of(context).push(
      NexusPageRoute.workspace(builder: (_) => const ProjectPickerPage()),
    );
  }

  void _handleTopBarWorkspace() {
    final state = ref.read(chatControllerProvider);
    final ws = state.currentWorkspacePath;
    if (ws == null || ws.isEmpty) {
      _openProjectPicker();
      return;
    }
    showNexusActionSheet<void>(
      context: context,
      title: state.currentProjectName ?? '当前项目',
      subtitle: ws,
      items: [
        ActionSheetItem(
          title: '打开项目主页',
          subtitle: '文件、终端、任务和产物',
          icon: Icons.home_outlined,
          onTap: () {
            final id = state.currentProjectId;
            if (id == null) {
              _openProjectPicker();
              return;
            }
            Navigator.of(context).push(NexusPageRoute.workspace(
              builder: (_) => ProjectHomePage(projectId: id),
            ));
          },
        ),
        ActionSheetItem(
          title: '浏览文件树',
          subtitle: '在应用内查看与导航项目目录',
          icon: Icons.folder_open_rounded,
          onTap: _openFileTree,
        ),
        ActionSheetItem(
          title: '切换项目',
          subtitle: '新建、导入或选择已有项目',
          icon: Icons.swap_horiz_rounded,
          onTap: _openProjectPicker,
        ),
        ActionSheetItem(
          title: '解绑当前项目',
          subtitle: '清除绑定，回到普通聊天',
          icon: Icons.link_off_rounded,
          destructive: true,
          onTap: () {
            ref.read(chatControllerProvider.notifier).setWorkspace(null);
            FloatingToast.show(context, '已解绑项目', tone: ToastTone.success);
          },
        ),
      ],
    );
  }

  void _openModelConfig() {
    Navigator.of(context).push(
      NexusPageRoute.settingsPage(builder: (_) => const SettingsPage()),
    );
  }

  Future<void> _configureModel() async {
    await Navigator.of(context).push(
      NexusPageRoute.settingsPage(builder: (_) => const ProviderListPage()),
    );
    if (mounted) await _chat.reloadProviderConfig();
  }

  void _openFileTree() {
    final ws = ref.read(chatControllerProvider).currentWorkspacePath;
    if (ws == null || ws.isEmpty) {
      _pickWorkspace();
      return;
    }
    showNexusSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: FileTreeSheet(
          workspacePath: ws,
          onReselectWorkspace: () =>
              _reselectWorkspaceFromSheet(sheetContext, ws),
          onCiteFile: (relativePath) =>
              unawaited(_citeWorkspaceFile(relativePath)),
        ),
      ),
    );
  }

  /// 文件树面板内的“重新选择工作区”：关面板 → 重新选择 → 目录变化则重开文件树。
  Future<void> _reselectWorkspaceFromSheet(
      BuildContext sheetContext, String oldWs) async {
    Navigator.pop(sheetContext);
    await _pickWorkspace();
    if (!mounted) return;
    final newWs = ref.read(chatControllerProvider).currentWorkspacePath;
    if (newWs != null && newWs.isNotEmpty && newWs != oldWs) {
      _openFileTree();
    }
  }

  final _controller = TextEditingController();
  final _draftService = const DraftService();
  Timer? _draftPersistTimer;
  final _skillStore = SkillStore();
  final _skillMatcher = SkillIntentMatcher();
  final _installedSkills = <_InstalledSkill>[];
  final _loadedSessionSkillIds = <String>{};
  List<_InstalledSkill> _skillSuggestions = const [];
  List<_InstalledSkill> _slashSkillSuggestions = const [];
  Timer? _skillSuggestionDebounce;
  bool _skillSuggestionsDismissed = false;
  static const _dismissedRecoveryTasksKey = 'recovery.dismissed_task_ids';
  bool _providerHintDismissed = false;
  final _attachments = <AttachmentFile>[];
  final ValueNotifier<int> _attachmentsRevision = ValueNotifier(0);
  final ValueNotifier<bool> _hasAttachments = ValueNotifier(false);
  String? _pendingClientRequestId;
  final ValueNotifier<bool> _attachmentPanelExpanded = ValueNotifier(false);
  final _picker = ImagePicker();
  final _scrollController = ScrollController();
  final _messageListKey = GlobalKey<ChatMessageListState>();
  late final ChatScrollCoordinator _scrollIndicator;
  bool _deepLinkScheduled = false;
  bool _handlingDeepLink = false;

  bool _longPressHintShown = false;
  final Map<String, String> _draftsByConversation = <String, String>{};
  StreamSubscription<List<String>>? _shareSub;
  StreamSubscription<NotificationIntent>? _notificationIntentSub;
  StreamSubscription<void>? _skillChangesSub;
  int _skillLoadGeneration = 0;
  String _pendingTaskType = 'general';
  String _pendingSourceType = 'manual';
  final Map<String, Completer<ToolApproval>> _pendingToolApprovals = {};

  /// 处于「文本选择模式」的消息索引（null = 无）。
  /// 正文默认不可选，否则长按会被文本选择器截走、消息菜单永远打不开。
  final ValueNotifier<int?> _selectingMessageIndex = ValueNotifier(null);

  /// M10：正在朗读的消息索引（null = 未朗读）。只驱动气泡上的
  /// 「停止朗读」与声波条，TTS 播放本身仍由 [TtsService] 负责。
  final ValueNotifier<int?> _speakingMessageIndex = ValueNotifier(null);

  void _onTtsSpeakingChanged() {
    if (!TtsService.instance.isSpeaking) _speakingMessageIndex.value = null;
  }

  ChatController get _chat => ref.read(chatControllerProvider.notifier);

  /// 供 part 文件中的扩展调用：`setState` 是 protected，扩展里不能直接调用。
  void _rebuild(VoidCallback fn) => setState(fn);

  void _notifyAttachmentsChanged() {
    _hasAttachments.value = _attachments.isNotEmpty;
    _attachmentsRevision.value++;
  }

  final BackgroundService _backgroundService = BackgroundService();

  @override
  void initState() {
    super.initState();
    TtsService.instance.speakingListenable.addListener(_onTtsSpeakingChanged);
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() {
          _providerHintDismissed =
              prefs.getBool('chat.provider_hint_dismissed') ?? false;
        });
      }
    });
    _controller.addListener(_onSkillInputChanged);
    _controller.addListener(_rememberCurrentDraft);
    WidgetsBinding.instance.addObserver(this);
    _scrollIndicator = ChatScrollCoordinator(_scrollController,
        isRunning: () => ref.read(chatControllerProvider).running,
        adjustDuration: (duration) =>
            MotionPreferences.adjustDuration(context, duration, listen: false));
    _scrollIndicator.reset();
    // 消费冷启动缓冲的分享内容。整批合并成一个会话：相册多选分享 3 张图不该
    // 生成 3 个新会话（此前对每条各调一次 _startNewConversation，异步时序下
    // 前面的会被后面的覆盖，用户最终只看得到最后一张）。
    final pendingShares = SharingService.instance.drainPending();
    if (pendingShares.isNotEmpty) {
      unawaited(_onSharedTexts(pendingShares));
    }
    // 监听热分享（其他 App 分享进来），同样按批次合并。
    _shareSub = SharingService.instance.shares.listen(
      (batch) => unawaited(_onSharedTexts(batch)),
    );
    // 应用锁：启动即触发（若开启）。
    Future.microtask(_maybeLock);
    // C2 断点恢复：启动时检测中断任务并提示继续执行。
    Future.microtask(_checkRecoverableTask);
    // E4 深度链接：冷启动预填 prompt / 打开记忆页。
    DeepLinkService.instance.addListener(_scheduleDeepLinkConsumption);
    _scheduleDeepLinkConsumption();
    // E3 通知点击：先消费冷启动缓冲（应用被点通知拉起时 ChatPage 尚未订阅），
    // 再订阅运行中的实时点击，保证两种路径都能导航到通知所指的会话/任务。
    for (final intent in NotificationIntentRouter.drainPending()) {
      unawaited(_handleNotificationIntent(intent));
    }
    _notificationIntentSub = NotificationIntentRouter.intents.listen((intent) {
      unawaited(_handleNotificationIntent(intent));
    });
    // G1 聊天背景:加载持久化配置到全局通知器。
    _backgroundService.load().then((c) {
      BackgroundService.bgNotifier.value = c;
    });
    _skillChangesSub = SkillCatalog.changes.listen((_) {
      unawaited(_loadInstalledSkills());
    });
    Future.microtask(_loadInstalledSkills);
  }

  static IconData _chatModeIcon(ChatMode mode) => switch (mode) {
        ChatMode.chat => Icons.chat_bubble_outline_rounded,
        ChatMode.agent => Icons.smart_toy_outlined,
        ChatMode.plan => Icons.checklist_rounded,
      };

  static Future<Set<String>> _dismissedRecoveryTaskIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_dismissedRecoveryTasksKey)?.toSet() ??
          <String>{};
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> _dismissRecoveryTask(String taskId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current =
          prefs.getStringList(_dismissedRecoveryTasksKey)?.toList() ??
              <String>[];
      if (!current.contains(taskId)) {
        current.add(taskId);
        await prefs.setStringList(_dismissedRecoveryTasksKey, current);
      }
    } catch (_) {
      // 记录「已忽略的恢复任务」失败只意味着下次打开可能再提一次恢复提示，
      // 属于可接受的重复打扰，不需要打断用户。
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final approval in _pendingToolApprovals.values) {
      if (!approval.isCompleted) approval.complete(ToolApproval.reject);
    }
    _pendingToolApprovals.clear();
    _shareSub?.cancel();
    _notificationIntentSub?.cancel();
    _skillChangesSub?.cancel();
    _skillSuggestionDebounce?.cancel();
    _draftPersistTimer?.cancel();
    _attachmentPanelExpanded.dispose();
    _controller.removeListener(_rememberCurrentDraft);
    _controller.removeListener(_onSkillInputChanged);
    _controller.dispose();
    _scrollIndicator.dispose();
    _scrollController.dispose();
    _selectingMessageIndex.dispose();
    TtsService.instance.speakingListenable
        .removeListener(_onTtsSpeakingChanged);
    _speakingMessageIndex.dispose();
    DeepLinkService.instance.removeListener(_scheduleDeepLinkConsumption);
    _attachmentsRevision.dispose();
    _hasAttachments.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _rememberCurrentDraft();
    }
    if (state == AppLifecycleState.resumed) {
      Future.microtask(_maybeLock);
    }
  }

  Future<bool> _ensureProviderConfigured() async {
    final store = ref.read(providerConfigStoreProvider);
    final config = await store.load();
    if (config.isConfigured) return true;

    if (!mounted) return false;
    final gotoConfig = await showConfirmAction(
      context,
      title: '尚未配置模型服务',
      message: '尚未配置模型服务，先去填入 API Key 或连接本地模型？',
      confirmLabel: '去配置',
      isDanger: false,
    );

    if (gotoConfig && mounted) {
      await Navigator.push(
        context,
        NexusPageRoute.settingsPage(builder: (_) => const ProviderListPage()),
      );
      await _chat.reloadProviderConfig();
      final reloaded = await store.load();
      return reloaded.isConfigured;
    }
    return false;
  }

  Future<void> _send() async {
    final state = ref.read(chatControllerProvider);
    final input = _controller.text.trim();
    // 纯附件（无文本）同样允许发送，与输入框可发送状态一致（文档 7.4）。
    final canSend = input.isNotEmpty || _attachments.isNotEmpty;
    if (!canSend || state.loading) return;
    if (state.running) {
      final accepted = _chat.steer(input);
      if (accepted) {
        _controller.clear();
        _clearCurrentDraft();
        if (mounted) {
          FloatingToast.show(context, '已接收，将在下一检查点生效', tone: ToastTone.success);
        }
      } else if (mounted) {
        FloatingToast.show(context, '任务已结束，请新建后续任务', tone: ToastTone.warning);
      }
      return;
    }

    final text = _resolveSlashSkillReferences(input);
    if (text == null) return;
    if (text.isEmpty && _attachments.isEmpty) {
      FloatingToast.show(context, '已加载 Skill，请补充任务内容', tone: ToastTone.warning);
      return;
    }

    final configured = await _ensureProviderConfigured();
    if (!configured) return;

    // 到这里任务一定会真正发起，是申请通知权限最合适的时机：用户刚给了明确理由
    // （"任务跑完要通知我"），比启动首帧弹窗的授权率更高。失败静默降级。
    unawaited(_chat.ensureNotificationPermissionOnce());

    final requestId = _pendingClientRequestId ?? UniqueId.generate('req');
    _pendingClientRequestId = requestId;
    final attachments = List<AttachmentFile>.of(_attachments);
    final originalText = _controller.text;
    _controller.clear();
    _attachments.clear();
    if (mounted) _notifyAttachmentsChanged();
    final taskType = _pendingTaskType;
    final sourceType = _pendingSourceType;
    _pendingTaskType = 'general';
    _pendingSourceType = 'manual';
    var sendSucceeded = false;
    try {
      await _chat.send(
        text: text,
        attachments: attachments,
        approveTool: _approveTool,
        taskType: taskType,
        sourceType: sourceType,
        clientRequestId: requestId,
      );
      sendSucceeded = true;
      _pendingClientRequestId = null;
      _clearCurrentDraft();
    } catch (_) {
      if (!mounted) return;
      _controller.value = TextEditingValue(
        text: originalText,
        selection: TextSelection.collapsed(offset: originalText.length),
      );
      _attachments
        ..clear()
        ..addAll(attachments);
      _notifyAttachmentsChanged();
      FloatingToast.show(context, '发送失败，输入已保留', tone: ToastTone.warning);
    }
    if (!sendSucceeded && mounted && _controller.text.isEmpty) {
      _controller.value = TextEditingValue(
        text: originalText,
        selection: TextSelection.collapsed(offset: originalText.length),
      );
    }
  }

  void _regenerate() {
    _chat.regenerate(approveTool: _approveTool);
  }

  void _editLatestQuestion() {
    final lastQuestion = ref.read(chatControllerProvider).messages.lastWhere(
        (message) => message.role == MessageRole.user,
        orElse: () => ChatMessage(role: MessageRole.user, parts: const []));
    final text = lastQuestion.text.trim();
    if (text.isEmpty) return;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    FloatingToast.show(context, '已填回上一条问题，可修改后重新发送');
  }

  void _stop() => _chat.stop();

  /// 暂停提示卡的「继续执行」：优先从断点续跑；断点已失效（例如应用重启过）
  /// 时把续跑指令填进输入框，由用户确认发送，不替用户自动发消息。
  void _continueAfterPause() {
    if (_chat.budgetPauseContext?.isNotEmpty ?? false) {
      unawaited(_chat.resumeFromBudgetPause(approveTool: _approveTool));
      return;
    }
    const prompt = '继续完成上一个任务，不要重复已经完成的步骤。';
    _controller.value = const TextEditingValue(
      text: prompt,
      selection: TextSelection.collapsed(offset: prompt.length),
    );
    FloatingToast.show(context, '断点已失效，已填好续跑指令，点发送即可继续');
  }

  void _pause() {
    if (_chat.pause()) return;
    // 没有前台运行控制器（例如后台开发任务）时暂停无法生效，明确告诉用户，
    // 不再表现为「点了没反应」。
    FloatingToast.show(
      context,
      '当前任务暂不支持暂停，长按按钮可停止',
      tone: ToastTone.warning,
    );
  }

  Future<void> _citeWorkspaceFile(String relativePath) async {
    final state = ref.read(chatControllerProvider);
    final workspace = state.currentWorkspacePath;
    final projectId = state.currentProjectId;
    if (workspace == null || projectId == null) return;
    try {
      final citation = await const ProjectContextService().cite(
        projectId: projectId,
        workspacePath: workspace,
        relativePath: relativePath,
      );
      await _chat.addFileCitation(citation);
      if (!mounted) return;
      FloatingToast.show(context, '已引用 ${citation.displayLabel}',
          tone: ToastTone.success);
    } catch (error) {
      if (mounted) {
        FloatingToast.show(context, '引用失败：$error', tone: ToastTone.warning);
      }
    }
  }

  /// 附件数量上限。
  ///
  /// 字节与数量限额的唯一来源是 [attachment_policy.dart]：选择阶段与发送阶段
  /// （`ChatController`）共用同一组常量，不再各自维护一份并靠注释对齐。
  static const int _maxAttachmentCount = maxAttachmentCount;

  /// 单个附件的字节上限。
  static const int _maxAttachmentBytes = maxAttachmentBytes;

  /// 所有附件的总字节预算。
  static const int _maxAttachmentTotalBytes = maxAttachmentTotalBytes;

  Future<void> _openHistory() async {
    final selected = await Navigator.of(context).push<Conversation>(
      NexusPageRoute.detail(builder: (_) => const HistoryPage()),
    );
    if (selected == null || !mounted) return;
    await _switchConversation(selected);
  }

  Future<void> _openPromptLibrary() async {
    final result = await Navigator.of(context).push<PromptApplyResult>(
      NexusPageRoute.detail(builder: (_) => const PromptLibraryPage()),
    );
    if (result == null || !mounted) return;
    if (result.mode == PromptApplyMode.systemPrompt) {
      _chat.setSystemPrompt(result.content);
      FloatingToast.show(context, AppStrings.applyAsSystemPrompt,
          tone: ToastTone.success);
    } else {
      _controller.text = result.content;
      _controller.selection =
          TextSelection.collapsed(offset: result.content.length);
      FloatingToast.show(context, AppStrings.insertedToInput,
          tone: ToastTone.success);
    }
  }

  // --- 渲染 ---

  void _fillSuggestion(QuickAction action) {
    if (action.id == 'select_workspace') {
      _pickWorkspace();
      return;
    }
    _pendingSourceType = 'quick_action';
    _pendingTaskType = _taskTypeForSuggestion(action.label);
    if (_pendingTaskType != 'general') {
      _chat.setMode(ChatMode.agent);
    }
    final state = ref.read(chatControllerProvider);
    final needsWorkspace =
        !(state.currentWorkspacePath?.trim().isNotEmpty ?? false) &&
            (action.label == '解读项目' ||
                action.label == '修复问题' ||
                action.label == '解读工作区');
    if (needsWorkspace) {
      _pickWorkspaceAndFill(action.prompt);
      return;
    }
    _fillInput(action.prompt);
  }

  String _taskTypeForSuggestion(String text) {
    if (text.contains('实现并验证') ||
        text.contains('测试与修复') ||
        text.contains('构建')) {
      return 'implement_and_verify';
    }
    if (text.contains('项目') || text.contains('工作区')) {
      return 'project_analysis';
    }
    if (text.contains('修复') || text.contains('问题')) return 'bug_fix';
    if (text.contains('审查') || text.contains('代码')) return 'code_review';
    if (text.contains('发布')) return 'release_check';
    return 'general';
  }

  Future<void> _pickWorkspaceAndFill(String text) async {
    await ref.read(chatControllerProvider.notifier).pickWorkspace();
    if (!mounted) return;
    _fillInput(text);
  }

  void _fillInput(String text) {
    _controller.text = text;
    final bracketIndex = text.indexOf('「');
    if (bracketIndex >= 0 && text.contains('」')) {
      _controller.selection = TextSelection.collapsed(offset: bracketIndex + 1);
    } else {
      _controller.selection = TextSelection.collapsed(offset: text.length);
    }
  }

  Widget _emptyState(BuildContext context) {
    final state = ref.read(chatControllerProvider);
    final ws = state.currentWorkspacePath;
    final hasWorkspace = ws != null && ws.isNotEmpty;
    final suggestions = <QuickAction>[
      if (!hasWorkspace)
        const QuickAction(id: 'select_workspace', label: '选择项目'),
      const QuickAction(label: '解读项目'),
      const QuickAction(label: '修复问题'),
      const QuickAction(
        label: '头脑风暴',
        prompt: '帮我头脑风暴一下「」的创意方向。要求：先提出 3~5 个角度，再挑一个最有潜力的展开，最后给出下一步行动建议。',
      ),
      const QuickAction(label: '解读工作区'),
    ];
    // 调用处用 Builder 包在 KeyboardInsetScope 之内：isKeyboardVisible 读到的是
    // 按输入焦点门控、订阅变化的有效键盘高度，键盘开合时只重建空态本身。
    // 详见 keyboard_avoider.dart 与 keyboard_insets.dart。
    final keyboardVisible = isKeyboardVisible(context);
    return ChatEmptyState(
      suggestions: suggestions,
      hasWorkspace: hasWorkspace,
      providerConfigured: state.providerConfigured,
      keyboardVisible: keyboardVisible,
      workspaceLabel: hasWorkspace ? p.basename(ws) : null,
      modelLabel: state.activeModel.isNotEmpty
          ? state.activeModel
          : state.activeProviderName,
      onSuggestionTap: _fillSuggestion,
      onWorkspaceTap: _handleTopBarWorkspace,
      onModelTap: _switchProvider,
      onConfigureModel: _configureModel,
      onCreateAgent: () {
        Navigator.of(context).push(
          NexusPageRoute.detail(
            builder: (_) => const AgentsPage(autoDescribe: true),
          ),
        );
      },
      onAnalyzeWorkspace: () =>
          _fillSuggestion(const QuickAction(label: '解读项目')),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(chatControllerProvider, (previous, next) {
      if (previous == null) return;
      _scrollIndicator.messagesChanged(
        previous: previous.messages,
        next: next.messages,
        resetSession: previous.conversationId != next.conversationId ||
            previous.loading ||
            next.loading ||
            previous.restoringConversation ||
            next.restoringConversation,
        running: next.running,
        completed: previous.running && !next.running,
      );
      if ((previous.loading && !next.loading) ||
          (previous.restoringConversation && !next.restoringConversation)) {
        _scheduleDeepLinkConsumption();
      }
      if (shouldStopSpeakingOnSwitch(previous, next,
          speakingHere: _speakingMessageIndex.value != null)) {
        // 停止后 speakingListenable 变为 false，朗读索引会随之清空。
        unawaited(TtsService.instance.stop());
      }
      // 整轮成功完成：一次轻触感（lightImpact，避免每轮都重震）。只在前台触发；动画 off 档由 NexusHaptics 跳过。
      if (runSucceededBetween(previous, next)) {
        final lifecycle = WidgetsBinding.instance.lifecycleState;
        if (lifecycle == null || lifecycle == AppLifecycleState.resumed) {
          NexusHaptics.light(context);
        }
      }
    });

    return ValueListenableBuilder<double>(
      valueListenable: ChatLayoutController.widthFactor,
      builder: (context, _, __) {
        // 逐字段 select：只有被订阅字段自身变化时才重建本页。
        // 高频变化的 liveReply（流式期间 ≤70ms 一次）**不在此订阅**，而是下沉到
        // 仅包裹消息列表的 Consumer 中，使输入胶囊 / 会话指标条 / 顶栏不会被
        // 每次流式增量带着整页重建。
        final loading =
            ref.watch(chatControllerProvider.select((s) => s.loading));
        final restoringConversation = ref.watch(
            chatControllerProvider.select((s) => s.restoringConversation));
        final conversationId =
            ref.watch(chatControllerProvider.select((s) => s.conversationId));
        final currentWorkspacePath = ref.watch(
            chatControllerProvider.select((s) => s.currentWorkspacePath));
        final contextTokens =
            ref.watch(chatControllerProvider.select((s) => s.contextTokens));
        final liveContextTokens = ref
            .watch(chatControllerProvider.select((s) => s.liveContextTokens));
        final activeModel =
            ref.watch(chatControllerProvider.select((s) => s.activeModel));
        final activeProviderName = ref
            .watch(chatControllerProvider.select((s) => s.activeProviderName));
        final providerConfigured = ref
            .watch(chatControllerProvider.select((s) => s.providerConfigured));
        final messages =
            ref.watch(chatControllerProvider.select((s) => s.messages));
        final running = ref.watch(runningProvider);
        final runProgress =
            ref.watch(chatControllerProvider.select((s) => s.runProgress));
        final paused =
            ref.watch(chatControllerProvider.select((s) => s.paused));
        final planMode =
            ref.watch(chatControllerProvider.select((s) => s.planMode));
        final chatMode =
            ref.watch(chatControllerProvider.select((s) => s.mode));
        final approvalMode =
            ref.watch(chatControllerProvider.select((s) => s.approvalMode));
        final planState =
            ref.watch(chatControllerProvider.select((s) => s.planState));
        final activityLog = ref.watch(chatControllerProvider.select(
          (s) => s.activityLog.isEmpty ? null : s.activityLog.last,
        ));
        final toolActivities =
            ref.watch(chatControllerProvider.select((s) => s.toolActivities));
        final conversationTitle = ref
            .watch(chatControllerProvider.select((s) => s.conversationTitle));
        final totalSteps =
            ref.watch(chatControllerProvider.select((s) => s.totalSteps));
        final sessionSkills = ref.watch(
            chatControllerProvider.select((s) => s.sessionSkillInstructions));
        final executionStage = resolveChatExecutionStage(
          toolActivities: toolActivities,
          running: running,
          paused: paused,
          planState: planState,
          runProgress: runProgress,
        );

        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            statusBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
            systemStatusBarContrastEnforced: false,
            systemNavigationBarContrastEnforced: false,
          ),
          child: Scaffold(
            key: _scaffoldKey,
            // 键盘高度只作用于底部输入区（KeyboardSpacer），不再让 Scaffold 按
            // viewInsets 缩小整个 body：部分 ROM 会残留过期的键盘 inset，body 被
            // 压缩一个键盘高度后底部露出背景（白块）、输入框悬在半空。
            resizeToAvoidBottomInset: false,
            backgroundColor: Colors.transparent, // Background handled by stack
            drawerScrimColor: isDark
                ? Colors.black.withValues(alpha: 0.35)
                : Colors.black.withValues(alpha: 0.05),
            drawer: ChatCatalogDrawer(
              currentConversationId: conversationId,
              currentWorkspacePath: currentWorkspacePath,
              contextTokens: contextTokens,
              liveContextTokens: liveContextTokens,
              activeModel: activeModel,
              activeProviderName: activeProviderName,
              messages: messages,
              isRunning: running,
              planModeEnabled: planMode,
              approvalMode: approvalMode,
              onApprovalModeTap: _selectApprovalMode,
              onNewConversation: () => _startNewConversation(),
              onSelectConversation: (conv) => _switchConversation(conv),
              onWorkspaceTap: _handleTopBarWorkspace,
              onModelTap: _switchProvider,
              onMcpMenu: () => Navigator.of(context).push(
                NexusPageRoute.detail(builder: (_) => const McpServersPage()),
              ),
              onPromptLibrary: _openPromptLibrary,
              onPlanModeToggle: () => _chat.setPlanMode(!planMode),
              onMore: _showAvatarMenu,
              onOpenHistory: _openHistory,
              onConversationDeleted: (id) {
                // 删掉的若是当前会话，立即另起新会话，避免停留在已删除的会话上。
                if (ref.read(chatControllerProvider).conversationId == id) {
                  _startNewConversation();
                }
              },
            ),
            body: Semantics(
              namesRoute: true,
              label: '对话',
              child: ValueListenableBuilder<double>(
                valueListenable: AppAppearanceController.glassIntensity,
                builder: (context, _, __) {
                  final glassIntensity =
                      AppAppearanceController.resolvedGlassIntensity;
                  return GlassSurfaceGroup(
                    child: Stack(
                      // 顶部悬浮层（顶栏、计划与工具面板）允许展示自身阴影，
                      // 不受页面 Stack 的默认裁剪影响。
                      clipBehavior: Clip.none,
                      children: [
                        // G1 聊天背景:自定义图 > 默认云朵图 > 渐变兜底;轻微 scrim 保消息可读。
                        //
                        // RepaintBoundary：这是全屏贴图，而本页没有任何分层，任何一处变化
                        // （流式输出、指标条刷新、滚动）都会一路 markNeedsPaint 到页面的
                        // 顶层边界层，把整张背景图跟着重画一遍。包起来后它只在自己的配置
                        // 变化时才重绘，其余时间直接复用 layer。
                        // 它是最底层且不含 BackdropFilter，不会干扰玻璃采样。
                        Positioned.fill(
                          child: RepaintBoundary(
                            child: ValueListenableBuilder<BackgroundConfig>(
                              valueListenable: BackgroundService.bgNotifier,
                              builder: (context, bg, _) {
                                final dark = Theme.of(context).brightness ==
                                    Brightness.dark;
                                final Widget? image = switch (bg.mode) {
                                  'clouds' => Image.asset(
                                      BackgroundService.cloudsAsset,
                                      fit: BoxFit.cover,
                                      cacheWidth: imageCacheWidth(context),
                                      errorBuilder: (_, __, ___) =>
                                          const SizedBox.shrink()),
                                  'custom' when bg.customPath != null =>
                                    Image.file(
                                      File(bg.customPath!),
                                      fit: BoxFit.cover,
                                      cacheWidth: imageCacheWidth(context),
                                      errorBuilder: (_, __, ___) =>
                                          const SizedBox.shrink(),
                                    ),
                                  _ => null,
                                };
                                if (image == null) {
                                  return const SizedBox.shrink();
                                }
                                // 图案背景上叠轻微同色 scrim 保消息可读;纯白/纯黑默认不加。
                                final scrim = bg.mode == 'custom' || dark
                                    ? (dark
                                        ? Colors.black.withValues(alpha: .18)
                                        : Colors.white.withValues(alpha: .10))
                                    : Colors.white.withValues(alpha: .06);
                                return Stack(fit: StackFit.expand, children: [
                                  image,
                                  Container(color: scrim),
                                ]);
                              },
                            ),
                          ),
                        ),
                        SafeArea(
                          bottom: false,
                          child: LayoutBuilder(builder: (context, constraints) {
                            // 横屏 / 平板等宽屏下限制正文最大宽度，避免输入框与卡片过宽（文档 9）。
                            final wide = constraints.maxWidth > 700;
                            // 顶部状态文字只在运行中显示，结束后不再残留旧状态。
                            final showActivityLog =
                                running && activityLog != null;
                            final hasTopDock = showActivityLog ||
                                (planState != null &&
                                    planState.status != 'cancelled') ||
                                toolActivities.isNotEmpty;
                            Widget column = Column(children: [
                              if (hasTopDock ||
                                  glassIntensity == GlassIntensity.flat)
                                SizedBox(
                                    height: capsuleTopBarHeight(context) +
                                        4), // Clear the absolute positioned top bar
                              if (showActivityLog)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(activityLog,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall),
                                  ),
                                ),
                              if ((planState != null &&
                                      planState.status != 'cancelled') ||
                                  toolActivities.isNotEmpty)
                                ConstrainedBox(
                                  // 顶部执行面板限高：最多占可用高度 38% 且不超过
                                  // 320dp，给消息列表留足空间。时间线只显示最近
                                  // 几条（其余进「查看全部」），不再嵌套滚动；
                                  // reverse 让内容超高时默认停在底部，最新一步
                                  // 始终可见，往下拖才看到上面的计划。
                                  constraints: BoxConstraints(
                                    maxHeight: math.min(
                                        constraints.maxHeight * 0.38, 320.0),
                                  ),
                                  child: SingleChildScrollView(
                                    key: const ValueKey('chat_activity_dock'),
                                    reverse: true,
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          12, 4, 12, 8),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          if (planState != null &&
                                              planState.status != 'cancelled')
                                            PlanPanel(
                                              plan: planState,
                                              goal: planState.steps.isEmpty
                                                  ? null
                                                  : planState
                                                      .steps.first.description,
                                              onApprove: () =>
                                                  _chat.respondToPlan(true),
                                              onCancel: () =>
                                                  _chat.respondToPlan(false),
                                              onResume: () =>
                                                  _chat.resumeFromBudgetPause(
                                                      approveTool:
                                                          _approveTool),
                                            ),
                                          if (toolActivities.isNotEmpty)
                                            ToolActivityTimeline(
                                              activities: toolActivities,
                                              running: running,
                                              compact: true,
                                              onConfirm: _confirmToolActivity,
                                              onReject: _rejectToolActivity,
                                              onReview: _reviewToolActivity,
                                              onRetry: _retryToolActivity,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: Stack(
                                  children: [
                                    loading || restoringConversation
                                        ? (restoringConversation
                                            ? const ConversationRestoreSkeleton()
                                            : const NexusChatMessageSkeleton())
                                        : (messages.isEmpty
                                            ? Builder(builder: _emptyState)
                                            : NotificationListener<
                                                Notification>(
                                                // 用户拖拽消息列表时暂停自动跟随，松手后恢复。
                                                onNotification: _scrollIndicator
                                                    .handleNotification,
                                                child: Consumer(
                                                  builder: (context, ref, _) {
                                                    // 高频流式文本在此单独订阅：只有本子树随
                                                    // liveReply 更新而重建，页面其余部分不动。
                                                    final liveReply = ref.watch(
                                                        liveReplyProvider);
                                                    return ValueListenableBuilder<
                                                        int?>(
                                                      valueListenable:
                                                          _selectingMessageIndex,
                                                      builder: (context,
                                                              selectionIndex,
                                                              _) =>
                                                          RepaintBoundary(
                                                        // Streaming tokens rebuild this subtree frequently. Isolate
                                                        // its raster work from the backdrop and glass controls.
                                                        child: GlassScrollEdge(
                                                          height: 20,
                                                          child:
                                                              ChatMessageList(
                                                            key:
                                                                _messageListKey,
                                                            sessionKey:
                                                                conversationId,
                                                            messages: messages,
                                                            liveReply:
                                                                liveReply,
                                                            controller:
                                                                _scrollController,
                                                            running: running,
                                                            runProgress:
                                                                runProgress,
                                                            onStop: running
                                                                ? _stop
                                                                : null,
                                                            padding: (hasTopDock ||
                                                                    glassIntensity ==
                                                                        GlassIntensity
                                                                            .flat)
                                                                ? const EdgeInsets
                                                                    .fromLTRB(
                                                                    16,
                                                                    0,
                                                                    16,
                                                                    10)
                                                                : EdgeInsets
                                                                    .fromLTRB(
                                                                    16,
                                                                    capsuleTopBarHeight(
                                                                            context) +
                                                                        12,
                                                                    16,
                                                                    10,
                                                                  ),
                                                            onLoadHistory: () =>
                                                                _chat
                                                                    .loadOlderHistory(),
                                                            onLongPress:
                                                                (index) {
                                                              if (!_longPressHintShown) {
                                                                _longPressHintShown =
                                                                    true;
                                                              }
                                                              _showMessageActions(
                                                                  index);
                                                            },
                                                            onRegenerate:
                                                                _regenerate,
                                                            onResumeRun:
                                                                _continueAfterPause,
                                                            onEditPrompt:
                                                                _editLatestQuestion,
                                                            onSwitchModel:
                                                                _switchProvider,
                                                            onSpeak: TtsService
                                                                    .instance
                                                                    .isAvailable
                                                                ? _speakMessageAt
                                                                : null,
                                                            speakingListenable:
                                                                TtsService
                                                                    .instance
                                                                    .speakingListenable,
                                                            speakingIndexListenable:
                                                                _speakingMessageIndex,
                                                            selectionIndex:
                                                                selectionIndex,
                                                            onExitSelection: () =>
                                                                _selectingMessageIndex
                                                                        .value =
                                                                    null,
                                                            trailingWidgets: const [],
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              )),
                                    Positioned(
                                      right: 16,
                                      bottom: 16,
                                      child: ListenableBuilder(
                                        listenable: _scrollIndicator,
                                        builder: (context, _) {
                                          final reduceMotion = MotionPreferences
                                              .shouldReduceMotion(context);
                                          return AnimatedSwitcher(
                                            duration: reduceMotion
                                                ? Duration.zero
                                                : NexusMotion.fast,
                                            switchInCurve:
                                                NexusMotion.curveEnter,
                                            switchOutCurve:
                                                NexusMotion.curveExit,
                                            transitionBuilder:
                                                (child, animation) =>
                                                    FadeTransition(
                                              opacity: animation,
                                              child: SlideTransition(
                                                position: Tween<Offset>(
                                                  begin: const Offset(0, 0.2),
                                                  end: Offset.zero,
                                                ).animate(animation),
                                                child: child,
                                              ),
                                            ),
                                            child: _scrollIndicator
                                                    .showScrollToBottom
                                                ? NexusBackToLatestButton(
                                                    key: const ValueKey(
                                                        'back_to_latest'),
                                                    onTap: _scrollIndicator
                                                        .scrollToBottom,
                                                    unreadCount:
                                                        _scrollIndicator
                                                            .unreadCount,
                                                    isRunning: running,
                                                  )
                                                : const SizedBox(
                                                    key: ValueKey(
                                                        'back_to_latest_hidden'),
                                                  ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ValueListenableBuilder<int>(
                                valueListenable: _attachmentsRevision,
                                builder: (context, _, __) {
                                  if (_attachments.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  return SizedBox(
                                    height: 56,
                                    child: ListView(
                                      scrollDirection: Axis.horizontal,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      children: _attachments.map((file) {
                                        // 与发送端共用图片名单：此前这里漏了 gif，
                                        // 于是 gif 能发却没有缩略图。
                                        final isImage =
                                            isImageAttachmentFileName(
                                                file.name);
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(right: 8),
                                          child: Stack(
                                            children: [
                                              Container(
                                                width: 52,
                                                height: 52,
                                                margin: const EdgeInsets.only(
                                                    top: 4, right: 4),
                                                child: NexusSurface(
                                                  level: SurfaceLevel.thin,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      image: isImage &&
                                                              file.bytes != null
                                                          ? DecorationImage(
                                                              image: MemoryImage(
                                                                  file.bytes!),
                                                              fit: BoxFit.cover)
                                                          : null,
                                                    ),
                                                    child: !isImage ||
                                                            file.bytes == null
                                                        ? const Center(
                                                            child: Icon(
                                                                Icons
                                                                    .insert_drive_file_outlined,
                                                                size: 24))
                                                        : null,
                                                  ),
                                                ),
                                              ),
                                              Positioned(
                                                right: -4,
                                                top: -4,
                                                child: Semantics(
                                                  button: true,
                                                  label: '移除附件 ${file.name}',
                                                  child: SizedBox(
                                                    width: 48,
                                                    height: 48,
                                                    child: IconButton(
                                                      padding: EdgeInsets.zero,
                                                      tooltip:
                                                          '移除附件 ${file.name}',
                                                      onPressed: () {
                                                        _attachments
                                                            .remove(file);
                                                        _notifyAttachmentsChanged();
                                                      },
                                                      icon: Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(2),
                                                        decoration:
                                                            BoxDecoration(
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .error,
                                                          shape:
                                                              BoxShape.circle,
                                                        ),
                                                        child: Icon(
                                                          Icons.close,
                                                          size: 12,
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .onError,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 8),
                              if (!providerConfigured &&
                                  !loading &&
                                  !restoringConversation &&
                                  !_providerHintDismissed)
                                ProviderSetupHint(
                                  onConfigure: _configureModel,
                                  onDismiss: () {
                                    setState(
                                        () => _providerHintDismissed = true);
                                    SharedPreferences.getInstance().then((p) =>
                                        p.setBool(
                                            'chat.provider_hint_dismissed',
                                            true));
                                  },
                                ),
                              SessionMetricsHud(
                                messages: messages,
                                totalSteps: totalSteps,
                                toolActivities: toolActivities,
                                running: running,
                                onTap: _openSessionMetricsSheet,
                                onCompress:
                                    running ? _requestContextCompression : null,
                                contextSnapshot: ref
                                    .read(chatControllerProvider)
                                    .contextSnapshot,
                              ),
                              // 避免三条 44dp 的同类横条在 360dp 屏上叠加。
                              ComposerSkillPromptSlot(
                                running: running,
                                sessionSkills: sessionSkills,
                                slashSkills:
                                    _toSkillItems(_slashSkillSuggestions),
                                suggestions: _toSkillItems(_skillSuggestions),
                                onSlashSelect: _insertSlashSkillReference,
                                onSuggestionSelect: _loadSuggestedSkill,
                                onSuggestionDismiss: _dismissSkillSuggestions,
                                onRemove: _removeSessionSkill,
                              ),
                              FloatingCapsuleInput(
                                glassIntensity: glassIntensity,
                                // 键盘与底部安全区统一由 KeyboardSpacer 处理。
                                bottomPadding: 8,
                                controller: _controller,
                                isRunning: running,
                                onSend: _send,
                                onStop: _stop,
                                onPause: _pause,
                                onResume: () => _chat.resume(),
                                isPaused: paused,
                                onAttachmentMenu: () {
                                  _attachmentPanelExpanded.value =
                                      !_attachmentPanelExpanded.value;
                                },
                                approvalMode: approvalMode,
                                onApprovalModeTap: _selectApprovalMode,
                                modeLabel: chatMode.label,
                                onModeTap: _showSessionConfiguration,
                                planModeEnabled: planMode,
                                hasAttachments: _attachments.isNotEmpty,
                                hasAttachmentsListenable: _hasAttachments,
                                isAttachmentExpanded:
                                    _attachmentPanelExpanded.value,
                                attachmentExpandedListenable:
                                    _attachmentPanelExpanded,
                              ),
                              ValueListenableBuilder<bool>(
                                valueListenable: _attachmentPanelExpanded,
                                builder: (context, expanded, _) =>
                                    NexusExpandSection(
                                  expanded: expanded,
                                  duration: NexusMotion.durationBase(context),
                                  reverseDuration:
                                      NexusMotion.durationFast(context),
                                  child: expanded
                                      ? AttachmentDrawerPanel(
                                          attachments: _attachments,
                                          onCamera: () async {
                                            _attachmentPanelExpanded.value =
                                                false;
                                            await _pickImage(
                                                ImageSource.camera);
                                          },
                                          onGallery: () async {
                                            _attachmentPanelExpanded.value =
                                                false;
                                            await _pickMultiImage();
                                          },
                                          onFile: () async {
                                            _attachmentPanelExpanded.value =
                                                false;
                                            await _pickFiles();
                                          },
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),
                              // 键盘弹出时占位有效键盘高度，把输入区顶到键盘
                              // 上方；收起时占位底部安全区。
                              const KeyboardSpacer(),
                            ]);
                            if (wide) {
                              column = Align(
                                alignment: Alignment.topCenter,
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 700),
                                  child: column,
                                ),
                              );
                            }
                            return KeyboardInsetScope(child: column);
                          }),
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: SafeArea(
                            bottom: false,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
                              child: CapsuleTopBar(
                                glassIntensity: glassIntensity,
                                maxContextTokens: contextTokens,
                                workspaceLabel: (currentWorkspacePath == null ||
                                        currentWorkspacePath.isEmpty ||
                                        currentWorkspacePath == '未选择项目')
                                    ? null
                                    : (ref
                                            .read(chatControllerProvider)
                                            .currentProjectName ??
                                        p.basename(currentWorkspacePath)),
                                modelLabel: activeModel.isNotEmpty
                                    ? activeModel
                                    : (activeProviderName.isEmpty
                                        ? '未配置模型'
                                        : activeProviderName),
                                modeLabel: chatMode.label,
                                sessionTitle:
                                    messages.isEmpty ? null : conversationTitle,
                                runningStage: executionStage?.label,
                                runningStageKind: executionStage?.stage,
                                statusActive: running,
                                currentContextTokens: liveContextTokens > 0
                                    ? liveContextTokens
                                    : messages.reversed
                                            .where((m) => m.usage != null)
                                            .map((m) =>
                                                m.usage!.promptTokens +
                                                m.usage!.completionTokens)
                                            .firstOrNull ??
                                        0,
                                onMenu: () =>
                                    _scaffoldKey.currentState?.openDrawer(),
                                onNewChat: () => _startNewConversation(),
                                onContextGaugeTap: () =>
                                    _scaffoldKey.currentState?.openDrawer(),
                                onTitleTap: _showSessionConfiguration,
                                onWorkspaceTap: _handleTopBarWorkspace,
                                onModeTap: _showChatModeSheet,
                              ),
                            ),
                          ),
                        ),
                      ], // Stack children
                    ), // Stack
                  );
                },
              ), // ValueListenableBuilder
            ), // Semantics
          ), // Scaffold
        ); // AnnotatedRegion
      },
    );
  }
}

class _InstalledSkill {
  const _InstalledSkill(this.pack, this.metadata);

  final SkillPack pack;
  final SkillMetadata metadata;
}

/// 附件体检的输入：一个「候选附件」，字节可能还没读进来。
///
/// 存在的理由：限额体检必须在读字节**之前**完成（附件字节会常驻内存直到发送，
/// 先读再丢等于白白打满一次内存峰值），但字节的来源不止一种——
/// - 选文件：`file_picker` 13 的 `PlatformFile` 不可构造，且 Android 的 SAF
///   `content://` 结果没有本地路径，只能靠它自己的 `lengthSync()` 拿免 I/O 大小、
///   再用 `readAsBytes()` 取字节；
/// - 相册 / 拍照 / 分享：字节本来就已经在手上（`XFile.readAsBytes()` / base64）。
///
/// 用一个统一的候选类型承载这两种情况，体检逻辑就只需要写一遍。
class _PickedAttachment {
  /// 需要先按大小体检、再按需读字节的来源（选文件）。
  const _PickedAttachment({
    required this.name,
    this.knownSize,
    this.readBytes,
  }) : knownBytes = null;

  /// 从已经拿到字节的来源构造（相册 / 拍照 / 分享）。
  const _PickedAttachment.inMemory({
    required this.name,
    required Uint8List this.knownBytes,
  })  : knownSize = null,
        readBytes = null;

  final String name;

  /// 已经在手的字节；为 `null` 表示需要靠 [readBytes] 现取。
  final Uint8List? knownBytes;

  /// 免 I/O 就能知道的大小（Android 原生上报值）；为 `null` 表示未知。
  final int? knownSize;

  /// 现取字节的回调（选文件场景走插件自己的 `readAsBytes()`，能处理 SAF URI）。
  final Future<Uint8List?> Function()? readBytes;

  /// 免 I/O 的已知大小；拿不到返回 `null`。
  int? get sizeIfKnown => knownBytes?.length ?? knownSize;
}

/// 可恢复任务提示弹窗的用户选择。
enum _RecoveryDecision {
  /// 忽略本次提示（同一任务后续冷启动不再弹出）。
  ignore,

  /// 项目目录不可访问，跳去重新绑定工作区。
  rebind,

  /// 从断点继续执行该任务。
  continueExecuting,
}

/// 冷启动检测到可恢复任务时的提示卡片。
///
/// 与原生 AlertDialog 对齐的语义，但视觉上贴合全站 Nexus 规范：状态徽标、
/// 工作区可访问状态醒目呈现，暂停原因在暂停任务上优先展示。
class _RecoverableTaskDialog extends StatelessWidget {
  const _RecoverableTaskDialog({
    required this.info,
    required this.accessible,
  });

  final DevelopmentTaskInfo info;
  final bool accessible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final isPaused = info.status == 'paused';

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppPalette.brand.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isPaused
                  ? Icons.pause_circle_outline_rounded
                  : Icons.replay_rounded,
              color: AppPalette.brand,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isPaused ? '任务已暂停' : '发现未完成的任务',
              style: const TextStyle(
                  fontSize: AppTokens.fontSizeTitle,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              NexusStatusPill.fromString(info.status, isCompact: true),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  info.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: AppTokens.fontSizeSubhead,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (info.prompt.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            _infoRow(
              icon: Icons.subject_rounded,
              text: info.prompt,
            ),
          ],
          const SizedBox(height: 8),
          _infoRow(
            icon: Icons.folder_outlined,
            text: info.workspacePath ?? '未绑定项目',
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                accessible
                    ? Icons.verified_user_outlined
                    : Icons.link_off_rounded,
                size: 16,
                color: accessible ? AppPalette.success : AppPalette.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  accessible ? '项目可访问' : '项目目录不可访问，需重新绑定',
                  style: TextStyle(
                    fontSize: AppTokens.fontSizeCaption,
                    fontWeight: FontWeight.w500,
                    color: accessible ? AppPalette.success : AppPalette.warning,
                  ),
                ),
              ),
            ],
          ),
          if (info.executedSteps.isNotEmpty) ...[
            const SizedBox(height: 8),
            _infoRow(
              icon: Icons.checklist_rounded,
              text: '已执行步骤：${info.executedSteps.join('、')}',
            ),
          ],
          if (info.pauseReason != null && info.pauseReason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _infoRow(
              icon: Icons.info_outline_rounded,
              text: '暂停原因：${info.pauseReason}',
              forceHighlight: true,
            ),
          ],
          const SizedBox(height: 6),
          Text(
            '忽略后可在仪表盘「待我处理」中随时继续。',
            style:
                TextStyle(fontSize: AppTokens.fontSizeFootnote, color: muted),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, _RecoveryDecision.ignore),
            child: const Text('忽略')),
        if (!accessible)
          TextButton(
            onPressed: () => Navigator.pop(context, _RecoveryDecision.rebind),
            child: const Text('重新绑定'),
          ),
        FilledButton.icon(
          onPressed: accessible
              ? () =>
                  Navigator.pop(context, _RecoveryDecision.continueExecuting)
              : null,
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: const Text('继续执行'),
        ),
      ],
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String text,
    bool forceHighlight = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 16,
          color: forceHighlight ? AppPalette.warning : AppPalette.brand,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppTokens.fontSizeCaption,
              height: 1.35,
              color: forceHighlight ? AppPalette.warning : null,
            ),
          ),
        ),
      ],
    );
  }
}
