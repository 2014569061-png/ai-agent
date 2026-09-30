import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/jobs/job_board_providers.dart';
import '../motion/nexus_page_route_factory.dart';
import '../tasks/task_details_page.dart';
import '../widgets/async_state_view.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_page_header.dart';
import '../theme/app_appearance_controller.dart';
import '../theme/app_palette.dart';
import '../widgets/glass_surface.dart';
import '../widgets/section_card.dart';

/// 任务与收件箱（阶段 7b）：后台任务和定时运行的统一视图。
///
/// 「收件箱」只列需要留意的条目（待审批、已暂停、失败、完成、定时运行结果），
/// 打开即标为已读；「全部任务」按时间列出最近的任务与定时运行。
class JobsInboxPage extends ConsumerStatefulWidget {
  const JobsInboxPage({super.key, this.onConversationSelected});

  final ValueChanged<Conversation>? onConversationSelected;

  @override
  ConsumerState<JobsInboxPage> createState() => _JobsInboxPageState();
}

class _JobsInboxPageState extends ConsumerState<JobsInboxPage> {
  bool _loading = true;
  Object? _error;
  List<InboxItem> _inbox = const [];
  List<JobSummary> _jobs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final board = await ref.read(jobBoardProvider.future);
      final inbox = await board.inbox();
      final jobs = await board.jobs();
      if (!mounted) return;
      setState(() {
        _inbox = inbox;
        _jobs = jobs;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _markAllSeen() async {
    if (_inbox.isEmpty) return;
    final board = await ref.read(jobBoardProvider.future);
    await board.markSeen(_inbox);
    ref.invalidate(inboxUnreadProvider);
    if (!mounted) return;
    setState(() => _inbox = const []);
    FloatingToast.show(context, '已全部标为已读');
  }

  Future<void> _openInboxItem(InboxItem item) async {
    final board = await ref.read(jobBoardProvider.future);
    await board.markSeen([item]);
    ref.invalidate(inboxUnreadProvider);
    if (!mounted) return;
    setState(() => _inbox = [
          for (final other in _inbox)
            if (other.key != item.key) other,
        ]);
    await _openJob(item.job);
  }

  Future<void> _openJob(JobSummary job) async {
    if (job.kind == JobKind.scheduledRun) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(job.title),
          content: SingleChildScrollView(
            child: SelectableText(job.detail ?? '（没有输出）'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
      return;
    }
    final board = await ref.read(jobBoardProvider.future);
    final task = await board.findTaskInfo(job.id);
    if (!mounted) return;
    if (task == null) {
      FloatingToast.show(context, '任务已删除');
      return;
    }
    await Navigator.of(context).push(NexusPageRoute.detail(
      builder: (_) => TaskDetailsPage(
        task: task,
        onConversationSelected: widget.onConversationSelected,
      ),
    ));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isFlat =
        AppAppearanceController.resolvedGlassIntensity == GlassIntensity.flat;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: isFlat
            ? (isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas)
            : Colors.transparent,
        appBar: NexusPageHeader(
          title: '任务与收件箱',
          subtitle: '后台任务、定时运行与待处理事项',
          onBack: () => Navigator.of(context).pop(),
          actions: [
            IconButton(
              tooltip: '全部标为已读',
              icon: const Icon(Icons.done_all_rounded, size: 20),
              onPressed: _inbox.isEmpty ? null : _markAllSeen,
            ),
            IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: _load,
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: _inbox.isEmpty ? '收件箱' : '收件箱 (${_inbox.length})'),
              const Tab(text: '全部任务'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            AsyncStateView(
              loading: _loading,
              error: _error,
              onRetry: _load,
              isEmpty: _inbox.isEmpty,
              emptyIcon: Icons.inbox_outlined,
              emptyTitle: '没有待处理事项',
              emptySubtitle: '任务需要审批、暂停、失败或完成时会出现在这里',
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _inbox.length,
                  itemBuilder: (context, index) {
                    final item = _inbox[index];
                    return _JobTile(
                      job: item.job,
                      label: inboxReasonLabel(item.reason),
                      icon: inboxReasonIcon(item.reason),
                      emphasize: item.reason == InboxReason.needsApproval ||
                          item.reason == InboxReason.failed,
                      onTap: () => _openInboxItem(item),
                    );
                  },
                ),
              ),
            ),
            AsyncStateView(
              loading: _loading,
              error: _error,
              onRetry: _load,
              isEmpty: _jobs.isEmpty,
              emptyIcon: Icons.task_alt_rounded,
              emptyTitle: '还没有任务',
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _jobs.length,
                  itemBuilder: (context, index) {
                    final job = _jobs[index];
                    return _JobTile(
                      job: job,
                      label: jobPhaseLabel(job.phase),
                      icon: jobPhaseIcon(job.phase),
                      emphasize: false,
                      onTap: () => _openJob(job),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({
    required this.job,
    required this.label,
    required this.icon,
    required this.emphasize,
    required this.onTap,
  });

  final JobSummary job;
  final String label;
  final IconData icon;
  final bool emphasize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kind = job.kind == JobKind.scheduledRun ? '定时' : '任务';
    return SectionCard(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: emphasize ? scheme.error : scheme.primary),
        title: Text(job.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            '$kind · $label · ${formatJobTime(job.updatedAt)}',
            if (job.detail != null) job.detail!,
          ].join('\n'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: job.detail != null,
        trailing: const Icon(Icons.chevron_right_rounded, size: 18),
        onTap: onTap,
      ),
    );
  }
}

String inboxReasonLabel(InboxReason reason) => switch (reason) {
      InboxReason.needsApproval => '等待审批',
      InboxReason.paused => '已暂停',
      InboxReason.failed => '失败',
      InboxReason.completed => '已完成',
      InboxReason.scheduledRun => '定时运行完成',
    };

IconData inboxReasonIcon(InboxReason reason) => switch (reason) {
      InboxReason.needsApproval => Icons.gpp_maybe_outlined,
      InboxReason.paused => Icons.pause_circle_outline_rounded,
      InboxReason.failed => Icons.error_outline_rounded,
      InboxReason.completed => Icons.check_circle_outline_rounded,
      InboxReason.scheduledRun => Icons.schedule_rounded,
    };

String jobPhaseLabel(JobPhase phase) => switch (phase) {
      JobPhase.queued => '排队中',
      JobPhase.running => '运行中',
      JobPhase.needsApproval => '等待审批',
      JobPhase.paused => '已暂停',
      JobPhase.completed => '已完成',
      JobPhase.failed => '失败',
      JobPhase.cancelled => '已取消',
      JobPhase.other => '其他',
    };

IconData jobPhaseIcon(JobPhase phase) => switch (phase) {
      JobPhase.queued => Icons.hourglass_empty_rounded,
      JobPhase.running => Icons.play_circle_outline_rounded,
      JobPhase.needsApproval => Icons.gpp_maybe_outlined,
      JobPhase.paused => Icons.pause_circle_outline_rounded,
      JobPhase.completed => Icons.check_circle_outline_rounded,
      JobPhase.failed => Icons.error_outline_rounded,
      JobPhase.cancelled => Icons.cancel_outlined,
      JobPhase.other => Icons.help_outline_rounded,
    };

String formatJobTime(DateTime time) {
  final local = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
