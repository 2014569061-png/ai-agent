import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_strings.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/floating_toast.dart';
import '../widgets/immersive_sheet.dart';

/// G1 工作区文件树:目录导航模式(进入子目录 / 后退 / 前进),
/// 替代旧版"递归平铺 + 网页预览"。
class FileTreeSheet extends StatefulWidget {
  const FileTreeSheet({
    super.key,
    required this.workspacePath,
    this.onReselectWorkspace,
  });

  final String workspacePath;

  /// 可选的“重新选择工作区”回调（面板内就地切换根目录）。
  final VoidCallback? onReselectWorkspace;

  @override
  State<FileTreeSheet> createState() => _FileTreeSheetState();
}

class _FileTreeSheetState extends State<FileTreeSheet> {
  late String _currentDir;
  final List<String> _back = [];
  final List<String> _forward = [];
  List<FileSystemEntity> _entities = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentDir = widget.workspacePath;
    _loadDirectory();
  }

  String get _currentLabel {
    final rel = p.relative(_currentDir, from: widget.workspacePath);
    return rel == '.' ? widget.workspacePath : rel;
  }

  Future<void> _loadDirectory() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final dir = Directory(_currentDir);
    if (!dir.existsSync()) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '目录不存在或已不可访问：$_currentDir';
        });
      }
      return;
    }
    try {
      final list = await dir.list(followLinks: false).toList();
      // 过滤隐藏项与构建目录
      final filtered = list.where((e) {
        final name = p.basename(e.path);
        return !name.startsWith('.') && name != 'build';
      }).toList();

      filtered.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase());
      });

      if (mounted) setState(() => _entities = filtered);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openDir(String path) {
    if (path == _currentDir) return;
    setState(() {
      _back.add(_currentDir);
      _forward.clear();
      _currentDir = path;
    });
    _loadDirectory();
  }

  void _goBack() {
    if (_back.isEmpty) return;
    setState(() {
      _forward.add(_currentDir);
      _currentDir = _back.removeLast();
    });
    _loadDirectory();
  }

  void _goForward() {
    if (_forward.isEmpty) return;
    setState(() {
      _back.add(_currentDir);
      _currentDir = _forward.removeLast();
    });
    _loadDirectory();
  }

  /// 上溯到上级目录（可越过工作区根），原目录压入后退栈以便连续返回。
  void _goUp() {
    final parent = p.dirname(_currentDir);
    if (parent == _currentDir) return;
    setState(() {
      _back.add(_currentDir);
      _forward.clear();
      _currentDir = parent;
    });
    _loadDirectory();
  }

  void _viewFile(File file) async {
    try {
      final content = await file.readAsString();
      if (!mounted) return;
      unawaited(showImmersiveDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(p.basename(file.path),
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
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
                FloatingToast.show(context, '已复制到剪贴板');
              },
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        ),
      ));
    } catch (e) {
      FloatingToast.show(context, '无法以文本读取此文件: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final projectName = p.basename(widget.workspacePath);

    return Container(
      // 外壳由 showImmersiveSheet 的 ImmersiveSurface 提供毛玻璃,这里不再铺不透明底色。
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
              borderRadius: BorderRadius.circular(AppTokens.radiusPill),
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
                            fontSize: 16, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: _currentDir));
                          FloatingToast.show(context, '已复制路径: $_currentDir');
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                _currentLabel,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurfaceVariant),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.copy_rounded,
                                size: 10,
                                color: theme.colorScheme.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                  tooltip: '上级目录',
                  onPressed:
                      p.dirname(_currentDir) == _currentDir ? null : _goUp,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  tooltip: '后退',
                  onPressed: _back.isEmpty ? null : _goBack,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                  tooltip: '前进',
                  onPressed: _forward.isEmpty ? null : _goForward,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: '刷新当前目录',
                  onPressed: _loadDirectory,
                ),
                if (widget.onReselectWorkspace != null)
                  IconButton(
                    icon:
                        const Icon(Icons.drive_folder_upload_rounded, size: 20),
                    tooltip: '重新选择工作区',
                    onPressed: widget.onReselectWorkspace,
                  ),
              ],
            ),
          ),
          const Divider(height: 20),
          // 列表
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _error != null
                    ? Center(
                        child: EmptyStateView.compact(
                          icon: Icons.error_outline_rounded,
                          title: '目录读取失败',
                          actionLabel: AppStrings.retry,
                          onAction: _loadDirectory,
                        ),
                      )
                    : _entities.isEmpty
                        ? const Center(
                            child: EmptyStateView.compact(
                              icon: Icons.folder_open_rounded,
                              title: '此目录为空',
                            ),
                          )
                        : ListView.builder(
                            itemCount: _entities.length,
                            itemBuilder: (context, index) {
                              final entity = _entities[index];
                              final isDir = entity is Directory;
                              final name = p.basename(entity.path);

                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  isDir
                                      ? Icons.folder_rounded
                                      : _getFileIcon(entity.path),
                                  size: 20,
                                  color: isDir
                                      ? AppPalette.warning
                                      : theme.colorScheme.primary,
                                ),
                                title: Text(
                                  isDir ? '$name/' : name,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isDir
                                        ? FontWeight.w500
                                        : FontWeight.w400,
                                  ),
                                ),
                                trailing: isDir
                                    ? const Icon(Icons.chevron_right, size: 18)
                                    : null,
                                onTap: isDir
                                    ? () => _openDir(entity.path)
                                    : () => _viewFile(entity as File),
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
      case '.go':
        return Icons.terminal;
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
