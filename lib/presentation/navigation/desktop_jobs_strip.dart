import 'dart:async';
import '../../application/desktop_host_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/jobs/job_board_providers.dart';
import '../theme/desktop_theme.dart';

export '../../application/jobs/job_board.dart';

/// 桌面底部状态栏的 Jobs 常驻段：有进行中任务或未读待处理时显示，
/// 点击原地展开浮层面板。平时完全隐藏，不抢视觉。
class DesktopJobsStrip extends ConsumerStatefulWidget {
  const DesktopJobsStrip({super.key, this.onOpenAll, this.onOpenJob});

  final VoidCallback? onOpenAll;
  final ValueChanged<JobSummary>? onOpenJob;

  @override
  ConsumerState<DesktopJobsStrip> createState() => _DesktopJobsStripState();
}

class _DesktopJobsStripState extends ConsumerState<DesktopJobsStrip> {
  static const _refreshInterval = Duration(seconds: 2);
  static const _inboxPreviewCount = 3;
  static const _recentPreviewCount = 6;

  final LayerLink _link = LayerLink();
  Timer? _timer;
  OverlayEntry? _panel;
  StateSetter? _panelSetState;

  List<JobSummary> _jobs = const <JobSummary>[];
  List<InboxItem> _inbox = const <InboxItem>[];
  int _unread = 0;
  String _signature = '';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(_refreshInterval, (_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _closePanel(notify: false);
    super.dispose();
  }

  List<JobSummary> get _active => <JobSummary>[
        for (final job in _jobs)
          if (job.isActive) job
      ];

  Future<void> _refresh() async {
    try {
      final board = await ref.read(jobBoardProvider.future);
      final jobs = await board.jobs(limit: 12);
      final inbox = await board.inbox();
      final unread = await board.unreadCount();
      if (!mounted) return;
      final signature = <String>[
        for (final job in jobs)
          '${job.id}:${job.rawStatus}:${job.updatedAt.millisecondsSinceEpoch}',
        for (final item in inbox) item.key,
        '$unread',
      ].join('|');
      if (signature == _signature) return;
      if (_loaded) {
        final old = {for (final job in _jobs) job.id: job.rawStatus};
        for (final job in jobs) {
          if (old.containsKey(job.id) &&
              old[job.id] != job.rawStatus &&
              const [
                JobPhase.completed,
                JobPhase.failed,
                JobPhase.needsApproval,
                JobPhase.needsVerification,
                JobPhase.partial
              ].contains(job.phase)) {
            unawaited(DesktopHostService.instance
                .notify(
                    '任务 · ${job.title}',
                    switch (job.phase) {
                      JobPhase.completed => '任务已完成，可以查看结果与验证记录',
                      JobPhase.failed => '任务失败，需要查看错误记录',
                      JobPhase.needsVerification => '结果尚待核实，请勿自动重试',
                      JobPhase.partial => '任务仅部分完成，请核对剩余事项',
                      _ => '任务需要审批，请返回 NEXUS 处理',
                    })
                .catchError((Object error) {
              debugPrint('桌面通知失败：$error');
            }));
          }
        }
      }
      setState(() {
        _jobs = jobs;
        _inbox = inbox;
        _unread = unread;
        _signature = signature;
        _loaded = true;
      });
      _panelSetState?.call(() {});
    } catch (_) {
      // 状态条是辅助信息：静默失败，下个刷新周期自动重试。
    }
  }

  void _togglePanel() {
    if (_panel != null) {
      _closePanel();
      return;
    }
    final entry = OverlayEntry(builder: (context) {
      return StatefulBuilder(builder: (context, setEntryState) {
        _panelSetState = setEntryState;
        final theme = Theme.of(context);
        final colors = DesktopTheme.maybeOf(context);
        final panelColor = colors?.panel ?? theme.colorScheme.surface;
        final border = colors?.border ?? theme.dividerColor;
        return Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closePanel,
              child: const SizedBox.expand(),
            ),
          ),
          CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topRight,
            followerAnchor: Alignment.bottomRight,
            offset: const Offset(-8, -8),
            child: SizedBox(
              width: 420,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: Material(
                  color: panelColor,
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _panelContent(context),
                ),
              ),
            ),
          ),
        ]);
      });
    });
    _panel = entry;
    Overlay.of(context).insert(entry);
    setState(() {});
  }

  void _closePanel({bool notify = true}) {
    final entry = _panel;
    _panel = null;
    _panelSetState = null;
    entry?.remove();
    if (notify && mounted) setState(() {});
  }

  void _openJob(JobSummary job) {
    _closePanel();
    widget.onOpenJob?.call(job);
  }

  IconData _phaseIcon(JobPhase phase) => switch (phase) {
        JobPhase.running => Icons.play_circle_outline,
        JobPhase.queued => Icons.schedule_outlined,
        JobPhase.needsApproval => Icons.verified_user_outlined,
        JobPhase.paused => Icons.pause_circle_outline,
        JobPhase.needsVerification => Icons.fact_check_outlined,
        JobPhase.partial => Icons.pending_actions_outlined,
        JobPhase.completed => Icons.check_circle_outline,
        JobPhase.failed => Icons.error_outline,
        JobPhase.cancelled => Icons.cancel_outlined,
        JobPhase.other => Icons.help_outline,
      };

  String _phaseLabel(JobPhase phase) => switch (phase) {
        JobPhase.running => '进行中',
        JobPhase.queued => '排队中',
        JobPhase.needsApproval => '待审批',
        JobPhase.paused => '已暂停',
        JobPhase.needsVerification => '待核实',
        JobPhase.partial => '部分完成',
        JobPhase.completed => '已完成',
        JobPhase.failed => '失败',
        JobPhase.cancelled => '已取消',
        JobPhase.other => '其他',
      };

  String _reasonLabel(InboxReason reason) => switch (reason) {
        InboxReason.needsApproval => '待审批',
        InboxReason.paused => '已暂停',
        InboxReason.needsVerification => '待核实',
        InboxReason.partial => '部分完成',
        InboxReason.failed => '失败',
        InboxReason.completed => '已完成',
        InboxReason.scheduledRun => '定时结果',
      };

  String _timeLabel(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }

  Color _phaseColor(JobPhase phase, Color accent, ThemeData theme) =>
      switch (phase) {
        JobPhase.running || JobPhase.queued => accent,
        JobPhase.needsApproval || JobPhase.paused => theme.colorScheme.tertiary,
        JobPhase.failed ||
        JobPhase.needsVerification =>
          theme.colorScheme.error,
        JobPhase.partial => theme.colorScheme.tertiary,
        _ => theme.hintColor,
      };

  Widget _panelContent(BuildContext context) {
    final theme = Theme.of(context);
    final colors = DesktopTheme.maybeOf(context);
    final accent = colors?.accent ?? theme.colorScheme.primary;
    final muted = colors?.muted ?? theme.hintColor;
    final inboxPreview = _inbox.take(_inboxPreviewCount).toList();
    final recent = _jobs.take(_recentPreviewCount).toList();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(children: [
          Expanded(
            child: Text('任务与待处理', style: theme.textTheme.titleSmall),
          ),
          TextButton(
            key: const ValueKey('jobs-panel-open-all'),
            onPressed: () {
              _closePanel();
              widget.onOpenAll?.call();
            },
            child: const Text('查看全部'),
          ),
        ]),
      ),
      const Divider(height: 1),
      Flexible(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          shrinkWrap: true,
          children: [
            if (inboxPreview.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                child: Text('待处理',
                    style: theme.textTheme.labelSmall?.copyWith(color: muted)),
              ),
              for (final item in inboxPreview)
                ListTile(
                  key: ValueKey('jobs-panel-inbox-${item.job.id}'),
                  dense: true,
                  leading: Icon(
                    _phaseIcon(item.job.phase),
                    size: 20,
                    color: _phaseColor(item.job.phase, accent, theme),
                  ),
                  title: Text(item.job.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      '${_reasonLabel(item.reason)} · ${_timeLabel(item.job.updatedAt)}'),
                  onTap: () => _openJob(item.job),
                ),
            ],
            if (recent.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                child: Text('最近任务',
                    style: theme.textTheme.labelSmall?.copyWith(color: muted)),
              ),
              for (final job in recent)
                ListTile(
                  key: ValueKey('jobs-panel-job-${job.id}'),
                  dense: true,
                  leading: Icon(
                    _phaseIcon(job.phase),
                    size: 20,
                    color: _phaseColor(job.phase, accent, theme),
                  ),
                  title: Text(job.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      '${_phaseLabel(job.phase)} · ${_timeLabel(job.updatedAt)}'),
                  onTap: () => _openJob(job),
                ),
            ],
            if (inboxPreview.isEmpty && recent.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text('暂无任务',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                ),
              ),
          ],
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = DesktopTheme.maybeOf(context);
    final accent = colors?.accent ?? theme.colorScheme.primary;
    final muted = colors?.muted ?? theme.hintColor;
    final active = _active;
    final visible = _loaded && (active.isNotEmpty || _unread > 0);
    if (!visible) return const SizedBox.shrink();
    final latest = active.isEmpty ? null : active.first;
    final dotColor = active.isNotEmpty ? accent : theme.colorScheme.tertiary;
    return CompositedTransformTarget(
      link: _link,
      child: Tooltip(
        message: latest == null ? '点击查看待处理任务' : '进行中：${latest.title}',
        child: InkWell(
          key: const ValueKey('desktop-jobs-strip'),
          borderRadius: BorderRadius.circular(8),
          onTap: _togglePanel,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                latest != null ? '${active.length} 个任务进行中' : '$_unread 条任务待处理',
                style: theme.textTheme.bodySmall,
              ),
              if (latest != null && _unread > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      Text('待处理 $_unread', style: theme.textTheme.labelSmall),
                ),
              ],
              const SizedBox(width: 2),
              Icon(
                _panel == null ? Icons.expand_less : Icons.expand_more,
                size: 14,
                color: muted,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
