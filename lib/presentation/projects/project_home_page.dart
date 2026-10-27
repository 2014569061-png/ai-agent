import '../widgets/nexus_disclosure.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../application/chat_controller.dart';
import '../../application/dependency_lockfile.dart';
import '../../application/environment_service.dart';
import '../../application/install_job_service.dart';
import '../../application/project_kind.dart';
import '../../application/project_settings.dart';
import '../../application/providers.dart';
import '../../application/task_service.dart';
import '../../infrastructure/tools/command_tool.dart';
import 'install_job_sheet.dart';
import '../environment/environment_status_view.dart';
import '../../infrastructure/database/app_database.dart';
import '../motion/nexus_page_route_factory.dart';
import '../tasks/task_details_page.dart';
import '../terminal/terminal_page.dart';
import '../theme/app_tokens.dart';
import '../theme/desktop_theme.dart';
import '../widgets/async_state_view.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_list_tile.dart';
import '../widgets/nexus_page_layout.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/nexus_status_pill.dart';
import '../widgets/section_card.dart';
import '../../application/apk_install_bridge.dart';
import '../../application/artifact_service.dart';
import '../../application/preview_service.dart';
import 'project_change_set_page.dart';
import 'project_git_page.dart';
import 'remote_execution_page.dart';
import 'static_web_delivery_page.dart';
import '../workspace/development_workbench_page.dart';
import '../workspace/file_tree_sheet.dart';
import '../workspace/terminal_sheet.dart';
import '../workspace/workspace_sheet_frame.dart';
import '../workspace/workspace_editor_page.dart';
import '../widgets/nexus_sheet.dart';
import '../../application/local_error_copy.dart';

class ProjectHomePage extends ConsumerStatefulWidget {
  const ProjectHomePage(
      {super.key, required this.projectId, this.onContinueInChat});

  final String projectId;
  final VoidCallback? onContinueInChat;

  @override
  ConsumerState<ProjectHomePage> createState() => _ProjectHomePageState();
}

class _ProjectHomePageState extends ConsumerState<ProjectHomePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Project? _project;
  List<FileSystemEntity> _files = const [];
  List<Task> _tasks = const [];
  bool _loading = true;
  String? _error;
  EnvironmentSnapshot? _environment;
  String? _environmentError;
  bool _filesLoading = false;
  bool _tasksLoading = false;
  bool _artifactsLoading = false;
  bool _environmentLoading = false;
  int _loadGeneration = 0;
  TerminalCommandService? _terminal;
  InstallJob? _installJob;
  bool _installing = false;
  PreviewSession? _preview;
  bool _previewBusy = false;
  PreviewService? _previewService;
  List<ProjectArtifact> _recordedArtifacts = const [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _reload();
  }

  @override
  void dispose() {
    _tabs.dispose();
    final previewService = _previewService;
    if (previewService != null) {
      unawaited(previewService.stop().catchError((Object error) {
        debugPrint('页面退出时预览停止未确认：$error');
      }));
    }
    _terminal?.stop();
    super.dispose();
  }

  Future<void> _reload() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _filesLoading = true;
        _tasksLoading = true;
        _artifactsLoading = true;
        _environmentLoading = true;
        _environmentError = null;
      });
    }
    try {
      final db = await ref.read(databaseProvider.future);
      final project = await db.findProject(widget.projectId);
      if (!mounted || generation != _loadGeneration) return;
      if (project == null) {
        setState(() {
          _error = '项目不存在';
          _loading = false;
        });
        return;
      }
      setState(() {
        _project = project;
        _loading = false;
        _error = null;
      });

      // The project shell is useful before filesystem and environment probes
      // finish. Load each section independently so one slow/failed probe does
      // not block the overview or the other tabs.
      unawaited(_loadFiles(project, generation));
      unawaited(_loadTasks(project, generation));
      unawaited(_loadArtifacts(project, generation));
      if (ProjectKindX.parse(project.projectKind) == ProjectKind.staticWeb) {
        // Static delivery uses the in-app HTTP server, not a Linux toolchain.
        setState(() {
          _environment = null;
          _environmentError = null;
          _environmentLoading = false;
        });
      } else {
        unawaited(_loadEnvironment(generation));
      }
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = LocalErrorCopy.of(error).headline();
        _loading = false;
      });
    }
  }

  bool _isCurrentLoad(int generation) =>
      mounted && generation == _loadGeneration;

  Future<void> _loadFiles(Project project, int generation) async {
    try {
      final dir = Directory(project.canonicalRootPath);
      var files = <FileSystemEntity>[];
      if (await dir.exists()) {
        files = await dir.list().toList();
        files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
      }
      if (!_isCurrentLoad(generation)) return;
      setState(() {
        _files = files;
        _filesLoading = false;
      });
    } catch (_) {
      if (_isCurrentLoad(generation)) {
        setState(() {
          _files = const [];
          _filesLoading = false;
        });
      }
    }
  }

  Future<void> _loadTasks(Project project, int generation) async {
    try {
      final db = await ref.read(databaseProvider.future);
      final tasks = await db.tasksForProject(project.id);
      if (!_isCurrentLoad(generation)) return;
      setState(() {
        _tasks = tasks;
        _tasksLoading = false;
      });
    } catch (_) {
      if (_isCurrentLoad(generation)) {
        setState(() {
          _tasks = const [];
          _tasksLoading = false;
        });
      }
    }
  }

  Future<void> _loadArtifacts(Project project, int generation) async {
    try {
      final db = await ref.read(databaseProvider.future);
      final artifacts =
          await const ArtifactService().list(db, projectId: project.id);
      if (!_isCurrentLoad(generation)) return;
      setState(() {
        _recordedArtifacts = artifacts;
        _artifactsLoading = false;
      });
    } catch (_) {
      if (_isCurrentLoad(generation)) {
        setState(() {
          _recordedArtifacts = const [];
          _artifactsLoading = false;
        });
      }
    }
  }

  Future<void> _loadEnvironment(int generation) async {
    try {
      final environment = await ref.read(environmentServiceProvider).inspect();
      if (!_isCurrentLoad(generation)) return;
      setState(() {
        _environment = environment;
        _environmentError = null;
        _environmentLoading = false;
      });
    } catch (error) {
      if (_isCurrentLoad(generation)) {
        setState(() {
          _environment = null;
          _environmentError = LocalErrorCopy.of(error).headline();
          _environmentLoading = false;
        });
      }
    }
  }

  Future<void> _continueInChat() async {
    final project = _project;
    if (project == null) return;
    await ref.read(chatControllerProvider.notifier).openProject(project);
    if (!mounted) return;
    if (widget.onContinueInChat != null) {
      widget.onContinueInChat!();
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = _project;
    return Scaffold(
      appBar: NexusPageHeader(
        title: project?.name ?? '项目',
        subtitle: project == null ||
                (DesktopTheme.maybeOf(context) == null &&
                    project.name ==
                        ProjectKindX.parse(project.projectKind).label)
            ? null
            : ProjectKindX.parse(project.projectKind).label,
        actions: [
          IconButton(
            tooltip: '刷新项目',
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: '概览'),
            Tab(text: '文件'),
            Tab(text: '终端'),
            Tab(text: '任务'),
            Tab(text: '产物'),
          ],
        ),
      ),
      body: NexusPageLayout(
          child: AsyncStateView(
        loading: _loading,
        error: _error,
        onRetry: _reload,
        child: project == null
            ? const SizedBox.shrink()
            : TabBarView(
                controller: _tabs,
                children: [
                  _overview(project),
                  _filesTab(project),
                  _terminalTab(project),
                  _tasksTab(),
                  _artifactsTab(project),
                ],
              ),
      )),
    );
  }

  Widget _overviewDetails({
    required bool mobile,
    required String title,
    required Widget child,
    IconData? icon,
    String? subtitle,
    EdgeInsetsGeometry? headerPadding,
  }) {
    if (!mobile) return child;
    final theme = Theme.of(context);
    return NexusDisclosure(
      headerPadding: headerPadding ??
          const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      contentPadding: EdgeInsets.only(top: icon != null ? 0 : 8),
      leading: icon == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: theme.colorScheme.primary),
              ),
            ),
      title: subtitle == null
          ? Text(title, style: const TextStyle(fontSize: 15))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
      child: child,
    );
  }

  Widget _overview(Project project) {
    // Match the accepted mobile prototype without changing desktop density or
    // the real loading, navigation and execution contracts below.
    final mobile = DesktopTheme.maybeOf(context) == null;
    final sectionGap = mobile ? 12.0 : AppTokens.sp4;
    final contentRadius = mobile ? BorderRadius.circular(24) : null;
    final toolPadding = mobile
        ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 12);
    final settings = ProjectSettings.decode(project.settingsJson);
    final accessible = Directory(project.canonicalRootPath).existsSync();
    return ListView(
      key: const ValueKey('project-home-overview-scroll'),
      padding: EdgeInsets.fromLTRB(
          mobile ? 20 : 16, 12, mobile ? 20 : 16, mobile ? 24 : 32),
      children: [
        SectionCard(
          key: const ValueKey('project-home-directory'),
          glass: mobile ? false : null,
          borderRadius: contentRadius,
          padding: mobile
              ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
              : const EdgeInsets.all(16),
          child: _overviewDetails(
              mobile: mobile,
              title: accessible ? '项目位置与信息' : '项目位置 · 目录不可访问',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: mobile
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.start,
                    children: [
                      if (mobile) ...[
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.code_rounded,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '项目目录',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            if (!mobile) ...[
                              const SizedBox(height: 4),
                              SelectableText(
                                key: const ValueKey('project-home-path'),
                                project.canonicalRootPath,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '复制项目路径',
                        constraints: mobile
                            ? const BoxConstraints(minWidth: 48, minHeight: 48)
                            : null,
                        icon: const Icon(Icons.copy_rounded, size: 20),
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: project.canonicalRootPath),
                          );
                          if (mounted) {
                            FloatingToast.show(context, '项目路径已复制',
                                tone: ToastTone.success);
                          }
                        },
                      ),
                    ],
                  ),
                  if (mobile) ...[
                    const SizedBox(height: 4),
                    SelectableText(
                      key: const ValueKey('project-home-path'),
                      project.canonicalRootPath,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            height: 1.5,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                  SizedBox(height: mobile ? 10 : 12),
                  Wrap(
                    spacing: mobile ? 6 : 8,
                    runSpacing: mobile ? 6 : 8,
                    children: [
                      _chip(ProjectKindX.parse(project.projectKind).label),
                      _chip(accessible ? '目录可访问' : '目录失效'),
                      _chip(project.sourceKind),
                    ],
                  ),
                ],
              )),
        ),
        SizedBox(height: sectionGap),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _continueInChat,
            style: FilledButton.styleFrom(
              minimumSize:
                  Size.fromHeight(mobile ? 48 : AppTokens.kControlHeight),
              padding: mobile
                  ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                  : null,
              shape: mobile
                  ? RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16))
                  : null,
            ),
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('继续开发此项目'),
          ),
        ),
        if (_environmentLoading ||
            _environment != null ||
            _environmentError != null) ...[
          SizedBox(height: sectionGap),
          SectionCard(
            key: const ValueKey('project-home-environment'),
            glass: mobile ? false : null,
            borderRadius: contentRadius,
            padding: mobile
                ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
                : const EdgeInsets.all(16),
            child: _overviewDetails(
                mobile: mobile,
                title: _environmentError != null
                    ? '运行环境 · 检查失败'
                    : _environmentLoading
                        ? '运行环境 · 检查中'
                        : _blockedReason(project) != null
                            ? '运行环境 · 需要配置'
                            : '运行环境与能力',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('运行环境', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    if (_environmentLoading)
                      const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        title: Text('正在检查本机环境…'),
                      )
                    else if (_environmentError != null)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.warning_amber_outlined),
                        title: const Text('环境检查失败'),
                        subtitle: Text(_environmentError!),
                        trailing: TextButton(
                          onPressed: _reload,
                          child: const Text('重试'),
                        ),
                      )
                    else
                      EnvironmentStatusView(
                        snapshot: _environment!,
                        compact: true,
                      ),
                    if (!_environmentLoading &&
                        _environmentError == null &&
                        _blockedReason(project) != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '缺失能力：${_blockedReason(project)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        onPressed:
                            _installing ? null : () => _planInstall(project),
                        child: const Text('安装缺失项'),
                      ),
                    ],
                  ],
                )),
          ),
        ],
        SizedBox(height: sectionGap),
        Padding(
          padding: EdgeInsets.only(left: 4, bottom: mobile ? 6 : 8),
          child: Text('项目工具', style: Theme.of(context).textTheme.titleSmall),
        ),
        SectionCard(
          key: const ValueKey('project-home-tools'),
          glass: mobile ? false : null,
          borderRadius: contentRadius,
          child: Column(
            children: [
              if (ProjectKindX.parse(project.projectKind) ==
                  ProjectKind.staticWeb)
                NexusListTile(
                  key: const ValueKey('project-web-delivery'),
                  icon: Icons.web_outlined,
                  padding: toolPadding,
                  showDivider: mobile,
                  title: '网页预览与交付',
                  subtitle: '本机预览、编辑文件、核对并导出 ZIP',
                  onTap: !accessible
                      ? null
                      : () async {
                          await Navigator.of(context)
                              .push(NexusPageRoute.workspace(
                            builder: (_) => StaticWebDeliveryPage(
                                projectId: project.id,
                                workspacePath: project.canonicalRootPath,
                                projectName: project.name),
                          ));
                          if (mounted) unawaited(_reload());
                        },
                ),
              NexusListTile(
                icon: Icons.play_circle_outline,
                padding: toolPadding,
                showDivider: mobile,
                title: '打开开发工作台',
                subtitle: '识别项目并执行验证',
                onTap: accessible
                    ? () {
                        Navigator.of(context).push(NexusPageRoute.workspace(
                          builder: (_) => DevelopmentWorkbenchPage(
                            workspacePath: project.canonicalRootPath,
                            projectId: project.id,
                          ),
                        ));
                      }
                    : () {
                        FloatingToast.show(context, '原目录不可访问，请重新定位',
                            tone: ToastTone.warning);
                      },
              ),
              _overviewDetails(
                  mobile: mobile,
                  icon: Icons.account_tree_outlined,
                  title: 'Git、变更与远程',
                  subtitle: '分支状态、变更集回退与远程连接验证',
                  headerPadding: toolPadding,
                  child: Column(children: [
                    NexusListTile(
                      icon: Icons.account_tree_outlined,
                      padding: toolPadding,
                      showDivider: mobile,
                      title: 'Git',
                      subtitle: '状态、按文件暂存和提交',
                      onTap: () {
                        Navigator.of(context).push(NexusPageRoute.workspace(
                          builder: (_) => ProjectGitPage(
                            workspacePath: project.canonicalRootPath,
                          ),
                        ));
                      },
                    ),
                    NexusListTile(
                      icon: Icons.difference_outlined,
                      padding: toolPadding,
                      showDivider: mobile,
                      title: '任务变更集',
                      subtitle: '选择具体任务回退，人工修改不会覆盖',
                      onTap: () {
                        Navigator.of(context).push(NexusPageRoute.workspace(
                          builder: (_) => ProjectChangeSetPage(
                            projectId: project.id,
                            workspacePath: project.canonicalRootPath,
                          ),
                        ));
                      },
                    ),
                    NexusListTile(
                      icon: Icons.cloud_outlined,
                      padding: toolPadding,
                      showDivider:
                          mobile && settings.previewCommand?.isNotEmpty == true,
                      title: '远程执行验证',
                      subtitle: mobile ? '验证电脑端连接，不会同步代码' : '握手后再决定是否同步代码',
                      onTap: () {
                        Navigator.of(context).push(NexusPageRoute.detail(
                          builder: (_) => const RemoteExecutionPage(),
                        ));
                      },
                    ),
                  ])),
              if (settings.previewCommand?.isNotEmpty == true)
                NexusListTile(
                  icon: Icons.language_outlined,
                  padding: toolPadding,
                  showDivider: false,
                  title: _previewBusy
                      ? '正在处理预览…'
                      : _preview == null
                          ? ProjectKindX.parse(project.projectKind) ==
                                  ProjectKind.staticWeb
                              ? '启动自定义预览服务'
                              : '启动预览服务'
                          : '预览 ${_preview!.url}',
                  subtitle: _preview == null
                      ? '默认监听 127.0.0.1'
                      : 'job ${_preview!.jobId}',
                  onTap: _previewBusy
                      ? null
                      : () => _togglePreview(project, settings),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filesTab(Project project) {
    if (_filesLoading) return _tabLoading('正在读取项目文件…');
    if (_files.isEmpty) {
      return const EmptyStateView(
        icon: Icons.folder_off_outlined,
        title: '没有可见文件',
        message: '目录为空，或原路径已失效。',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        SectionCard(
          child: Column(
            children: [
              NexusListTile(
                icon: Icons.account_tree_outlined,
                title: '打开文件树',
                subtitle: '预览文本并引用到对话',
                onTap: () {
                  showNexusSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (sheetContext) => WorkspaceSheetFrame(
                      child: FileTreeSheet(
                        workspacePath: project.canonicalRootPath,
                      ),
                    ),
                  );
                },
              ),
              for (final entity in _files.take(40))
                NexusListTile(
                  icon: entity is Directory
                      ? Icons.folder_outlined
                      : Icons.insert_drive_file_outlined,
                  title: p.basename(entity.path),
                  subtitle: entity is File ? '文件' : '目录',
                  onTap: entity is File
                      ? () {
                          Navigator.of(context).push(NexusPageRoute.workspace(
                            builder: (_) => WorkspaceEditorPage(
                              workspacePath: project.canonicalRootPath,
                              relativePath: p.basename(entity.path),
                              projectId: project.id,
                            ),
                          ));
                        }
                      : null,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _terminalTab(Project project) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        SectionCard(
          child: NexusListTile(
            icon: Icons.terminal_rounded,
            title: '远程交互终端',
            subtitle: '连接 SSH/PTY 会话，支持 Vim、Node、Python 和移动辅助键盘',
            onTap: () {
              Navigator.push(
                context,
                NexusPageRoute.detail(
                  builder: (_) => const TerminalPage(),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: NexusListTile(
            icon: Icons.splitscreen_outlined,
            title: '项目命令与作业',
            subtitle: '在当前项目目录执行构建命令并管理后台作业',
            onTap: () {
              _terminal ??= TerminalCommandService(
                workspacePath: project.canonicalRootPath,
              );
              showNexusSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => WorkspaceSheetFrame(
                  child: TerminalSheet(
                    workspacePath: project.canonicalRootPath,
                    sharedService: _terminal,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _tasksTab() {
    if (_tasksLoading) return _tabLoading('正在加载任务…');
    if (_tasks.isEmpty) {
      return const EmptyStateView(
        icon: Icons.flag_outlined,
        title: '还没有任务',
        message: '从对话里发起开发任务后会出现在这里。',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        SectionCard(
          child: Column(
            children: [
              for (final task in _tasks) _projectTaskTile(task),
            ],
          ),
        ),
      ],
    );
  }

  Widget _projectTaskTile(Task task) {
    final info = TaskService().describe(task);
    final project = _project;
    return NexusListTile(
      icon: Icons.task_alt_outlined,
      title: info.title,
      subtitle: TaskService.taskTypeLabel(info.type),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          NexusStatusPill.fromString(info.status, isCompact: true),
          IconButton(
            tooltip: '回退本任务改动',
            icon: const Icon(Icons.difference_outlined),
            onPressed: project == null
                ? null
                : () {
                    Navigator.of(context).push(NexusPageRoute.workspace(
                      builder: (_) => ProjectChangeSetPage(
                        projectId: project.id,
                        workspacePath: project.canonicalRootPath,
                        taskId: task.id,
                        taskLabel: info.title,
                      ),
                    ));
                  },
          ),
        ],
      ),
      onTap: () {
        Navigator.of(context).push(NexusPageRoute.detail(
          builder: (_) => TaskDetailsPage(task: info),
        ));
      },
    );
  }

  Widget _artifactsTab(Project project) {
    if (_artifactsLoading) return _tabLoading('正在加载产物…');
    if (_recordedArtifacts.isEmpty) {
      return const EmptyStateView(
        icon: Icons.inventory_2_outlined,
        title: '还没有产物',
        message: '验证通过后会按 taskId/runId 归档到这里。',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        SectionCard(
          child: Column(
            children: [
              for (final artifact in _recordedArtifacts)
                NexusListTile(
                  icon: artifact.kind == 'apk'
                      ? Icons.android_outlined
                      : Icons.inventory_2_outlined,
                  title: artifact.relativePath,
                  subtitle: '${_artifactKindLabel(artifact.kind)} · '
                      '${artifact.bytes} bytes · '
                      '${artifact.taskId == 'manual' ? '手动验证' : '任务产物'}',
                  onTap: artifact.taskId == 'manual'
                      ? () => _copyArtifactPath(project, artifact)
                      : () => _openArtifactTask(artifact),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '复制产物路径',
                        icon: const Icon(Icons.copy_rounded),
                        onPressed: () => _copyArtifactPath(project, artifact),
                      ),
                      if (artifact.taskId != 'manual')
                        IconButton(
                          tooltip: '查看所属任务结果',
                          icon: const Icon(Icons.open_in_new_rounded),
                          onPressed: () => _openArtifactTask(artifact),
                        ),
                      if (artifact.kind == 'apk')
                        IconButton(
                          tooltip: '安装 APK',
                          icon: const Icon(Icons.install_mobile_rounded),
                          onPressed: () =>
                              _installRecordedArtifact(project, artifact),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tabLoading(String label) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(strokeWidth: 2),
          const SizedBox(height: 12),
          Text(label),
        ],
      ),
    );
  }

  String _artifactKindLabel(String kind) => switch (kind.toLowerCase()) {
        'apk' => 'APK',
        'web' => '网页',
        'archive' => '压缩包',
        _ => '文件',
      };

  Future<void> _copyArtifactPath(
      Project project, ProjectArtifact artifact) async {
    try {
      final file = await const ArtifactService().verifiedPayload(artifact);
      await Clipboard.setData(ClipboardData(text: file.path));
      if (mounted) {
        FloatingToast.show(context, '已复制校验副本的本地路径；对外使用请在成果中心分享',
            tone: ToastTone.success);
      }
    } catch (_) {
      if (mounted) {
        FloatingToast.show(context, '成果副本缺失或已变化，请重新生成',
            tone: ToastTone.warning);
      }
    }
  }

  Future<void> _openArtifactTask(ProjectArtifact artifact) async {
    try {
      final db = await ref.read(databaseProvider.future);
      final task = await db.findTask(artifact.taskId);
      if (!mounted) return;
      if (task == null) {
        FloatingToast.show(context, '未找到产物对应的任务记录', tone: ToastTone.warning);
        return;
      }
      await Navigator.of(context).push(NexusPageRoute.detail(
        builder: (_) => TaskDetailsPage(task: TaskService().describe(task)),
      ));
    } catch (error) {
      if (mounted) {
        FloatingToast.show(context, '无法打开任务结果：$error', tone: ToastTone.warning);
      }
    }
  }

  Future<void> _togglePreview(Project project, ProjectSettings settings) async {
    final command = settings.previewCommand;
    if (_previewBusy || command == null || command.isEmpty) return;
    setState(() => _previewBusy = true);
    try {
      _terminal ??= TerminalCommandService(
        workspacePath: project.canonicalRootPath,
      );
      _previewService ??= PreviewService(
        terminal: _terminal!,
        workspacePath: project.canonicalRootPath,
      );
      if (_preview != null) {
        await _previewService!.stop();
        if (!mounted) return;
        setState(() => _preview = null);
        return;
      }
      final session = await _previewService!.start(
        projectId: project.id,
        workspacePath: project.canonicalRootPath,
        command: command,
        preferredPort: settings.previewPort ?? 8765,
        allowLan: settings.allowLanPreview,
      );
      if (!mounted) return;
      setState(() => _preview = session);
      FloatingToast.show(context, '预览已就绪 ${session.url}',
          tone: ToastTone.success);
    } catch (error) {
      if (mounted) {
        FloatingToast.show(context, LocalErrorCopy.of(error, action: '预览').headline(), tone: ToastTone.warning);
      }
    } finally {
      if (mounted) setState(() => _previewBusy = false);
    }
  }

  Future<void> _installRecordedArtifact(
      Project project, ProjectArtifact artifact) async {
    String path;
    try {
      path = (await const ArtifactService().verifiedPayload(artifact)).path;
    } catch (_) {
      if (mounted) {
        FloatingToast.show(context, '成果副本缺失或已变化，未启动安装',
            tone: ToastTone.warning);
      }
      return;
    }
    final result = await const ApkInstallBridge().install(path);
    if (!mounted) return;
    final message = switch (result.status) {
      'started' => '已拉起系统安装器，返回后会保留安装结果',
      'cancelled' => '用户取消安装',
      'permission_required' => '需要允许安装未知应用后再试',
      _ => result.message ?? '安装失败',
    };
    FloatingToast.show(
      context,
      message,
      tone: result.started ? ToastTone.success : ToastTone.warning,
    );
  }

  Future<void> _planInstall(Project project) async {
    final snapshot = _environment;
    if (snapshot == null) return;
    _terminal ??= TerminalCommandService(
      workspacePath: project.canonicalRootPath,
    );
    String? extraCommand;
    try {
      extraCommand = const DependencyLockfile()
          .resolve(
            workspacePath: project.canonicalRootPath,
            kind: ProjectKindX.parse(project.projectKind),
          )
          ?.installCommand;
    } on LockfileConflict catch (conflict) {
      extraCommand = await _chooseLockfile(conflict);
      if (extraCommand == null) return;
    }
    final installer = InstallJobService(
      terminal: _terminal!,
      environment: ref.read(environmentServiceProvider),
    );
    final job = installer.plan(
      kind: ProjectKindX.parse(project.projectKind),
      snapshot: snapshot,
      settings: ProjectSettings.decode(project.settingsJson),
      workspacePath: project.canonicalRootPath,
      extraCommand: extraCommand,
    );
    setState(() => _installJob = job);
    if (!mounted) return;
    await showNexusSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return InstallJobSheet(
              job: _installJob ?? job,
              busy: _installing,
              onClose: () => Navigator.pop(sheetContext),
              onStart: () async {
                await _runInstall(installer, job.id);
                setSheetState(() {});
              },
            );
          },
        );
      },
    );
  }

  Future<String?> _chooseLockfile(LockfileConflict conflict) {
    return showNexusSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('检测到多个锁文件，请选择包管理器')),
            for (final choice in conflict.choices)
              ListTile(
                title: Text(choice.label),
                subtitle: Text(choice.installCommand),
                onTap: () => Navigator.pop(context, choice.installCommand),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _runInstall(
    InstallJobService installer,
    String jobId,
  ) async {
    setState(() => _installing = true);
    try {
      final result = await installer.run(
        jobId,
        startJob: (command) => _terminal!.startJob(
          command: command,
          workingDirectory: _project?.canonicalRootPath,
        ),
      );
      if (mounted) setState(() => _installJob = result);
      await ref.read(environmentServiceProvider).inspect(force: true);
      if (mounted) await _reload();
    } catch (error) {
      if (mounted) {
        FloatingToast.show(context, LocalErrorCopy.of(error).headline(), tone: ToastTone.danger);
      }
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  String? _blockedReason(Project project) {
    final snapshot = _environment;
    if (snapshot == null) return null;
    return ref.read(environmentServiceProvider).blockedReasonFor(
          kind: ProjectKindX.parse(project.projectKind),
          settings: ProjectSettings.decode(project.settingsJson),
          snapshot: snapshot,
        );
  }

  Widget _chip(String label) {
    final mobile = DesktopTheme.maybeOf(context) == null;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: mobile ? 8 : 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius:
            BorderRadius.circular(mobile ? AppTokens.radiusControl : 999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
