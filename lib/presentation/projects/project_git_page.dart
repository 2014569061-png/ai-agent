import 'package:flutter/material.dart';

import '../../application/git_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/async_state_view.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_list_tile.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/section_card.dart';

class ProjectGitPage extends StatefulWidget {
  const ProjectGitPage({super.key, required this.workspacePath});

  final String workspacePath;

  @override
  State<ProjectGitPage> createState() => _ProjectGitPageState();
}

class _ProjectGitPageState extends State<ProjectGitPage> {
  late final GitService _git;
  List<GitStatusEntry> _entries = const [];
  final Set<String> _selected = {};
  bool _loading = true;
  String? _error;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _git = GitService(workspacePath: widget.workspacePath);
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await _git.status(widget.workspacePath);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _commit() async {
    if (_selected.isEmpty) {
      FloatingToast.show(context, '请先选择要提交的文件', tone: ToastTone.warning);
      return;
    }
    if (_message.trim().isEmpty) {
      FloatingToast.show(context, '请填写提交说明', tone: ToastTone.warning);
      return;
    }
    try {
      await _git.stage(widget.workspacePath, _selected.toList());
      await _git.commit(widget.workspacePath, _message.trim());
      _selected.clear();
      _message = '';
      await _reload();
      if (mounted) {
        FloatingToast.show(context, '已提交所选文件', tone: ToastTone.success);
      }
    } catch (error) {
      if (mounted) {
        FloatingToast.show(context, '提交失败：$error', tone: ToastTone.danger);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const NexusPageHeader(
        title: 'Git',
        subtitle: '查看状态、按文件暂存并提交',
      ),
      body: AsyncStateView(
        loading: _loading,
        error: _error,
        onRetry: _reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    SectionCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TextField(
                            decoration: const InputDecoration(
                              labelText: '提交说明',
                              hintText: '只提交你勾选的文件',
                            ),
                            onChanged: (value) => _message = value,
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _commit,
                            child: const Text('暂存并提交所选文件'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppTokens.sp4),
                    if (_entries.isEmpty)
                      const EmptyStateView(
                        icon: Icons.check_circle_outline,
                        title: '工作区干净',
                        message: '没有可提交的改动。',
                      )
                    else
                      SectionCard(
                        child: Column(
                          children: [
                            for (final entry in _entries)
                              NexusListTile(
                                icon: _selected.contains(entry.path)
                                    ? Icons.check_box
                                    : Icons.check_box_outline_blank,
                                title: entry.path,
                                subtitle:
                                    'index=${entry.indexStatus} worktree=${entry.workTreeStatus}',
                                onTap: () {
                                  setState(() {
                                    if (_selected.contains(entry.path)) {
                                      _selected.remove(entry.path);
                                    } else {
                                      _selected.add(entry.path);
                                    }
                                  });
                                },
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
