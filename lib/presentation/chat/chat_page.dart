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

  void _notifyAttachmentsChanged() {
    _hasAttachments.value = _attachments.isNotEmpty;
    _attachmentsRevision.value++;
  }

  final BackgroundService _backgroundService = BackgroundService();

  void _rememberCurrentDraft() {
    final state = ref.read(chatControllerProvider);
    final conversationId = state.conversationId;
    if (conversationId == null) return;
    final draft = _controller.text;
    if (draft.trim().isEmpty) {
      _draftsByConversation.remove(conversationId);
    } else {
      _draftsByConversation[conversationId] = draft;
    }
    _schedulePersistDraft(
      conversationId: conversationId,
      projectId: state.currentProjectId,
      text: draft,
    );
  }

  void _schedulePersistDraft({
    required String conversationId,
    String? projectId,
    required String text,
  }) {
    _draftPersistTimer?.cancel();
    _draftPersistTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(_persistDraft(
        conversationId: conversationId,
        projectId: projectId,
        text: text,
      ));
    });
  }

  Future<void> _persistDraft({
    required String conversationId,
    String? projectId,
    required String text,
  }) async {
    try {
      final db = await ref.read(databaseProvider.future);
      final key = DraftService.keyFor(
        conversationId: conversationId,
        projectId: projectId,
      );
      final attachments = await _stageCurrentAttachments();
      final references = [
        for (final citation
            in ref.read(chatControllerProvider).pendingCitations)
          citation.toJson(),
      ];
      if (text.trim().isEmpty && attachments.isEmpty && references.isEmpty) {
        await _draftService.clear(db, key);
        return;
      }
      await _draftService.save(
        db,
        draftKey: key,
        conversationId: conversationId,
        projectId: projectId,
        text: text,
        attachments: attachments,
        references: references,
      );
    } catch (_) {
      // 草稿自动保存（防抖 300ms）失败只影响「切换会话后能否恢复未发送内容」，
      // 不能反过来打断正在输入的用户；这也是高频路径，不宜逐次上报。
    }
  }

  Future<List<DraftAttachment>> _stageCurrentAttachments() async {
    final staged = <DraftAttachment>[];
    for (final file in _attachments) {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        staged.add(DraftAttachment(
          id: UniqueId.generate('att'),
          name: file.name,
          mime: file.extension ?? 'application/octet-stream',
          path: file.path ?? '',
          status: file.path == null ? 'missing' : 'ready',
        ));
        continue;
      }
      staged.add(await _draftService.stageFile(
        id: UniqueId.generate('att'),
        name: file.name,
        mime: file.extension ?? 'application/octet-stream',
        bytes: bytes,
      ));
    }
    return staged;
  }

  void _clearCurrentDraft() {
    final state = ref.read(chatControllerProvider);
    final conversationId = state.conversationId;
    if (conversationId == null) return;
    _draftsByConversation.remove(conversationId);
    unawaited(_persistDraft(
      conversationId: conversationId,
      projectId: state.currentProjectId,
      text: '',
    ));
  }

  Future<void> _restoreDraft(String? conversationId) async {
    var draft = conversationId == null
        ? ''
        : (_draftsByConversation[conversationId] ?? '');
    if (draft.isEmpty && conversationId != null) {
      try {
        final db = await ref.read(databaseProvider.future);
        final key = DraftService.keyFor(
          conversationId: conversationId,
          projectId: ref.read(chatControllerProvider).currentProjectId,
        );
        final stored = await _draftService.load(db, key);
        draft = stored?.text ?? '';
        if (draft.isNotEmpty) {
          _draftsByConversation[conversationId] = draft;
        }
        if (stored != null) {
          _restoreDraftAttachments(stored);
          for (final reference in stored.references) {
            unawaited(_chat.addFileCitation(FileCitation.fromJson(reference)));
          }
        }
      } catch (_) {
        // 草稿恢复失败即退回空草稿：用户看到的是一个空输入框，而不会因为一次
        // 读取异常导致整个聊天页无法打开。
      }
    }
    if (!mounted ||
        ref.read(chatControllerProvider).conversationId != conversationId) {
      return;
    }
    _controller.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
    // 文本选择模式是"当前这条消息"的临时态，切换会话就该退出，
    // 否则会在另一个会话里意外留下一个可选气泡。
    if (_selectingMessageIndex.value != null) {
      _selectingMessageIndex.value = null;
    }
  }

  Future<void> _startNewConversation({String? initialText}) async {
    _rememberCurrentDraft();
    await _chat.newConversation();
    if (!mounted) return;
    _attachments.clear();
    _notifyAttachmentsChanged();
    final conversationId = ref.read(chatControllerProvider).conversationId;
    await _restoreDraft(conversationId);
    if (!mounted ||
        ref.read(chatControllerProvider).conversationId != conversationId) {
      return;
    }
    if (initialText != null) {
      _controller.value = TextEditingValue(
        text: initialText,
        selection: TextSelection.collapsed(offset: initialText.length),
      );
    }
    _resetSessionSkills();
  }

  Future<void> _switchConversation(Conversation conversation) async {
    _rememberCurrentDraft();
    await _chat.switchConversation(conversation);
    if (!mounted ||
        ref.read(chatControllerProvider).conversationId != conversation.id) {
      return;
    }
    _attachments.clear();
    _notifyAttachmentsChanged();
    await _restoreDraft(conversation.id);
    _resetSessionSkills();
  }

  void _resetSessionSkills() {
    setState(() {
      _loadedSessionSkillIds.clear();
      _skillSuggestions = const [];
      _slashSkillSuggestions = const [];
      _skillSuggestionsDismissed = false;
    });
    _onSkillInputChanged();
  }

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

  Future<void> _loadInstalledSkills() async {
    final generation = ++_skillLoadGeneration;
    try {
      final database = await ref.read(databaseProvider.future);
      final installed = await _skillStore.all(database);
      if (!mounted || generation != _skillLoadGeneration) return;
      final skills = installed
          .where((pack) => pack.enabled)
          .map((pack) {
            final metadata = _skillStore.readMetadata(pack);
            return metadata == null ? null : _InstalledSkill(pack, metadata);
          })
          .whereType<_InstalledSkill>()
          .toList(growable: false);
      final activeIds = skills.map((item) => item.pack.id).toSet();
      final removedSessionIds = _loadedSessionSkillIds
          .where((id) => !activeIds.contains(id))
          .toList(growable: false);
      if (!mounted || generation != _skillLoadGeneration) return;
      setState(() {
        _installedSkills
          ..clear()
          ..addAll(skills);
        _loadedSessionSkillIds.removeWhere((id) => !activeIds.contains(id));
        _skillSuggestions = const [];
        _slashSkillSuggestions = const [];
      });
      for (final id in removedSessionIds) {
        _chat.removeSessionSkillInstruction(id);
      }
      _refreshSkillSuggestions();
    } catch (_) {
      // Skill suggestions are an optional local enhancement.
    }
  }

  void _onSkillInputChanged() {
    _skillSuggestionDebounce?.cancel();
    _skillSuggestionDebounce =
        Timer(const Duration(milliseconds: 320), _refreshSkillSuggestions);
  }

  void _refreshSkillSuggestions() {
    if (!mounted) return;
    if (_installedSkills.isEmpty) {
      if (_skillSuggestions.isNotEmpty || _slashSkillSuggestions.isNotEmpty) {
        setState(() {
          _skillSuggestions = const [];
          _slashSkillSuggestions = const [];
        });
      }
      return;
    }
    final input = _controller.text.trim();
    // 候选规则（前缀过滤、排除已加载、上限 5 条）与去重比较都在
    // skill_suggestion_rules.dart 里，有单测覆盖。
    final slashSuggestions = selectSlashSkillSuggestions<_InstalledSkill>(
      skills: _installedSkills,
      query: slashSkillQuery(input),
      nameOf: (item) => item.metadata.name,
      isLoaded: (item) => _loadedSessionSkillIds.contains(item.pack.id),
    );
    final suggestions = !shouldOfferIntentSkillSuggestions(
            input: input, dismissed: _skillSuggestionsDismissed)
        ? const <_InstalledSkill>[]
        : _skillMatcher
            .match(input, _installedSkills.map((item) => item.metadata))
            .map((match) => _installedSkills.firstWhere(
                (item) => item.metadata.name == match.metadata.name))
            .where((item) => !_loadedSessionSkillIds.contains(item.pack.id))
            .toList(growable: false);
    if (sameSkillSuggestionOrder<_InstalledSkill>(
            suggestions, _skillSuggestions, idOf: (item) => item.pack.id) &&
        sameSkillSuggestionOrder<_InstalledSkill>(
            slashSuggestions, _slashSkillSuggestions,
            idOf: (item) => item.pack.id)) {
      return;
    }
    setState(() {
      _skillSuggestions = suggestions;
      _slashSkillSuggestions = slashSuggestions;
    });
  }

  void _dismissSkillSuggestions() {
    _skillSuggestionDebounce?.cancel();
    setState(() {
      _skillSuggestionsDismissed = true;
      _skillSuggestions = const [];
    });
  }

  void _loadSuggestedSkill(SkillSuggestionItem item) {
    final skill = _installedSkills
        .where((candidate) => candidate.pack.id == item.id)
        .firstOrNull;
    if (skill == null) return;
    final body = _skillStore.readBody(skill.pack, maxChars: 8000);
    if (body == null || body.trim().isEmpty) {
      FloatingToast.show(context, 'Skill 内容不可用', tone: ToastTone.warning);
      return;
    }
    _chat.addSessionSkillInstruction(
      id: skill.pack.id,
      name: skill.metadata.name,
      instruction: '## 当前会话已加载 Skill：${skill.metadata.name}\n\n$body',
    );
    setState(() {
      _loadedSessionSkillIds.add(skill.pack.id);
      _skillSuggestions = _skillSuggestions
          .where((candidate) => candidate.pack.id != skill.pack.id)
          .toList(growable: false);
    });
    HapticFeedback.selectionClick();
    FloatingToast.show(context, '已为当前会话加载 ${skill.metadata.name}');
  }

  void _insertSlashSkillReference(SkillSuggestionItem item) {
    final current = _controller.text;
    // 文本变换抽到 slash_skill_query.dart（纯函数、有单测）：这里只负责把结果
    // 写回输入框并收起候选。
    final next = insertSlashSkillReference(current, item.name);
    if (next == null) return;
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    setState(() => _slashSkillSuggestions = const []);
    HapticFeedback.selectionClick();
  }

  void _removeSessionSkill(String id) {
    _chat.removeSessionSkillInstruction(id);
    setState(() => _loadedSessionSkillIds.remove(id));
    _refreshSkillSuggestions();
  }

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
                                _chatModeIcon(mode),
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

  static IconData _chatModeIcon(ChatMode mode) => switch (mode) {
        ChatMode.chat => Icons.chat_bubble_outline_rounded,
        ChatMode.agent => Icons.smart_toy_outlined,
        ChatMode.plan => Icons.checklist_rounded,
      };

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

  /// 会话指标条（对标 DeepSeek 输入区上方的指标胶囊）。
  ///
  /// 空会话与纯聊天不渲染，避免在首页制造噪音；自定义聊天背景下
  /// 自动切深色半透明底，保证可读性。
  /// 输入区上方的技能提示槽位。
  ///
  /// 三条技能提示（`/` 补全 / 自动建议 / 已加载）视觉同构、都只在非运行态出现，
  /// 因此共用一个槽位，只渲染优先级最高的那条（规则见 [resolveComposerSkillSlot]）。
  /// 输入区上方因此最多只剩：运行状态条（或指标条）+ 上下文提示 + 本槽位。
  List<SkillSuggestionItem> _toSkillItems(List<_InstalledSkill> skills) =>
      skills
          .map((skill) => SkillSuggestionItem(
                id: skill.pack.id,
                name: skill.metadata.name,
                description: skill.metadata.description,
              ))
          .toList(growable: false);

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

  void _scheduleDeepLinkConsumption() {
    if (!mounted || _deepLinkScheduled) return;
    _deepLinkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _deepLinkScheduled = false;
      if (mounted) unawaited(_consumeDeepLink());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _consumeDeepLink() async {
    if (!mounted || _handlingDeepLink) return;
    final state = ref.read(chatControllerProvider);
    // Initialization must finish first: otherwise its old conversation can
    // overwrite the new one. The state listener retries when restoration ends.
    if (state.loading || state.restoringConversation) return;
    _handlingDeepLink = true;
    final links = DeepLinkService.instance;
    try {
      final prompt = links.drainPrompt();
      // An empty string is an explicit new-chat request, not "no request".
      if (prompt != null) await _startNewConversation(initialText: prompt);
      if (!mounted) return;
      if (links.drainNewAgent()) {
        unawaited(Navigator.of(context).push(NexusPageRoute.detail(
            builder: (_) => const AgentsPage(autoDescribe: true))));
      }
      if (links.drainMemory()) {
        unawaited(Navigator.of(context)
            .push(NexusPageRoute.detail(builder: (_) => const MemoryPage())));
      }
    } catch (_) {
      // A failed navigation should not crash the page or auto-send the prompt.
      if (mounted) FloatingToast.show(context, '无法打开深链接，请重试');
    } finally {
      _handlingDeepLink = false;
      if (mounted && links.hasPending) _scheduleDeepLinkConsumption();
    }
  }

  /// 消费一条通知点击意图，把用户带回通知所指的会话或任务。
  ///
  /// 通知是「尽力而为」的入口：目标可能已被删除（会话被清理、任务被移除），此时
  /// 必须给出明确提示，而不是静默无反应——用户刚在锁屏上点了通知，什么都不发生
  /// 会被理解成「应用坏了」。
  Future<void> _handleNotificationIntent(NotificationIntent intent) async {
    try {
      final database = await ref.read(databaseProvider.future);
      if (!mounted) return;
      switch (intent.kind) {
        case NotificationIntentKind.conversation:
          final conversation = await database.findConversation(intent.id);
          if (!mounted) return;
          if (conversation == null) {
            FloatingToast.show(context, '该会话已不存在', tone: ToastTone.warning);
            return;
          }
          await _switchConversation(conversation);
        case NotificationIntentKind.task:
          final task = await database.findTask(intent.id);
          if (!mounted) return;
          if (task == null) {
            FloatingToast.show(context, '该任务已不存在', tone: ToastTone.warning);
            return;
          }
          await Navigator.of(context).push(NexusPageRoute.detail(
            builder: (_) => TaskDetailsPage(task: TaskService().describe(task)),
          ));
        case NotificationIntentKind.approval:
          // 锁屏审批的裁决已由后台 isolate 写入数据库，这里只需把用户带回应用，
          // 待处理入口就在当前会话页。已在前台时给一句提示，避免"点了没反应"。
          final state = ref.read(chatControllerProvider);
          if (state.running || state.toolActivities.isNotEmpty) {
            FloatingToast.show(context, '请回到当前会话处理待审批操作');
          }
        case NotificationIntentKind.automation:
          await Navigator.of(context).push(NexusPageRoute.detail(
            builder: (_) => DeviceAutomationPage(initialFireId: intent.id),
          ));
      }
    } catch (error) {
      if (mounted) {
        FloatingToast.error(context, '无法打开通知目标', rawDetail: error.toString());
      }
    }
  }

  /// 检测可续跑的后台任务（进程被杀遗留的 running + 预算暂停的 paused），提示用户是否继续。
  ///
  /// 用户点过「忽略」的任务会被记录到 SharedPreferences，之后不再反复打扰
  /// （同一任务除非被再次发起，否则只在首次冷启动提示一次）。仪表盘的
  /// 「待我处理」区始终保留这些可恢复任务的常驻入口，因此这里静默忽略不会
  /// 让任务失去发现途径。
  Future<void> _checkRecoverableTask() async {
    try {
      final tasks = await _chat.recoverableTasks();
      if (!mounted || tasks.isEmpty) return;
      final dismissed = await _dismissedRecoveryTaskIds();
      final candidates =
          tasks.where((task) => !dismissed.contains(task.id)).toList();
      if (candidates.isEmpty) return;
      final info = TaskService().describe(candidates.first);
      final accessible =
          await WorkspaceService().isAccessible(info.workspacePath);
      if (!mounted) return;
      final resume = await showNexusDialog<_RecoveryDecision>(
        context: context,
        builder: (_) => _RecoverableTaskDialog(
          info: info,
          accessible: accessible,
        ),
      );
      if (!mounted) return;
      switch (resume) {
        case _RecoveryDecision.ignore:
          await _dismissRecoveryTask(candidates.first.id);
        case _RecoveryDecision.rebind:
          await _pickWorkspace();
        case _RecoveryDecision.continueExecuting:
          await _dismissRecoveryTask(candidates.first.id);
          await _chat.resumeTask(candidates.first.id,
              approveTool: _approveTool);
        case null:
          break;
      }
    } catch (e, stack) {
      debugPrint('恢复检测失败: $e\n$stack');
    }
  }

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

  /// 生物识别锁：开启且设备支持时，启动/回前台需验证身份。
  Future<void> _maybeLock() async {
    final lock = ref.read(appLockServiceProvider);
    if (!await lock.isEnabled()) return;
    if (!await lock.canUseBiometrics()) return;
    if (!mounted) return;
    final ok = await lock.authenticate();
    if (!ok && mounted) {
      await _showLockFailed(lock);
    }
  }

  Future<void> _showLockFailed(AppLockService lock) async {
    final retry = await showConfirmAction(
      context,
      barrierDismissible: false,
      title: '身份验证失败',
      message: '可重试，或退出应用。',
      confirmLabel: '重试',
      cancelLabel: '退出',
      isDanger: false,
    );
    if (!mounted) return;
    if (retry) {
      unawaited(_maybeLock());
    } else {
      unawaited(SystemNavigator.pop());
    }
  }

  /// 处理系统分享内容：图片转附件，文本/URL 预填输入框；均自动新建会话。
  /// 把一批分享内容合并进同一个新会话。
  ///
  /// 系统分享可以一次带上多张图（相册多选分享）。此前对每条内容各调一次
  /// `_startNewConversation`，分享 3 张图会演出 3 个会话，而且都是异步的，
  /// 前面的会被后面的覆盖，用户最终只看得到最后一张。
  Future<void> _onSharedTexts(List<String> shared) async {
    if (!mounted) return;
    final items = shared.where(SharingService.isShareableText).toList();
    if (items.isEmpty) return;
    _pendingSourceType = 'share';

    final attachments = <AttachmentFile>[];
    final texts = <String>[];
    for (final item in items) {
      if (item.startsWith('data:image/')) {
        final attachment = _decodeSharedImage(item);
        if (attachment != null) attachments.add(attachment);
      } else {
        texts.add(item);
      }
    }
    if (attachments.isEmpty && texts.isEmpty) return;

    await _startNewConversation();
    if (!mounted) return;
    if (attachments.isNotEmpty) {
      _attachments.addAll(attachments);
      _notifyAttachmentsChanged();
    }
    final merged = texts.join('\n\n');
    if (merged.isNotEmpty) {
      _controller.value = TextEditingValue(
        text: merged,
        selection: TextSelection.collapsed(offset: merged.length),
      );
    }
    if (attachments.isNotEmpty) {
      FloatingToast.show(
        context,
        attachments.length > 1
            ? '已接收 ${attachments.length} 张图片，可点击发送'
            : '已接收图片，可点击发送',
        tone: ToastTone.success,
      );
    }
  }

  /// 解码分享进来的 `data:image/...;base64,...`。
  ///
  /// 单张解码失败（base64 被截断等）只提示并丢弃该张，不影响同批其他内容。
  AttachmentFile? _decodeSharedImage(String dataUri) {
    try {
      final comma = dataUri.indexOf(',');
      if (comma < 0) throw const FormatException('缺少 base64 分隔符');
      final bytes = base64Decode(dataUri.substring(comma + 1));
      final mime = dataUri.substring('data:'.length, comma).split(';').first;
      final extension = mime.contains('/') ? mime.split('/').last : 'jpg';
      return AttachmentFile(
        name: '分享图片.$extension',
        bytes: bytes,
      );
    } catch (error) {
      if (mounted) {
        FloatingToast.error(context, '图片分享解析失败', rawDetail: error.toString());
      }
      return null;
    }
  }

  // --- 操作 ---

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

  /// Resolves explicit `/skill_name` references before the user message is sent.
  /// The command itself stays out of conversation history; its content is injected
  /// into this session only, exactly as a tapped suggestion would be.
  String? _resolveSlashSkillReferences(String input) {
    // token 的识别（哪些是完整命令）与删除都在 slash_skill_query.dart 里，有单测；
    // 这里只负责副作用：加载技能到当前会话。
    final names = slashSkillCommandNames(input);
    if (names.isEmpty) return input;

    final recognized = <String>{};
    for (final name in names) {
      final skill = _installedSkills
          .where((candidate) => candidate.metadata.name == name)
          .firstOrNull;
      // Unknown slash tokens are ordinary user text (for example /tmp or
      // /build). Only a known installed Skill is consumed as a command.
      if (skill == null) continue;
      if (!_loadedSessionSkillIds.contains(skill.pack.id)) {
        final body = _skillStore.readBody(skill.pack, maxChars: 8000);
        if (body == null || body.trim().isEmpty) {
          FloatingToast.show(context, 'Skill 不可读取：/$name',
              tone: ToastTone.warning);
          return null;
        }
        _chat.addSessionSkillInstruction(
          id: skill.pack.id,
          name: skill.metadata.name,
          instruction: '## 当前会话已加载 Skill：${skill.metadata.name}\n\n$body',
        );
        if (mounted) {
          setState(() => _loadedSessionSkillIds.add(skill.pack.id));
        }
      }
      recognized.add(name);
    }
    if (recognized.isEmpty) return input;
    return removeSlashSkillCommands(input, recognized);
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

  void _restoreDraftAttachments(ConversationDraft draft) {
    final restored = <AttachmentFile>[];
    var missing = 0;
    for (final item in draft.attachments) {
      if (item.status == 'missing' || item.path.isEmpty) {
        missing++;
        continue;
      }
      // 草稿里的附件只有名字与路径，字节在真正发送前由发送管线补读；
      // 这里刻意留 bytes: null，避免为了「恢复草稿」就把文件全读进内存，
      // 也让发送端能区分「无字节」与「空文件」。
      restored.add(AttachmentFile(
        name: item.name,
        path: item.path,
      ));
    }
    if (!mounted) return;
    _attachments
      ..clear()
      ..addAll(restored);
    _notifyAttachmentsChanged();
    if (missing > 0) {
      FloatingToast.show(context, '有 $missing 个附件失效，请重新选择',
          tone: ToastTone.warning);
    }
  }

  String _buildMarkdown(ChatState state) {
    final content = StringBuffer('# ${state.conversationTitle}\n\n');
    final toolNamesById = <String, String>{};
    for (final message in state.messages) {
      if (message.role != MessageRole.assistant) continue;
      for (final call in message.toolCalls) {
        toolNamesById[call.id] = call.name;
      }
    }
    for (final message in state.messages) {
      final role = switch (message.role) {
        MessageRole.user => '用户',
        MessageRole.assistant => '助手',
        MessageRole.system => '系统',
        MessageRole.tool => '工具',
      };
      final text = message.role == MessageRole.tool
          ? SensitiveToolPolicy.redactText(
              toolNamesById[message.toolCallId] ?? '', message.text)
          : message.text;
      content.write('## $role\n\n$text\n\n');
    }
    return content.toString();
  }

  Future<void> _copyConversation() async {
    final state = ref.read(chatControllerProvider);
    if (state.messages.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _buildMarkdown(state)));
    if (mounted) {
      FloatingToast.show(context, AppStrings.conversationCopied,
          tone: ToastTone.success);
    }
  }

  Future<void> _exportConversation() async {
    final state = ref.read(chatControllerProvider);
    if (state.messages.isEmpty) return;
    final content = _buildMarkdown(state);
    final path =
        await exportConversationMarkdown(state.conversationTitle, content);
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) return;
    FloatingToast.show(context,
        kIsWeb || path.isEmpty ? AppStrings.copiedToClipboard : '已导出到 $path',
        tone: ToastTone.success);
  }

  /// 出站分享：把整段对话以 Markdown 文本分享到系统分享面板。
  Future<void> _shareConversation() async {
    final state = ref.read(chatControllerProvider);
    if (state.messages.isEmpty) return;
    final content = _buildMarkdown(state);
    try {
      await SharePlus.instance
          .share(ShareParams(text: content, subject: state.conversationTitle));
    } catch (e) {
      if (mounted) {
        FloatingToast.error(context, '分享失败', rawDetail: e.toString());
      }
    }
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

  /// 附件数量上限。
  ///
  /// 字节与数量限额的唯一来源是 [attachment_policy.dart]：选择阶段与发送阶段
  /// （`ChatController`）共用同一组常量，不再各自维护一份并靠注释对齐。
  static const int _maxAttachmentCount = maxAttachmentCount;

  /// 单个附件的字节上限。
  static const int _maxAttachmentBytes = maxAttachmentBytes;

  /// 所有附件的总字节预算。
  static const int _maxAttachmentTotalBytes = maxAttachmentTotalBytes;

  Future<void> _pickFiles() async {
    // 选择器只负责「选」：file_picker 13 起 `withData` 已移除，`pickFiles` 也不再
    // 返回 null（取消时是空列表）。字节一律在体检通过后再自己读，避免用户点确定
    // 的瞬间把所有选中文件全读进内存，选 5 个视频就是几百 MB 的峰值，而它们可能
    // 一个都超限、根本用不上。
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      // 名单来自 attachment_policy.dart，与发送端的类型闸门是同一份，因此选择器
      // 里不会出现「能选、但发送时被丢弃」的扩展名。
      allowedExtensions: acceptedAttachmentExtensions,
    );
    if (!mounted) return;
    await _attachPickedFiles([
      for (final file in picked)
        _PickedAttachment(
          name: file.name,
          // 原生上报的大小可以免 I/O 拿到；拿不到时体检阶段会再退回读盘。
          knownSize: file.lengthSync(),
          // 走插件自己的 readAsBytes()：Android 的 SAF content:// 结果没有本地
          // 路径，只有插件能读它的字节。
          readBytes: () async {
            try {
              return await file.readAsBytes();
            } catch (_) {
              return null;
            }
          },
        ),
    ]);
  }

  /// 把选中的文件加入附件区，并做数量 / 单文件 / 总量三重体检。
  ///
  /// 三重判断都尽量发生在**读取字节之前**：附件字节会常驻内存直到发送，先读再丢
  /// 等于把内存峰值白白打满一次。被跳过的文件按原因汇总成一条提示，而不是静默
  /// 丢弃——用户挑了文件却什么都没发生，只会以为应用坏了。
  ///
  /// 参数是本项目自己的候选类型，因此相册、拍照、分享等来源都能复用同一套体检与
  /// 提示，不必都伪装成插件的 `PlatformFile`。
  Future<void> _attachPickedFiles(List<_PickedAttachment> picked) async {
    if (!mounted || picked.isEmpty) return;
    final accepted = <AttachmentFile>[];
    var usedBytes = _attachments.fold<int>(0, (sum, file) => sum + file.size);
    var rejectedSize = 0;
    var rejectedCount = 0;
    var rejectedRead = 0;

    for (final file in picked) {
      if (_attachments.length + accepted.length >= _maxAttachmentCount) {
        rejectedCount++;
        continue;
      }
      var bytes = file.knownBytes;
      // 免 I/O 的大小优先（Android 原生上报）；未知时先不判定，等读到字节再算。
      final size = file.sizeIfKnown;
      if (size != null &&
          (size <= 0 ||
              size > _maxAttachmentBytes ||
              !fitsIntoBudget(size: size, usedBytes: usedBytes))) {
        rejectedSize++;
        continue;
      }
      if (bytes == null) {
        bytes = await file.readBytes?.call();
        if (bytes == null) {
          rejectedRead++;
          continue;
        }
        // 之前拿不到大小，现在读到了，补做一次限额判定。
        if (size == null &&
            (bytes.isEmpty ||
                bytes.length > _maxAttachmentBytes ||
                !fitsIntoBudget(size: bytes.length, usedBytes: usedBytes))) {
          rejectedSize++;
          continue;
        }
      }
      if (bytes.isEmpty) {
        rejectedRead++;
        continue;
      }
      usedBytes += bytes.length;
      accepted.add(AttachmentFile(name: file.name, bytes: bytes));
    }

    if (accepted.isNotEmpty) {
      _attachments.addAll(accepted);
      _notifyAttachmentsChanged();
    }
    if (!mounted) return;
    final perFileMb = _maxAttachmentBytes ~/ (1024 * 1024);
    final totalMb = _maxAttachmentTotalBytes ~/ (1024 * 1024);
    final problems = <String>[
      if (rejectedSize > 0)
        '$rejectedSize 个超过单文件 $perFileMb MB 或总预算 $totalMb MB',
      if (rejectedCount > 0) '$rejectedCount 个超过 $_maxAttachmentCount 个上限',
      if (rejectedRead > 0) '$rejectedRead 个无法读取',
    ];
    if (problems.isNotEmpty) {
      FloatingToast.show(
        context,
        '已添加 ${accepted.length} 个附件；${problems.join('，')}已跳过',
        tone: ToastTone.warning,
      );
    }
  }

  /// 相册多选图片（A6：多图一次性发送）。
  Future<void> _pickMultiImage() async {
    try {
      final files = await _picker.pickMultiImage(
          maxWidth: 1280, maxHeight: 1280, imageQuality: 80);
      if (files.isEmpty || !mounted) return;
      // 先按剩余配额截断再读字节：多选 50 张时不该先把 50 张全解码进内存。
      final remaining = _maxAttachmentCount - _attachments.length;
      if (remaining <= 0) {
        FloatingToast.show(context, '最多添加 $_maxAttachmentCount 个附件',
            tone: ToastTone.warning);
        return;
      }
      final selected =
          files.length > remaining ? files.sublist(0, remaining) : files;
      final attachments = <_PickedAttachment>[];
      for (final xfile in selected) {
        final bytes = await xfile.readAsBytes();
        attachments.add(
            _PickedAttachment.inMemory(name: xfile.name, knownBytes: bytes));
      }
      await _attachPickedFiles(attachments);
    } catch (e) {
      if (mounted) {
        FloatingToast.error(context, '无法获取图片', rawDetail: e.toString());
      }
    }
  }

  /// 拍照/相册：压缩到 1280px / 80% 质量，控制 base64 体积，复用现有附件管线。
  Future<void> _pickImage(ImageSource source) async {
    try {
      final xfile = await _picker.pickImage(
          source: source, maxWidth: 1280, maxHeight: 1280, imageQuality: 80);
      if (xfile == null || !mounted) return;
      final bytes = await xfile.readAsBytes();
      if (!mounted) return;
      await _attachPickedFiles([
        _PickedAttachment.inMemory(name: xfile.name, knownBytes: bytes),
      ]);
    } catch (e) {
      if (mounted) {
        FloatingToast.error(context, '无法获取图片', rawDetail: e.toString());
      }
    }
  }

  Future<ToolApproval> _approveTool(
    ToolCall call,
    ToolRisk risk,
    bool sensitive,
  ) async {
    if (!mounted) return ToolApproval.reject;
    final previous = _pendingToolApprovals[call.id];
    if (previous != null && !previous.isCompleted) {
      previous.complete(ToolApproval.reject);
    }
    final approval = Completer<ToolApproval>();
    _pendingToolApprovals[call.id] = approval;
    try {
      return await approval.future;
    } finally {
      if (identical(_pendingToolApprovals[call.id], approval)) {
        _pendingToolApprovals.remove(call.id);
      }
    }
  }

  bool _resolveToolApproval(String callId, ToolApproval decision) {
    final approval = _pendingToolApprovals[callId];
    if (approval == null || approval.isCompleted) return false;
    approval.complete(decision);
    return true;
  }

  void _confirmToolActivity(ToolActivity activity) {
    if (!_resolveToolApproval(activity.call.id, ToolApproval.allowOnce)) {
      FloatingToast.show(context, '该审批已失效，请重试任务', tone: ToastTone.warning);
    }
  }

  void _rejectToolActivity(ToolActivity activity) {
    if (!_resolveToolApproval(activity.call.id, ToolApproval.reject)) {
      FloatingToast.show(context, '该审批已失效，请重试任务', tone: ToastTone.warning);
    }
  }

  void _reviewToolActivity(ToolActivity activity) {
    if (!_pendingToolApprovals.containsKey(activity.call.id)) {
      FloatingToast.show(context, '该审批已失效，请重试任务', tone: ToastTone.warning);
      return;
    }
    unawaited(_showToolApprovalDetails(activity));
  }

  Future<void> _showToolApprovalDetails(ToolActivity activity) async {
    final decision = await promptToolApproval(
      context,
      ref,
      activity.call,
      activity.risk,
      activity.sensitive,
    );
    if (!mounted) return;
    _resolveToolApproval(activity.call.id, decision);
  }

  void _retryToolActivity(ToolActivity activity) {
    final state = ref.read(chatControllerProvider);
    if (state.running) {
      FloatingToast.show(context, '当前任务仍在运行', tone: ToastTone.warning);
      return;
    }
    unawaited(_confirmToolRetry(activity));
  }

  Future<void> _confirmToolRetry(ToolActivity activity) async {
    final unknownEffect = activity.effect == ToolEffect.unknown;
    final confirmed = await showConfirmAction(
      context,
      title: '重试上一次任务？',
      message: unknownEffect
          ? '该操作的副作用无法确认。请先检查目标状态，避免重复写入后再重试。'
          : '将重新运行上一条请求和其工具步骤。',
      confirmLabel: '确认重试',
      isDanger: unknownEffect,
    );
    if (confirmed && mounted) _regenerate();
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
