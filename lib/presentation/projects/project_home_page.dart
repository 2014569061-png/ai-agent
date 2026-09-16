import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
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
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_list_tile.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/section_card.dart';
import '../../application/apk_install_bridge.dart';
import '../../application/artifact_service.dart';
import '../../application/preview_service.dart';
import 'project_change_set_page.dart';
import 'project_git_page.dart';
import 'remote_execution_page.dart';
import '../workspace/development_workbench_page.dart';
import '../workspace/file_tree_sheet.dart';
import '../workspace/terminal_sheet.dart';
import '../workspace/workspace_editor_page.dart';

class ProjectHomePage extends ConsumerStatefulWidget {
  const ProjectHomePage({super.key, required this.projectId});

  final String projectId;

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
    if (previewService != null) unawaited(previewService.stop());
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
      unawaited(_loadEnvironment(generation));
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = '$error';
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
          _environmentError = '$error';
          _environmentLoading = false;
        });
      }
    }
  }

  Future<void> _continueInChat() async {
    final project = _project;
    if (project == null) return;
    await ref.read(chatControllerProvider.notifier).openProject(project);
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final project = _project;
    return Scaffold(
      backgroundColor: isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas,
      appBar: NexusPageHeader(
        title: project?.name ?? '项目',
        subtitle: project == null
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyStateView(
                  icon: Icons.error_outline,
                  title: '无法打开项目',
                  message: _error,
                )
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _overview(project!),
                    _filesTab(project),
                    _terminalTab(project),
                    _tasksTab(),
                    _artifactsTab(project),
                  ],
                ),
    );
  }

  Widget _overview(Project project) {
    final settings = ProjectSettings.decode(project.settingsJson);
    final accessible = Directory(project.canonicalRootPath).existsSync();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        SectionCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(project.name,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(project.canonicalRootPath,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip(ProjectKindX.parse(project.projectKind).label),
                  _chip(accessible ? '目录可访问' : '目录失效'),
                  _chip(project.sourceKind),
                ],
              ),
            ],
          ),
        ),
        if (_environmentLoading ||
            _environment != null ||
            _environmentError != null) ...[
          const SizedBox(height: AppTokens.sp4),
          SectionCard(
            padding: const EdgeInsets.all(16),
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
                    onPressed: _installing ? null : () => _planInstall(project),
                    child: const Text('安装缺失项'),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: AppTokens.sp4),
        SectionCard(
          child: Column(
            children: [
              NexusListTile(
                icon: Icons.chat_bubble_outline,
                title: '继续开发',
                subtitle: '把当前项目带到对话里',
                onTap: _continueInChat,
              ),
              NexusListTile(
                icon: Icons.play_circle_outline,
                title: '运行 / 预览',
                subtitle: settings.previewCommand?.isNotEmpty == true
                    ? settings.previewCommand
                    : '未配置预览命令',
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
              NexusListTile(
                icon: Icons.verified_outlined,
                title: '执行验证',
                subtitle: settings.testCommand?.isNotEmpty == true
                    ? settings.testCommand
                    : '使用项目检测出的检查命令',
                onTap: accessible
                    ? () {
                        Navigator.of(context).push(NexusPageRoute.workspace(
                          builder: (_) => DevelopmentWorkbenchPage(
                            workspacePath: project.canonicalRootPath,
                            projectId: project.id,
                          ),
                        ));
                      }
                    : null,
              ),
              NexusListTile(
                icon: Icons.account_tree_outlined,
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
                title: '任务变更集',
                subtitle: '回退本任务改动，人工修改不会覆盖',
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
                title: '远程执行验证',
                subtitle: '握手后再决定是否同步代码',
                onTap: () {
                  Navigator.of(context).push(NexusPageRoute.detail(
                    builder: (_) => const RemoteExecutionPage(),
                  ));
                },
              ),
              if (settings.previewCommand?.isNotEmpty == true)
                NexusListTile(
                  icon: Icons.language_outlined,
                  title: _preview == null ? '启动预览服务' : '预览 ${_preview!.url}',
                  subtitle: _preview == null
                      ? '默认监听 127.0.0.1'
                      : 'job ${_preview!.jobId}',
                  onTap: () => _togglePreview(project, settings),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        SectionCard(
          child: Column(
            children: [
              NexusListTile(
                icon: Icons.account_tree_outlined,
                title: '打开文件树',
                subtitle: '预览文本并引用到对话',
                onTap: () {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (sheetContext) => SizedBox(
                      height: MediaQuery.of(context).size.height * 0.75,
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        SectionCard(
          child: NexusListTile(
            icon: Icons.terminal_rounded,
            title: '全屏交互终端 (PTY)',
            subtitle: '实时 SSH/PTY 会话，支持 Vim、Node、Python 及移动辅助键盘',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
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
            title: '终端作业面板 (Sheet)',
            subtitle: '在项目目录中执行构建命令与后台作业管理',
            onTap: () {
              _terminal ??= TerminalCommandService(
                workspacePath: project.canonicalRootPath,
              );
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => SizedBox(
                  height: MediaQuery.of(context).size.height * 0.75,
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        SectionCard(
          child: Column(
            children: [
              for (final task in _tasks)
                NexusListTile(
                  icon: Icons.task_alt_outlined,
                  title: TaskService().describe(task).title,
                  subtitle: '${task.status} · ${task.type}',
                  onTap: () {
                    Navigator.of(context).push(NexusPageRoute.detail(
                      builder: (_) => TaskDetailsPage(
                        task: TaskService().describe(task),
                      ),
                    ));
                  },
                ),
            ],
          ),
        ),
      ],
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
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
                  subtitle:
                      '${artifact.kind} · ${artifact.bytes} bytes · task ${artifact.taskId}',
                  onTap: artifact.kind == 'apk'
                      ? () => _installRecordedArtifact(project, artifact)
                      : null,
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

  Future<void> _togglePreview(Project project, ProjectSettings settings) async {
    final command = settings.previewCommand;
    if (command == null || command.isEmpty) return;
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
        FloatingToast.show(context, '预览失败：$error', tone: ToastTone.warning);
      }
    }
  }

  Future<void> _installRecordedArtifact(
      Project project, ProjectArtifact artifact) async {
    final path = p.join(project.canonicalRootPath, artifact.relativePath);
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
    await showModalBottomSheet<void>(
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
    return showModalBottomSheet<String>(
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
        FloatingToast.show(context, '$error', tone: ToastTone.danger);
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
