import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audit/audit_log_page.dart';
import '../chat/chat_page.dart';
import '../dashboard/dashboard_page.dart';
import '../history/history_page.dart';
import '../jobs/jobs_inbox_page.dart';
import '../settings/settings_page.dart';
import '../projects/project_picker_page.dart';
import '../tasks/task_details_page.dart';
import '../workspace/terminal_sheet.dart';
import 'desktop_workspace_chrome.dart';
import '../theme/desktop_theme.dart';
import '../motion/nexus_motion.dart';
import 'desktop_devices_dialog.dart';
import 'desktop_chat_bridge.dart';
import 'desktop_command_center.dart';
import 'desktop_workflows_dialog.dart';
import '../../application/desktop_workflow_service.dart';
import '../../application/desktop_worktree_service.dart';
import '../../application/desktop_host_service.dart';
import '../../application/desktop_scheduler.dart';
import '../../application/desktop_run_service.dart';
import '../../application/desktop_pty_session.dart';
import '../terminal/desktop_terminal_panel.dart';
import 'desktop_workbench_panels.dart';
import '../../application/desktop_workbench_service.dart';
import '../../application/file_citation.dart';
import '../../domain/models.dart';
import '../../application/task_service.dart';
import '../../application/chat_controller.dart';
import '../../application/desktop_search_service.dart';
import '../../application/desktop_device_service.dart';
import '../../application/providers.dart';
import '../../infrastructure/database/app_database.dart' show Project;

enum DesktopShortcutAction { commandPalette, search, navigate }

class DesktopShortcut {
  const DesktopShortcut._();

  static DesktopShortcutAction? actionFor(LogicalKeySet keys) {
    if (keys ==
            LogicalKeySet(
                LogicalKeyboardKey.control, LogicalKeyboardKey.keyK) ||
        keys ==
            LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyK)) {
      return DesktopShortcutAction.commandPalette;
    }
    if (keys ==
            LogicalKeySet(
                LogicalKeyboardKey.control, LogicalKeyboardKey.keyP) ||
        keys ==
            LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyP)) {
      return DesktopShortcutAction.search;
    }
    return null;
  }

  static int? navigationIndex(LogicalKeySet keys) {
    const digits = <LogicalKeyboardKey>[
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
    ];
    for (var i = 0; i < digits.length; i++) {
      if (keys == LogicalKeySet(LogicalKeyboardKey.control, digits[i]) ||
          keys == LogicalKeySet(LogicalKeyboardKey.meta, digits[i])) {
        return i;
      }
    }
    return null;
  }
}

class _DesktopIntent extends Intent {
  const _DesktopIntent(this.action, [this.index]);

  final DesktopShortcutAction action;
  final int? index;
}

/// Desktop-first application shell.
///
/// The existing pages remain the source of truth for business workflows. This
/// shell only supplies desktop navigation and keeps the mobile chat entrypoint
/// unchanged on narrow windows.
class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({super.key});

  static const minWidth = 900.0;
  static const preferredWidth = 1280.0;
  static const minHeight = 640.0;

  static bool usesDesktopLayoutFor(Size size) =>
      size.width >= minWidth && size.height >= minHeight;

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  int _index = 0, _sideTab = 0;
  double _sideWidth = 560, _terminalHeight = 220;
  int _terminalTab = 3;
  final Map<String, Widget> _interactiveTerminals = {};
  // A new installation starts focused; explicit layouts remain persistent.
  bool _sideOpen = false, _terminalOpen = false, _layoutEdited = false;
  bool _resizing = false;
  Future<void> _layoutSave = Future.value();
  final _chatBridge = DesktopChatBridge();
  final _terminalPool = DesktopTerminalPool();
  DesktopScheduler? _scheduler;
  static const _lifecycleChannel = MethodChannel('nexus/desktop_lifecycle');
  late final List<Widget> _pages = [
    ChatPage(desktopBridge: _chatBridge),
    const DashboardPage(),
    HistoryPage(
        onConversationSelected: (conversation) =>
            unawaited(_openConversation(conversation))),
    JobsInboxPage(
        onConversationSelected: (conversation) =>
            unawaited(_openConversation(conversation))),
    const AuditLogPage(),
  ];
  static const _items = <({IconData icon, String label})>[
    (icon: Icons.chat_bubble_outline, label: '会话'),
    (icon: Icons.dashboard_outlined, label: '工作台'),
    (icon: Icons.history, label: '历史'),
    (icon: Icons.task_alt, label: '任务'),
    (icon: Icons.fact_check_outlined, label: '审计'),
  ];

  @override
  void initState() {
    super.initState();
    _lifecycleChannel.setMethodCallHandler((call) async {
      if (call.method != 'prepareClose') throw MissingPluginException();
      final result = await WidgetsBinding.instance.handleRequestAppExit();
      if (result == AppExitResponse.exit) {
        _scheduler?.dispose();
        await DesktopPtySessions.instance.closeAll();
        await DesktopRunService.instance.stopAll();
      }
      return result == AppExitResponse.exit;
    });
    unawaited(_loadLayout());
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      _scheduler = DesktopScheduler(() => ref.read(databaseProvider.future))
        ..start();
    }
    unawaited(
        DesktopHostService.instance.initialize().catchError((Object error) {
      debugPrint('桌面宿主初始化失败：$error');
    }));
  }

  @override
  void dispose() {
    _scheduler?.dispose();
    _lifecycleChannel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _loadLayout() async {
    try {
      final settings = await DesktopLayoutSettings.load();
      if (!mounted || _layoutEdited) return;
      setState(() {
        _sideWidth = settings.sideWidth;
        _terminalHeight = settings.terminalHeight;
        _sideOpen = settings.sideOpen;
        _terminalOpen = settings.terminalOpen;
        _sideTab = settings.sideTab;
      });
    } catch (error) {
      _error('读取桌面布局失败：$error');
    }
  }

  void _saveLayout() {
    _layoutEdited = true;
    final settings = DesktopLayoutSettings(
        sideWidth: _sideWidth,
        terminalHeight: _terminalHeight,
        sideOpen: _sideOpen,
        terminalOpen: _terminalOpen,
        sideTab: _sideTab);
    _layoutSave =
        _layoutSave.then((_) => settings.save()).catchError((Object error) {
      _error('保存桌面布局失败：$error');
    });
  }

  void _error(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Widget _pageFor(int index) => _pages[index.clamp(0, _pages.length - 1)];
  void _select(int index) {
    if (index >= 0 && index < _pages.length) setState(() => _index = index);
  }

  Future<void> _pickProject() async {
    await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ProjectPickerPage()));
    if (mounted) _select(0);
  }

  Future<void> _openProject(Project project) async {
    try {
      await ref.read(chatControllerProvider.notifier).openProject(project);
      if (mounted) _select(0);
    } catch (error) {
      _error('打开项目失败：$error');
    }
  }

  Future<void> _newConversation({bool isolated = false}) async {
    try {
      if (_chatBridge.newConversation != null) {
        await _chatBridge.newConversation!();
      } else {
        await ref.read(chatControllerProvider.notifier).newConversation();
      }
      if (!mounted) return;
      ref.read(chatControllerProvider.notifier).setMode(ChatMode.agent);
      _select(0);
      if (isolated) {
        final chat = ref.read(chatControllerProvider);
        final root = chat.currentWorkspacePath;
        if (root == null || chat.conversationId == null) {
          throw StateError('请先选择 Git 项目');
        }
        final service = ref.read(desktopWorktreeServiceProvider);
        final oldBinding = await service.binding(chat.conversationId!);
        final source =
            oldBinding?.root ?? (await service.listWorktrees(root)).first.path;
        final worktree = await service.ensureSessionWorktree(source,
            conversationId: chat.conversationId!);
        await service.bind(chat.conversationId!, source, worktree.path);
        await ref
            .read(chatControllerProvider.notifier)
            .bindDesktopWorkspace(worktree.path);
      }
    } catch (error) {
      _error('创建会话失败：$error');
    }
  }

  Future<void> _openConversation(String conversationId) async {
    try {
      if (_chatBridge.switchConversation != null) {
        await _chatBridge.switchConversation!(conversationId);
      } else {
        await ref
            .read(chatControllerProvider.notifier)
            .switchConversationById(conversationId);
      }
      if (mounted) _select(0);
    } catch (error) {
      _error('打开会话失败：$error');
    }
  }

  Future<void> _openSession(String id) async {
    try {
      final conversation =
          await (await ref.read(databaseProvider.future)).findConversation(id);
      if (conversation == null) {
        _error('会话已删除');
        return;
      }
      await _openConversation(conversation.id);
    } catch (error) {
      _error('打开会话失败：$error');
    }
  }

  Future<void> _citeFile(String path) async {
    final current = ref.read(chatControllerProvider);
    final root = current.currentWorkspacePath;
    final projectId = current.currentProjectId;
    if (root == null || projectId == null) {
      _error('请先选择项目');
      return;
    }
    try {
      final content =
          await ref.read(desktopWorkspaceFilesProvider).preview(root, path);
      if (!mounted ||
          ref.read(chatControllerProvider).conversationId !=
              current.conversationId ||
          ref.read(chatControllerProvider).currentProjectId != projectId) {
        return;
      }
      await ref.read(chatControllerProvider.notifier).addFileCitation(
          FileCitation(
              projectId: projectId,
              relativePath: path,
              contentHash: FileCitation.hashOf(content),
              excerpt: content.length > 2000
                  ? content.substring(0, 2000)
                  : content));
      _select(0);
    } catch (error) {
      _error('添加文件上下文失败：$error');
    }
  }

  DesktopWorkbenchPanel _panel(
          {required VoidCallback close, ValueChanged<int>? onTab}) =>
      DesktopWorkbenchPanel(
          tab: _sideTab,
          onTab: onTab ??
              (tab) {
                setState(() => _sideTab = tab);
                _saveLayout();
              },
          onClose: close,
          onProject: () => unawaited(_pickProject()),
          onChat: () => _select(0),
          onReview: () {
            _select(0);
            _chatBridge.insertPrompt
                ?.call('请审查当前工作区的 Git 改动，检查错误与回归风险，并报告验证依据。');
          },
          onTerminal: _openTerminal,
          onCite: (path) => unawaited(_citeFile(path)));

  void _openSide(int tab) {
    setState(() {
      _sideTab = tab;
      _sideOpen = true;
    });
    _saveLayout();
    if (MediaQuery.sizeOf(context).width >= 1200) return;
    showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
            builder: (_, dialogSetState) => Dialog(
                child: SizedBox(
                    width: math.min(_sideWidth,
                        MediaQuery.sizeOf(dialogContext).width - 48),
                    height: MediaQuery.sizeOf(dialogContext).height - 96,
                    child: _panel(
                        close: () => Navigator.pop(dialogContext),
                        onTab: (tab) {
                          setState(() => _sideTab = tab);
                          dialogSetState(() {});
                          _saveLayout();
                        })))));
  }

  void _closeSide() {
    setState(() => _sideOpen = false);
    _saveLayout();
  }

  void _toggleTerminal() {
    final size = MediaQuery.sizeOf(context);
    if (size.width < 1200 && size.height < 760) {
      final root = ref.read(chatControllerProvider).currentWorkspacePath;
      showDialog<void>(
          context: context,
          builder: (context) => Dialog(
              child: SizedBox(
                  width: math.min(900, size.width - 48),
                  height: size.height - 96,
                  child: Column(children: [
                    Row(children: [
                      const SizedBox(width: 16),
                      const Expanded(child: Text('终端')),
                      IconButton(
                          tooltip: '关闭终端',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close)),
                    ]),
                    Expanded(
                        child: root == null
                            ? DesktopPanelEmpty(
                                message: '选择项目后执行命令',
                                action: () {
                                  Navigator.pop(context);
                                  unawaited(_pickProject());
                                })
                            : TerminalSheet(
                                workspacePath: root,
                                embedded: true,
                                sharedService:
                                    _terminalPool.forWorkspace(root))),
                  ]))));
      return;
    }

    setState(() => _terminalOpen = !_terminalOpen);
    _saveLayout();
  }

  void _openTerminal() {
    final size = MediaQuery.sizeOf(context);
    if (size.width < 1200 && size.height < 760) {
      _toggleTerminal();
      return;
    }
    setState(() {
      _terminalOpen = true;
      _terminalTab = 3;
    });
    _saveLayout();
  }

  void _setLayout(String mode) {
    setState(() {
      _sideOpen = mode != '专注';
      _terminalOpen = mode == '执行';
      _sideTab = mode == '执行' ? 3 : 0;
      _sideWidth = mode == '审查' ? 780 : 560;
    });
    _saveLayout();
  }

  Future<void> _manageIsolation({bool merge = false}) async {
    final chat = ref.read(chatControllerProvider);
    if (chat.running ||
        ref.read(chatControllerProvider.notifier).hasBoundDevelopmentRun) {
      _error('请先停止运行中的任务');
      return;
    }
    final id = chat.conversationId;
    if (id == null) return;
    final service = ref.read(desktopWorktreeServiceProvider);
    try {
      final binding = await service.binding(id);
      if (binding == null) throw StateError('当前会话没有独立工作区');
      if (DesktopHostService.instance.hasTerminal(binding.workspace) ||
          DesktopRunService.instance.running(binding.workspace)) {
        throw StateError('请先停止独立工作区的终端与开发服务器');
      }
      final snapshot = await service.git.inspect(binding.workspace);
      if (snapshot.files.isNotEmpty) throw StateError('请先提交或保存独立工作区中的改动');
      if (merge) {
        await service.git.mergeBranch(binding.root, snapshot.branch);
        _error('已将已提交改动合并到原工作区');
      } else {
        await service.removeSessionWorktree(binding.root, conversationId: id);
        await service.unbind(id);
        await ref
            .read(chatControllerProvider.notifier)
            .bindDesktopWorkspace(binding.root);
        _error('独立工作区已清理，分支和会话保留');
      }
    } catch (error) {
      _error('$error');
    }
  }

  Future<void> _showWorkflows() async {
    final workflow = await showDialog<DesktopWorkflow>(
        context: context, builder: (_) => const DesktopWorkflowsDialog());
    if (workflow == null || !mounted) return;
    _select(0);
    ref.read(chatControllerProvider.notifier).setMode(ChatMode.agent);
    _chatBridge.insertPrompt?.call(workflow.prompt);
  }

  void _showCommandPanel() {
    showDialog<void>(
        context: context,
        builder: (_) => DesktopCommandCenter(
              onOpenResult: _openSearchResult,
              actions: [
                DesktopCommandAction(
                    icon: Icons.auto_awesome_outlined,
                    label: '工作流模板',
                    onRun: () => unawaited(_showWorkflows())),
                for (var i = 0; i < _items.length; i++)
                  DesktopCommandAction(
                      icon: _items[i].icon,
                      label: _items[i].label,
                      group: '导航',
                      hint: 'Ctrl+${i + 1}',
                      onRun: () => _select(i)),
                DesktopCommandAction(
                    icon: Icons.add,
                    label: '新建编码会话',
                    onRun: () => unawaited(_newConversation())),
                DesktopCommandAction(
                    icon: Icons.alt_route,
                    label: '新建独立分支会话',
                    onRun: () => unawaited(_newConversation(isolated: true))),
                DesktopCommandAction(
                    icon: Icons.merge,
                    label: '合并独立分支的已提交改动',
                    onRun: () => unawaited(_manageIsolation(merge: true))),
                DesktopCommandAction(
                    icon: Icons.archive_outlined,
                    label: '清理当前独立工作区',
                    onRun: () => unawaited(_manageIsolation())),
                for (final mode in ['专注', '执行', '审查'])
                  DesktopCommandAction(
                      icon: Icons.view_quilt_outlined,
                      label: '$mode布局',
                      group: '布局',
                      onRun: () => _setLayout(mode)),
                DesktopCommandAction(
                    icon: Icons.difference_outlined,
                    label: '查看改动',
                    onRun: () => _openSide(0)),
                DesktopCommandAction(
                    icon: Icons.web, label: '预览项目', onRun: () => _openSide(1)),
                DesktopCommandAction(
                    icon: Icons.folder_outlined,
                    label: '浏览项目文件',
                    onRun: () => _openSide(2)),
                DesktopCommandAction(
                    icon: Icons.terminal,
                    label: '展开 / 收起终端',
                    onRun: _toggleTerminal),
                DesktopCommandAction(
                    icon: Icons.phone_android,
                    label: 'Android 设备',
                    onRun: () => showDialog<void>(
                        context: context,
                        builder: (_) => const DesktopDevicesDialog())),
                DesktopCommandAction(
                    icon: Icons.settings_outlined,
                    label: '打开设置',
                    onRun: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const SettingsPage()))),
              ],
            ));
  }

  Future<void> _showSearch() async {
    await showDialog<void>(
        context: context,
        builder: (_) => DesktopCommandCenter(
            actions: const [],
            maxSearchResults: 30,
            onOpenResult: _openSearchResult));
  }

  Future<void> _openSearchResult(DesktopSearchResult result) async {
    try {
      final db = await ref.read(databaseProvider.future);
      if (!mounted) return;
      switch (result.kind) {
        case DesktopSearchKind.conversation:
          final conversation = await db.findConversation(result.id);
          if (conversation != null) await _openConversation(conversation.id);
        case DesktopSearchKind.project:
          final project = await db.findProject(result.id);
          if (project != null) await _openProject(project);
        case DesktopSearchKind.file:
          final root = ref.read(chatControllerProvider).currentWorkspacePath;
          if (root != null) await _citeFile(result.subtitle);
        case DesktopSearchKind.task:
          final task = await db.findTask(result.id);
          if (task != null && mounted) {
            await Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => TaskDetailsPage(
                    task: DevelopmentTaskInfo.fromTask(task),
                    onConversationSelected: (conversation) =>
                        unawaited(_openConversation(conversation)))));
          }
      }
    } catch (error) {
      _error('打开失败：$error');
    }
  }

  Map<LogicalKeySet, Intent> get _shortcuts => {
        for (final modifier in [
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.meta
        ]) ...{
          LogicalKeySet(modifier, LogicalKeyboardKey.keyK):
              const _DesktopIntent(DesktopShortcutAction.commandPalette),
          LogicalKeySet(modifier, LogicalKeyboardKey.keyP):
              const _DesktopIntent(DesktopShortcutAction.search),
          for (var i = 0; i < 5; i++)
            LogicalKeySet(
                modifier,
                const [
                  LogicalKeyboardKey.digit1,
                  LogicalKeyboardKey.digit2,
                  LogicalKeyboardKey.digit3,
                  LogicalKeyboardKey.digit4,
                  LogicalKeyboardKey.digit5
                ][i]): _DesktopIntent(DesktopShortcutAction.navigate, i),
        },
      };

  Widget _terminalPane(BuildContext context, String? root, double height) {
    final colors = DesktopTheme.maybeOf(context)!;
    final activities =
        ref.watch(chatControllerProvider.select((s) => s.toolActivities));
    final errors = activities.where((a) => a.ok == false).length;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
          height: 32,
          padding: const EdgeInsets.only(left: 12, right: 4),
          decoration: BoxDecoration(
              color: colors.panel,
              border: Border(top: BorderSide(color: colors.border))),
          child: Row(children: [
            Icon(Icons.terminal_rounded, size: 13, color: colors.muted),
            const SizedBox(width: 6),
            Expanded(
                child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (var i = 0; i < 4; i++)
                        TextButton(
                            key: ValueKey('desktop-terminal-tab-$i'),
                            onPressed: () {
                              setState(() {
                                _terminalTab = i;
                                _terminalOpen = true;
                              });
                              _saveLayout();
                            },
                            style: TextButton.styleFrom(
                                minimumSize: const Size(0, 26),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 10),
                                foregroundColor:
                                    _terminalTab == i && _terminalOpen
                                        ? colors.text
                                        : colors.muted),
                            child: Text(
                                ['命令运行器', '运行日志', '问题 $errors', '交互终端'][i],
                                style: TextStyle(
                                    fontSize: DesktopTheme.smallSize,
                                    fontWeight:
                                        _terminalTab == i && _terminalOpen
                                            ? FontWeight.w600
                                            : FontWeight.w400))),
                    ]))),
            IconButton(
                key: const ValueKey('desktop-terminal-toggle'),
                visualDensity: VisualDensity.compact,
                tooltip: _terminalOpen ? '收起终端' : '展开终端',
                onPressed: _toggleTerminal,
                icon: Icon(
                    _terminalOpen
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_up,
                    size: 16,
                    color: colors.muted)),
          ])),
      if (_terminalOpen)
        DesktopResizeHandle(
            key: const ValueKey('desktop-terminal-resize'),
            vertical: false,
            onDelta: (delta) {
              setState(() =>
                  _terminalHeight = (_terminalHeight - delta).clamp(160, 480));
              _layoutEdited = true;
            },
            onEnd: () {
              setState(() => _resizing = false);
              _saveLayout();
            }),
      Offstage(
          offstage: !_terminalOpen,
          child: SizedBox(
              height: height,
              child: IndexedStack(index: _terminalTab, children: [
                if (root == null)
                  DesktopPanelEmpty(
                      message: '选择项目后执行命令',
                      action: () => unawaited(_pickProject()))
                else
                  TerminalSheet(
                      key: ValueKey('desktop-terminal-$root'),
                      workspacePath: root,
                      embedded: true,
                      sharedService: _terminalPool.forWorkspace(root)),
                DesktopExecutionPanel(onChat: () => _select(0)),
                DesktopExecutionPanel(
                    onChat: () => _select(0), errorsOnly: true),
                if (root == null)
                  const DesktopPanelEmpty(message: '选择项目后启动交互终端')
                else
                  Builder(builder: (_) {
                    _interactiveTerminals.putIfAbsent(
                        root,
                        () => DesktopTerminalPanel(
                            key: ValueKey('pty-$root'), workspacePath: root));
                    final roots = _interactiveTerminals.keys.toList();
                    return IndexedStack(
                        index: roots.indexOf(root),
                        children: _interactiveTerminals.values.toList());
                  }),
              ]))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(desktopDeviceServiceProvider);
    final root =
        ref.watch(chatControllerProvider.select((s) => s.currentWorkspacePath));
    return LayoutBuilder(builder: (context, constraints) {
      if (!DesktopShell.usesDesktopLayoutFor(
        Size(constraints.maxWidth, constraints.maxHeight),
      )) {
        return _pageFor(_index);
      }
      return Theme(
          data: DesktopTheme.apply(Theme.of(context),
              highContrast: MediaQuery.highContrastOf(context)),
          child: Builder(builder: (context) {
            final colors = DesktopTheme.maybeOf(context)!;
            final inlineSide = _sideOpen && constraints.maxWidth >= 1200;
            final sideWidth = _sideWidth
                .clamp(340.0, math.max(340.0, constraints.maxWidth - 700.0))
                .toDouble();
            final terminalHeight = _terminalHeight
                .clamp(160.0, math.max(160.0, constraints.maxHeight * .34))
                .toDouble();
            final navigatorVisible = constraints.maxWidth >= 1040 ||
                MediaQuery.textScalerOf(context).scale(12) <= 18;
            Widget frame(Widget child) => Container(
                decoration: BoxDecoration(
                    color: colors.panel,
                    border: Border.all(color: colors.border),
                    borderRadius:
                        BorderRadius.circular(DesktopTheme.panelRadius)),
                clipBehavior: Clip.antiAlias,
                child: child);
            final scaffold = Scaffold(
                backgroundColor: colors.sidebar,
                body: Column(children: [
                  DesktopWorkspaceHeader(
                      onProject: () => unawaited(_pickProject()),
                      onSearch: () => unawaited(_showSearch()),
                      onCommands: _showCommandPanel),
                  Expanded(
                      child: Row(children: [
                    DesktopActivityRail(
                        items: _items,
                        selectedIndex: _index,
                        onSelected: _select,
                        onSettings: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) => const SettingsPage())),
                        onDevices: () => showDialog<void>(
                            context: context,
                            builder: (_) => const DesktopDevicesDialog())),
                    if (navigatorVisible)
                      DesktopProjectNavigator(
                          onProject: () => unawaited(_pickProject()),
                          onOpenProject: (id) {
                            final projects = ref
                                    .read(desktopProjectsProvider)
                                    .asData
                                    ?.value ??
                                const [];
                            for (final project in projects) {
                              if (project.id == id) {
                                unawaited(_openProject(project));
                                break;
                              }
                            }
                          },
                          onNew: () => unawaited(_newConversation()),
                          onSession: (id) => unawaited(_openSession(id)),
                          onCite: (path) => unawaited(_citeFile(path)),
                          onDevices: () => showDialog<void>(
                              context: context,
                              builder: (_) => const DesktopDevicesDialog())),
                    Expanded(
                        child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                            child: frame(Column(children: [
                              _DesktopTopBar(
                                  label:
                                      _index == 0 ? null : _items[_index].label,
                                  onSearch: () => unawaited(_showSearch()),
                                  onCommands: _showCommandPanel,
                                  onNew: () => unawaited(_newConversation()),
                                  onSession: () =>
                                      _chatBridge.sessionSettings?.call(),
                                  onDrawer: () =>
                                      _chatBridge.openDrawer?.call(),
                                  onSide: () => inlineSide
                                      ? _closeSide()
                                      : _openSide(_sideTab),
                                  sideOpen: inlineSide,
                                  onLayout: _setLayout,
                                  onWorkflows: () =>
                                      unawaited(_showWorkflows()),
                                  onIsolated: () => unawaited(
                                      _newConversation(isolated: true)),
                                  onDevices: () => showDialog<void>(
                                      context: context,
                                      builder: (_) =>
                                          const DesktopDevicesDialog())),
                              Expanded(
                                  child: IndexedStack(
                                      index: _index, children: _pages)),
                              if (_index == 0)
                                DesktopTaskResultStrip(
                                    onReview: () => _openSide(0)),
                              if (!inlineSide)
                                if (constraints.maxHeight < 760)
                                  TextButton.icon(
                                      key: const ValueKey(
                                          'desktop-terminal-toggle'),
                                      onPressed: _toggleTerminal,
                                      icon: const Icon(Icons.terminal),
                                      label: const Text('打开终端'))
                                else
                                  _terminalPane(context, root, terminalHeight),
                            ])))),
                    if (inlineSide)
                      DesktopResizeHandle(
                          key: const ValueKey('desktop-side-resize'),
                          vertical: true,
                          onDelta: (delta) {
                            setState(() {
                              _resizing = true;
                              _sideWidth = (_sideWidth - delta).clamp(340, 780);
                            });
                            _layoutEdited = true;
                          },
                          onEnd: () {
                            setState(() => _resizing = false);
                            _saveLayout();
                          }),
                    AnimatedSize(
                        duration: _resizing
                            ? Duration.zero
                            : DesktopTheme.motionDuration(
                                context, NexusMotion.pageExit),
                        alignment: Alignment.centerRight,
                        curve: Curves.easeOutCubic,
                        child: inlineSide
                            ? SizedBox(
                                width: sideWidth,
                                child: FocusTraversalGroup(
                                    policy: ReadingOrderTraversalPolicy(),
                                    child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            0, 10, 10, 10),
                                        child: Column(children: [
                                          Expanded(
                                              child: _panel(close: _closeSide)),
                                          const SizedBox(height: 8),
                                          frame(_terminalPane(
                                              context, root, terminalHeight)),
                                        ]))))
                            : const SizedBox.shrink()),
                  ])),
                  DesktopWorkspaceStatus(
                      onTerminal: _toggleTerminal,
                      onChanges: () => _openSide(0)),
                ]));
            return Shortcuts(
                shortcuts: _shortcuts,
                child: Actions(
                    actions: {
                      _DesktopIntent:
                          CallbackAction<_DesktopIntent>(onInvoke: (intent) {
                        switch (intent.action) {
                          case DesktopShortcutAction.commandPalette:
                            _showCommandPanel();
                          case DesktopShortcutAction.search:
                            unawaited(_showSearch());
                          case DesktopShortcutAction.navigate:
                            if (intent.index != null) _select(intent.index!);
                        }
                        return null;
                      }),
                    },
                    child: FocusTraversalGroup(
                      policy: ReadingOrderTraversalPolicy(),
                      child: Focus(autofocus: true, child: scaffold),
                    )));
          }));
    });
  }
}

class _DesktopTopBar extends ConsumerWidget {
  const _DesktopTopBar(
      {this.label,
      required this.onSearch,
      required this.onCommands,
      required this.onNew,
      required this.onSession,
      required this.onDrawer,
      required this.onSide,
      required this.sideOpen,
      required this.onLayout,
      required this.onWorkflows,
      required this.onIsolated,
      required this.onDevices});
  final String? label;
  final VoidCallback onSearch,
      onCommands,
      onNew,
      onSession,
      onDrawer,
      onSide,
      onDevices;
  final bool sideOpen;
  final ValueChanged<String> onLayout;
  final VoidCallback onWorkflows, onIsolated;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatControllerProvider
        .select((s) => (s.conversationTitle, s.running, s.paused)));
    final colors = DesktopTheme.maybeOf(context)!;
    final theme = Theme.of(context);
    return Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.border))),
        child: Row(children: [
          Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                  color: colors.selected,
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(
                  label == null
                      ? Icons.auto_awesome_outlined
                      : Icons.dashboard_outlined,
                  size: 15,
                  color: colors.accent)),
          const SizedBox(width: 10),
          Expanded(
              child: InkWell(
                  onTap: label == null ? onSession : null,
                  child: Text(label ?? chat.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium))),
          if (label == null && chat.$2)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(chat.$3 ? '已暂停' : '执行中',
                    style: theme.textTheme.bodySmall)),
          PopupMenuButton<String>(
            key: const ValueKey('desktop-layout-picker'),
            tooltip: '切换工作区布局',
            onSelected: onLayout,
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: '专注',
                  child: ListTile(
                      leading: Icon(Icons.chat_bubble_outline),
                      title: Text('专注'),
                      subtitle: Text('集中处理当前会话'))),
              PopupMenuItem(
                  value: '执行',
                  child: ListTile(
                      leading: Icon(Icons.terminal),
                      title: Text('执行'),
                      subtitle: Text('展开工具与终端'))),
              PopupMenuItem(
                  value: '审查',
                  child: ListTile(
                      leading: Icon(Icons.difference_outlined),
                      title: Text('审查'),
                      subtitle: Text('并排查看代码改动'))),
            ],
            icon: Icon(Icons.space_dashboard_outlined,
                size: 17, color: colors.muted),
          ),
          IconButton(
              tooltip: '新建编码会话',
              onPressed: onNew,
              icon: Icon(Icons.add_rounded, size: 17, color: colors.muted)),
          IconButton(
              tooltip: sideOpen ? '收起文件与改动' : '打开文件与改动',
              onPressed: onSide,
              icon: Icon(Icons.view_sidebar_outlined,
                  size: 16, color: sideOpen ? colors.text : colors.muted)),
          PopupMenuButton<String>(
              tooltip: '工作区操作',
              onSelected: (value) => switch (value) {
                    'layout-focus' => onLayout('专注'),
                    'layout-execute' => onLayout('执行'),
                    'layout-review' => onLayout('审查'),
                    'workflows' => onWorkflows(),
                    'isolated' => onIsolated(),
                    'commands' => onCommands(),
                    'devices' => onDevices(),
                    'session' => onSession(),
                    _ => onDrawer(),
                  },
              itemBuilder: (_) => const [
                    PopupMenuItem(value: 'layout-focus', child: Text('专注布局')),
                    PopupMenuItem(value: 'layout-execute', child: Text('执行布局')),
                    PopupMenuItem(value: 'layout-review', child: Text('审查布局')),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'workflows', child: Text('工作流模板')),
                    PopupMenuItem(value: 'isolated', child: Text('新建独立分支会话')),
                    PopupMenuItem(
                        value: 'commands', child: Text('命令面板  Ctrl+K')),
                    PopupMenuItem(value: 'session', child: Text('会话设置')),
                    PopupMenuItem(value: 'drawer', child: Text('更多会话操作')),
                    PopupMenuItem(value: 'devices', child: Text('Android 设备')),
                  ]),
        ]));
  }
}
