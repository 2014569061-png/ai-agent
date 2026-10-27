import 'package:flutter/material.dart';
import '../widgets/nexus_page_layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/change_review.dart';
import '../../application/change_set_service.dart';
import '../../application/providers.dart';
import '../../application/task_service.dart';
import '../widgets/async_state_view.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_list_tile.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/section_card.dart';
import '../../application/local_error_copy.dart';

class ProjectChangeSetPage extends ConsumerStatefulWidget {
  const ProjectChangeSetPage({
    super.key,
    required this.projectId,
    required this.workspacePath,
    this.taskId,
    this.taskLabel,
  });

  final String projectId;
  final String workspacePath;
  final String? taskId;
  final String? taskLabel;

  @override
  ConsumerState<ProjectChangeSetPage> createState() =>
      _ProjectChangeSetPageState();
}

class _ProjectChangeSetPageState extends ConsumerState<ProjectChangeSetPage> {
  List<DevelopmentTaskInfo> _tasks = const <DevelopmentTaskInfo>[];
  DevelopmentTaskInfo? _task;
  ChangeSet? _set;
  bool _loading = true;
  String? _error;
  String? _emptyNotice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _task = null;
      _set = null;
      _error = null;
      _emptyNotice = null;
      _loading = true;
    });
    try {
      final db = await ref.read(databaseProvider.future);
      final requestedTaskId = widget.taskId;
      final tasks = await TaskService().changeSetTasks(db,
          projectId: widget.projectId, taskId: requestedTaskId);
      if (!mounted) return;
      if (tasks.isEmpty) {
        setState(() {
          _loading = false;
          _tasks = const <DevelopmentTaskInfo>[];
          _emptyNotice =
              requestedTaskId == null ? '还没有可回退的任务' : '未找到要回退的任务，或任务不属于当前项目';
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _loading = false;
      });
      if (requestedTaskId != null || tasks.length == 1) {
        await _selectTask(tasks.first);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = LocalErrorCopy.of(error).headline();
        _loading = false;
      });
    }
  }

  Future<void> _selectTask(DevelopmentTaskInfo task) async {
    setState(() {
      _task = task;
      _set = null;
      _error = null;
      _emptyNotice = null;
      _loading = true;
    });
    try {
      final review = task.changeReview ??
          const ChangeReview(
            files: [],
            mark: ChangeVerificationMark.unverified,
          );
      // Reuse the persisted set unless the task has changed files since;
      // capturing again after manual edits would treat them as task output.
      final set = await const ChangeSetService().loadOrCapture(
        projectId: widget.projectId,
        taskId: task.id,
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
        _error = LocalErrorCopy.of(error).headline();
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
    );
    if (!mounted) return;
    if (conflicts.isEmpty) {
      FloatingToast.show(context, '已按任务变更集回退', tone: ToastTone.success);
    } else {
      FloatingToast.show(
        context,
        '部分文件未回退：${conflicts.map((item) => '${item.path}（${item.reason}）').join('、')}',
        tone: ToastTone.warning,
      );
    }
  }

  Widget _taskSelector() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        SectionCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '按任务选择要回退的变更集',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(
                '回退前请确认任务范围；包含删除或移动的文件只报告，不自动恢复。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(
            children: [
              for (final task in _tasks)
                NexusListTile(
                  key: ValueKey('rollback-task-${task.id}'),
                  icon: Icons.task_alt_outlined,
                  title: task.title,
                  subtitle:
                      '${TaskService.taskTypeLabel(task.type)} · ${task.status}',
                  onTap: () => _selectTask(task),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final set = _set;
    final selectedTitle = _task == null ? widget.taskLabel : _task!.title;
    final showSelector =
        !_loading && _error == null && _emptyNotice == null && _task == null;
    return Scaffold(
      appBar: NexusPageHeader(
        title: '任务变更集',
        subtitle: selectedTitle == null
            ? '选择要回退的具体任务，人工修改不会被覆盖'
            : '当前任务：$selectedTitle · 人工修改不会被覆盖',
      ),
      body: NexusPageLayout(
          child: showSelector
              ? _taskSelector()
              : AsyncStateView(
                  loading: _loading,
                  error: _error,
                  isEmpty: set == null || set.files.isEmpty,
                  emptyIcon: Icons.history_outlined,
                  emptyTitle: _emptyNotice ?? '没有可回退内容',
                  emptySubtitle: _emptyNotice == null ? _error : null,
                  onRetry: _load,
                  child: set == null
                      ? const SizedBox.shrink()
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                          children: [
                            SectionCard(
                              child: Column(
                                children: [
                                  for (final file in set.files)
                                    NexusListTile(
                                      icon: Icons.difference_outlined,
                                      title: file.relativePath,
                                      subtitle: file.reversible
                                          ? file.operation
                                          : '${file.operation} · ${file.note ?? '不可自动回退'}',
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
                )),
    );
  }
}
