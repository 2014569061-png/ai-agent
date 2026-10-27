import '../theme/mobile_theme.dart';
import 'package:flutter/material.dart';
import '../search/global_search_page.dart';
import '../widgets/nexus_page_layout.dart';
import '../scheduled/scheduled_tasks_page.dart';
import '../workflows/mobile_workflows_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/jobs/job_board_providers.dart';
import '../motion/nexus_page_route_factory.dart';
import '../tasks/task_details_page.dart';
import '../theme/app_theme.dart';
import '../widgets/async_state_view.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_page_header.dart';
import '../theme/desktop_theme.dart';
import '../widgets/desktop_page_summary.dart';
import '../widgets/section_card.dart';
import '../widgets/nexus_status_pill.dart';

/// 任务与收件箱（阶段 7b）：后台任务和定时运行的统一视图。
///
/// 「收件箱」只列需要留意的条目（待审批、已暂停、失败、完成、定时运行结果），
/// 打开即标为已读；最近任务有上限，待处理独立保留未解决任务。
class JobsInboxPage extends ConsumerStatefulWidget {
  const JobsInboxPage(
      {super.key, this.onConversationSelected, this.onJobSelected});

  final ValueChanged<String>? onConversationSelected;
  final ValueChanged<JobSummary>? onJobSelected;

  @override
  ConsumerState<JobsInboxPage> createState() => _JobsInboxPageState();
}

class _JobsInboxPageState extends ConsumerState<JobsInboxPage> {
  bool _loading = true;
  Object? _error;
  List<InboxItem> _inbox = const [];
  List<JobSummary> _jobs = const [];
  List<JobSummary> _attention = const [];
  int _loadGeneration = 0;
  bool _marking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final board = await ref.read(jobBoardProvider.future);
      final inbox = await board.inbox();
      final jobs = await board.jobs();
      final attention = await board.attentionJobs();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _inbox = inbox;
        _jobs = jobs;
        _attention = attention;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _markAllSeen() async {
    if (_inbox.isEmpty || _marking) return;
    final captured = List<InboxItem>.of(_inbox);
    setState(() => _marking = true);
    try {
      final board = await ref.read(jobBoardProvider.future);
      await board.markSeen(captured);
      ref.invalidate(inboxUnreadProvider);
      if (!mounted) return;
      setState(() => _inbox = JobBoard.remainingAfterSeen(_inbox, captured));
      FloatingToast.show(context, '已将当时显示的事项标为已读；待处理任务仍保留');
      // Supersede reads started before acknowledgement was persisted.
      await _load();
    } catch (_) {
      if (mounted) FloatingToast.show(context, '未能更新已读状态，列表已保留，请重试');
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  Future<void> _openInboxItem(InboxItem item) async {
    try {
      final board = await ref.read(jobBoardProvider.future);
      await board.markSeen([item]);
      ref.invalidate(inboxUnreadProvider);
      if (!mounted) return;
      setState(() => _inbox = JobBoard.remainingAfterSeen(_inbox, [item]));
      await _load();
    } catch (_) {
      if (mounted) FloatingToast.show(context, '已读状态未保存，事项仍保留');
    }
    if (mounted) await _openJob(item.job);
  }

  Future<void> _openJob(JobSummary job) async {
    final selected = widget.onJobSelected;
    if (selected != null) {
      selected(job);
      return;
    }
    if (job.kind == JobKind.scheduledRun) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(job.title),
          content: SingleChildScrollView(
            child: SelectableText([
              jobPhaseLabel(job.phase),
              if (job.safetyNotice != null) job.safetyNotice!,
              job.detail ?? '（没有输出）',
            ].join('\n\n')),
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
    final desktop = DesktopTheme.maybeOf(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: MobileTheme.pageBackground(context),
        appBar: NexusPageHeader(
          title: desktop == null ? '任务' : '任务与收件箱',
          largeTitle:
              desktop == null && !(ModalRoute.of(context)?.canPop ?? false),
          subtitle: desktop == null ? null : '后台任务、定时运行与任务动态',
          actions: [
            IconButton(
                tooltip: '全量搜索',
                icon: const Icon(Icons.search),
                onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                        builder: (_) => GlobalSearchPage(
                            onConversationSelected:
                                widget.onConversationSelected)))),
            PopupMenuButton<String>(
              tooltip: '更多任务操作',
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (action) {
                switch (action) {
                  case 'read':
                    _markAllSeen();
                  case 'refresh':
                    _load();
                  case 'scheduled':
                    Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const ScheduledTasksPage()));
                  case 'workflows':
                    Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const MobileWorkflowsPage()));
                  case 'info':
                    showDialog<void>(
                        context: context,
                        builder: (_) => AlertDialog(
                                title: const Text('关于任务列表'),
                                content: const Text(
                                    '最近任务、待处理各最多 100 项；收件箱显示未读事项。已读不等于处理完成。可使用搜索查找更早记录。'),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('知道了'))
                                ]));
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'scheduled', child: Text('定时任务与提醒')),
                const PopupMenuItem(value: 'workflows', child: Text('工作流')),
                PopupMenuItem(
                    value: 'read',
                    enabled: _inbox.isNotEmpty && !_marking,
                    child: const Text('全部标为已读')),
                const PopupMenuItem(value: 'refresh', child: Text('刷新')),
                const PopupMenuItem(value: 'info', child: Text('列表说明')),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(58),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: SizedBox(
                  height: 44,
                  child: TabBar(
                    dividerColor: Colors.transparent,
                    tabs: [
                      Tab(
                          text: _attention.isEmpty
                              ? '待处理'
                              : '待处理 ${_attention.length}'),
                      const Tab(text: '最近任务'),
                      Tab(
                          text:
                              _inbox.isEmpty ? '收件箱' : '收件箱 ${_inbox.length}'),
                    ],
                  )),
            ),
          ),
        ),
        body: NexusPageLayout(
            child: Column(children: [
          if (desktop != null)
            DesktopPageSummary(items: [
              (
                icon: Icons.inbox_outlined,
                label: '待处理',
                value: _loading
                    ? '读取中'
                    : _error != null
                        ? '读取失败'
                        : '${_attention.length}'
              ),
              (
                icon: Icons.task_alt,
                label: '近期任务',
                value: _loading
                    ? '读取中'
                    : _error != null
                        ? '读取失败'
                        : '${_jobs.length}'
              ),
            ]),
          Expanded(
              child: TabBarView(
            children: [
              AsyncStateView(
                loading: _loading,
                refreshing: _loading && _attention.isNotEmpty,
                retainContentOnError: _attention.isNotEmpty,
                error: _error,
                onRetry: _load,
                isEmpty: _attention.isEmpty,
                emptyIcon: Icons.fact_check_outlined,
                emptyTitle: '没有待处理任务',
                emptySubtitle: '需要审批、核实或继续处理的任务会显示在这里',
                child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _attention.length,
                      itemBuilder: (context, index) {
                        final job = _attention[index];
                        return _JobTile(
                            job: job,
                            label: jobPhaseLabel(job.phase),
                            icon: jobPhaseIcon(job.phase),
                            emphasize: true,
                            onTap: () => _openJob(job));
                      },
                    )),
              ),
              AsyncStateView(
                loading: _loading,
                refreshing: _loading && _jobs.isNotEmpty,
                retainContentOnError: _jobs.isNotEmpty,
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
                        emphasize: job.phase == JobPhase.needsVerification ||
                            job.phase == JobPhase.partial,
                        onTap: () => _openJob(job),
                      );
                    },
                  ),
                ),
              ),
              AsyncStateView(
                loading: _loading,
                refreshing: _loading && _inbox.isNotEmpty,
                retainContentOnError: _inbox.isNotEmpty,
                error: _error,
                onRetry: _load,
                isEmpty: _inbox.isEmpty,
                emptyIcon: Icons.inbox_outlined,
                emptyTitle: '没有未读事项',
                emptySubtitle: '任务需要审批、核实、暂停、失败或完成时会出现在这里',
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
                            item.reason == InboxReason.failed ||
                            item.reason == InboxReason.needsVerification ||
                            item.reason == InboxReason.partial,
                        onTap: () => _openInboxItem(item),
                      );
                    },
                  ),
                ),
              ),
            ],
          )),
        ])),
      ),
    );
  }
}

/// 收件箱理由 -> 徽标语义。文案仍用 [inboxReasonLabel]，这里只决定颜色与图标。
NexusStatusType _statusTypeForLabel(String label) => switch (label) {
      '等待审批' || '待核实' => NexusStatusType.waitingApproval,
      '已暂停' || '部分完成' => NexusStatusType.paused,
      '失败' => NexusStatusType.failed,
      '已完成' || '定时运行完成' => NexusStatusType.completed,
      _ => NexusStatusType.draft,
    };

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
    final semantic = AppTheme.semanticOf(context);
    final accent = job.phase == JobPhase.failed
        ? scheme.error
        : job.phase == JobPhase.completed
            ? semantic.success
            : emphasize
                ? semantic.warning
                : scheme.primary;
    final kind = job.kind == JobKind.scheduledRun ? '定时' : '任务';
    return SectionCard(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: ListTile(
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(MobileTheme.insetRadius),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 24, color: accent),
        ),
        title: Tooltip(
            message: job.title,
            child: Text(job.title,
                maxLines:
                    MediaQuery.textScalerOf(context).scale(14) > 19 ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w500))),
        // 状态从「任务 · 等待审批 · 18:57」里的一串文字，改成右侧一颗徽标：
        // 扫列表时先看到颜色和短词，不用逐字读到第三段。
        subtitle: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '$kind · ${formatJobTime(job.updatedAt)}',
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                NexusStatusPill(
                  status: _statusTypeForLabel(label),
                  customLabel: label,
                  isCompact: true,
                ),
              ],
            ),
            if (job.safetyNotice != null)
              Text(job.safetyNotice!,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            if (job.detail != null)
              Text(job.detail!,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
        isThreeLine: job.detail != null || job.safetyNotice != null,
        trailing: const Icon(Icons.chevron_right_rounded, size: 18),
        onTap: onTap,
      ),
    );
  }
}

String inboxReasonLabel(InboxReason reason) => switch (reason) {
      InboxReason.needsApproval => '等待审批',
      InboxReason.paused => '已暂停',
      InboxReason.needsVerification => '待核实',
      InboxReason.partial => '部分完成',
      InboxReason.failed => '失败',
      InboxReason.completed => '已完成',
      InboxReason.scheduledRun => '定时运行完成',
    };

IconData inboxReasonIcon(InboxReason reason) => switch (reason) {
      InboxReason.needsApproval => Icons.gpp_maybe_outlined,
      InboxReason.paused => Icons.pause_circle_outline_rounded,
      InboxReason.needsVerification => Icons.fact_check_outlined,
      InboxReason.partial => Icons.pending_actions_outlined,
      InboxReason.failed => Icons.error_outline_rounded,
      InboxReason.completed => Icons.check_circle_outline_rounded,
      InboxReason.scheduledRun => Icons.schedule_rounded,
    };

String jobPhaseLabel(JobPhase phase) => switch (phase) {
      JobPhase.queued => '排队中',
      JobPhase.running => '运行中',
      JobPhase.needsApproval => '等待审批',
      JobPhase.paused => '已暂停',
      JobPhase.needsVerification => '待核实',
      JobPhase.partial => '部分完成',
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
      JobPhase.needsVerification => Icons.fact_check_outlined,
      JobPhase.partial => Icons.pending_actions_outlined,
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
