import '../l10n/app_strings.dart';
import '../widgets/floating_toast.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../application/chat_controller.dart';
import '../../application/draft_service.dart';
import '../../application/file_citation.dart';
import '../../application/project_context_service.dart';
import '../../application/app_lock_service.dart';
import '../../application/providers.dart';
import '../../application/task_service.dart';
import '../../domain/unique_id.dart';
import '../../application/workspace_service.dart';
import '../../application/skill_intent_matcher.dart';
import '../../application/tts_text.dart';
import '../../domain/sensitive_tool_policy.dart';
import '../../domain/models.dart';
import '../../domain/session_metrics.dart';
import '../../domain/tool_result.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/skills/skill_parser.dart';
import '../../infrastructure/skills/skill_store.dart';
import '../../infrastructure/tts/tts_service.dart';
import '../../infrastructure/files/conversation_exporter.dart';
import '../../infrastructure/share/deep_link_service.dart';
import '../../infrastructure/share/sharing_service.dart';
import '../agents/agents_page.dart';
import '../dashboard/dashboard_page.dart';
import '../history/history_page.dart';
import '../tasks/development_tasks_page.dart';
import '../memory/memory_page.dart';
import '../mcp/mcp_servers_page.dart';
import '../prompts/prompt_library_page.dart';
import 'widgets/plan_panel.dart';
import '../settings/provider_list_page.dart';
import '../settings/settings_page.dart';
import 'chat_layout_controller.dart';
import 'composer_skill_slot.dart';
import '../workspace/file_tree_sheet.dart';
import '../workspace/development_workbench_page.dart';
import '../projects/project_home_page.dart';
import '../projects/project_picker_page.dart';
import '../projects/storage_access_flow.dart';
import '../utils/keyboard_insets.dart';

import 'widgets/floating_capsule_input.dart';
import 'widgets/attachment_drawer_panel.dart';
import 'widgets/session_metrics_bar.dart';
import 'widgets/session_metrics_sheet.dart';
import '../../../infrastructure/background_service.dart';
import 'widgets/session_context_sheet.dart';
import 'widgets/capsule_top_bar.dart';
import 'widgets/chat_empty_state.dart';
import 'widgets/chat_message_list.dart';
import 'widgets/model_picker_sheet.dart';
import 'widgets/tool_activity_section.dart';
import 'widgets/skill_suggestion_bar.dart';
import 'widgets/chat_catalog_drawer.dart';
import '../widgets/nexus_sheet.dart';
import '../widgets/nexus_action_sheet.dart';
import '../widgets/confirm_action.dart';
import '../widgets/nexus_surface.dart';
import '../widgets/nexus_status_pill.dart';
import '../widgets/tool_approval_helper.dart';
import '../theme/app_tokens.dart';
import '../motion/nexus_page_route_factory.dart';
import '../widgets/nexus_loading_skeleton.dart';
import '../widgets/glass_surface_group.dart';
import 'widgets/nexus_back_to_latest_button.dart';
import '../theme/app_appearance_controller.dart';
import '../widgets/liquid_glass.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage>
    with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  Future<void> _pickWorkspace() async {
    // 与项目页的「导入目录」保持一致：先拿到文件访问权限，再进目录选择器。
    if (!await ensureAllFilesAccess(context)) return;
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
  final _attachments = <PlatformFile>[];
  final ValueNotifier<int> _attachmentsRevision = ValueNotifier(0);
  final ValueNotifier<bool> _hasAttachments = ValueNotifier(false);
  String? _pendingClientRequestId;
  final ValueNotifier<bool> _attachmentPanelExpanded = ValueNotifier(false);
  final _picker = ImagePicker();
  final _scrollController = ScrollController();
  bool _showScrollToBottom = false;
  int _unreadNewMessagesCount = 0;
  final ValueNotifier<int> _scrollIndicatorRevision = ValueNotifier(0);
  bool _followTailScheduled = false;
  bool _followTailAnimate = false;

  /// 用户是否正在用手指拖拽消息列表。
  ///
  /// 用 [ScrollNotification] 的 `dragDetails` 判定，而不是
  /// `position.isScrollingNotifier`——后者在程序化 `jumpTo`/`animateTo` 期间
  /// 也为 true，会把「自己的自动跟随」误判成用户拖拽而永久停止跟随。
  bool _userDragging = false;
  bool _longPressHintShown = false;
  final Map<String, String> _draftsByConversation = <String, String>{};
  StreamSubscription<String>? _shareSub;
  String _pendingTaskType = 'general';
  String _pendingSourceType = 'manual';
  final Map<String, Completer<ToolApproval>> _pendingToolApprovals = {};

  /// 处于「文本选择模式」的消息索引（null = 无）。
  /// 正文默认不可选，否则长按会被文本选择器截走、消息菜单永远打不开。
  final ValueNotifier<int?> _selectingMessageIndex = ValueNotifier(null);

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
    } catch (_) {}
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
      } catch (_) {}
    }
    if (!mounted) return;
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
    await _restoreDraft(ref.read(chatControllerProvider).conversationId);
    if (initialText != null && initialText.isNotEmpty) {
      _controller.value = TextEditingValue(
        text: initialText,
        selection: TextSelection.collapsed(offset: initialText.length),
      );
    }
    _resetSessionSkills();
  }

  Future<void> _startNewConversationWithAttachment(
    PlatformFile attachment,
  ) async {
    await _startNewConversation();
    if (!mounted) return;
    _attachments.add(attachment);
    _notifyAttachmentsChanged();
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
    _controller.addListener(_onSkillInputChanged);
    _controller.addListener(_rememberCurrentDraft);
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    // 消费冷启动缓冲的分享内容。
    for (final shared in SharingService.instance.drainPending()) {
      _onSharedText(shared);
    }
    // 监听热分享（其他 App 分享进来）。
    _shareSub = SharingService.instance.shares.listen(_onSharedText);
    // 应用锁：启动即触发（若开启）。
    Future.microtask(_maybeLock);
    // C2 断点恢复：启动时检测中断任务并提示继续执行。
    Future.microtask(_checkRecoverableTask);
    // E4 深度链接：冷启动预填 prompt / 打开记忆页。
    _consumeDeepLink();
    // G1 聊天背景:加载持久化配置到全局通知器。
    _backgroundService.load().then((c) {
      BackgroundService.bgNotifier.value = c;
    });
    Future.microtask(_loadInstalledSkills);
  }

  Future<void> _loadInstalledSkills() async {
    try {
      final database = await ref.read(databaseProvider.future);
      final installed = await _skillStore.all(database);
      final skills = installed
          .map((pack) {
            final metadata = _skillStore.readMetadata(pack);
            return metadata == null ? null : _InstalledSkill(pack, metadata);
          })
          .whereType<_InstalledSkill>()
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _installedSkills
          ..clear()
          ..addAll(skills);
      });
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
    if (!mounted || _installedSkills.isEmpty) {
      return;
    }
    final input = _controller.text.trim();
    final slashMatch = RegExp(r'(?:^|\s)/([a-z0-9_-]*)$').firstMatch(input);
    final slashSuggestions = slashMatch == null
        ? const <_InstalledSkill>[]
        : _installedSkills
            .where((item) =>
                item.metadata.name.startsWith(slashMatch.group(1)!) &&
                !_loadedSessionSkillIds.contains(item.pack.id))
            .take(5)
            .toList(growable: false);
    final suggestions = input.length < 2
        ? const <_InstalledSkill>[]
        : _skillSuggestionsDismissed
            ? const <_InstalledSkill>[]
            : _skillMatcher
                .match(input, _installedSkills.map((item) => item.metadata))
                .map((match) => _installedSkills.firstWhere(
                    (item) => item.metadata.name == match.metadata.name))
                .where((item) => !_loadedSessionSkillIds.contains(item.pack.id))
                .toList(growable: false);
    if (_sameSkillSuggestions(suggestions, _skillSuggestions) &&
        _sameSkillSuggestions(slashSuggestions, _slashSkillSuggestions)) {
      return;
    }
    setState(() {
      _skillSuggestions = suggestions;
      _slashSkillSuggestions = slashSuggestions;
    });
  }

  bool _sameSkillSuggestions(
      List<_InstalledSkill> left, List<_InstalledSkill> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index].pack.id != right[index].pack.id) return false;
    }
    return true;
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
    final match = RegExp(r'(?:^|\s)/[a-z0-9_-]*$').firstMatch(current);
    if (match == null) return;
    final prefix = current.substring(0, match.start);
    final matchedText = match.group(0)!;
    final separator = matchedText.startsWith(RegExp(r'\s'))
        ? matchedText.substring(0, 1)
        : '';
    final next = '$prefix$separator/${item.name} ';
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
                      fontSize: 15,
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
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: activeColor,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 24, minHeight: 24),
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
                          duration: const Duration(milliseconds: 180),
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
                                  fontSize: 13,
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
  Widget _buildSkillPromptSlot({
    required bool running,
    required List<SessionSkillInstruction> sessionSkills,
  }) {
    final slot = resolveComposerSkillSlot(
      running: running,
      hasSlashMatches: _slashSkillSuggestions.isNotEmpty,
      hasSuggestions: _skillSuggestions.isNotEmpty,
      hasLoadedSkills: sessionSkills.isNotEmpty,
    );

    switch (slot) {
      case ComposerSkillSlot.slash:
        return SlashSkillReferenceBar(
          skills: _toSkillItems(_slashSkillSuggestions),
          onSelect: _insertSlashSkillReference,
        );
      case ComposerSkillSlot.suggestion:
        return SkillSuggestionBar(
          suggestions: _toSkillItems(_skillSuggestions),
          onSelect: _loadSuggestedSkill,
          onDismiss: _dismissSkillSuggestions,
        );
      case ComposerSkillSlot.loaded:
        return LoadedSkillBar(
          skills: sessionSkills
              .map((skill) => SkillSuggestionItem(
                    id: skill.id,
                    name: skill.name,
                    description: '',
                  ))
              .toList(growable: false),
          onRemove: _removeSessionSkill,
        );
      case ComposerSkillSlot.none:
        return const SizedBox.shrink();
    }
  }

  List<SkillSuggestionItem> _toSkillItems(List<_InstalledSkill> skills) =>
      skills
          .map((skill) => SkillSuggestionItem(
                id: skill.pack.id,
                name: skill.metadata.name,
                description: skill.metadata.description,
              ))
          .toList(growable: false);

  Widget _buildSessionMetricsBar({
    required List<ChatMessage> messages,
    required int totalSteps,
    required List<ToolActivity> toolActivities,
    required int liveContextTokens,
    required int contextTokens,
    required bool running,
  }) {
    final metrics = SessionMetrics.from(
      messages: messages,
      steps: totalSteps,
      toolExecutionMs: toolActivities.fold<int>(
        0,
        (sum, activity) => sum + activity.executionMs,
      ),
    );
    if (metrics.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: ValueListenableBuilder<BackgroundConfig>(
        valueListenable: BackgroundService.bgNotifier,
        builder: (context, background, _) => SessionMetricsBar(
          metrics: metrics,
          onImageBackground: background.mode != 'default',
          // 键盘弹出或运行中时收窄为 2 组：前者要腾出键盘上方空间，
          // 后者输入区已被运行状态条占用，不宜再堆一行满宽指标。
          maxGroups: (running || isKeyboardVisible(context)) ? 2 : null,
          onTap: () => showSessionMetricsSheet(
            context,
            metrics: metrics,
            liveContextTokens: liveContextTokens,
            contextLimit: contextTokens,
          ),
        ),
      ),
    );
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    // 灵敏检测：用户上滑离开底部超过 100px 立即唤出回底胶囊，避免抢屏
    final show = maxScroll - currentScroll > 100;
    if (show != _showScrollToBottom) {
      _showScrollToBottom = show;
      _scrollIndicatorRevision.value++;
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    HapticFeedback.lightImpact();
    _showScrollToBottom = false;
    _unreadNewMessagesCount = 0;
    _scrollIndicatorRevision.value++;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return false;
    return _scrollController.position.extentAfter <= 120;
  }

  /// 跟踪用户拖拽状态：`dragDetails` 仅在手指/触控拖拽时非空，程序化滚动为 null。
  /// 只关心纵向列表，忽略附件条等横向滚动通知。
  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is ScrollStartNotification) {
      _userDragging = notification.dragDetails != null;
    } else if (notification is ScrollUpdateNotification) {
      if (notification.dragDetails != null) _userDragging = true;
    } else if (notification is ScrollEndNotification) {
      _userDragging = false;
    }
    return false;
  }

  /// 合并同一帧内的流式滚动请求，避免每次文本刷新都重启动画。
  void _scheduleFollowTail({required bool animate}) {
    if (!_scrollController.hasClients) return;
    // 用户正在拖拽时不抢滚动位置：松手后由下一次流式回调自然接管跟随。
    if (_userDragging) return;
    if (!_isNearBottom()) {
      if (!_showScrollToBottom && mounted) {
        _showScrollToBottom = true;
        _scrollIndicatorRevision.value++;
      }
      return;
    }
    _followTailAnimate = _followTailAnimate || animate;
    if (_followTailScheduled) return;
    _followTailScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followTailScheduled = false;
      if (!mounted || !_scrollController.hasClients) return;
      if (_userDragging) {
        _followTailAnimate = false;
        return;
      }
      if (!_isNearBottom()) {
        if (!_showScrollToBottom) {
          _showScrollToBottom = true;
          _scrollIndicatorRevision.value++;
        }
        _followTailAnimate = false;
        return;
      }
      final target = _scrollController.position.maxScrollExtent;
      final animate =
          _followTailAnimate && !ref.read(chatControllerProvider).running;
      _followTailAnimate = false;
      if ((target - _scrollController.position.pixels).abs() < 2) return;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  void _consumeDeepLink() {
    final prompt = DeepLinkService.instance.drainPrompt();
    if (prompt != null && prompt.isNotEmpty) {
      _startNewConversation(initialText: prompt);
    }
    if (DeepLinkService.instance.drainNewAgent()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).push(NexusPageRoute.detail(
              builder: (_) => const AgentsPage(autoDescribe: true)));
        }
      });
    }
    if (DeepLinkService.instance.drainMemory()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context)
              .push(NexusPageRoute.detail(builder: (_) => const MemoryPage()));
        }
      });
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
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final approval in _pendingToolApprovals.values) {
      if (!approval.isCompleted) approval.complete(ToolApproval.reject);
    }
    _pendingToolApprovals.clear();
    _shareSub?.cancel();
    _skillSuggestionDebounce?.cancel();
    _draftPersistTimer?.cancel();
    _attachmentPanelExpanded.dispose();
    _controller.removeListener(_rememberCurrentDraft);
    _controller.removeListener(_onSkillInputChanged);
    _controller.dispose();
    _scrollController.dispose();
    _selectingMessageIndex.dispose();
    _scrollIndicatorRevision.dispose();
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
  void _onSharedText(String shared) {
    if (!mounted) return;
    _pendingSourceType = 'share';
    if (shared.startsWith('data:image/')) {
      try {
        final comma = shared.indexOf(',');
        final bytes = base64Decode(shared.substring(comma + 1));
        _startNewConversationWithAttachment(
          PlatformFile(name: '分享图片.jpg', size: bytes.length, bytes: bytes),
        ).then((_) {
          if (mounted) {
            FloatingToast.show(context, '已接收图片，可点击发送', tone: ToastTone.success);
          }
        });
      } catch (e) {
        FloatingToast.error(context, '图片分享解析失败', rawDetail: e.toString());
      }
      return;
    }
    _startNewConversation(initialText: shared);
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

    final requestId = _pendingClientRequestId ?? UniqueId.generate('req');
    _pendingClientRequestId = requestId;
    final attachments = List<PlatformFile>.of(_attachments);
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
    final matches = RegExp(r'(^|\s)/([a-z0-9_-]{1,64})(?=\s|$)')
        .allMatches(input)
        .toList(growable: false);
    if (matches.isEmpty) return input;

    for (final match in matches) {
      final name = match.group(2)!;
      final skill = _installedSkills
          .where((candidate) => candidate.metadata.name == name)
          .firstOrNull;
      if (skill == null) {
        FloatingToast.show(context, '未找到 Skill：/$name',
            tone: ToastTone.warning);
        return null;
      }
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
    }
    return input
        .replaceAll(RegExp(r'(^|\s)/[a-z0-9_-]{1,64}(?=\s|$)'), ' ')
        .trim();
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

  Widget _buildContextCompressionHint({
    required int liveContextTokens,
    required int contextTokens,
    required bool running,
    List<String> omittedContext = const [],
  }) {
    if (omittedContext.isEmpty &&
        (running || contextTokens <= 0 || liveContextTokens <= 0)) {
      return const SizedBox.shrink();
    }
    final ratio = contextTokens <= 0 ? 0.0 : liveContextTokens / contextTokens;
    if (omittedContext.isEmpty && ratio < .8) return const SizedBox.shrink();
    final warning = ratio >= .95;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: warning
            ? AppPalette.warning.withValues(alpha: .14)
            : AppPalette.brand.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          onTap: _showSessionContext,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(
                    warning
                        ? Icons.warning_amber_rounded
                        : Icons.compress_rounded,
                    size: 16,
                    color: warning ? AppPalette.warning : AppPalette.brand),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    omittedContext.isNotEmpty
                        ? '因预算省略：${omittedContext.join('、')}'
                        : warning
                            ? '上下文已接近容量，下一轮可能压缩较早记录'
                            : '上下文使用较高，较早记录将在接近上限时自动压缩',
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _stop() => _chat.stop();

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
    final restored = <PlatformFile>[];
    var missing = 0;
    for (final item in draft.attachments) {
      if (item.status == 'missing' || item.path.isEmpty) {
        missing++;
        continue;
      }
      restored.add(PlatformFile(name: item.name, path: item.path, size: 0));
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
  void _showSessionContext() {
    showNexusSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) => SessionContextSheet(
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
          onTap: _showSessionContext,
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

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: FileType.custom,
        allowedExtensions: [
          'png',
          'jpg',
          'jpeg',
          'webp',
          'gif',
          'txt',
          'md',
          'csv',
          'json',
          'mp3',
          'm4a',
          'wav',
          'ogg',
          'aac',
          'mp4',
          'mov',
          'webm',
          'mkv'
        ]);
    if (result == null || !mounted) return;
    _attachments.addAll(result.files);
    _notifyAttachmentsChanged();
  }

  /// 相册多选图片（A6：多图一次性发送）。
  Future<void> _pickMultiImage() async {
    try {
      final files = await _picker.pickMultiImage(
          maxWidth: 1280, maxHeight: 1280, imageQuality: 80);
      if (files.isEmpty || !mounted) return;
      final attachments = <PlatformFile>[];
      for (final xfile in files) {
        final bytes = await xfile.readAsBytes();
        attachments.add(PlatformFile(
            name: xfile.name, size: bytes.length, bytes: bytes));
      }
      if (mounted && attachments.isNotEmpty) {
        _attachments.addAll(attachments);
        _notifyAttachmentsChanged();
      }
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
      final name = xfile.name;
      _attachments.add(PlatformFile(
        name: name,
        size: bytes.length,
        bytes: bytes,
      ));
      _notifyAttachmentsChanged();
    } catch (e) {
      if (mounted) {
        FloatingToast.error(context, '无法获取图片', rawDetail: e.toString());
      }
    }
  }

  /// 消息长按菜单：助手消息 → 朗读 / 停止朗读 / 复制；用户消息 → 编辑 / 复制。
  Future<void> _showMessageActions(int messageIndex) async {
    final message = ref.read(chatControllerProvider).messages[messageIndex];
    final isUser = message.role == MessageRole.user;
    final tts = TtsService.instance;
    // 朗读只对助手正文开放（不含工具气泡）；平台不支持时不展示入口。
    final canSpeak = message.role == MessageRole.assistant && tts.isAvailable;
    final speaking = canSpeak && tts.isSpeaking;
    // 打开菜单即退出上一条消息的选择模式，避免两个状态并存。
    if (_selectingMessageIndex.value != null) {
      _selectingMessageIndex.value = null;
    }
    final action = await showNexusActionSheet<String>(
      context: context,
      title: AppStrings.messageActions,
      items: [
        if (canSpeak)
          ActionSheetItem(
            icon: speaking ? Icons.stop_rounded : Icons.volume_up_rounded,
            title: speaking ? AppStrings.stopSpeaking : AppStrings.speakAloud,
            value: 'speak',
          ),
        if (isUser)
          const ActionSheetItem(
            icon: Icons.edit_outlined,
            title: '编辑并重发',
            subtitle: '替换此消息，并重新生成其后的回复',
            value: 'edit',
          ),
        const ActionSheetItem(
          icon: Icons.call_split_outlined,
          title: '新建分支',
          subtitle: '只复制到此的对话上下文，不重放工具、不改文件',
          value: 'fork',
        ),
        const ActionSheetItem(
          icon: Icons.copy_outlined,
          title: AppStrings.copyFullText,
          value: 'copy',
        ),
        if (message.role != MessageRole.tool)
          const ActionSheetItem(
            icon: Icons.text_fields_rounded,
            title: AppStrings.selectText,
            subtitle: '进入后可拖动选择局部文本',
            value: 'select',
          ),
      ],
    );
    if (!mounted || action == null) return;
    if (action == 'edit') {
      await _editAndResend(messageIndex, message);
    } else if (action == 'fork') {
      try {
        await _chat.forkFromMessage(messageIndex);
        if (mounted) {
          FloatingToast.show(context, '已新建会话分支，不会重放工具或改文件',
              tone: ToastTone.success);
        }
      } catch (error) {
        if (mounted) {
          FloatingToast.show(context, '无法创建分支：$error', tone: ToastTone.warning);
        }
      }
    } else if (action == 'speak') {
      await _toggleSpeak(message.text);
    } else if (action == 'select') {
      _selectingMessageIndex.value = messageIndex;
    } else if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: message.text));
      if (mounted) {
        unawaited(HapticFeedback.lightImpact());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已复制全文'),
            duration: Duration(milliseconds: 1200),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// G1：按索引朗读消息（长按菜单与读屏动作共用的入口）。
  void _speakMessageAt(int index) {
    final messages = ref.read(chatControllerProvider).messages;
    if (index < 0 || index >= messages.length) return;
    unawaited(_toggleSpeak(messages[index].text));
  }

  /// G1：朗读 / 停止朗读助手消息正文。内容为空或设备不可用时给出提示。
  Future<void> _toggleSpeak(String markdown) async {
    final tts = TtsService.instance;
    if (tts.isSpeaking) {
      await tts.stop();
      return;
    }
    final content = speakableText(markdown);
    if (content.isEmpty) {
      if (mounted) {
        FloatingToast.show(context, AppStrings.noSpeakableContent);
      }
      return;
    }
    final started = await tts.speak(content);
    if (!started && mounted) {
      FloatingToast.show(context, AppStrings.ttsUnsupported);
    }
  }

  /// 编辑用户消息：确认后替换原消息并重新生成其后的回复。
  Future<void> _editAndResend(int messageIndex, ChatMessage message) async {
    if (ref.read(chatControllerProvider).running) return;
    final controller = TextEditingController(text: message.text);
    final submitted = await showNexusDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        return AlertDialog(
          title: const Text('编辑并重发'),
          content: TextField(
            controller: controller,
            maxLines: 6,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '输入新的内容',
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.14)
                              : Colors.black.withValues(alpha: 0.12),
                          width: 0.8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusControl),
                        ),
                      ),
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('取消'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppPalette.brand,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusControl),
                        ),
                      ),
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('保存并重发'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
    final newText = controller.text;
    // Dialog 路由退出动画结束前，TextField 仍可能访问 controller；延后一帧释放，
    // 避免快速点击保存/取消时出现 "used after disposed"。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
    if (submitted != true || !mounted) return;
    await _chat.editAndResend(
      messageIndex: messageIndex,
      newText: newText,
      approveTool: _approveTool,
    );
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
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 24, minHeight: 24),
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
                          duration: const Duration(milliseconds: 180),
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
                                  fontSize: 12,
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
                    fontSize: 11,
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
    final agents = await database.allAgents();
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
    // 注意：此处的 context 来自 Scaffold body 内的 LayoutBuilder，
    // 已是被消费过 inset 的作用域，必须用 isKeyboardVisible 而非
    // MediaQuery.viewInsetsOf（后者在这里恒为 0）。详见 keyboard_insets.dart。
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
      onAnalyzeWorkspace: () =>
          _fillSuggestion(const QuickAction(label: '解读项目')),
    );
  }

  String? _currentRunningStage({
    required List<ToolActivity> toolActivities,
    required bool running,
    required bool paused,
    required PlanState? planState,
  }) {
    if (!running) {
      if (planState != null && !planState.isConfirmed) {
        return '等待确认计划';
      }
      return null;
    }
    if (paused) return '已暂停，可继续或追加指令';
    final current = toolActivities.lastOrNull;
    if (current?.status == '等待确认') {
      return '等待确认：${current!.call.name}';
    }
    if (current?.status == '执行中') {
      return '正在执行：${current!.call.name}';
    }
    return '生成中…';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(chatControllerProvider, (previous, next) {
      if (previous == null) return;
      final messageAdded = next.messages.length > previous.messages.length;
      final completed = previous.running && !next.running;
      if (!_isNearBottom() && messageAdded) {
        _unreadNewMessagesCount +=
            next.messages.length - previous.messages.length;
        _showScrollToBottom = true;
        _scrollIndicatorRevision.value++;
      }
      if (next.running || messageAdded || completed) {
        _scheduleFollowTail(
            animate: (messageAdded || completed) && !next.running);
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
        final messages =
            ref.watch(chatControllerProvider.select((s) => s.messages));
        final running = ref.watch(runningProvider);
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
        final activityLog =
            ref.watch(chatControllerProvider.select((s) => s.activityLog));
        final toolActivities =
            ref.watch(chatControllerProvider.select((s) => s.toolActivities));
        final conversationTitle = ref
            .watch(chatControllerProvider.select((s) => s.conversationTitle));
        final totalSteps =
            ref.watch(chatControllerProvider.select((s) => s.totalSteps));
        final sessionSkills = ref.watch(
            chatControllerProvider.select((s) => s.sessionSkillInstructions));
        final omittedContext =
            ref.watch(chatControllerProvider.select((s) => s.omittedContext));

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
            body: ValueListenableBuilder<double>(
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
                                    errorBuilder: (_, __, ___) =>
                                        const SizedBox.shrink()),
                                'custom' when bg.customPath != null =>
                                  Image.file(
                                    File(bg.customPath!),
                                    fit: BoxFit.cover,
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
                          final hasTopDock = activityLog.isNotEmpty ||
                              (planState != null &&
                                  planState.status != 'cancelled') ||
                              toolActivities.isNotEmpty;
                          Widget column = Column(children: [
                            if (hasTopDock ||
                                glassIntensity == GlassIntensity.flat)
                              const SizedBox(
                                  height: kCapsuleTopBarHeight +
                                      4), // Clear the absolute positioned top bar
                            if (activityLog.isNotEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(activityLog.last,
                                      style:
                                          Theme.of(context).textTheme.bodySmall),
                                ),
                              ),
                            if ((planState != null &&
                                    planState.status != 'cancelled') ||
                                toolActivities.isNotEmpty)
                              Padding(
                                key: const ValueKey('chat_activity_dock'),
                                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    if (planState != null &&
                                        planState.status != 'cancelled')
                                      PlanPanel(
                                        plan: planState,
                                        goal: planState.steps.isEmpty
                                            ? null
                                            : planState.steps.first.description,
                                        onApprove: () =>
                                            _chat.respondToPlan(true),
                                        onCancel: () =>
                                            _chat.respondToPlan(false),
                                        onResume: () =>
                                            _chat.resumeFromBudgetPause(
                                                approveTool: _approveTool),
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
                            Expanded(
                              child: Stack(
                                children: [
                                  loading
                                      ? const NexusChatMessageSkeleton()
                                      : (messages.isEmpty
                                          ? _emptyState(context)
                                          : NotificationListener<
                                              ScrollNotification>(
                                              // 用户拖拽消息列表时暂停自动跟随，松手后恢复。
                                              onNotification:
                                                  _handleScrollNotification,
                                              child: Consumer(
                                                builder: (context, ref, _) {
                                                  // 高频流式文本在此单独订阅：只有本子树随
                                                  // liveReply 更新而重建，页面其余部分不动。
                                                  final liveReply = ref
                                                      .watch(liveReplyProvider);
                                                  return ValueListenableBuilder<
                                                      int?>(
                                                    valueListenable:
                                                        _selectingMessageIndex,
                                                    builder: (context,
                                                            selectionIndex, _) =>
                                                        ChatMessageList(
                                                    sessionKey: conversationId,
                                                    messages: messages,
                                                    liveReply: liveReply,
                                                    controller: _scrollController,
                                                    running: running,
                                                    padding: (hasTopDock ||
                                                            glassIntensity ==
                                                                GlassIntensity
                                                                    .flat)
                                                        ? const EdgeInsets
                                                            .fromLTRB(
                                                            16, 0, 16, 10)
                                                        : const EdgeInsets
                                                            .fromLTRB(
                                                            16,
                                                            kCapsuleTopBarHeight +
                                                                12,
                                                            16,
                                                            10,
                                                          ),
                                                    onLoadOlder: () =>
                                                        _chat.loadOlderMessages(),
                                                    onLongPress: (index) {
                                                      if (!_longPressHintShown) {
                                                        _longPressHintShown =
                                                            true;
                                                      }
                                                      _showMessageActions(index);
                                                    },
                                                    onRegenerate: _regenerate,
                                                    onEditPrompt:
                                                        _editLatestQuestion,
                                                    onSwitchModel:
                                                        _switchProvider,
                                                    onSpeak: TtsService
                                                            .instance.isAvailable
                                                        ? _speakMessageAt
                                                        : null,
                                                    speakingListenable: TtsService
                                                        .instance
                                                        .speakingListenable,
                                                          selectionIndex:
                                                              selectionIndex,
                                                          onExitSelection: () =>
                                                              _selectingMessageIndex
                                                                  .value = null,
                                                          trailingWidgets:
                                                              const [],
                                                        ),
                                                  );
                                                },
                                              ),
                                            )),
                                  Positioned(
                                    right: 16,
                                    bottom: 16,
                                    child: ValueListenableBuilder<int>(
                                      valueListenable:
                                          _scrollIndicatorRevision,
                                      builder: (context, _, __) {
                                        if (!_showScrollToBottom) {
                                          return const SizedBox.shrink();
                                        }
                                        return NexusBackToLatestButton(
                                          onTap: _scrollToBottom,
                                          unreadCount: _unreadNewMessagesCount,
                                          isRunning: running,
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
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  children: _attachments.map((file) {
                                    final name = file.name.toLowerCase();
                                    final isImage = name.endsWith('.jpg') ||
                                        name.endsWith('.png') ||
                                        name.endsWith('.jpeg') ||
                                        name.endsWith('.webp');
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
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
                                                      BorderRadius.circular(8),
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
                                            right: 0,
                                            top: 0,
                                            child: GestureDetector(
                                              onTap: () {
                                                _attachments.remove(file);
                                                _notifyAttachmentsChanged();
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.all(2),
                                                decoration: BoxDecoration(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .error,
                                                    shape: BoxShape.circle),
                                                child: Icon(Icons.close,
                                                    size: 12,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onError),
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
                            _buildSessionMetricsBar(
                              messages: messages,
                              totalSteps: totalSteps,
                              toolActivities: toolActivities,
                              liveContextTokens: liveContextTokens,
                              contextTokens: contextTokens,
                              running: running,
                            ),
                            _buildContextCompressionHint(
                              liveContextTokens: liveContextTokens,
                              contextTokens: contextTokens,
                              running: running,
                              omittedContext: omittedContext,
                            ),
                            // 技能提示只占一个槽位（/ 补全 > 自动建议 > 已加载），
                            // 避免三条 44dp 的同类横条在 360dp 屏上叠加。
                            _buildSkillPromptSlot(
                              running: running,
                              sessionSkills: sessionSkills,
                            ),
                            FloatingCapsuleInput(
                              glassIntensity: glassIntensity,
                              controller: _controller,
                              isRunning: running,
                              runningStage: _currentRunningStage(
                                toolActivities: toolActivities,
                                running: running,
                                paused: paused,
                                planState: planState,
                              ),
                              onSend: _send,
                              onStop: _stop,
                              onPause: () => _chat.pause(),
                              onResume: () => _chat.resume(),
                              isPaused: paused,
                              onAttachmentMenu: () {
                                _attachmentPanelExpanded.value =
                                    !_attachmentPanelExpanded.value;
                              },
                              approvalMode: approvalMode,
                              onApprovalModeTap: _selectApprovalMode,
                              modeLabel: chatMode.label,
                              onModeTap: _showSessionContext,
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
                              builder: (context, expanded, _) {
                                if (!expanded) return const SizedBox.shrink();
                                return AttachmentDrawerPanel(
                                  attachments: _attachments,
                                  onCamera: () async {
                                    _attachmentPanelExpanded.value = false;
                                    await _pickImage(ImageSource.camera);
                                  },
                                  onGallery: () async {
                                    _attachmentPanelExpanded.value = false;
                                    await _pickMultiImage();
                                  },
                                  onFile: () async {
                                    _attachmentPanelExpanded.value = false;
                                    await _pickFiles();
                                  },
                                );
                              },
                            ),
                          ]);
                          if (wide) {
                            column = Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 700),
                                child: column,
                              ),
                            );
                          }
                          return column;
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
                              runningStage: _currentRunningStage(
                                toolActivities: toolActivities,
                                running: running,
                                paused: paused,
                                planState: planState,
                              ),
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
                              onMenu: () => _scaffoldKey.currentState?.openDrawer(),
                              onNewChat: () => _startNewConversation(),
                              onContextGaugeTap: () =>
                                  _scaffoldKey.currentState?.openDrawer(),
                              onTitleTap: _showSessionContext,
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
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
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
                      fontSize: 14, fontWeight: FontWeight.w600),
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
                    fontSize: 13,
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
            style: TextStyle(fontSize: 12, color: muted),
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
              fontSize: 13,
              height: 1.35,
              color: forceHighlight ? AppPalette.warning : null,
            ),
          ),
        ),
      ],
    );
  }
}
