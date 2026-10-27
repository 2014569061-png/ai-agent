import 'dart:async';
import '../theme/app_tokens.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../application/change_review.dart';
import '../../application/change_set_service.dart';
import '../../application/chat_controller.dart';
import '../../application/desktop_workbench_service.dart';
import '../../application/task_service.dart';
import '../theme/app_palette.dart';
import 'desktop_checkpoint_timeline.dart';
import 'desktop_task_result_dialog.dart';
import '../theme/desktop_theme.dart';
import 'desktop_preview_panel.dart';
import 'desktop_review_panel.dart';

String desktopTaskStatus(String? status) => switch (status) {
      'running' => '执行中',
      'paused' => '已暂停',
      'completed' || 'done' || 'succeeded' => '已完成',
      'failed' => '失败',
      'cancelled' || 'canceled' => '已停止',
      _ => '会话',
    };

Future<void> openDesktopEditor(BuildContext context, WidgetRef ref, String root,
    {String? path, bool choose = false}) async {
  final files = ref.read(desktopWorkspaceFilesProvider);
  try {
    if (choose || await files.editorPath() == null) {
      final result = await FilePicker.pickFiles(
          dialogTitle: '选择外部编辑器程序', type: FileType.any);
      final executable = result.isEmpty ? null : result.single.path;
      if (executable == null) return;
      await files.configureEditor(executable);
    }
    await files.openEditor(root, path: path);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('打开编辑器失败：$error')));
    }
  }
}

class DesktopWorkbenchPanel extends StatelessWidget {
  const DesktopWorkbenchPanel(
      {super.key,
      required this.tab,
      required this.onTab,
      required this.onClose,
      required this.onProject,
      required this.onChat,
      required this.onReview,
      required this.onTerminal,
      this.onCite});
  final int tab;
  final ValueChanged<int> onTab;
  final VoidCallback onClose, onProject, onChat, onReview, onTerminal;
  final ValueChanged<String>? onCite;

  @override
  Widget build(BuildContext context) {
    final colors = DesktopTheme.maybeOf(context)!;
    return Material(
        color: colors.panel,
        shape: RoundedRectangleBorder(
            side: BorderSide(color: colors.border),
            borderRadius: BorderRadius.circular(DesktopTheme.panelRadius)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Container(
              height: 40,
              padding: const EdgeInsets.only(left: 12, right: 4),
              child: Row(children: [
                Icon(Icons.space_dashboard_outlined,
                    size: 15, color: colors.muted),
                const SizedBox(width: 6),
                Expanded(
                    child: Text('开发工作台',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: DesktopTheme.labelSize,
                            fontWeight: FontWeight.w600,
                            color: colors.text))),
                IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '收起侧面板',
                    onPressed: onClose,
                    icon: Icon(Icons.close_rounded,
                        size: 16, color: colors.muted)),
              ])),
          Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                      color: colors.hover,
                      borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                      border: Border.all(color: colors.border)),
                  child: Row(children: [
                    for (var i = 0; i < 4; i++)
                      Expanded(
                          child: TextButton(
                              key: ValueKey('desktop-side-tab-$i'),
                              onPressed: () => onTab(i),
                              style: TextButton.styleFrom(
                                  minimumSize: const Size(0, 26),
                                  padding: EdgeInsets.zero,
                                  foregroundColor:
                                      i == tab ? colors.accent : colors.muted,
                                  backgroundColor: i == tab
                                      ? colors.selected
                                      : Colors.transparent),
                              child: Text(const ['改动', '预览', '文件', '执行'][i],
                                  style: TextStyle(
                                      fontSize: DesktopTheme.smallSize,
                                      fontWeight: i == tab
                                          ? FontWeight.w600
                                          : FontWeight.w400),
                                  maxLines: 1))),
                  ]))),
          const Divider(),
          Expanded(
              child: IndexedStack(index: tab, children: [
            DesktopReviewPanel(
                onProject: onProject, onCite: onCite, onReview: onReview),
            DesktopPreviewPanel(onProject: onProject, onTerminal: onTerminal),
            DesktopFilesPanel(onProject: onProject, onCite: onCite),
            DesktopExecutionPanel(onChat: onChat),
          ])),
        ]));
  }
}

class DesktopPanelEmpty extends StatelessWidget {
  const DesktopPanelEmpty(
      {super.key, required this.message, this.action, this.label});
  final String message;
  final VoidCallback? action;
  final String? label;
  @override
  Widget build(BuildContext context) => Center(
      child: SingleChildScrollView(
          child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall),
                if (action != null) ...[
                  const SizedBox(height: 12),
                  TextButton(onPressed: action, child: Text(label ?? '选择项目'))
                ],
              ]))));
}

class DesktopFilesPanel extends ConsumerStatefulWidget {
  const DesktopFilesPanel({super.key, required this.onProject, this.onCite});
  final VoidCallback onProject;
  final ValueChanged<String>? onCite;
  @override
  ConsumerState<DesktopFilesPanel> createState() => _DesktopFilesPanelState();
}

class _DesktopFilesPanelState extends ConsumerState<DesktopFilesPanel> {
  String? _root, _selected;
  String _directory = '.';
  Future<List<DesktopFileEntry>>? _entries;
  Future<String>? _content;

  void _load(String root, String directory) {
    _root = root;
    _directory = directory;
    _selected = null;
    _content = null;
    _entries = ref.read(desktopWorkspaceFilesProvider).list(root, directory);
  }

  @override
  Widget build(BuildContext context) {
    final root =
        ref.watch(chatControllerProvider.select((s) => s.currentWorkspacePath));
    if (root == null) {
      return DesktopPanelEmpty(message: '选择项目后浏览文件', action: widget.onProject);
    }
    if (_root != root) _load(root, '.');
    final colors = DesktopTheme.maybeOf(context)!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            IconButton(
                tooltip: _selected != null ? '返回文件列表' : '上一级目录',
                onPressed: _selected != null || _directory != '.'
                    ? () => setState(() {
                          if (_selected != null) {
                            _selected = null;
                            _content = null;
                          } else {
                            _load(root, p.dirname(_directory));
                          }
                        })
                    : null,
                icon: const Icon(Icons.arrow_back, size: 16)),
            Expanded(
                child: Text(
                    _selected ??
                        (_directory == '.' ? p.basename(root) : _directory),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall)),
            IconButton(
                tooltip: '刷新文件',
                onPressed: () => setState(() {
                      if (_selected != null) {
                        _content = ref
                            .read(desktopWorkspaceFilesProvider)
                            .preview(root, _selected!);
                      } else {
                        _load(root, _directory);
                      }
                    }),
                icon: const Icon(Icons.refresh, size: 16)),
            PopupMenuButton<String>(
                tooltip: '编辑器选项',
                onSelected: (value) => unawaited(openDesktopEditor(
                    context, ref, root,
                    path: _selected, choose: value == 'choose')),
                itemBuilder: (_) => const [
                      PopupMenuItem(value: 'open', child: Text('在外部编辑器打开')),
                      PopupMenuItem(value: 'choose', child: Text('选择编辑器程序'))
                    ]),
          ])),
      if (_selected != null)
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(spacing: 4, children: [
              TextButton.icon(
                  onPressed: () =>
                      openDesktopEditor(context, ref, root, path: _selected),
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: const Text('编辑')),
              if (widget.onCite != null)
                TextButton.icon(
                    onPressed: () =>
                        widget.onCite!(_selected!.replaceAll('\\', '/')),
                    icon: const Icon(Icons.alternate_email, size: 14),
                    label: const Text('加入上下文')),
            ])),
      const Divider(),
      Expanded(
          child: _selected == null
              ? FutureBuilder<List<DesktopFileEntry>>(
                  future: _entries,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return DesktopPanelEmpty(
                          message: '读取目录失败：${snapshot.error}');
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final entries = snapshot.data!;
                    if (entries.isEmpty) {
                      return const DesktopPanelEmpty(message: '目录为空');
                    }
                    return ListView.builder(
                        itemCount:
                            entries.length + (entries.length >= 1000 ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == entries.length) {
                            return const Padding(
                                padding: EdgeInsets.all(12),
                                child: Text('仅显示前 1000 项，可在外部编辑器浏览全部'));
                          }
                          final entry = entries[index];
                          return ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              key: ValueKey(
                                  'desktop-file-${entry.relativePath}'),
                              leading: Icon(
                                  entry.directory
                                      ? Icons.folder_outlined
                                      : Icons.insert_drive_file_outlined,
                                  size: 16),
                              title: Text(entry.name,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              onTap: () => setState(() {
                                    if (entry.directory) {
                                      _load(root, entry.relativePath);
                                    } else {
                                      _selected = entry.relativePath;
                                      _content = ref
                                          .read(desktopWorkspaceFilesProvider)
                                          .preview(root, entry.relativePath);
                                    }
                                  }));
                        });
                  })
              : FutureBuilder<String>(
                  future: _content,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return DesktopPanelEmpty(
                          message: '${snapshot.error}',
                          action: () => unawaited(openDesktopEditor(
                              context, ref, root,
                              path: _selected)),
                          label: '打开编辑器');
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                            snapshot.data!.isEmpty ? '空文件' : snapshot.data!,
                            style: DesktopTheme.monospaceStyle(context,
                                size: DesktopTheme.smallSize,
                                color: colors.text)));
                  })),
    ]);
  }
}

class DesktopChangesPanel extends ConsumerStatefulWidget {
  const DesktopChangesPanel({super.key, required this.onProject});
  final VoidCallback onProject;
  @override
  ConsumerState<DesktopChangesPanel> createState() =>
      _DesktopChangesPanelState();
}

class _DesktopChangesPanelState extends ConsumerState<DesktopChangesPanel> {
  /// 复查范围：0=任务 diff，1=会话 checkpoint 时间线（Review 2.0）。
  static const int _modeTasks = 0, _modeCheckpoints = 1;

  int _mode = _modeTasks;
  String? _taskId, _filePath;
  String? _historyConversation;
  int _historyLimit = 30;
  bool _restoring = false;

  Future<void> _restore(DevelopmentTaskInfo info, String root,
      {String? filePath}) async {
    final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('恢复修改前的文件'),
                content: Text(
                    '${filePath ?? '该任务的全部改动'}\n\n将检查当前内容是否仍与任务输出一致。后续人工修改会跳过并报告。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('恢复修改前版本'))
                ]));
    if (approved != true || !mounted) return;
    setState(() => _restoring = true);
    try {
      final files = ref.read(desktopWorkspaceFilesProvider);
      final current = ref.read(chatControllerProvider);
      if (current.running ||
          current.currentProjectId != info.projectId ||
          current.currentWorkspacePath != root) {
        throw StateError('当前项目或运行状态已变化，请重新检查任务');
      }
      if (info.workspacePath == null ||
          await files.resolve(root, '.') !=
              await files.resolve(info.workspacePath!, '.')) {
        throw StateError('任务记录的工作区与当前项目不同');
      }
      final service = const ChangeSetService();
      final captured = await service.loadOrCapture(
          projectId: info.projectId!,
          taskId: info.id,
          workspacePath: root,
          review: info.changeReview!);
      final subset = filePath == null
          ? captured
          : ChangeSet(
              id: captured.id,
              taskId: captured.taskId,
              projectId: captured.projectId,
              createdAt: captured.createdAt,
              version: captured.version,
              files: captured.files
                  .where((file) =>
                      file.relativePath.replaceAll('\\', '/') ==
                      (p.isAbsolute(filePath)
                              ? p.relative(filePath, from: root)
                              : filePath)
                          .replaceAll('\\', '/'))
                  .toList());
      if (subset.files.isEmpty) throw StateError('没有对应的可恢复文件');
      final conflicts =
          await service.rollback(workspacePath: root, changeSet: subset);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(conflicts.isEmpty
              ? '已恢复修改前版本'
              : '未恢复：${conflicts.map((c) => '${c.path}（${c.reason}）').join('、')}')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('恢复失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(chatControllerProvider.select((s) => (
          s.conversationId,
          s.currentWorkspacePath,
          s.currentProjectId,
          s.running
        )));
    if (_historyConversation != identity.$1) {
      _historyConversation = identity.$1;
      _historyLimit = 30;
      _taskId = null;
      _filePath = null;
    }
    if (_mode == _modeCheckpoints) {
      // 会话级 checkpoint 时间线：与任务 diff 复查共用一个面板入口。
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _scopeRow(),
        const Divider(height: 1),
        const Expanded(child: DesktopCheckpointTimeline()),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _scopeRow(),
      const Divider(height: 1),
      Expanded(child: _tasksPane(identity)),
    ]);
  }

  Widget _scopeRow() {
    return Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Wrap(spacing: 4, runSpacing: 4, children: [
          _scopeChip('任务前', _modeTasks),
          _scopeChip('检查点', _modeCheckpoints),
        ]));
  }

  Widget _scopeChip(String label, int mode) {
    final colors = DesktopTheme.maybeOf(context);
    final selected = _mode == mode;
    return TextButton(
        key: ValueKey('desktop-changes-scope-$mode'),
        onPressed: () => setState(() => _mode = mode),
        style: TextButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            minimumSize: const Size(0, 30),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            backgroundColor: selected ? colors?.selected : null),
        child: Text(label));
  }

  Widget _tasksPane((String?, String?, String?, bool) identity) {
    final history = ref.watch(_historyLimit == 30 || identity.$1 == null
        ? desktopTasksProvider(identity.$1)
        : desktopTaskPageProvider((identity.$1!, _historyLimit)));
    return history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => DesktopPanelEmpty(message: '读取任务改动失败：$error'),
        data: (tasks) {
          final infos = tasks
              .take(_historyLimit)
              .map(DevelopmentTaskInfo.fromTask)
              .toList();
          if (infos.isEmpty) {
            return DesktopPanelEmpty(
                message: identity.$2 == null ? '选择项目后开始编码任务' : '当前会话还没有任务改动',
                action: identity.$2 == null ? widget.onProject : null);
          }
          final info = infos.where((task) => task.id == _taskId).firstOrNull ??
              infos.first;
          final changes =
              info.changeReview?.files ?? const <FileChangeSummary>[];
          final file = changes.where((f) => f.path == _filePath).firstOrNull;
          final canRestore = !identity.$4 &&
              !_restoring &&
              info.status != 'running' &&
              identity.$2 != null &&
              info.projectId != null &&
              info.projectId == identity.$3 &&
              changes.isNotEmpty;
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButton<String>(
                              isExpanded: true,
                              value: info.id,
                              items: infos
                                  .map((task) => DropdownMenuItem(
                                      value: task.id,
                                      child: Text(task.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis)))
                                  .toList(),
                              onChanged: _restoring
                                  ? null
                                  : (value) => setState(() {
                                        _taskId = value;
                                        _filePath = null;
                                      })),
                          if (tasks.length > _historyLimit)
                            TextButton(
                              key: const ValueKey('desktop-load-older-tasks'),
                              onPressed: _restoring
                                  ? null
                                  : () => setState(() => _historyLimit += 30),
                              child: const Text('加载更早任务'),
                            ),
                          Text(
                              '${desktopTaskStatus(info.status)} · ${info.changeReview?.mark.label ?? '未验证'}',
                              style: Theme.of(context).textTheme.bodySmall),
                          if (info.summary?.isNotEmpty == true)
                            Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(info.summary!,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis)),
                          Text('任务记录的差异 · ${changes.length} 个文件',
                              style: Theme.of(context).textTheme.bodySmall),
                        ])),
                if (file != null)
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Wrap(spacing: 4, children: [
                        TextButton.icon(
                            onPressed: () => setState(() => _filePath = null),
                            icon: const Icon(Icons.arrow_back, size: 14),
                            label: const Text('文件列表')),
                        if (identity.$2 != null)
                          TextButton(
                              onPressed: () => openDesktopEditor(
                                  context, ref, identity.$2!,
                                  path: file.path),
                              child: const Text('编辑')),
                        TextButton(
                            onPressed: canRestore
                                ? () => _restore(info, identity.$2!,
                                    filePath: file.path)
                                : null,
                            child: const Text('恢复此文件')),
                      ])),
                const Divider(),
                Expanded(
                    child: changes.isEmpty
                        ? const DesktopPanelEmpty(message: '这项任务未记录文件修改')
                        : file != null
                            ? _DesktopDiff(file: file)
                            : ListView(children: [
                                for (final change in changes)
                                  ListTile(
                                      dense: true,
                                      key: ValueKey(
                                          'desktop-change-${change.path}'),
                                      leading: const Icon(
                                          Icons.difference_outlined,
                                          size: 16),
                                      title: Text(change.path,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: DesktopTheme.monospaceStyle(
                                              context,
                                              size: DesktopTheme.smallSize)),
                                      subtitle: Text(
                                          '${change.operation}  +${change.linesAdded} / −${change.linesRemoved}'),
                                      onTap: () => setState(
                                          () => _filePath = change.path)),
                              ])),
                if (changes.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.all(12),
                      child: OutlinedButton(
                          onPressed: canRestore
                              ? () => _restore(info, identity.$2!)
                              : null,
                          child: Text(_restoring ? '正在恢复…' : '恢复本任务修改前版本'))),
              ]);
        });
  }
}

class _DesktopDiff extends StatelessWidget {
  const _DesktopDiff({required this.file});
  final FileChangeSummary file;
  @override
  Widget build(BuildContext context) {
    if (file.diff.isEmpty) {
      return const DesktopPanelEmpty(message: '没有保存文本差异，可在外部编辑器查看当前文件');
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text =
        file.diff.length > 65536 ? file.diff.substring(0, 65536) : file.diff;
    return SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (file.truncated || text.length < file.diff.length)
            const Text('差异已截断，当前展示部分记录'),
          SelectableText.rich(
              TextSpan(
                  children: text
                      .split('\n')
                      .map((line) => TextSpan(
                          text: '$line\n',
                          style: TextStyle(
                              color: line.startsWith('+')
                                  ? (dark
                                      ? AppPalette.darkSuccess
                                      : AppPalette.lightSuccess)
                                  : line.startsWith('-')
                                      ? Theme.of(context).colorScheme.error
                                      : null)))
                      .toList()),
              style: DesktopTheme.monospaceStyle(context,
                  size: DesktopTheme.smallSize)),
        ]));
  }
}

class DesktopExecutionPanel extends ConsumerWidget {
  const DesktopExecutionPanel(
      {super.key, required this.onChat, this.errorsOnly = false});
  final VoidCallback onChat;
  final bool errorsOnly;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final execution = ref.watch(chatControllerProvider
        .select((s) => (s.toolActivities, s.runProgress, s.running, s.paused)));
    final activities = errorsOnly
        ? execution.$1.where((a) => a.ok == false).toList()
        : execution.$1;
    if (errorsOnly && activities.isEmpty) {
      return const DesktopPanelEmpty(message: '没有失败的工具调用');
    }
    if (activities.isEmpty && execution.$2 == null) {
      return const DesktopPanelEmpty(message: '执行工具后，在这里查看步骤和输出');
    }
    return ListView(padding: const EdgeInsets.all(12), children: [
      Text(
          execution.$2?.label ??
              (execution.$4
                  ? '已暂停'
                  : execution.$3
                      ? '执行中'
                      : '执行记录'),
          style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      for (final activity in activities)
        ExpansionTile(
            tilePadding: EdgeInsets.zero,
            key: ValueKey('desktop-execution-${activity.call.id}'),
            initiallyExpanded:
                activity.ok == false || activity.status == '等待确认',
            title: Text(activity.call.name,
                style: DesktopTheme.monospaceStyle(context,
                    size: DesktopTheme.smallSize)),
            subtitle: Text('${activity.status} · ${activity.executionMs} ms'),
            children: [
              if (activity.status == '等待确认')
                TextButton(onPressed: onChat, child: const Text('在会话中处理请求')),
              SelectableText(activity.result ?? '暂无输出',
                  style: DesktopTheme.monospaceStyle(context,
                      size: DesktopTheme.smallSize)),
              const SizedBox(height: 8),
            ]),
    ]);
  }
}

class DesktopCitationStrip extends ConsumerWidget {
  const DesktopCitationStrip({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final citations =
        ref.watch(chatControllerProvider.select((s) => s.pendingCitations));
    if (citations.isEmpty) return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Wrap(spacing: 6, runSpacing: 4, children: [
          for (final citation in citations)
            InputChip(
                avatar: const Icon(Icons.alternate_email, size: 14),
                label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Text(citation.displayLabel,
                        overflow: TextOverflow.ellipsis)),
                onDeleted: () => ref
                    .read(chatControllerProvider.notifier)
                    .removeFileCitation(citation)),
        ]));
  }
}

class DesktopTaskResultStrip extends ConsumerWidget {
  const DesktopTaskResultStrip({super.key, required this.onReview});
  final VoidCallback onReview;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(chatControllerProvider
        .select((s) => (s.conversationId, s.running, s.currentWorkspacePath)));
    final tasks = ref.watch(desktopTasksProvider(current.$1)).asData?.value;
    if (current.$2 || tasks == null || tasks.isEmpty) {
      return const SizedBox.shrink();
    }
    final info = DevelopmentTaskInfo.fromTask(tasks.first);
    if (info.status == 'running') return const SizedBox.shrink();
    final review = info.changeReview;
    return Container(
        key: const ValueKey('desktop-task-result'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
            border:
                Border(top: BorderSide(color: Theme.of(context).dividerColor))),
        child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                  '最近任务：${desktopTaskStatus(info.status)} · ${review?.mark.label ?? '未验证'}',
                  style: Theme.of(context).textTheme.bodySmall),
              TextButton(
                  onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => DesktopTaskResultDialog(
                          task: info, onReview: onReview)),
                  child: const Text('结果与验证')),
              TextButton(
                  onPressed: onReview,
                  child: Text('查看改动 (${review?.files.length ?? 0})')),
              if (current.$3 != null)
                TextButton(
                    onPressed: () =>
                        openDesktopEditor(context, ref, current.$3!),
                    child: const Text('打开编辑器')),
            ]));
  }
}

/// A focusable divider: drag it, or use the arrow keys in its axis.
class DesktopResizeHandle extends StatelessWidget {
  const DesktopResizeHandle(
      {super.key,
      required this.vertical,
      required this.onDelta,
      required this.onEnd});
  final bool vertical;
  final ValueChanged<double> onDelta;
  final VoidCallback onEnd;
  void _move(double delta) {
    onDelta(delta);
    onEnd();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
          bindings: {
            SingleActivator(vertical
                ? LogicalKeyboardKey.arrowLeft
                : LogicalKeyboardKey.arrowUp): () => _move(-12),
            SingleActivator(vertical
                ? LogicalKeyboardKey.arrowRight
                : LogicalKeyboardKey.arrowDown): () => _move(12),
          },
          child: Semantics(
              label: vertical ? '调整侧面板宽度' : '调整命令面板高度',
              child: FocusableActionDetector(
                  mouseCursor: vertical
                      ? SystemMouseCursors.resizeLeftRight
                      : SystemMouseCursors.resizeUpDown,
                  child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: vertical
                          ? (details) => onDelta(details.delta.dx)
                          : null,
                      onHorizontalDragEnd: vertical ? (_) => onEnd() : null,
                      onVerticalDragUpdate: !vertical
                          ? (details) => onDelta(details.delta.dy)
                          : null,
                      onVerticalDragEnd: !vertical ? (_) => onEnd() : null,
                      child: SizedBox(
                          width: vertical ? 6 : null,
                          height: vertical ? null : 6,
                          child: Center(
                              child: Container(
                                  width: vertical ? 1 : null,
                                  height: vertical ? null : 1,
                                  color: Theme.of(context).dividerColor)))))));
}
