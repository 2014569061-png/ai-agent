import 'dart:io';

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
import '../widgets/async_state_view.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_list_tile.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/section_card.dart';
import '../widgets/confirm_action.dart';
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
    final template = await showNexusSheet<ProjectTemplate>(
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
      // 刻意不在这里要求「所有文件访问权限」。
      //
      // 系统目录选择器给出的授权已经够读取，而 ProjectService.importDirectory
      // 也明确把写入探测当作「能写就更好」而不是闸门（见那里的注释）。旧代码把
      // 授权挡在选目录之前，等于让「只想浏览、只想让模型读代码」的用户必须先
      // 交出全盘访问权限，否则连只读导入都做不了——而只读导入本来是被支持的，
      // 且有测试钉住（写入探测失败要记录 directoryWritable: false）。
      // 现在改为：先导入；导入后发现目录只读，再主动引导补权限（_offerWriteAccess）。
      // 统一走 WorkspaceService：Android 的目录授权与最近目录记录都在这里处理。
      final path =
          await ref.read(chatControllerProvider.notifier).pickWorkspace();
      if (!mounted || path == null || path.isEmpty) return;
      await _offerWriteAccess();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        FloatingToast.show(context, '$error', tone: ToastTone.danger);
      }
    }
  }

  /// 目录导入成功但只能读取时，主动引导补齐写权限。
  ///
  /// 只读目录可以被正常导入（可浏览、可让模型读代码），所以不阻塞导入；但用户
  /// 迟早会想让模型改代码，届时只丢一句「请去系统设置里开启」等于把死路留给
  /// 用户。这里直接给出「去授权」动作，授权后重新探测写入能力并落库，省掉一次
  /// 重新导入。
  Future<void> _offerWriteAccess() async {
    try {
      final projectId = ref.read(chatControllerProvider).currentProjectId;
      if (projectId == null || !mounted) return;
      final db = await ref.read(databaseProvider.future);
      final project = await db.findProject(projectId);
      if (project == null) return;
      final settings = ProjectSettings.decode(project.settingsJson);
      if (settings.directoryWritable || !mounted) return;

      final grant = await showConfirmAction(
        context,
        title: '目录目前只能读取',
        message: '已导入该目录，现在可以浏览、也可以让模型读取代码，但还不能修改文件。'
            '需要修改文件时，请在系统设置为 NEXUS Agent 开启「所有文件访问权限」。',
        confirmLabel: '去授权',
        cancelLabel: '稍后再说',
        isDanger: false,
      );
      if (!grant || !mounted) return;

      final granted = await ensureAllFilesAccess(context);
      if (!granted || !mounted) return;

      // 以真实的写探测为准，而不是「授权调用返回了 true」：刚授权时系统可能还
      // 没同步，直接标记可写会得到一个改不了文件却显示可写的项目。
      final writable = await ProjectService.probeWritable(
        Directory(project.canonicalRootPath),
      );
      if (writable && mounted) {
        await ProjectService(db: db).updateSettings(
          projectId,
          settings.copyWith(directoryWritable: true),
        );
      }
      if (!mounted) return;
      FloatingToast.show(
        context,
        writable ? '已获得文件访问权限，现在可以修改项目文件' : '仍未获得写权限，之后可重新导入目录或在系统设置里开启',
        tone: writable ? ToastTone.success : ToastTone.warning,
      );
    } catch (_) {
      // 引导失败不应影响导入结果。
    }
  }

  Future<void> _importZip() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    final file = picked.singleOrNull;
    if (file == null) return;
    final Uint8List? bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      return;
    }
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
    final packageController = TextEditingController(text: 'com.nexus.starter');
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
      body: AsyncStateView(
        loading: _loading,
        onRetry: _reload,
        child: ListView(
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
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (currentId == project.id)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Semantics(
                                  label: '当前项目',
                                  child:
                                      const Icon(Icons.check_rounded, size: 18),
                                ),
                              ),
                            IconButton(
                              tooltip: '打开项目主页',
                              icon: const Icon(Icons.chevron_right_rounded),
                              onPressed: () {
                                Navigator.of(context).push(
                                  NexusPageRoute.workspace(
                                    builder: (_) => ProjectHomePage(
                                      projectId: project.id,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        onTap: () => _open(project),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
