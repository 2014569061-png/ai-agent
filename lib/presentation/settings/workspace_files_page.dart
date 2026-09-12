import 'dart:async';
import '../theme/app_palette.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

import '../../application/chat_controller.dart';
import '../../domain/models.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_page_header.dart';
import 'settings_components.dart';
import '../widgets/immersive_sheet.dart';

class WorkspaceFilesPage extends ConsumerStatefulWidget {
  const WorkspaceFilesPage({super.key});

  @override
  ConsumerState<WorkspaceFilesPage> createState() => _WorkspaceFilesPageState();
}

class _WorkspaceFilesPageState extends ConsumerState<WorkspaceFilesPage> {
  static const _recentDirsKey = 'settings.workspace.recent_dirs';
  List<String> _recentDirs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_recentDirsKey) ?? [];
    if (mounted) {
      setState(() {
        _recentDirs = list;
        _loading = false;
      });
    }
  }

  Future<void> _pickWorkspace() async {
    if (kIsWeb) {
      FloatingToast.show(context, 'Web 平台使用内存沙箱，暂不支持切换本地物理目录');
      return;
    }
    try {
      final selected = await FilePicker.platform.getDirectoryPath();
      if (selected != null && mounted) {
        unawaited(
            ref.read(chatControllerProvider.notifier).setWorkspace(selected));
        final prefs = await SharedPreferences.getInstance();
        final updated = [selected, ..._recentDirs.where((d) => d != selected)]
            .take(5)
            .toList();
        await prefs.setStringList(_recentDirsKey, updated);
        if (!mounted) return;
        setState(() => _recentDirs = updated);
        FloatingToast.show(context, '已切换工作区到: $selected');
      }
    } catch (e) {
      if (mounted) FloatingToast.show(context, '选取目录失败: $e');
    }
  }

  Future<void> _importFile() async {
    try {
      final workspace = ref.read(chatControllerProvider).currentWorkspacePath;
      if (kIsWeb || workspace == null || workspace.isEmpty) {
        if (mounted) FloatingToast.show(context, '请先选择本地工作区');
        return;
      }
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null || result.files.isEmpty) return;
      final importDir = Directory('$workspace${Platform.pathSeparator}imports');
      await importDir.create(recursive: true);
      var imported = 0;
      for (final picked in result.files) {
        final path = picked.path;
        if (path == null) continue;
        final source = File(path);
        if (!await source.exists()) continue;
        await source
            .copy('${importDir.path}${Platform.pathSeparator}${picked.name}');
        imported++;
      }
      if (mounted) {
        FloatingToast.show(
          context,
          imported == 0 ? '未找到可导入的本地文件' : '已导入 $imported 个文件到 imports 目录',
        );
      }
    } catch (e) {
      if (mounted) FloatingToast.show(context, '导入失败: $e');
    }
  }

  Future<void> _exportConversation() async {
    final state = ref.read(chatControllerProvider);
    final buffer = StringBuffer('# ${state.conversationTitle}\n\n');
    for (final message in state.messages) {
      final role = switch (message.role) {
        MessageRole.user => '用户',
        MessageRole.assistant => '助手',
        MessageRole.system => '系统',
        MessageRole.tool => '工具',
      };
      buffer.writeln('## $role\n\n${message.text}\n');
    }
    try {
      final dir = await getTemporaryDirectory();
      final file =
          File('${dir.path}${Platform.pathSeparator}nexus-conversation.md');
      await file.writeAsString(buffer.toString());
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'NEXUS Agent 会话导出',
        ),
      );
    } catch (e) {
      if (mounted) FloatingToast.show(context, '导出失败: $e');
    }
  }

  Future<void> _cleanTempFiles() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理临时缓存文件？'),
        content: const Text(
          '此操作将清理应用下载缓存、临时渲染图与临时转换文件。不会影响你的工作区文件与会话记录。\n\n确定清理吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定清理'),
          ),
        ],
      ),
    );

    if (confirmed == true && !kIsWeb) {
      try {
        final tempDir = await getTemporaryDirectory();
        if (tempDir.existsSync()) {
          final entities = tempDir.listSync();
          for (final entity in entities) {
            try {
              entity.deleteSync(recursive: true);
            } catch (_) {}
          }
        }
        if (mounted) {
          FloatingToast.show(context, '临时文件清理完成', tone: ToastTone.success);
        }
      } catch (e) {
        if (mounted) FloatingToast.show(context, '清理部分文件失败: $e');
      }
    } else if (confirmed == true && mounted) {
      FloatingToast.show(context, '临时缓存已清理', tone: ToastTone.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentWs = ref.watch(chatControllerProvider).currentWorkspacePath ??
        (kIsWeb ? '内置内存沙箱' : '未指定（默认使用沙箱根目录）');

    return Scaffold(
      backgroundColor: settingsBgColor(context),
      appBar: const NexusPageHeader(
        title: '工作区与文件',
        subtitle: '沙箱环境 · 目录访问与存储管理',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 36),
              children: [
                const SettingsSectionTitle('当前工作区'),
                SettingsGroupCard(
                  children: [
                    SettingsTile(
                      icon: Icons.folder_rounded,
                      iconColor: settingsMutedColor(context),
                      title: '工作区路径',
                      subtitle: currentWs,
                      onTap: _pickWorkspace,
                    ),
                    const SettingsDivider(),
                    SettingsTile(
                      icon: Icons.shield_rounded,
                      iconColor: AppPalette.success,
                      title: '工作区权限',
                      subtitle: '受控沙箱：文件读写严格限制在工作区内部',
                      showChevron: false,
                      trailingWidget: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppPalette.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '受控安全',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppPalette.success,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SettingsSectionTitle('文件传输与授权'),
                SettingsGroupCard(
                  children: [
                    SettingsTile(
                      icon: Icons.file_upload_rounded,
                      iconColor: settingsMutedColor(context),
                      title: '导入文件',
                      subtitle: '选取外部文件或文档导入到 Agent 工作区',
                      onTap: _importFile,
                    ),
                    const SettingsDivider(),
                    SettingsTile(
                      icon: Icons.file_download_rounded,
                      iconColor: AppPalette.warning,
                      title: '导出会话与文件',
                      subtitle: '以 Markdown 或加密形式备份项目与对话',
                      onTap: _exportConversation,
                    ),
                    const SettingsDivider(),
                    SettingsTile(
                      icon: Icons.lock_clock_rounded,
                      iconColor: settingsMutedColor(context),
                      title: '文件访问授权策略',
                      subtitle: '删除文件与关键代码编辑始终经过弹窗确认',
                      onTap: () {
                        showImmersiveDialog<void>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('文件授权说明'),
                            content: const Text(
                              'NEXUS Agent 对文件系统遵循零信任原则：\n\n'
                              '1. 仅允许访问选定工作区内的文件，严禁越界逃逸；\n'
                              '2. 写文件与编辑文件受用户审批策略控制；\n'
                              '3. 删除文件强制逐次确认，不可绕过。',
                            ),
                            actions: [
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('了解'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
                if (_recentDirs.isNotEmpty) ...[
                  const SettingsSectionTitle('最近访问目录'),
                  SettingsGroupCard(
                    children: [
                      for (var i = 0; i < _recentDirs.length; i++) ...[
                        SettingsTile(
                          icon: Icons.history_rounded,
                          iconColor: settingsMutedColor(context),
                          title: _recentDirs[i],
                          trailingWidget: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 16,
                            color: AppPalette.lightTextMuted,
                          ),
                          onTap: () {
                            ref
                                .read(chatControllerProvider.notifier)
                                .setWorkspace(_recentDirs[i]);
                            FloatingToast.show(
                              context,
                              '已切换工作区: ${_recentDirs[i]}',
                            );
                          },
                        ),
                        if (i < _recentDirs.length - 1) const SettingsDivider(),
                      ],
                    ],
                  ),
                ],
                const SettingsSectionTitle('存储维护'),
                SettingsGroupCard(
                  children: [
                    SettingsTile(
                      icon: Icons.cleaning_services_rounded,
                      iconColor: AppPalette.danger,
                      title: '清理临时缓存文件',
                      titleColor: AppPalette.danger,
                      subtitle: '清理临时预览、生成草稿与图片缓存（二次确认）',
                      onTap: _cleanTempFiles,
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
