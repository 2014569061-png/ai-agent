import '../l10n/app_strings.dart';
import '../widgets/floating_toast.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:convert';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../application/chat_controller.dart';
import '../../application/app_lock_service.dart';
import '../../application/providers.dart';
import '../../application/tts_service.dart';
import '../../domain/models.dart';
import '../../infrastructure/database/app_database.dart';
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
import '../workspace/file_tree_sheet.dart';
import '../workspace/terminal_sheet.dart';

import 'widgets/floating_capsule_input.dart';
import 'widgets/environment_sheet.dart';
import '../../../infrastructure/background_service.dart';
import 'widgets/session_context_sheet.dart';
import 'widgets/capsule_top_bar.dart';
import 'widgets/chat_empty_state.dart';
import 'widgets/chat_message_list.dart';
import 'widgets/model_picker_sheet.dart';
import 'widgets/tool_activity_section.dart';
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
  final _attachments = <PlatformFile>[];
  final _speech = SpeechToText();
  final _picker = ImagePicker();
  final _recorder = AudioRecorder();
  final _scrollController = ScrollController();
  bool _showScrollToBottom = false;
  bool _followTailScheduled = false;
  bool _followTailAnimate = false;
  bool _listening = false;
  bool _recording = false;
  bool _longPressHintShown = false;
  final Map<String, String> _draftsByConversation = <String, String>{};
  StreamSubscription<String>? _shareSub;
  String _pendingTaskType = 'general';
  String _pendingSourceType = 'manual';

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
  }

  @override
  void initState() {
    super.initState();
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

  /// 合并同一帧内的流式滚动请求，避免每次文本刷新都重启动画。
  void _scheduleFollowTail({required bool animate}) {
    if (!_scrollController.hasClients) return;
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

  /// 检测是否有进程被杀前遗留的「运行中」任务，提示用户是否继续。
  Future<void> _checkRecoverableTask() async {
    try {
      final tasks = await _chat.recoverableTasks();
      if (!mounted || tasks.isEmpty) return;
      final resume = await showImmersiveDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('发现未完成的任务'),
          content: const Text('上次有一个 Agent 任务在后台中断，是否继续执行？'),
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
    _controller.dispose();
    _recorder.dispose();
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
      _maybeLock();
    } else {
      SystemNavigator.pop();
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
    final text = _controller.text.trim();
    // 纯附件（无文本）同样允许发送，与输入框可发送状态一致（文档 7.4）。
    final canSend = text.isNotEmpty || _attachments.isNotEmpty;
    if (!canSend || state.running || state.loading) return;

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

  void _regenerate() {
    _chat.regenerate(approveTool: _approveTool);
  }

  void _stop() => _chat.stop();

  String _buildMarkdown(ChatState state) {
    final content = StringBuffer('# ${state.conversationTitle}\n\n');
    for (final message in state.messages) {
      final role = switch (message.role) {
        MessageRole.user => '用户',
        MessageRole.assistant => '助手',
        MessageRole.system => '系统',
        MessageRole.tool => '工具',
      };
      content.write('## $role\n\n${message.text}\n\n');
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
          icon: Icons.smart_toy_outlined,
          title: 'Agent 管理',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AgentsPage()),
            );
          },
        ),
        ActionSheetItem(
          icon: Icons.settings_outlined,
          title: '设置',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsPage()),
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

  /// 附件入口：底部菜单在「拍照 / 相册 / 多图 / 文件 / 录音 / 粘贴图片」间选择。
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
        ActionSheetItem(
          icon: _recording ? Icons.stop_circle_outlined : Icons.mic_none,
          title: _recording ? '停止录音' : '录音',
          value: 'record',
        ),
        const ActionSheetItem(
          icon: Icons.content_paste_outlined,
          title: '粘贴图片',
          value: 'paste',
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
      case 'record':
        await _recordAudio();
      case 'paste':
        await _pasteClipboardImage();
    }
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

  /// 按住说话 / 点击切换语音识别。识别结果回填输入框，可继续编辑后发送。
  Future<void> _toggleVoice() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    try {
      final available = await _speech.initialize();
      if (!available) {
        if (mounted) FloatingToast.error(context, AppStrings.voiceError);
        return;
      }
      if (mounted) setState(() => _listening = true);
      await _speech.listen(
        onResult: (result) {
          if (result.finalResult) {
            final text = _controller.text.trim();
            _controller.text =
                (text.isEmpty ? '' : '$text ') + result.recognizedWords;
            _controller.selection =
                TextSelection.collapsed(offset: _controller.text.length);
            if (mounted) setState(() => _listening = false);
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _listening = false);
        FloatingToast.error(context, AppStrings.voiceError,
            rawDetail: e.toString());
      }
    }
  }

  /// A2：朗读助手消息（系统 TTS）。
  Future<void> _readAloud(ChatMessage message) async {
    final text = message.text.trim();
    if (text.isEmpty) return;
    await TtsService.instance.speak(text);
  }

  /// 消息长按菜单：助手消息 → 朗读 / 停止朗读 / 复制；用户消息 → 编辑 / 复制。
  Future<void> _showMessageActions(int messageIndex) async {
    final message = ref.read(chatControllerProvider).messages[messageIndex];
    final isUser = message.role == MessageRole.user;
    final action = await showImmersiveActionSheet<String>(
      context: context,
      title: '消息操作',
      items: [
        if (isUser)
          const ActionSheetItem(
            icon: Icons.edit_outlined,
            title: '编辑并重发',
            subtitle: '替换此消息，并重新生成其后的回复',
            value: 'edit',
          ),
        const ActionSheetItem(
          icon: Icons.volume_up_outlined,
          title: '朗读',
          value: 'read',
        ),
        const ActionSheetItem(
          icon: Icons.stop_circle_outlined,
          title: '停止朗读',
          value: 'stop',
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
    } else if (action == 'read') {
      await _readAloud(message);
    } else if (action == 'stop') {
      await TtsService.instance.stop();
    } else if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: message.text));
      if (mounted) {
        HapticFeedback.lightImpact();
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

  /// A6：本地录音，再次点击停止并加入附件。
  Future<void> _recordAudio() async {
    if (_recording) {
      final path = await _recorder.stop();
      _recording = false;
      if (path != null) {
        final bytes = await XFile(path).readAsBytes();
        if (!mounted) return;
        setState(() => _attachments.add(PlatformFile(
            name: '录音.m4a', size: bytes.length, path: path, bytes: bytes)));
        FloatingToast.show(context, '录音已添加', tone: ToastTone.success);
      }
      if (mounted) setState(() {});
      return;
    }
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) FloatingToast.error(context, '未获得麦克风权限');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          p.join(dir.path, 'rec-${DateTime.now().millisecondsSinceEpoch}.m4a');
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path);
      _recording = true;
      if (mounted) {
        setState(() {});
        FloatingToast.show(context, '录音中，再次点击停止');
      }
    } catch (e, stack) {
      debugPrint('录音启动失败: $e\n$stack');
      _recording = false;
      if (mounted) FloatingToast.error(context, '录音不可用');
    }
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
              Row(children: [
                const Icon(Icons.psychology_outlined),
                const SizedBox(width: 12),
                const Expanded(
                    child: Text('思考程度',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700))),
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
    const suggestions = [
      QuickAction(label: '解读项目'),
      QuickAction(label: '修复问题'),
      QuickAction(
        label: '头脑风暴',
        prompt:
            '帮我头脑风暴一下「」的创意方向。要求：先提出 3~5 个角度，再挑一个最有潜力的展开，最后给出下一步行动建议。',
      ),
      QuickAction(label: '解读工作区'),
    ];
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return ChatEmptyState(
      suggestions: suggestions,
      hasWorkspace: hasWorkspace,
      keyboardVisible: keyboardVisible,
      onSuggestionTap: _fillSuggestion,
    );
  }

  String? _currentRunningStage(ChatState state) {
    if (!state.running) {
      if (state.planState != null && !state.planState!.isConfirmed) {
        return '等待确认计划';
      }
      return null;
    }
    if (state.toolActivities.any((a) => a.status == 'running')) {
      return '工具执行中…';
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
        final state = ref.watch(chatControllerProvider);
        if (state.loading) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: Colors.transparent, // Background handled by stack
          drawer: ChatCatalogDrawer(
            currentConversationId: state.conversationId,
            currentWorkspacePath: state.currentWorkspacePath,
            contextTokens: state.contextTokens,
            liveContextTokens: state.liveContextTokens,
            activeModel: state.activeModel,
            activeProviderName: state.activeProviderName,
            messages: state.messages,
            isRunning: state.running,
            planModeEnabled: state.planMode,
            approvalMode: state.approvalMode,
            onApprovalModeTap: _selectApprovalMode,
            onNewConversation: () => _startNewConversation(),
            onSelectConversation: (conv) => _switchConversation(conv),
            onWorkspaceTap: _handleTopBarWorkspace,
            onModelTap: _switchProvider,
            onMcpMenu: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const McpServersPage()),
            ),
            onPromptLibrary: _openPromptLibrary,
            onPlanModeToggle: () => _chat.setPlanMode(!state.planMode),
            onMore: _showAvatarMenu,
            onOpenHistory: _openHistory,
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
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: Theme.of(context).brightness == Brightness.dark
                          ? const [
                              Color(0xFF000000), // Deep absolute black
                              Color(0xFF0A0F1C), // Very dark blue
                              Color(0xFF131124), // Dark purple/blue
                            ]
                          : const [
                              Color(0xFFFFFFFF), // Pure white
                              Color(0xFFF4F7FB), // Soft icy blue
                              Color(0xFFE6EFFF), // Light blue corner
                            ],
                    ),
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
                    if (state.activityLog.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(state.activityLog.last,
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                      ),
                    Expanded(
                      child: Stack(
                        children: [
                          state.messages.isEmpty
                              ? _emptyState(context)
                              : ChatMessageList(
                                  sessionKey: state.conversationId,
                                  messages: state.messages,
                                  liveReply: state.liveReply,
                                  controller: _scrollController,
                                  running: state.running,
                                  onLongPress: (index) {
                                    if (!_longPressHintShown) {
                                      _longPressHintShown = true;
                                    }
                                    _showMessageActions(index);
                                  },
                                  onRegenerate: _regenerate,
                                  trailingWidgets: [
                                    if (state.planState != null &&
                                        state.planState!.status != 'cancelled')
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: PlanPanel(
                                          plan: state.planState!,
                                          goal: state.planState!.steps.isEmpty
                                              ? null
                                              : state.planState!.steps.first
                                                  .description,
                                          onApprove: () =>
                                              _chat.respondToPlan(true),
                                          onCancel: () =>
                                              _chat.respondToPlan(false),
                                          onResume: () => _chat
                                              .resumeFromBudgetPause(
                                                  approveTool: _approveTool),
                                        ),
                                      ),
                                    if (state.toolActivities.isNotEmpty)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: ToolActivityCapsule(
                                          activities: state.toolActivities,
                                          running: state.running,
                                        ),
                                      ),
                                  ],
                                ),
                          if (_showScrollToBottom)
                            Positioned(
                              right: 16,
                              bottom: 16,
                              child: ImmersiveSurface(
                                level: ImmersiveMaterialLevel.thick,
                                borderRadius: BorderRadius.circular(20),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: _scrollToBottom,
                                    borderRadius: BorderRadius.circular(20),
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: state.running ? 10 : 8,
                                        vertical: 7,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer
                                            .withValues(alpha: 0.90),
                                        borderRadius: BorderRadius.circular(20),
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
                                          if (state.running) ...[
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
                                                fontWeight: FontWeight.w600,
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
                    const SizedBox(height: 6),
                    FloatingCapsuleInput(
                      controller: _controller,
                      isRunning: state.running,
                      runningStage: _currentRunningStage(state),
                      onSend: _send,
                      onStop: _stop,
                      onAttachmentMenu: _showAttachmentMenu,
                      onCommandMenu: _openPromptLibrary,
                      onMcpMenu: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const McpServersPage())),
                      onPlanModeToggle: () {
                        ref
                            .read(chatControllerProvider.notifier)
                            .setPlanMode(!state.planMode);
                      },
                      onApprovalModeTap: _selectApprovalMode,
                      onTerminalPreview: _openTerminal,
                      onEnvSetup: _openEnvSetup,
                      onOpenDashboard: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DashboardPage(
                            onConversationSelected: (c) =>
                                _switchConversation(c),
                          ),
                        ),
                      ),
                      planModeEnabled: state.planMode,
                      approvalMode: state.approvalMode,
                      onVoiceToggle: _toggleVoice,
                      isListening: _listening,
                      modelLabel: state.activeModel.isEmpty
                          ? (state.activeProviderName.isEmpty
                              ? null
                              : state.activeProviderName)
                          : state.activeModel,
                      workspaceLabel: state.currentWorkspacePath == null ||
                              state.currentWorkspacePath!.isEmpty
                          ? '无工作区'
                          : p.basename(state.currentWorkspacePath!),
                      onModelTap: _switchProvider,
                      onWorkspaceTap: _handleTopBarWorkspace,
                      hasAttachments: _attachments.isNotEmpty,
                      attachmentCount: _attachments.length,
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
              // G1 工具执行明细悬浮胶囊:悬浮于聊天之上,不内联挤压消息流。
              // G1 顶部渐变模糊条:消息从其下滚动穿过时渐隐(ZCode 顶栏样式)。
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: MediaQuery.paddingOf(context).top +
                    kCapsuleTopBarHeight +
                    4,
                // 仅负责视觉蒙版；不拦截其后绘制的顶部悬浮组件事件。
                child: IgnorePointer(
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Theme.of(context)
                                  .colorScheme
                                  .surface
                                  .withValues(alpha: .25),
                              Theme.of(context)
                                  .colorScheme
                                  .surface
                                  .withValues(alpha: .05),
                              Theme.of(context)
                                  .colorScheme
                                  .surface
                                  .withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 4,
                left: 12,
                right: 12,
                child: CapsuleTopBar(
                  maxContextTokens: state.contextTokens,
                  workspaceLabel: state.currentWorkspacePath == null ||
                          state.currentWorkspacePath!.isEmpty
                      ? null
                      : p.basename(state.currentWorkspacePath!),
                  modelLabel: state.activeModel.isNotEmpty
                      ? state.activeModel
                      : (state.activeProviderName.isEmpty
                          ? null
                          : state.activeProviderName),
                  sessionTitle: state.conversationTitle,
                  runningStage: _currentRunningStage(state),
                  statusActive: state.running,
                  currentContextTokens: state.liveContextTokens > 0
                      ? state.liveContextTokens
                      : state.messages.reversed
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
            ], // Stack children
          ), // Stack
        ); // Scaffold
      },
    );
  }
}
