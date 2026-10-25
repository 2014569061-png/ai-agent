import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/chat_controller.dart';
import '../../application/desktop_device_service.dart';
import '../../application/desktop_git_service.dart';
import '../../application/desktop_runtime_service.dart';
import '../../application/desktop_workbench_service.dart';
import '../../application/desktop_worktree_service.dart';
import '../agents/agents_page.dart';
import '../knowledge/knowledge_page.dart';
import '../memory/memory_page.dart';
import '../plugins/plugins_page.dart';
import '../theme/desktop_theme.dart';
import 'desktop_jobs_strip.dart';
import 'desktop_workbench_panels.dart';

class DesktopActivityRail extends StatelessWidget {
  const DesktopActivityRail(
      {super.key,
      required this.items,
      required this.selectedIndex,
      required this.onSelected,
      required this.onSettings,
      required this.onDevices});
  final List<({IconData icon, String label})> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onSettings, onDevices;
  @override
  Widget build(BuildContext context) {
    final colors = DesktopTheme.maybeOf(context)!;
    final iconOnly = MediaQuery.textScalerOf(context).scale(12) > 16;
    return Container(
      width: 68,
      decoration: BoxDecoration(
        color: colors.sidebar,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: Column(children: [
        const SizedBox(height: 10),
        Expanded(
            child: SingleChildScrollView(
                child: Column(children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Tooltip(
                message: '${items[i].label} · Ctrl+${i + 1}',
                child: Semantics(
                  label: items[i].label,
                  button: true,
                  onTap: () => onSelected(i),
                  excludeSemantics: true,
                  selected: selectedIndex == i,
                  child: TextButton(
                    key: ValueKey('desktop-nav-${items[i].label}'),
                    onPressed: () => onSelected(i),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          vertical: 9, horizontal: 3),
                      minimumSize: const Size(54, 54),
                      foregroundColor:
                          selectedIndex == i ? colors.accent : colors.muted,
                      backgroundColor: selectedIndex == i
                          ? colors.selected
                          : Colors.transparent,
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(items[i].icon, size: 20),
                      if (!iconOnly) ...[
                        const SizedBox(height: 5),
                        Text(items[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: DesktopTheme.smallSize,
                                fontWeight: FontWeight.w500)),
                      ],
                    ]),
                  ),
                ),
              ),
            ),
        ]))),
        Divider(indent: 14, endIndent: 14, color: colors.border),
        IconButton(
            tooltip: 'Android 设备',
            onPressed: onDevices,
            icon: Icon(Icons.phone_android_outlined,
                size: 19, color: colors.muted)),
        IconButton(
            tooltip: '设置',
            onPressed: onSettings,
            icon: Icon(Icons.settings_outlined, size: 19, color: colors.muted)),
        const SizedBox(height: 8),
      ]),
    );
  }
}

class DesktopProjectNavigator extends ConsumerStatefulWidget {
  const DesktopProjectNavigator(
      {super.key,
      required this.onProject,
      required this.onOpenProject,
      required this.onNew,
      required this.onSession,
      required this.onCite,
      required this.onDevices});
  final VoidCallback onProject, onNew, onDevices;
  final ValueChanged<String> onOpenProject;
  final ValueChanged<String> onSession, onCite;
  @override
  ConsumerState<DesktopProjectNavigator> createState() =>
      _DesktopProjectNavigatorState();
}

class _DesktopProjectNavigatorState
    extends ConsumerState<DesktopProjectNavigator> {
  final _resourcesScrollController = ScrollController();

  @override
  void dispose() {
    _resourcesScrollController.dispose();
    super.dispose();
  }

  bool _files = false;
  int _sessionLimit = 30;
  String? _sessionProject;
  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  @override
  Widget build(BuildContext context) {
    final colors = DesktopTheme.maybeOf(context)!;
    final chat = ref.watch(chatControllerProvider.select((s) => (
          s.currentProjectId,
          s.currentProjectName,
          s.conversationId,
          s.running,
          s.paused,
          s.toolActivities.any((tool) => tool.status == '等待确认'),
          s.currentWorkspacePath
        )));
    final projects =
        ref.watch(desktopProjectsProvider).asData?.value ?? const [];
    if (_sessionProject != chat.$1) {
      _sessionProject = chat.$1;
      _sessionLimit = 30;
    }
    final sessionProvider = _sessionLimit == 30
        ? desktopSessionsProvider(chat.$1)
        : desktopSessionPageProvider((chat.$1, _sessionLimit));
    final sessions = ref.watch(sessionProvider);
    final devices = ref.watch(desktopDevicesProvider);
    final currentWorkspace = chat.$7;
    final isWorktree = currentWorkspace != null &&
        ref
            .watch(desktopWorktreeServiceProvider)
            .isWorktreeWorkspace(currentWorkspace);
    return SizedBox(
        width: 236,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
              child: Row(children: [
                Expanded(
                    child: Text('项目工作区',
                        style: TextStyle(
                            fontSize: DesktopTheme.smallSize,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                            color: colors.muted))),
                IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '新建编码会话',
                    onPressed: widget.onNew,
                    icon: const Icon(Icons.add_rounded, size: 18)),
              ])),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: PopupMenuButton<String>(
                  tooltip: chat.$2 == null ? '选择项目' : '切换项目：${chat.$2}',
                  onSelected: (id) => id == 'pick'
                      ? widget.onProject()
                      : widget.onOpenProject(id),
                  itemBuilder: (_) => [
                        const PopupMenuItem<String>(
                            enabled: false, child: Text('最近项目')),
                        for (final project in projects)
                          PopupMenuItem(
                              value: project.id, child: Text(project.name)),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                            value: 'pick', child: Text('打开或管理项目…')),
                      ],
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                          color: colors.panel,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: colors.border)),
                      child: Row(children: [
                        Icon(Icons.folder_outlined,
                            size: 15, color: colors.muted),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(chat.$2 ?? '选择项目',
                                style: const TextStyle(
                                    fontSize: DesktopTheme.labelSize,
                                    fontWeight: FontWeight.w500),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis)),
                        Icon(Icons.unfold_more_rounded,
                            size: 15, color: colors.muted),
                      ])))),
          Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                      color: colors.hover,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.border)),
                  child: Row(children: [
                    for (final fileTab in [false, true])
                      Expanded(
                          child: TextButton(
                              key: ValueKey(fileTab
                                  ? 'desktop-navigator-files'
                                  : 'desktop-navigator-tasks'),
                              onPressed: () => setState(() => _files = fileTab),
                              style: TextButton.styleFrom(
                                  minimumSize: const Size(0, 28),
                                  foregroundColor: _files == fileTab
                                      ? colors.text
                                      : colors.muted,
                                  backgroundColor: _files == fileTab
                                      ? colors.panel
                                      : Colors.transparent),
                              child: Text(fileTab ? '文件' : '会话'))),
                  ]))),
          const Divider(),
          Expanded(
              child: _files
                  ? DesktopFilesPanel(
                      onProject: widget.onProject, onCite: widget.onCite)
                  : sessions.when(
                      loading: () =>
                          const DesktopPanelEmpty(message: '正在读取会话…'),
                      error: (_, __) => DesktopPanelEmpty(
                          message: '会话读取失败',
                          label: '重试',
                          action: () => ref.invalidate(sessionProvider)),
                      data: (items) => items.isEmpty
                          ? DesktopPanelEmpty(
                              message: '创建会话，开始项目工作',
                              action: widget.onNew,
                              label: '新建会话')
                          : ListView(
                              padding: const EdgeInsets.all(8),
                              children: [
                                  for (final session
                                      in items.take(_sessionLimit))
                                    Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 4),
                                        decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: chat.$3 == session.id
                                                ? Border.all(
                                                    color: colors.accent
                                                        .withValues(alpha: .3))
                                                : null,
                                            color: chat.$3 == session.id
                                                ? colors.selected
                                                : null),
                                        child: Material(
                                            type: MaterialType.transparency,
                                            child: ListTile(
                                                dense: true,
                                                key: ValueKey(
                                                    'desktop-session-${session.id}'),
                                                title: Row(children: [
                                                  if (chat.$3 == session.id &&
                                                      isWorktree) ...[
                                                    Icon(Icons.alt_route,
                                                        size: 13,
                                                        color: colors.accent),
                                                    const SizedBox(width: 4),
                                                  ],
                                                  Expanded(
                                                      child: Text(session.title,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis)),
                                                  if (chat.$3 == session.id &&
                                                      isWorktree) ...[
                                                    const SizedBox(width: 4),
                                                    Container(
                                                        key: ValueKey(
                                                            'desktop-session-worktree-${session.id}'),
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 4,
                                                                vertical: 1),
                                                        decoration: BoxDecoration(
                                                            color: colors.accent
                                                                .withValues(
                                                                    alpha:
                                                                        0.15),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        3)),
                                                        child: Text('Worktree',
                                                            style: TextStyle(
                                                                fontSize: 9,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: colors
                                                                    .accent))),
                                                  ],
                                                ]),
                                                subtitle: Text(
                                                    chat.$3 == session.id &&
                                                            chat.$6
                                                        ? '等待确认'
                                                        : chat.$3 ==
                                                                    session
                                                                        .id &&
                                                                chat.$4
                                                            ? (chat.$5
                                                                ? '已暂停'
                                                                : '执行中')
                                                            : desktopTaskStatus(
                                                                session.status),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall),
                                                onTap: () => widget
                                                    .onSession(session.id)))),
                                  if (items.length > _sessionLimit)
                                    TextButton(
                                      key: const ValueKey(
                                          'desktop-load-older-sessions'),
                                      onPressed: () =>
                                          setState(() => _sessionLimit += 30),
                                      child: const Text('加载更早会话'),
                                    ),
                                ]))),
          const Divider(),
          // Scale the resource area without starving the conversation list.
          // A persistent thumb makes overflow discoverable at large text sizes.
          SizedBox(
              height: MediaQuery.textScalerOf(context).scale(190).clamp(96.0,
                  MediaQuery.sizeOf(context).height.clamp(320.0, 1000.0) * .30),
              child: Scrollbar(
                  controller: _resourcesScrollController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  child: ListView(
                      key: const ValueKey('desktop-resource-shortcuts'),
                      controller: _resourcesScrollController,
                      padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
                      children: [
                        Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text('项目资源',
                                style: Theme.of(context).textTheme.bodySmall)),
                        _resource(Icons.smart_toy_outlined, 'Agent',
                            () => _open(const AgentsPage())),
                        _resource(Icons.menu_book_outlined, '知识库',
                            () => _open(const KnowledgePage())),
                        _resource(Icons.favorite_border, '记忆',
                            () => _open(const MemoryPage())),
                        _resource(Icons.extension_outlined, '技能与 MCP',
                            () => _open(const PluginsPage())),
                      ]))),
          const Divider(),
          ListTile(
              dense: true,
              onTap: widget.onDevices,
              leading: const Icon(Icons.phone_android_outlined, size: 16),
              title: const Text('设备'),
              subtitle: Text(
                  devices.when(
                      data: (value) => value.label,
                      loading: () => '检测设备…',
                      error: (_, __) => '设备检测失败'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis)),
        ]));
  }

  Widget _resource(IconData icon, String label, VoidCallback action) =>
      ListTile(
          dense: true,
          minVerticalPadding: 0,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          visualDensity: VisualDensity.compact,
          leading: Icon(icon, size: 15),
          title: Text(label,
              style: const TextStyle(fontSize: AppTokens.fontSizeMeta)),
          onTap: action);
}

class DesktopWorkspaceHeader extends ConsumerWidget {
  const DesktopWorkspaceHeader(
      {super.key,
      required this.onProject,
      required this.onSearch,
      required this.onCommands});
  final VoidCallback onProject, onSearch, onCommands;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = DesktopTheme.maybeOf(context)!;
    final chat = ref.watch(chatControllerProvider
        .select((s) => (s.currentWorkspacePath, s.currentProjectName)));
    final git = chat.$1 == null
        ? null
        : ref.watch(desktopGitSnapshotProvider(chat.$1!));
    final isWorktree = chat.$1 != null &&
        ref.watch(desktopWorktreeServiceProvider).isWorktreeWorkspace(chat.$1!);
    return Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
            color: colors.sidebar,
            border: Border(bottom: BorderSide(color: colors.border))),
        child: Row(children: [
          Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: colors.accent, borderRadius: BorderRadius.circular(9)),
              child: Text('N',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontSize: AppTokens.fontSizeBadge,
                      fontWeight: FontWeight.w700))),
          const SizedBox(width: 8),
          Text('NEXUS',
              style: TextStyle(
                  fontSize: DesktopTheme.labelSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: colors.text)),
          const SizedBox(width: 10),
          Text('/', style: TextStyle(color: colors.muted)),
          const SizedBox(width: 6),
          Expanded(
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                        child: TextButton(
                            onPressed: onProject,
                            child: Text(chat.$2 ?? '选择项目',
                                maxLines: 1, overflow: TextOverflow.ellipsis))),
                    if (MediaQuery.textScalerOf(context).scale(12) <= 18 &&
                        chat.$1 != null) ...[
                      const SizedBox(width: 6),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: colors.hover,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: colors.border)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                    color: DesktopTheme.statusSuccess,
                                    shape: BoxShape.circle)),
                            const SizedBox(width: 5),
                            Text(isWorktree ? '独立 Worktree' : '本地工作区',
                                style: TextStyle(
                                    fontSize: AppTokens.fontSizeBadge,
                                    fontWeight: FontWeight.w500,
                                    color: colors.muted)),
                          ])),
                    ],
                  ]))),
          if (MediaQuery.textScalerOf(context).scale(12) <= 18 &&
              chat.$1 != null)
            TextButton.icon(
                onPressed: git?.asData?.value == null
                    ? null
                    : () async {
                        final snapshot = git!.asData!.value;
                        try {
                          final service = ref.read(desktopGitServiceProvider);
                          final branches =
                              await service.branches(snapshot.root);
                          if (!context.mounted) return;
                          final branch = await showDialog<String>(
                              context: context,
                              builder: (context) => SimpleDialog(
                                      title: const Text('切换分支'),
                                      children: [
                                        for (final branch in branches)
                                          SimpleDialogOption(
                                              onPressed: () => Navigator.pop(
                                                  context, branch),
                                              child: Text(branch))
                                      ]));
                          if (branch == null || !context.mounted) return;
                          await service.checkout(snapshot.root, branch);
                          if (!context.mounted) return;
                          ref.invalidate(desktopGitSnapshotProvider(chat.$1!));
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('切换分支失败：$error')));
                          }
                        }
                      },
                icon: const Icon(Icons.account_tree_outlined, size: 14),
                label: Text(git?.asData?.value.branch ?? 'Git',
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
          IconButton(
              tooltip: '搜索会话、项目和任务',
              onPressed: onSearch,
              icon: Icon(Icons.search_rounded, size: 17, color: colors.muted)),
          TextButton.icon(
              key: const ValueKey('desktop-command-launcher'),
              onPressed: onCommands,
              style: TextButton.styleFrom(
                  backgroundColor: colors.panel,
                  foregroundColor: colors.muted,
                  side: BorderSide(color: colors.border)),
              icon: const Icon(Icons.keyboard_command_key_rounded, size: 15),
              label: const Text('命令  Ctrl+K',
                  style: TextStyle(fontSize: DesktopTheme.smallSize))),
        ]));
  }
}

class DesktopWorkspaceStatus extends ConsumerWidget {
  const DesktopWorkspaceStatus(
      {super.key,
      required this.onTerminal,
      required this.onChanges,
      this.onJobs,
      this.onOpenJob});
  final VoidCallback onTerminal, onChanges;
  final VoidCallback? onJobs;
  final ValueChanged<JobSummary>? onOpenJob;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatControllerProvider
        .select((s) => (s.currentWorkspacePath, s.running, s.paused)));
    final runtime = ref.watch(desktopRuntimeProvider);
    final git = chat.$1 == null
        ? null
        : ref.watch(desktopGitSnapshotProvider(chat.$1!));
    return Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
            color: DesktopTheme.maybeOf(context)!.sidebar,
            border:
                Border(top: BorderSide(color: Theme.of(context).dividerColor))),
        child: Row(children: [
          Expanded(
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                      onPressed: onTerminal,
                      icon: Icon(Icons.terminal_rounded,
                          size: 13,
                          color: DesktopTheme.maybeOf(context)!.muted),
                      label: Text(runtime.asData?.value.label ?? '本地环境',
                          style: TextStyle(
                              fontSize: DesktopTheme.smallSize,
                              color: DesktopTheme.maybeOf(context)!.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)))),
          TextButton(
              onPressed: onChanges,
              child: Text(
                  chat.$1 == null
                      ? '未选择项目'
                      : git?.hasError == true
                          ? 'Git 未就绪'
                          : git?.asData?.value == null
                              ? '读取 Git…'
                              : '${git!.asData!.value.files.length} 个文件有改动',
                  style: TextStyle(
                      fontSize: DesktopTheme.smallSize,
                      color: DesktopTheme.maybeOf(context)!.muted))),
          DesktopJobsStrip(onOpenAll: onJobs, onOpenJob: onOpenJob),
          if (MediaQuery.textScalerOf(context).scale(12) <= 18) ...[
            const SizedBox(width: 12),
            Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                    color: chat.$2
                        ? DesktopTheme.statusWarning
                        : DesktopTheme.statusSuccess,
                    shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(
                chat.$3
                    ? 'Agent 已暂停'
                    : chat.$2
                        ? 'Agent 正在执行'
                        : 'Agent 就绪',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ]));
  }
}
