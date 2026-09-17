import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../application/chat_controller.dart';
import '../../application/project_kind.dart';
import '../../application/project_service.dart';
import '../../application/project_settings.dart';
import '../../application/project_template_service.dart';
import '../../application/providers.dart';
import '../../infrastructure/database/app_database.dart';
import '../motion/nexus_page_route_factory.dart';
import '../theme/app_tokens.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_list_tile.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/section_card.dart';
import '../widgets/nexus_sheet.dart';
import 'project_home_page.dart';
import 'storage_access_flow.dart';

class ProjectPickerPage extends ConsumerStatefulWidget {
  const ProjectPickerPage({super.key});

  @override
  ConsumerState<ProjectPickerPage> createState() => _ProjectPickerPageState();
}

class _ProjectPickerPageState extends ConsumerState<ProjectPickerPage> {
  List<Project> _projects = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<ProjectService> _service() async {
    final db = await ref.read(databaseProvider.future);
    return ProjectService(db: db);
  }

  Future<void> _reload() async {
    try {
      final service = await _service();
      await service.migrateLegacyWorkspaces();
      final projects = await service.list();
      if (!mounted) return;
      setState(() {
        _projects = projects;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      FloatingToast.show(context, '加载项目失败: $error', tone: ToastTone.danger);
    }
  }

  Future<void> _open(Project project) async {
    try {
      await ref.read(chatControllerProvider.notifier).openProject(project);
      if (!mounted) return;
      Navigator.of(context).pop(project);
    } catch (error) {
      if (mounted) {
        FloatingToast.show(context, '$error', tone: ToastTone.danger);
      }
    }
  }

  Future<void> _createFromTemplate() async {
    final template = await showModalBottomSheet<ProjectTemplate>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final templates = const ProjectTemplateService().all();
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('选择模板')),
              for (final template in templates)
                ListTile(
                  title: Text(template.label),
                  subtitle: Text(template.summary),
                  onTap: () => Navigator.pop(context, template),
                ),
            ],
          ),
        );
      },
    );
    if (template == null || !mounted) return;
    final name = await _askName('新建 ${template.label}', template.label);
    if (name == null || name.trim().isEmpty) return;
    String? packageName;
    String? appName;
    if (template.kind == ProjectKind.javaApk) {
      final extras = await _askJavaApkConfig();
      if (extras == null) return;
      packageName = extras.$1;
      appName = extras.$2;
    }
    try {
      final service = await _service();
      final project = await service.createFromTemplate(
        CreateProjectRequest(
          name: name,
          templateId: template.id,
          packageName: packageName,
          appName: appName,
        ),
      );
      await _open(project);
    } catch (error) {
      if (mounted) {
        FloatingToast.show(context, '$error', tone: ToastTone.danger);
      }
    }
  }

  Future<void> _importDirectory() async {
    if (kIsWeb) {
      FloatingToast.show(context, 'Web 暂不支持导入本地目录');
      return;
    }
    try {
      // 先完成授权，再执行导入：没有「所有文件访问权限」时，用户选中的目录
      // 对 dart:io 往往只读，导入会退化成一个改不了文件的项目。
      if (!await ensureAllFilesAccess(context)) return;
      if (!mounted) return;
      // 统一走 WorkspaceService：Android 的目录授权与最近目录记录都在这里处理。
      final path =
          await ref.read(chatControllerProvider.notifier).pickWorkspace();
      if (!mounted || path == null || path.isEmpty) return;
      await _warnIfDirectoryReadOnly();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        FloatingToast.show(context, '$error', tone: ToastTone.danger);
      }
    }
  }

  /// 目录可读但不可写时给出可操作的提示。
  ///
  /// Android 11+ 分区存储下，系统目录选择器给出的路径可能只具备读取权限；
  /// 这种目录允许导入（可浏览、可让模型读取代码），但改文件会失败，
  /// 所以必须明确告诉用户去哪里补权限，而不是留一个无解的「目录不可写」。
  Future<void> _warnIfDirectoryReadOnly() async {
    try {
      final projectId = ref.read(chatControllerProvider).currentProjectId;
      if (projectId == null) return;
      final db = await ref.read(databaseProvider.future);
      final project = await db.findProject(projectId);
      if (project == null) return;
      final settings = ProjectSettings.decode(project.settingsJson);
      if (settings.directoryWritable || !mounted) return;
      FloatingToast.show(
        context,
        '目录已导入，但当前只能读取。需要修改文件时，请在系统设置里为 NEXUS Agent '
        '开启「所有文件访问权限」。',
        tone: ToastTone.warning,
      );
    } catch (_) {
      // 提示失败不应影响导入结果。
    }
  }

  Future<void> _importZip() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    try {
      final service = await _service();
      final project = await service.importArchive(
        ImportArchiveRequest(
          archivePath: file.name,
          bytes: bytes,
          name: p.basenameWithoutExtension(file.name),
        ),
      );
      await _open(project);
    } catch (error) {
      if (mounted) {
        FloatingToast.show(context, '$error', tone: ToastTone.danger);
      }
    }
  }

  Future<(String, String)?> _askJavaApkConfig() async {
    final packageController =
        TextEditingController(text: 'com.nexus.starter');
    final appController = TextEditingController(text: 'NexusStarter');
    final result = await showNexusDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('小型 Java APK 配置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: packageController,
              decoration: const InputDecoration(labelText: '包名'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: appController,
              decoration: const InputDecoration(labelText: '应用名称'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              (packageController.text.trim(), appController.text.trim()),
            ),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      packageController.dispose();
      appController.dispose();
    });
    return result;
  }

  Future<String?> _askName(String title, String initial) async {
    final controller = TextEditingController(text: initial);
    final result = await showNexusDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '项目名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final currentId = ref.watch(
        chatControllerProvider.select((state) => state.currentProjectId));
    return Scaffold(
      appBar: const NexusPageHeader(
        title: '项目',
        subtitle: '选择、新建或导入开发项目',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                SectionCard(
                  child: Column(
                    children: [
                      NexusListTile(
                        icon: Icons.add_box_outlined,
                        title: '从模板新建',
                        subtitle: '静态网页 / Node / Python / 小型 Java APK',
                        onTap: _createFromTemplate,
                      ),
                      NexusListTile(
                        icon: Icons.folder_open_outlined,
                        title: '导入目录',
                        subtitle: '打开已有本地工程',
                        onTap: _importDirectory,
                      ),
                      NexusListTile(
                        icon: Icons.unarchive_outlined,
                        title: '导入 ZIP',
                        subtitle: '解压到应用管理的项目目录',
                        onTap: _importZip,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTokens.sp4),
                if (_projects.isEmpty)
                  const EmptyStateView(
                    icon: Icons.account_tree_outlined,
                    title: '还没有项目',
                    message: '新建模板或导入目录后，对话会记住这个项目。',
                  )
                else
                  SectionCard(
                    child: Column(
                      children: [
                        for (final project in _projects)
                          NexusListTile(
                            icon: Icons.folder_outlined,
                            title: project.name,
                            subtitle:
                                '${ProjectKindX.parse(project.projectKind).label} · ${project.canonicalRootPath}',
                            trailing: currentId == project.id
                                ? const Icon(Icons.check_rounded, size: 18)
                                : IconButton(
                                    tooltip: '打开项目主页',
                                    icon: const Icon(Icons.chevron_right_rounded),
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        NexusPageRoute.workspace(
                                          builder: (_) =>
                                              ProjectHomePage(projectId: project.id),
                                        ),
                                      );
                                    },
                                  ),
                            onTap: () => _open(project),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
