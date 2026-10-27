import 'dart:async';
import '../theme/app_tokens.dart';
import '../../application/desktop_diff.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../application/chat_controller.dart';
import '../../application/desktop_git_service.dart';
import '../theme/app_palette.dart';
import '../theme/desktop_theme.dart';
import '../markdown/code_block.dart' show SimpleSyntaxHighlighter;
import 'desktop_workbench_panels.dart';

class DesktopReviewPanel extends ConsumerStatefulWidget {
  const DesktopReviewPanel(
      {super.key,
      required this.onProject,
      this.onCite,
      required this.onReview});
  final VoidCallback onProject, onReview;
  final ValueChanged<String>? onCite;

  @override
  ConsumerState<DesktopReviewPanel> createState() => _DesktopReviewPanelState();
}

class _DesktopReviewPanelState extends ConsumerState<DesktopReviewPanel> {
  String? _path;
  String? _root;
  bool _staged = false, _taskHistory = false, _busy = false;
  DesktopGitSnapshot? _snapshot;
  Future<String>? _diff;

  Future<void> _stage(DesktopGitSnapshot snapshot, DesktopGitFile file) async {
    setState(() => _busy = true);
    try {
      final git = ref.read(desktopGitServiceProvider);
      if (_staged) {
        await git.unstage(snapshot, file);
      } else {
        await git.stage(snapshot, file);
      }
      if (!mounted) return;
      ref.invalidate(desktopGitSnapshotProvider(_root!));
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_staged ? '已取消暂存，工作区文件保留' : '已暂存所选文件')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Git 操作失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyHunk(DesktopGitSnapshot snapshot, String patch,
      {bool staged = false, bool reverse = false}) async {
    if (!staged) {
      final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('恢复此差异块？'),
                  content: const Text('将撤销此块在工作区中的改动。其余差异块保留。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('恢复此块'))
                  ]));
      if (accepted != true) return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(desktopGitServiceProvider)
          .applyPatch(snapshot.root, patch, staged: staged, reverse: reverse);
      if (!mounted) return;
      ref.invalidate(desktopGitSnapshotProvider(_root!));
      setState(() {
        _diff = null;
        _snapshot = null;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('差异块操作失败，文件可能已变化：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace =
        ref.watch(chatControllerProvider.select((s) => s.currentWorkspacePath));
    if (_root != workspace) {
      _root = workspace;
      _path = null;
      _diff = null;
      _snapshot = null;
    }
    if (workspace == null) {
      return DesktopPanelEmpty(
          message: '选择项目后查看真实文件改动', action: widget.onProject);
    }
    final colors = DesktopTheme.maybeOf(context)!;
    final state = ref.watch(desktopGitSnapshotProvider(workspace));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(children: [
            Expanded(
                child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      _scope(
                          '工作区',
                          !_taskHistory && !_staged,
                          () => setState(() {
                                _staged = false;
                                _taskHistory = false;
                                _diff = null;
                              })),
                      _scope(
                          '已暂存',
                          !_taskHistory && _staged,
                          () => setState(() {
                                _staged = true;
                                _taskHistory = false;
                                _diff = null;
                              })),
                      _scope('任务记录', _taskHistory,
                          () => setState(() => _taskHistory = true)),
                    ]))),
            IconButton(
                tooltip: '刷新 Git 改动',
                constraints:
                    const BoxConstraints.tightFor(width: 32, height: 32),
                padding: const EdgeInsets.all(6),
                icon: const Icon(Icons.refresh, size: 16),
                onPressed: () =>
                    ref.invalidate(desktopGitSnapshotProvider(workspace))),
          ])),
      const Divider(),
      Expanded(
          child: _taskHistory
              ? DesktopChangesPanel(onProject: widget.onProject)
              : state.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => DesktopPanelEmpty(
                      message: '无法读取 Git 改动：$error\n可切换到任务记录查看 Agent 保存的差异。',
                      action: () =>
                          ref.invalidate(desktopGitSnapshotProvider(workspace)),
                      label: '重试'),
                  data: (snapshot) {
                    final entries = snapshot.files
                        .where((file) => _staged ? file.staged : file.unstaged)
                        .toList();
                    final selected =
                        entries.where((f) => f.path == _path).firstOrNull ??
                            entries.firstOrNull;
                    if (selected != null &&
                        (_snapshot != snapshot ||
                            _path != selected.path ||
                            _diff == null)) {
                      _snapshot = snapshot;
                      _path = selected.path;
                      _diff = ref
                          .read(desktopGitServiceProvider)
                          .diff(snapshot, selected, staged: _staged);
                    }
                    if (selected == null) {
                      return DesktopPanelEmpty(
                          message: _staged ? '暂无暂存文件' : '工作区干净，没有未暂存改动');
                    }
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 300),
                                        child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                                color: colors.sidebar,
                                                borderRadius:
                                                    BorderRadius.circular(AppTokens.radiusControl),
                                                border: Border.all(
                                                    color: colors.border)),
                                            child: DropdownButtonHideUnderline(
                                                child: DropdownButton<String>(
                                                    isDense: true,
                                                    isExpanded: true,
                                                    value: selected.path,
                                                    items: entries
                                                        .map((file) => DropdownMenuItem(
                                                            value: file.path,
                                                            child: Text(
                                                                file.path,
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: DesktopTheme.monospaceStyle(
                                                                    context,
                                                                    size: DesktopTheme
                                                                        .smallSize))))
                                                        .toList(),
                                                    onChanged: (path) =>
                                                        setState(() {
                                                          _path = path;
                                                          _diff = null;
                                                        }))))),
                                    OutlinedButton(
                                        onPressed: widget.onReview,
                                        child: const Text('检查改动')),
                                    FilledButton(
                                        onPressed: _busy || selected.conflicted
                                            ? null
                                            : () => unawaited(
                                                _stage(snapshot, selected)),
                                        child: Text(_busy
                                            ? '处理中…'
                                            : _staged
                                                ? '取消暂存'
                                                : '暂存改动')),
                                  ])),
                          if (selected.conflicted)
                            Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text('此文件存在冲突，请解决冲突后暂存。',
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error))),
                          Container(
                              color: colors.sidebar,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              child: Row(children: [
                                Expanded(
                                    child: Text(
                                        '${entries.length} 个文件 · ${snapshot.branch}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall)),
                                if (widget.onCite != null &&
                                    !selected.worktree.contains('D'))
                                  TextButton(
                                      style: TextButton.styleFrom(
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          minimumSize: const Size(0, 28),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8)),
                                      onPressed: () {
                                        // File citation paths are relative to the chosen workspace.
                                        widget.onCite!(p.relative(
                                            p.join(
                                                snapshot.root, selected.path),
                                            from: workspace));
                                      },
                                      child: const Text('加入上下文')),
                              ])),
                          const Divider(),
                          Expanded(
                              child: FutureBuilder<String>(
                                  future: _diff,
                                  builder: (context, diff) {
                                    if (diff.hasError) {
                                      return DesktopPanelEmpty(
                                          message: '读取差异失败：${diff.error}');
                                    }
                                    if (!diff.hasData) {
                                      return const Center(
                                          child: CircularProgressIndicator());
                                    }
                                    if (diff.data!.isEmpty) {
                                      return const DesktopPanelEmpty(
                                          message: '没有文本差异（可能是二进制文件或文件模式变更）');
                                    }
                                    return DesktopDiffView(
                                        text: diff.data!,
                                        onStageHunk: selected.untracked
                                            ? null
                                            : (patch) => _applyHunk(
                                                snapshot, patch,
                                                staged: true, reverse: _staged),
                                        onRevertHunk: _staged ||
                                                selected.untracked
                                            ? null
                                            : (patch) => _applyHunk(
                                                snapshot, patch, reverse: true),
                                        onOpenFile: () => openDesktopEditor(
                                            context, ref, snapshot.root,
                                            path: selected.path),
                                        staged: _staged,
                                        busy: _busy);
                                  })),
                        ]);
                  })),
    ]);
  }

  Widget _scope(String label, bool selected, VoidCallback onTap) => TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: const Size(0, 28),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          foregroundColor: selected
              ? DesktopTheme.maybeOf(context)!.text
              : DesktopTheme.maybeOf(context)!.muted,
          backgroundColor:
              selected ? DesktopTheme.maybeOf(context)!.selected : null),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400)));
}

class DesktopDiffView extends StatefulWidget {
  const DesktopDiffView(
      {super.key,
      required this.text,
      this.onStageHunk,
      this.onRevertHunk,
      this.onOpenFile,
      this.staged = false,
      this.busy = false});
  final String text;
  final Future<void> Function(String)? onStageHunk, onRevertHunk;
  final VoidCallback? onOpenFile;
  final bool staged, busy;
  @override
  State<DesktopDiffView> createState() => _DesktopDiffViewState();
}

class _DesktopDiffViewState extends State<DesktopDiffView> {
  late DesktopDiff _diff;
  final Set<int> _collapsed = {};
  @override
  void initState() {
    super.initState();
    _diff = DesktopDiff.parse(widget.text);
  }

  @override
  void didUpdateWidget(covariant DesktopDiffView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _diff = DesktopDiff.parse(widget.text);
      _collapsed.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = DesktopTheme.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final added = dark ? AppPalette.darkSuccess : AppPalette.lightSuccess;
    final removed = Theme.of(context).colorScheme.error;
    final rows = <Object>[..._diff.preamble];
    for (var i = 0; i < _diff.hunks.length; i++) {
      rows.add((i, _diff.hunks[i]));
      if (!_collapsed.contains(i)) rows.addAll(_diff.hunks[i].lines);
    }
    return Column(children: [
      if (widget.onOpenFile != null)
        Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
                onPressed: widget.onOpenFile,
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('打开文件'))),
      Expanded(
          child: SelectionArea(
              child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    if (row is String) {
                      return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 2),
                          child: Text(row,
                              style: DesktopTheme.monospaceStyle(context,
                                  size: 12, color: colors.muted)));
                    }
                    if (row is (int, DesktopDiffHunk)) {
                      return Container(
                          decoration: BoxDecoration(
                              color: colors.sidebar,
                              border: Border.symmetric(
                                  horizontal:
                                      BorderSide(color: colors.border))),
                          child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                TextButton.icon(
                                    onPressed: () => setState(() {
                                          if (!_collapsed.add(row.$1)) {
                                            _collapsed.remove(row.$1);
                                          }
                                        }),
                                    icon: Icon(
                                        _collapsed.contains(row.$1)
                                            ? Icons.chevron_right
                                            : Icons.expand_more,
                                        size: 14),
                                    label: Text(row.$2.header,
                                        style: DesktopTheme.monospaceStyle(
                                            context,
                                            size: 12))),
                                if (widget.onStageHunk != null)
                                  TextButton(
                                      onPressed: widget.busy
                                          ? null
                                          : () =>
                                              widget.onStageHunk!(row.$2.patch),
                                      child: Text(
                                          widget.staged ? '取消暂存此块' : '暂存此块')),
                                if (widget.onRevertHunk != null)
                                  TextButton(
                                      onPressed: widget.busy
                                          ? null
                                          : () => widget
                                              .onRevertHunk!(row.$2.patch),
                                      child: const Text('恢复此块')),
                              ]));
                    }
                    final line = row as DesktopDiffLine;
                    return Container(
                        color: line.text.startsWith('+')
                            ? added.withValues(alpha: .09)
                            : line.text.startsWith('-')
                                ? removed.withValues(alpha: .09)
                                : null,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                  width: 34,
                                  child: Text('${line.oldLine ?? ''}',
                                      textAlign: TextAlign.right,
                                      style: DesktopTheme.monospaceStyle(
                                          context,
                                          size: 11.5,
                                          color: colors.muted))),
                              const SizedBox(width: 6),
                              SizedBox(
                                  width: 34,
                                  child: Text('${line.newLine ?? ''}',
                                      textAlign: TextAlign.right,
                                      style: DesktopTheme.monospaceStyle(
                                          context,
                                          size: 11.5,
                                          color: colors.muted))),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text.rich(
                                      const SimpleSyntaxHighlighter()
                                          .format(line.text),
                                      style:
                                          DesktopTheme.monospaceStyle(context,
                                              size: 12,
                                              color: line.text.startsWith('+')
                                                  ? added
                                                  : line.text.startsWith('-')
                                                      ? removed
                                                      : colors.text))),
                            ]));
                  }))),
    ]);
  }
}
