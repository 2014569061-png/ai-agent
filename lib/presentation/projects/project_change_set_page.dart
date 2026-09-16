import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/change_review.dart';
import '../../application/change_set_service.dart';
import '../../application/providers.dart';
import '../../application/task_service.dart';
import '../theme/app_palette.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_list_tile.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/section_card.dart';

class ProjectChangeSetPage extends ConsumerStatefulWidget {
  const ProjectChangeSetPage({
    super.key,
    required this.projectId,
    required this.workspacePath,
  });

  final String projectId;
  final String workspacePath;

  @override
  ConsumerState<ProjectChangeSetPage> createState() =>
      _ProjectChangeSetPageState();
}

class _ProjectChangeSetPageState extends ConsumerState<ProjectChangeSetPage> {
  ChangeSet? _set;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await ref.read(databaseProvider.future);
      final tasks = await db.tasksForProject(widget.projectId, limit: 1);
      if (tasks.isEmpty) {
        setState(() {
          _loading = false;
          _error = '还没有可回退的任务';
        });
        return;
      }
      final info = TaskService().describe(tasks.first);
      final review = info.changeReview ??
          const ChangeReview(
            files: [],
            mark: ChangeVerificationMark.unverified,
          );
      final set = await const ChangeSetService().capture(
        projectId: widget.projectId,
        taskId: tasks.first.id,
        workspacePath: widget.workspacePath,
        review: review,
      );
      if (!mounted) return;
      setState(() {
        _set = set;
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

  Future<void> _rollback() async {
    final set = _set;
    if (set == null) return;
    final conflicts = await const ChangeSetService().rollback(
      workspacePath: widget.workspacePath,
      changeSet: set,
      currentHashes: {
        for (final file in set.files) file.relativePath: file.afterHash,
      },
    );
    if (!mounted) return;
    if (conflicts.isEmpty) {
      FloatingToast.show(context, '已按任务变更集回退', tone: ToastTone.success);
    } else {
      FloatingToast.show(
        context,
        '部分文件无法静默覆盖：${conflicts.map((item) => item.path).join('、')}',
        tone: ToastTone.warning,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final set = _set;
    return Scaffold(
      backgroundColor: isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas,
      appBar: const NexusPageHeader(
        title: '任务变更集',
        subtitle: '回退前检查当前版本，人工修改不会被覆盖',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyStateView(
                  icon: Icons.history_outlined,
                  title: '没有可回退内容',
                  message: _error,
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    SectionCard(
                      child: Column(
                        children: [
                          for (final file in set!.files)
                            NexusListTile(
                              icon: Icons.difference_outlined,
                              title: file.relativePath,
                              subtitle: file.reversible
                                  ? file.operation
                                  : '${file.operation} · 不可自动回退',
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _rollback,
                      child: const Text('回退本任务改动'),
                    ),
                  ],
                ),
    );
  }
}
