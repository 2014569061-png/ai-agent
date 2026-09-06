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
import '../../application/audit_service.dart';
import '../../application/providers.dart';
import '../../application/tts_service.dart';
import '../../domain/models.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/files/conversation_exporter.dart';
import '../../infrastructure/share/deep_link_service.dart';
import '../../infrastructure/share/sharing_service.dart';
import '../agents/agents_page.dart';
import '../history/history_page.dart';
import '../memory/memory_page.dart';
import '../mcp/mcp_servers_page.dart';
import '../prompts/prompt_library_page.dart';
import 'widgets/plan_panel.dart';
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
import 'widgets/tool_approval_sheet.dart';
import 'widgets/chat_catalog_drawer.dart';
import '../widgets/immersive_sheet.dart';
import '../widgets/immersive_surface.dart';
import '../theme/app_tokens.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage>
    with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void _pickWorkspace() async {
    await ref.read(chatControllerProvider.notifier).pickWorkspace();
  }

  void _handleTopBarWorkspace() {
    final ws = ref.read(chatControllerProvider).currentWorkspacePath;
    if (ws == null || ws.isEmpty) {
      _pickWorkspace();
    } else {
      _openFileTree();
    }
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
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: FileTreeSheet(workspacePath: ws),
      ),
    );
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
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.9,
        child: TerminalSheet(workspacePath: ws),
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
  bool _listening = false;
  bool _recording = false;
  bool _longPressHintShown = false;
  StreamSubscription<String>? _shareSub;

  ChatController get _chat => ref.read(chatControllerProvider.notifier);

  final BackgroundService _backgroundService = BackgroundService();

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
    final show = maxScroll - currentScroll > 250;
    if (show != _showScrollToBottom) {
      setState(() => _showScrollToBottom = show);
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _consumeDeepLink() {
    final prompt = DeepLinkService.instance.drainPrompt();
    if (prompt != null && prompt.isNotEmpty) {
      _chat.newConversation();
      _controller.text = prompt;
      _controller.selection = TextSelection.collapsed(offset: prompt.length);
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
    } catch (_) {
      // 恢复检测失败不阻断启动。
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
    if (shared.startsWith('data:image/')) {
      try {
        final comma = shared.indexOf(',');
        final bytes = base64Decode(shared.substring(comma + 1));
        _chat.newConversation();
        setState(() => _attachments.add(
            PlatformFile(name: '分享图片.jpg', size: bytes.length, bytes: bytes)));
        FloatingToast.show(context, '已接收图片，可点击发送', tone: ToastTone.success);
      } catch (e) {
        FloatingToast.error(context, '图片分享解析失败', rawDetail: e.toString());
      }
      return;
    }
    _chat.newConversation();
    _controller.text = shared;
    _controller.selection = TextSelection.collapsed(offset: shared.length);
  }

  // --- 操作 ---

  Future<void> _send() async {
    final state = ref.read(chatControllerProvider);
    final text = _controller.text.trim();
    // 纯附件（无文本）同样允许发送，与输入框可发送状态一致（文档 7.4）。
    final canSend = text.isNotEmpty || _attachments.isNotEmpty;
    if (!canSend || state.running || state.loading) return;
    _controller.clear();
    final attachments = List<PlatformFile>.of(_attachments);
    _attachments.clear();
    await _chat.send(
        text: text, attachments: attachments, approveTool: _approveTool);
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
      builder: (context) => SessionContextSheet(
        state: ref.read(chatControllerProvider),
        onSelectModel: _switchProvider,
        onSelectAgent: _selectAgent,
        onPickWorkspace: _pickWorkspace,
        onClearWorkspace: () =>
            ref.read(chatControllerProvider.notifier).setWorkspace(null),
        onReasoningEffort: _showReasoningEffortSheet,
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
    showImmersiveSheet<void>(
      context: context,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .72,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          children: [
            ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: const Text('会话上下文'),
              onTap: () {
                Navigator.pop(context);
                _showSessionContext();
              },
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text(AppStrings.switchModel),
              onTap: () {
                Navigator.pop(context);
                _switchProvider();
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text(AppStrings.regenerate),
              enabled: !state.running &&
                  state.messages.isNotEmpty &&
                  state.messages.last.role == MessageRole.assistant,
              onTap: () {
                Navigator.pop(context);
                _regenerate();
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_copy_outlined),
              title: const Text(AppStrings.copyConversation),
              enabled: state.messages.isNotEmpty,
              onTap: () {
                Navigator.pop(context);
                _copyConversation();
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text(AppStrings.exportMarkdown),
              enabled: state.messages.isNotEmpty,
              onTap: () {
                Navigator.pop(context);
                _exportConversation();
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('分享会话'),
              enabled: state.messages.isNotEmpty,
              onTap: () {
                Navigator.pop(context);
                _shareConversation();
              },
            ),
            ListTile(
              leading: const Icon(Icons.smart_toy_outlined),
              title: const Text('Agent 管理'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AgentsPage()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('设置'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsPage()));
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFiles() async {
    final state = ref.read(chatControllerProvider);
    if (state.running) return;
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
          'pdf',
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
    final state = ref.read(chatControllerProvider);
    if (state.running) return;
    final choice = await showImmersiveSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text(AppStrings.takePhoto),
              onTap: () => Navigator.pop(context, 'camera')),
          ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text(AppStrings.fromGallery),
              onTap: () => Navigator.pop(context, 'gallery')),
          ListTile(
              leading: const Icon(Icons.collections_outlined),
              title: const Text('多图选择'),
              onTap: () => Navigator.pop(context, 'multi')),
          ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text(AppStrings.addFile),
              onTap: () => Navigator.pop(context, 'file')),
          ListTile(
              leading: Icon(
                  _recording ? Icons.stop_circle_outlined : Icons.mic_none),
              title: Text(_recording ? '停止录音' : '录音'),
              onTap: () => Navigator.pop(context, 'record')),
          ListTile(
              leading: const Icon(Icons.content_paste_outlined),
              title: const Text('粘贴图片'),
              onTap: () => Navigator.pop(context, 'paste')),
        ]),
      ),
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
    final action = await showImmersiveSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (isUser)
            ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('编辑并重发'),
                subtitle: const Text('替换此消息，并重新生成其后的回复'),
                onTap: () => Navigator.pop(context, 'edit')),
          ListTile(
              leading: const Icon(Icons.volume_up_outlined),
              title: const Text('朗读'),
              onTap: () => Navigator.pop(context, 'read')),
          ListTile(
              leading: const Icon(Icons.stop_circle_outlined),
              title: const Text('停止朗读'),
              onTap: () => Navigator.pop(context, 'stop')),
          ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('复制全文'),
              onTap: () => Navigator.pop(context, 'copy')),
        ]),
      ),
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
    if (submitted != true || !mounted) return;
    await _chat.editAndResend(
      messageIndex: messageIndex,
      newText: controller.text,
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
    } catch (_) {
      _recording = false;
      if (mounted) FloatingToast.error(context, '录音不可用');
    }
  }

  Future<ToolApproval> _approveTool(ToolCall call, ToolRisk risk) async {
    if (!mounted) return ToolApproval.reject;
    final trust = await ref.read(toolTrustStoreProvider.future);
    if (!mounted) return ToolApproval.reject;
    // 信任清单直通：命中（含本会话允许）直接放行，不再打断用户。
    if (trust.isTrusted(call.name, risk)) {
      return ToolApproval.allowAlways;
    }
    final decision = await showImmersiveSheet<ToolApproval>(
      context: context,
      builder: (context) => ToolApprovalSheet(call: call, risk: risk),
    );
    // 记录会话级/始终允许的授予，便于审计追溯；授予失败不阻断主流程。
    if (decision == ToolApproval.allowAlways ||
        decision == ToolApproval.allowSession) {
      if (decision == ToolApproval.allowAlways) {
        await trust.allowAlways(call.name);
      } else {
        trust.allowSession(call.name);
      }
      _recordToolGrant(call, risk, decision!);
    }
    return decision ?? ToolApproval.reject;
  }

  /// 把「始终允许 / 本会话允许」的授予写入审计，溯源决策链路。
  void _recordToolGrant(ToolCall call, ToolRisk risk, ToolApproval decision) {
    final audit = ref.read(auditServiceProvider);
    final db = ref.read(databaseProvider.future);
    db.then((database) {
      audit.log(
        database,
        type: 'tool_grant',
        detail: call.name,
        decision: decision.name,
        risk: risk.name,
        conversationId: ref.read(chatControllerProvider).conversationId,
      );
    });
  }

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
    final state = ref.read(chatControllerProvider);
    if (state.running) return;
    final selected = await Navigator.of(context).push<Conversation>(
      MaterialPageRoute(builder: (_) => const HistoryPage()),
    );
    if (selected == null || !mounted) return;
    await _chat.switchConversation(selected);
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

  void _fillSuggestion(String text) {
    final state = ref.read(chatControllerProvider);
    final needsWorkspace =
        !(state.currentWorkspacePath?.trim().isNotEmpty ?? false) &&
            (text == '解读项目' || text == '修复问题' || text == '解读工作区');
    if (needsWorkspace) {
      _pickWorkspaceAndFill(text);
      return;
    }
    _fillInput(text);
  }

  Future<void> _pickWorkspaceAndFill(String text) async {
    await ref.read(chatControllerProvider.notifier).pickWorkspace();
    if (!mounted) return;
    _fillInput(text);
  }

  void _fillInput(String text) {
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
  }

  Widget _emptyState(BuildContext context) {
    final state = ref.read(chatControllerProvider);
    final ws = state.currentWorkspacePath;
    final hasWorkspace = ws != null && ws.isNotEmpty;
    final suggestions = const ['解读项目', '修复问题', '头脑风暴', '解读工作区'];
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return ChatEmptyState(
      suggestions: suggestions,
      hasWorkspace: hasWorkspace,
      keyboardVisible: keyboardVisible,
      onSuggestionTap: _fillSuggestion,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(chatControllerProvider, (previous, next) {
      if (previous == null) return;
      if ((next.running || next.messages.length > previous.messages.length) &&
          !_showScrollToBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
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
            currentWorkspacePath: state.currentWorkspacePath,
            contextTokens: state.contextTokens,
            activeModel: state.activeModel,
            activeProviderName: state.activeProviderName,
            messages: state.messages,
            isRunning: state.running,
            planModeEnabled: state.planMode,
            onNewConversation: () => _chat.newConversation(),
            onSelectConversation: (conv) => _chat.switchConversation(conv),
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
                        height: 52), // Clear the absolute positioned top bar
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
                                  messages: state.messages,
                                  controller: _scrollController,
                                  running: state.running,
                                  onLongPress: (index) {
                                    if (!_longPressHintShown) {
                                      _longPressHintShown = true;
                                    }
                                    _showMessageActions(index);
                                  },
                                  onRegenerate: _regenerate,
                                ),
                          if (_showScrollToBottom)
                            Positioned(
                              right: 16,
                              bottom: 16,
                              child: FloatingActionButton.small(
                                onPressed: _scrollToBottom,
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                child: Icon(Icons.arrow_downward,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer),
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
                      onTerminalPreview: _openTerminal,
                      onEnvSetup: _openEnvSetup,
                      planModeEnabled: state.planMode,
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
                height: MediaQuery.paddingOf(context).top + 68,
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
                  statusActive: state.running,
                  currentContextTokens: state.messages.reversed
                          .where((m) => m.usage != null)
                          .map((m) =>
                              m.usage!.promptTokens + m.usage!.completionTokens)
                          .firstOrNull ??
                      0,
                  onMenu: () => _scaffoldKey.currentState?.openDrawer(),
                  onNewChat: () => _chat.newConversation(),
                  onContextGaugeTap: () =>
                      _scaffoldKey.currentState?.openDrawer(),
                ),
              ),

              if (state.planState != null &&
                  state.planState!.status != 'cancelled')
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 112,
                  left: 16,
                  right: 16,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: PlanPanel(
                      plan: state.planState!,
                      goal: state.planState!.steps.isEmpty
                          ? null
                          : state.planState!.steps.first.description,
                      onApprove: () => _chat.respondToPlan(true),
                      onCancel: () => _chat.respondToPlan(false),
                    ),
                  ),
                ),
              if (state.toolActivities.isNotEmpty)
                ToolActivityCapsule(
                  activities: state.toolActivities,
                  running: state.running,
                ),
            ], // Stack children
          ), // Stack
        ); // Scaffold
      },
    );
  }
}
