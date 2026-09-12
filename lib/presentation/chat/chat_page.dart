import '../l10n/app_strings.dart';
import '../widgets/floating_toast.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:super_clipboard/super_clipboard.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../application/chat_controller.dart';
import '../../application/app_lock_service.dart';
import '../../application/providers.dart';
import '../../application/skill_intent_matcher.dart';
import '../../application/tts_text.dart';
import '../../domain/sensitive_tool_policy.dart';
import '../../domain/models.dart';
import '../../domain/session_metrics.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/skills/skill_parser.dart';
import '../../infrastructure/skills/skill_store.dart';
import '../../infrastructure/tts/tts_service.dart';
import '../../infrastructure/files/conversation_exporter.dart';
import '../../infrastructure/share/deep_link_service.dart';
import '../../infrastructure/share/sharing_service.dart';
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
import '../workspace/terminal_sheet.dart';
import '../workspace/development_workbench_page.dart';
import '../utils/keyboard_insets.dart';

import 'widgets/floating_capsule_input.dart';
import 'widgets/session_metrics_bar.dart';
import 'widgets/session_metrics_sheet.dart';
import 'widgets/input_tool_grid_sheet.dart';
import 'widgets/environment_sheet.dart';
import '../../../infrastructure/background_service.dart';
import 'widgets/session_context_sheet.dart';
import 'widgets/capsule_top_bar.dart';
import 'widgets/chat_empty_state.dart';
import 'widgets/chat_message_list.dart';
import 'widgets/model_picker_sheet.dart';
import 'widgets/tool_activity_section.dart';
import 'widgets/run_status_card.dart';
import 'widgets/skill_suggestion_bar.dart';
import 'widgets/chat_catalog_drawer.dart';
import '../widgets/immersive_sheet.dart';
import '../widgets/immersive_action_sheet.dart';
import '../widgets/immersive_surface.dart';
import '../widgets/tool_approval_helper.dart';
import '../theme/app_tokens.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage>
    with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  Future<void> _pickWorkspace() async {
    await ref.read(chatControllerProvider.notifier).pickWorkspace();
  }

  void _handleTopBarWorkspace() {
    final ws = ref.read(chatControllerProvider).currentWorkspacePath;
    if (ws == null || ws.isEmpty) {
      _pickWorkspace();
      return;
    }
    // 已有工作区：弹出操作面板，提供浏览 / 重选 / 解绑三条路径，
    // 修复“选定工作区后主界面无重新选择入口”的问题（复用会话上下文菜单同款能力）。
    showImmersiveActionSheet<void>(
      context: context,
      title: '当前工作区',
      subtitle: ws,
      items: [
        ActionSheetItem(
          title: '浏览文件树',
          subtitle: '在应用内查看与导航项目目录',
          icon: Icons.folder_open_rounded,
          onTap: _openFileTree,
        ),
        ActionSheetItem(
          title: '重新选择工作区',
          subtitle: '调用系统目录选择器更换目录',
          icon: Icons.drive_folder_upload_rounded,
          onTap: _pickWorkspace,
        ),
        ActionSheetItem(
          title: '解绑当前工作区',
          subtitle: '清除绑定，回到无工作区状态',
          icon: Icons.link_off_rounded,
          destructive: true,
          onTap: () {
            ref.read(chatControllerProvider.notifier).setWorkspace(null);
            FloatingToast.show(context, '已解绑工作区', tone: ToastTone.success);
          },
        ),
      ],
    );
  }

  void _openModelConfig() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

  void _openFileTree() {
    final ws = ref.read(chatControllerProvider).currentWorkspacePath;
    if (ws == null || ws.isEmpty) {
      _pickWorkspace();
      return;
    }
    showImmersiveSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: FileTreeSheet(
          workspacePath: ws,
          onReselectWorkspace: () =>
              _reselectWorkspaceFromSheet(sheetContext, ws),
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

  // G1 开发环境引导:检测/安装 Termux、授权、Go 工具链。
  void _openEnvSetup() {
    showImmersiveSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: const EnvironmentSheet(),
      ),
    );
  }

  void _openTerminal() {
    final ws = ref.read(chatControllerProvider).currentWorkspacePath;
    if (ws == null || ws.isEmpty) {
      _pickWorkspace();
      return;
    }
    showImmersiveSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.9,
        child: TerminalSheet(
          workspacePath: ws,
          onReselectWorkspace: () =>
              _reselectWorkspaceFromSheet(sheetContext, ws),
        ),
      ),
    );
  }

  final _controller = TextEditingController();
  final _skillStore = SkillStore();
  final _skillMatcher = SkillIntentMatcher();
  final _installedSkills = <_InstalledSkill>[];
  final _loadedSessionSkillIds = <String>{};
  List<_InstalledSkill> _skillSuggestions = const [];
  List<_InstalledSkill> _slashSkillSuggestions = const [];
  Timer? _skillSuggestionDebounce;
  bool _skillSuggestionsDismissed = false;
  final _attachments = <PlatformFile>[];
  final _picker = ImagePicker();
  final _scrollController = ScrollController();
  bool _showScrollToBottom = false;
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

  // 首页能力开关（对标 DeepSeek 的「深度思考」/「智能搜索」）。
  // 持久化键与 ChatController._prepareRun 读取的键保持完全一致，
  // 这样这里切换后，下一次发送即可生效，无需改动控制器。
  static const _kDeepReasoningPref = 'settings.llm.deep_reasoning';
  static const _kWebBrowsingPref = 'settings.tool.web_browsing';

  bool _deepThinking = true;
  bool _webSearch = true;

  ChatController get _chat => ref.read(chatControllerProvider.notifier);

  final BackgroundService _backgroundService = BackgroundService();

  void _rememberCurrentDraft() {
    final conversationId = ref.read(chatControllerProvider).conversationId;
    if (conversationId == null) return;
    final draft = _controller.text;
    if (draft.trim().isEmpty) {
      _draftsByConversation.remove(conversationId);
    } else {
      _draftsByConversation[conversationId] = draft;
    }
  }

  void _clearCurrentDraft() {
    final conversationId = ref.read(chatControllerProvider).conversationId;
    if (conversationId != null) {
      _draftsByConversation.remove(conversationId);
    }
  }

  void _restoreDraft(String? conversationId) {
    final draft = conversationId == null
        ? ''
        : (_draftsByConversation[conversationId] ?? '');
    _controller.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
  }

  Future<void> _startNewConversation({String? initialText}) async {
    _rememberCurrentDraft();
    await _chat.newConversation();
    if (!mounted) return;
    _attachments.clear();
    _restoreDraft(ref.read(chatControllerProvider).conversationId);
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
    setState(() => _attachments.add(attachment));
  }

  Future<void> _switchConversation(Conversation conversation) async {
    _rememberCurrentDraft();
    await _chat.switchConversation(conversation);
    if (!mounted ||
        ref.read(chatControllerProvider).conversationId != conversation.id) {
      return;
    }
    _attachments.clear();
    _restoreDraft(conversation.id);
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
    // 首页能力开关：读取「深度思考 / 智能搜索」的持久化状态。
    Future.microtask(_loadHomeToggles);
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

  /// 读取首页两个能力开关的持久化状态（默认均开启）。
  Future<void> _loadHomeToggles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deep = prefs.getBool(_kDeepReasoningPref) ?? true;
      final web = prefs.getBool(_kWebBrowsingPref) ?? true;
      if (!mounted) return;
      setState(() {
        _deepThinking = deep;
        _webSearch = web;
      });
    } catch (_) {
      // 读取失败时保持默认值（两项默认开启）。
    }
  }

  Future<void> _setHomeToggle(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {
      // 持久化失败不阻塞交互，本次会话内仍然生效。
    }
  }

  void _toggleDeepThinking() {
    final next = !_deepThinking;
    setState(() => _deepThinking = next);
    HapticFeedback.selectionClick();
    _setHomeToggle(_kDeepReasoningPref, next);
    FloatingToast.show(context, next ? '深度思考已开启' : '深度思考已关闭');
  }

  void _toggleWebSearch() {
    final next = !_webSearch;
    setState(() => _webSearch = next);
    HapticFeedback.selectionClick();
    _setHomeToggle(_kWebBrowsingPref, next);
    FloatingToast.show(context, next ? '智能搜索已开启' : '智能搜索已关闭');
  }

  /// 语音输入入口。当前工程未接入语音识别能力（无 speech 依赖、
  /// AndroidManifest 也未声明 RECORD_AUDIO），因此先给出明确提示，
  /// 待接入后把这里替换为「按住说话」的录音 / 转写流程即可。
  void _handleVoiceInput() {
    HapticFeedback.mediumImpact();
    FloatingToast.show(context, '语音输入尚未接入，可先用键盘输入');
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
      setState(() => _showScrollToBottom = show);
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    HapticFeedback.lightImpact();
    setState(() => _showScrollToBottom = false);
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
        setState(() => _showScrollToBottom = true);
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
          setState(() => _showScrollToBottom = true);
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
    if (DeepLinkService.instance.drainMemory()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const MemoryPage()));
        }
      });
    }
  }

  /// 检测可续跑的后台任务（进程被杀遗留的 running + 预算暂停的 paused），提示用户是否继续。
  Future<void> _checkRecoverableTask() async {
    try {
      final tasks = await _chat.recoverableTasks();
      if (!mounted || tasks.isEmpty) return;
      final resume = await showImmersiveDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('发现未完成的任务'),
          content: const Text('上次有 Agent 任务在后台中断或暂停，是否继续执行？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('忽略')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('继续执行')),
          ],
        ),
      );
      if (resume == true && mounted) {
        await _chat.resumeTask(tasks.first.id, approveTool: _approveTool);
      }
    } catch (e, stack) {
      debugPrint('恢复检测失败: $e\n$stack');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shareSub?.cancel();
    _skillSuggestionDebounce?.cancel();
    _controller.removeListener(_onSkillInputChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
    final retry = await showImmersiveDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('身份验证失败'),
        content: const Text('可重试，或退出应用。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('退出')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('重试')),
        ],
      ),
    );
    if (!mounted) return;
    if (retry == true) {
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
    final gotoConfig = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('尚未配置模型服务'),
        content: const Text('尚未配置模型服务，先去填入 API Key 或连接本地模型？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('去配置'),
          ),
        ],
      ),
    );

    if (gotoConfig == true && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProviderListPage()),
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
    if (!canSend || state.running || state.loading) return;

    final text = _resolveSlashSkillReferences(input);
    if (text == null) return;
    if (text.isEmpty && _attachments.isEmpty) {
      FloatingToast.show(context, '已加载 Skill，请补充任务内容', tone: ToastTone.warning);
      return;
    }

    final configured = await _ensureProviderConfigured();
    if (!configured) return;

    _clearCurrentDraft();
    _controller.clear();
    final attachments = List<PlatformFile>.of(_attachments);
    _attachments.clear();
    final taskType = _pendingTaskType;
    final sourceType = _pendingSourceType;
    _pendingTaskType = 'general';
    _pendingSourceType = 'manual';
    await _chat.send(
      text: text,
      attachments: attachments,
      approveTool: _approveTool,
      taskType: taskType,
      sourceType: sourceType,
    );
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
  }) {
    if (running || contextTokens <= 0 || liveContextTokens <= 0) {
      return const SizedBox.shrink();
    }
    final ratio = liveContextTokens / contextTokens;
    if (ratio < .8) return const SizedBox.shrink();
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
                    warning
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

  Future<void> _steerCurrentRun() async {
    final input = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('补充运行指令'),
        content: TextField(
          controller: input,
          autofocus: true,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(hintText: '下一轮执行时生效'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, input.text),
            child: const Text('加入'),
          ),
        ],
      ),
    );
    input.dispose();
    if (!mounted || text == null || text.trim().isEmpty) return;
    _chat.steer(text);
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
    showImmersiveSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SessionContextSheet(
        state: ref.read(chatControllerProvider),
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
        onReasoningEffort: () {
          Navigator.pop(sheetContext);
          _showReasoningEffortSheet();
        },
        onTogglePlanMode: () {
          ref
              .read(chatControllerProvider.notifier)
              .setPlanMode(!ref.read(chatControllerProvider).planMode);
        },
      ),
    );
  }

  Future<void> _switchProvider() async {
    final store = ref.read(providerConfigStoreProvider);
    final state = ref.read(chatControllerProvider);
    final currentId = state.activeProviderId;
    final profiles = await store.loadAll();
    if (!mounted) return;
    final selected = await showImmersiveSheet<ModelPickerSelection>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ModelPickerSheet(
        profiles: profiles,
        selectedId: currentId,
        reasoningEffort: state.activeReasoningEffort,
        planMode: state.planMode,
        onOpenSettings: () {
          Navigator.of(context).pop();
          _openModelConfig();
        },
        onOpenTools: () {
          Navigator.of(context).pop();
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const McpServersPage()));
        },
      ),
    );
    if (selected == null || !mounted) return;
    await _chat.switchProvider(selected.profile);
    if (selected.planMode != state.planMode) {
      _chat.setPlanMode(selected.planMode);
    }
    if (mounted) {
      FloatingToast.show(
          context, '已切换到 ${selected.profile.name} / ${selected.profile.model}');
    }
  }

  void _showAvatarMenu() {
    final state = ref.read(chatControllerProvider);
    showImmersiveActionSheet<void>(
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
              MaterialPageRoute(
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
          icon: Icons.build_circle_outlined,
          title: '开发工作台',
          subtitle: '一键执行构建模板并查看产物校验和',
          onTap: () async {
            final workspace =
                ref.read(chatControllerProvider).currentWorkspacePath;
            if (workspace == null || workspace.isEmpty) {
              if (mounted) {
                FloatingToast.show(context, '请先选择工作区', tone: ToastTone.warning);
              }
              return;
            }
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  DevelopmentWorkbenchPage(workspacePath: workspace),
            ));
          },
        ),
        ActionSheetItem(
          icon: Icons.dashboard_outlined,
          title: '仪表盘',
          subtitle: 'Token 消耗、费用指标与运行态',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DashboardPage()),
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
    setState(() => _attachments.addAll(result.files));
  }

  /// 相册多选图片（A6：多图一次性发送）。
  Future<void> _pickMultiImage() async {
    try {
      final files = await _picker.pickMultiImage(
          maxWidth: 1280, maxHeight: 1280, imageQuality: 80);
      if (files.isEmpty || !mounted) return;
      for (final xfile in files) {
        final bytes = await xfile.readAsBytes();
        if (mounted) {
          setState(() => _attachments.add(PlatformFile(
              name: xfile.name, size: bytes.length, bytes: bytes)));
        }
      }
    } catch (e) {
      if (mounted) {
        FloatingToast.error(context, '无法获取图片', rawDetail: e.toString());
      }
    }
  }

  /// 附件入口：底部菜单在「拍照 / 相册 / 多图 / 文件 / 粘贴图片」间选择。
  Future<void> _showAttachmentMenu() async {
    final choice = await showImmersiveActionSheet<String>(
      context: context,
      title: '添加附件',
      items: [
        const ActionSheetItem(
          icon: Icons.photo_camera_outlined,
          title: AppStrings.takePhoto,
          value: 'camera',
        ),
        const ActionSheetItem(
          icon: Icons.photo_library_outlined,
          title: AppStrings.fromGallery,
          value: 'gallery',
        ),
        const ActionSheetItem(
          icon: Icons.collections_outlined,
          title: '多图选择',
          value: 'multi',
        ),
        const ActionSheetItem(
          icon: Icons.attach_file,
          title: AppStrings.addFile,
          value: 'file',
        ),
        const ActionSheetItem(
          icon: Icons.content_paste_outlined,
          title: '粘贴图片',
          value: 'paste',
        ),
        const ActionSheetItem(
          icon: Icons.grid_view_rounded,
          title: '更多工具',
          subtitle: '命令、MCP、终端、环境与仪表盘',
          value: 'tools',
        ),
        ActionSheetItem(
          icon: Icons.checklist_rounded,
          title:
              ref.read(chatControllerProvider).planMode ? '关闭计划模式' : '开启计划模式',
          value: 'plan',
        ),
        if (ref.read(chatControllerProvider).running)
          const ActionSheetItem(
            icon: Icons.playlist_add_rounded,
            title: '补充运行指令',
            subtitle: '不打断当前运行，下一轮执行时生效',
            value: 'steer',
          ),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'camera':
        await _pickImage(ImageSource.camera);
      case 'gallery':
        await _pickImage(ImageSource.gallery);
      case 'multi':
        await _pickMultiImage();
      case 'file':
        await _pickFiles();
      case 'paste':
        await _pasteClipboardImage();
      case 'tools':
        if (mounted) _openToolsSheet();
      case 'plan':
        _chat.setPlanMode(!ref.read(chatControllerProvider).planMode);
      case 'steer':
        await _steerCurrentRun();
    }
  }

  /// 「更多工具」网格：承接原先输入区「工具」chip 的全部能力
  /// （命令库 / MCP / 终端 / 环境 / 仪表盘 / 计划模式 / 审批模式）。
  ///
  /// 对标 DeepSeek 后输入区只保留「深度思考 / 智能搜索」两个 chip，
  /// 这些进阶入口统一收进「＋」菜单，避免首页出现第三个 chip。
  void _openToolsSheet() {
    final state = ref.read(chatControllerProvider);
    InputToolGridSheet.show(
      context,
      onCommandMenu: _openPromptLibrary,
      onMcpMenu: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const McpServersPage())),
      onTerminalPreview: _openTerminal,
      onEnvSetup: _openEnvSetup,
      onOpenDashboard: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DashboardPage(
            onConversationSelected: (c) => _switchConversation(c),
          ),
        ),
      ),
      onOpenWorkbench: () {
        Navigator.of(context).pop();
        final workspace = ref.read(chatControllerProvider).currentWorkspacePath;
        if (workspace == null || workspace.isEmpty) {
          FloatingToast.show(context, '请先选择工作区', tone: ToastTone.warning);
          return;
        }
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DevelopmentWorkbenchPage(workspacePath: workspace),
        ));
      },
      planModeEnabled: state.planMode,
      onPlanModeToggle: () => _chat.setPlanMode(!state.planMode),
      approvalMode: state.approvalMode,
      onApprovalModeTap: _selectApprovalMode,
    );
  }

  /// 拍照/相册：压缩到 1280px / 80% 质量，控制 base64 体积，复用现有附件管线。
  Future<void> _pickImage(ImageSource source) async {
    try {
      final xfile = await _picker.pickImage(
          source: source, maxWidth: 1280, maxHeight: 1280, imageQuality: 80);
      if (xfile == null || !mounted) return;
      final bytes = await xfile.readAsBytes();
      final name = xfile.name;
      setState(() => _attachments
          .add(PlatformFile(name: name, size: bytes.length, bytes: bytes)));
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
    final action = await showImmersiveActionSheet<String>(
      context: context,
      title: '消息操作',
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
          icon: Icons.copy_outlined,
          title: '复制全文',
          value: 'copy',
        ),
      ],
    );
    if (!mounted || action == null) return;
    if (action == 'edit') {
      await _editAndResend(messageIndex, message);
    } else if (action == 'speak') {
      await _toggleSpeak(message.text);
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
    final submitted = await showImmersiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑并重发'),
        content: TextField(
          controller: controller,
          maxLines: 6,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入新的内容',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存并重发')),
        ],
      ),
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

  /// A5：从剪贴板粘贴图片为附件。
  Future<void> _pasteClipboardImage() async {
    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) {
        if (mounted) FloatingToast.error(context, '剪贴板不可用');
        return;
      }
      final reader = await clipboard.read();
      FileFormat format;
      String ext;
      if (reader.canProvide(Formats.png)) {
        format = Formats.png;
        ext = 'png';
      } else if (reader.canProvide(Formats.jpeg)) {
        format = Formats.jpeg;
        ext = 'jpg';
      } else {
        if (mounted) FloatingToast.error(context, '剪贴板没有图片');
        return;
      }
      final bytes = await _readClipboardFile(reader, format);
      if (bytes == null) {
        if (mounted) FloatingToast.error(context, '无法读取剪贴板图片');
        return;
      }
      if (mounted) {
        setState(() => _attachments.add(PlatformFile(
            name: '剪贴板图片.$ext', size: bytes.length, bytes: bytes)));
        FloatingToast.show(context, '已粘贴图片', tone: ToastTone.success);
      }
    } catch (e) {
      if (mounted) {
        FloatingToast.error(context, '无法读取剪贴板，请手动选图', rawDetail: e.toString());
      }
    }
  }

  /// 通过 super_clipboard 的 getFile 回调读取图片字节。
  Future<Uint8List?> _readClipboardFile(
      ClipboardReader reader, FileFormat format) {
    final completer = Completer<Uint8List?>();
    reader.getFile(
      format,
      (file) async {
        try {
          completer.complete(await file.readAll());
        } catch (_) {
          completer.complete(null);
        }
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    return completer.future
        .timeout(const Duration(seconds: 8), onTimeout: () => null);
  }

  Future<ToolApproval> _approveTool(ToolCall call, ToolRisk risk) =>
      promptToolApproval(context, ref, call, risk);

  Future<void> _selectApprovalMode() async {
    final currentMode = ref.read(chatControllerProvider).approvalMode;
    final selected = await showImmersiveActionSheet<ApprovalMode>(
      context: context,
      title: '操作权限',
      items: [
        for (final mode in ApprovalMode.values)
          ActionSheetItem(
            icon: mode == ApprovalMode.fullAccess
                ? Icons.shield_outlined
                : Icons.verified_user_outlined,
            title: _approvalModeTitle(mode),
            subtitle: _approvalModeDescription(mode),
            selected: currentMode == mode,
            value: mode,
          ),
      ],
    );
    if (selected != null && mounted) {
      ref.read(chatControllerProvider.notifier).setApprovalMode(selected);
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
    final selected = await showImmersiveSheet<Agent>(
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
      MaterialPageRoute(builder: (_) => const HistoryPage()),
    );
    if (selected == null || !mounted) return;
    await _switchConversation(selected);
  }

  Future<void> _openPromptLibrary() async {
    final result = await Navigator.of(context).push<PromptApplyResult>(
      MaterialPageRoute(builder: (_) => const PromptLibraryPage()),
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

  Future<void> _showReasoningEffortSheet() async {
    final store = ref.read(providerConfigStoreProvider);
    final config = await store.load();
    if (!mounted) return;
    final effort = await showImmersiveSheet<ReasoningEffort>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.psychology_outlined),
                SizedBox(width: 12),
                Expanded(
                    child: Text('思考程度',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500))),
              ]),
              const SizedBox(height: 4),
              const Text(
                  '仅推理模型（OpenAI o1/o3/GPT-5、Claude thinking、Gemini 2.0 thinking）生效，其他模型忽略。',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.mutedOnGlassLight)),
              const SizedBox(height: 16),
              Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: ReasoningEffort.values
                      .map((e) => ChoiceChip(
                            label: Text(_effortLabel(e)),
                            selected: config.reasoningEffort == e,
                            onSelected: (_) => Navigator.pop(context, e),
                          ))
                      .toList()),
            ],
          ),
        ),
      ),
    );
    if (effort == null || !mounted) return;
    await store.save(config.copyWith(reasoningEffort: effort));
    _chat.setReasoningEffort(effort);
    if (mounted) {
      FloatingToast.show(context, '思考程度已设为「${_effortLabel(effort)}」');
    }
  }

  String _effortLabel(ReasoningEffort effort) {
    switch (effort) {
      case ReasoningEffort.off:
        return '关';
      case ReasoningEffort.low:
        return '低';
      case ReasoningEffort.medium:
        return '中';
      case ReasoningEffort.high:
        return '高';
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
        const QuickAction(id: 'select_workspace', label: '选择工作区'),
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
      keyboardVisible: keyboardVisible,
      workspaceLabel: hasWorkspace ? p.basename(ws) : null,
      modelLabel: state.activeModel.isNotEmpty
          ? state.activeModel
          : state.activeProviderName,
      onSuggestionTap: _fillSuggestion,
      onWorkspaceTap: _handleTopBarWorkspace,
      onModelTap: _switchProvider,
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

        if (loading) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator(strokeWidth: 2)));
        }
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: Colors.transparent, // Background handled by stack
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
              MaterialPageRoute(builder: (_) => const McpServersPage()),
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
          body: Stack(
            // 顶部悬浮层（顶栏、计划与工具面板）允许展示自身阴影，
            // 不受页面 Stack 的默认裁剪影响。
            clipBehavior: Clip.none,
            children: [
              // G1 聊天背景:自定义图 > 默认云朵图 > 渐变兜底;轻微 scrim 保消息可读。
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppPalette.darkCanvas
                        : AppPalette.lightCanvas,
                  ),
                ),
              ),
              Positioned.fill(
                child: ValueListenableBuilder<BackgroundConfig>(
                  valueListenable: BackgroundService.bgNotifier,
                  builder: (context, bg, _) {
                    final dark =
                        Theme.of(context).brightness == Brightness.dark;
                    final Widget? image = switch (bg.mode) {
                      'clouds' => Image.asset(BackgroundService.cloudsAsset,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const SizedBox.shrink()),
                      'custom' when bg.customPath != null => Image.file(
                          File(bg.customPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const SizedBox.shrink()),
                      _ => null,
                    };
                    if (image == null) return const SizedBox.shrink();
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
              SafeArea(
                bottom: false,
                child: LayoutBuilder(builder: (context, constraints) {
                  // 横屏 / 平板等宽屏下限制正文最大宽度，避免输入框与卡片过宽（文档 9）。
                  final wide = constraints.maxWidth > 700;
                  Widget column = Column(children: [
                    const SizedBox(
                        height: kCapsuleTopBarHeight +
                            4), // Clear the absolute positioned top bar
                    // 计划面板改为 Stack 顶层悬浮，避免挤压消息区和被顶部蒙版覆盖。
                    if (activityLog.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(activityLog.last,
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                      ),
                    Expanded(
                      child: Stack(
                        children: [
                          messages.isEmpty
                              ? _emptyState(context)
                              : NotificationListener<ScrollNotification>(
                                  // 用户拖拽消息列表时暂停自动跟随，松手后恢复。
                                  onNotification: _handleScrollNotification,
                                  child: Consumer(
                                    builder: (context, ref, _) {
                                      // 高频流式文本在此单独订阅：只有本子树随
                                      // liveReply 更新而重建，页面其余部分不动。
                                      final liveReply =
                                          ref.watch(liveReplyProvider);
                                      return ChatMessageList(
                                        sessionKey: conversationId,
                                        messages: messages,
                                        liveReply: liveReply,
                                        controller: _scrollController,
                                        running: running,
                                        onLoadOlder: () =>
                                            _chat.loadOlderMessages(),
                                        onLongPress: (index) {
                                          if (!_longPressHintShown) {
                                            _longPressHintShown = true;
                                          }
                                          _showMessageActions(index);
                                        },
                                        onRegenerate: _regenerate,
                                        onEditPrompt: _editLatestQuestion,
                                        onSwitchModel: _switchProvider,
                                        onSpeak: TtsService.instance.isAvailable
                                            ? _speakMessageAt
                                            : null,
                                        speakingListenable: TtsService
                                            .instance.speakingListenable,
                                        trailingWidgets: [
                                          if (planState != null &&
                                              planState.status != 'cancelled')
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 12),
                                              child: PlanPanel(
                                                plan: planState,
                                                goal: planState.steps.isEmpty
                                                    ? null
                                                    : planState.steps.first
                                                        .description,
                                                onApprove: () =>
                                                    _chat.respondToPlan(true),
                                                onCancel: () =>
                                                    _chat.respondToPlan(false),
                                                onResume: () =>
                                                    _chat.resumeFromBudgetPause(
                                                        approveTool:
                                                            _approveTool),
                                              ),
                                            ),
                                          if (toolActivities.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 12),
                                              child: ToolActivityCapsule(
                                                activities: toolActivities,
                                                running: running,
                                              ),
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                          if (_showScrollToBottom)
                            Positioned(
                              right: 16,
                              bottom: 16,
                              child: ImmersiveSurface(
                                level: ImmersiveMaterialLevel.thick,
                                borderRadius:
                                    BorderRadius.circular(AppTokens.radiusPill),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: _scrollToBottom,
                                    borderRadius: BorderRadius.circular(
                                        AppTokens.radiusPill),
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: running ? 12 : 8,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer
                                            .withValues(alpha: 0.90),
                                        borderRadius: BorderRadius.circular(
                                            AppTokens.radiusPill),
                                        border: Border.all(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withValues(alpha: 0.35),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (running) ...[
                                            SizedBox(
                                              width: 12,
                                              height: 12,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                        Color>(
                                                  Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              '生成中 · 回到底部',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onPrimaryContainer,
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                          ],
                                          Icon(
                                            Icons.arrow_downward_rounded,
                                            size: 16,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onPrimaryContainer,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_attachments.isNotEmpty)
                      SizedBox(
                        height: 56,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
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
                                    margin:
                                        const EdgeInsets.only(top: 4, right: 4),
                                    child: ImmersiveSurface(
                                      level: ImmersiveMaterialLevel.thin,
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          image: isImage && file.bytes != null
                                              ? DecorationImage(
                                                  image:
                                                      MemoryImage(file.bytes!),
                                                  fit: BoxFit.cover)
                                              : null,
                                        ),
                                        child: !isImage || file.bytes == null
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
                                      onTap: () => setState(
                                          () => _attachments.remove(file)),
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
                    if (running)
                      RunStatusCard(
                        stage: _currentRunningStage(
                              toolActivities: toolActivities,
                              running: running,
                              paused: paused,
                              planState: planState,
                            ) ??
                            '正在执行',
                        toolCount: toolActivities.length,
                        paused: paused,
                        awaitingApproval:
                            toolActivities.lastOrNull?.status == '等待确认',
                        onStop: _stop,
                      ),
                    _buildContextCompressionHint(
                      liveContextTokens: liveContextTokens,
                      contextTokens: contextTokens,
                      running: running,
                    ),
                    // 技能提示只占一个槽位（/ 补全 > 自动建议 > 已加载），
                    // 避免三条 44dp 的同类横条在 360dp 屏上叠加。
                    _buildSkillPromptSlot(
                      running: running,
                      sessionSkills: sessionSkills,
                    ),
                    FloatingCapsuleInput(
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
                      onAttachmentMenu: _showAttachmentMenu,
                      onVoiceInput: _handleVoiceInput,
                      deepThinking: _deepThinking,
                      onDeepThinkingToggle: _toggleDeepThinking,
                      webSearch: _webSearch,
                      onWebSearchToggle: _toggleWebSearch,
                      planModeEnabled: planMode,
                      hasAttachments: _attachments.isNotEmpty,
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
                  child: CapsuleTopBar(
                    maxContextTokens: contextTokens,
                    workspaceLabel: currentWorkspacePath == null ||
                            currentWorkspacePath.isEmpty
                        ? null
                        : p.basename(currentWorkspacePath),
                    modelLabel: activeModel.isNotEmpty
                        ? activeModel
                        : (activeProviderName.isEmpty
                            ? null
                            : activeProviderName),
                    sessionTitle: messages.isEmpty ? null : conversationTitle,
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
                  ),
                ),
              ),
            ], // Stack children
          ), // Stack
        ); // Scaffold
      },
    );
  }
}

class _InstalledSkill {
  const _InstalledSkill(this.pack, this.metadata);

  final SkillPack pack;
  final SkillMetadata metadata;
}
