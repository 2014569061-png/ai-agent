import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'web_preview_dialog.dart';
import '../widgets/immersive_sheet.dart';

class FileTreeSheet extends StatefulWidget {
  const FileTreeSheet({super.key, required this.workspacePath});
  final String workspacePath;

  @override
  State<FileTreeSheet> createState() => _FileTreeSheetState();
}

class _FileTreeSheetState extends State<FileTreeSheet> {
  List<FileSystemEntity> _entities = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDirectory();
  }

  Future<void> _loadDirectory() async {
    setState(() => _loading = true);
    final dir = Directory(widget.workspacePath);
    if (await dir.exists()) {
      try {
        final list =
            await dir.list(recursive: true, followLinks: false).toList();
        // 过滤隐藏文件与临时目录
        final filtered = list.where((e) {
          final rel = p.relative(e.path, from: widget.workspacePath);
          return !rel.startsWith('.') &&
              !rel.contains('/.') &&
              !rel.contains('\\.') &&
              !rel.contains('build');
        }).toList();

        // 排序：目录在前，按名称升序
        filtered.sort((a, b) {
          final aIsDir = a is Directory;
          final bIsDir = b is Directory;
          if (aIsDir && !bIsDir) return -1;
          if (!aIsDir && bIsDir) return 1;
          return a.path.compareTo(b.path);
        });

        if (mounted) {
          setState(() {
            _entities = filtered;
            _loading = false;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _loading = false);
      }
    } else {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _viewFile(File file) async {
    try {
      final content = await file.readAsString();
      if (!mounted) return;
      showImmersiveDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(p.basename(file.path),
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: SingleChildScrollView(
              child: SelectableText(
                content,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('复制全部'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: content));
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
              },
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法以文本读取此文件: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final projectName = p.basename(widget.workspacePath);

    return Container(
      // 外壳由 showImmersiveSheet 的 ImmersiveSurface 提供毛玻璃，这里不再铺不透明底色。
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽条
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          // 标题与操作栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.folder_open, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        projectName.isEmpty ? '项目工作区' : projectName,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        widget.workspacePath,
                        style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.phone_iphone_rounded, size: 18),
                  label: const Text('网页预览'),
                  onPressed: () {
                    final indexPath =
                        p.join(widget.workspacePath, 'index.html');
                    showImmersiveDialog(
                      context: context,
                      builder: (_) => WebPreviewDialog(
                          indexPath: indexPath,
                          workspacePath: widget.workspacePath),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: '刷新文件树',
                  onPressed: _loadDirectory,
                ),
              ],
            ),
          ),
          const Divider(height: 20),
          // 列表
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _entities.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.create_new_folder_outlined,
                                size: 48,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.5)),
                            const SizedBox(height: 10),
                            Text('工作区暂无文件\n可直接让 AI 在此创建项目或写代码',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _entities.length,
                        itemBuilder: (context, index) {
                          final entity = _entities[index];
                          final isDir = entity is Directory;
                          final relPath = p.relative(entity.path,
                              from: widget.workspacePath);

                          return ListTile(
                            dense: true,
                            leading: Icon(
                              isDir ? Icons.folder : _getFileIcon(entity.path),
                              size: 20,
                              color: isDir
                                  ? Colors.amber[700]
                                  : theme.colorScheme.primary,
                            ),
                            title: Text(
                              relPath,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight:
                                    isDir ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                            onTap:
                                isDir ? null : () => _viewFile(entity as File),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon(String path) {
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.dart':
        return Icons.flutter_dash;
      case '.html':
      case '.htm':
        return Icons.html;
      case '.css':
        return Icons.css;
      case '.js':
      case '.ts':
      case '.json':
        return Icons.javascript;
      case '.py':
        return Icons.code;
      case '.md':
      case '.txt':
        return Icons.description;
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.svg':
        return Icons.image;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }
}
