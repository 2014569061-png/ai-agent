import '../../theme/mobile_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../application/chat_controller.dart';
import '../../../domain/tool_result.dart';
import '../tool_humanizer.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_tokens.dart';
import '../../theme/desktop_theme.dart';
import '../../widgets/nexus_disclosure.dart';
import '../../widgets/nexus_execution_status.dart';
import '../../widgets/nexus_sheet.dart';
import '../../widgets/nexus_status_badge.dart';
import '../../widgets/section_card.dart';
import '../../motion/morph_icon.dart';
import '../transcript_view_policy.dart';

/// 工具执行内联时间线：直接出现在消息流尾部（Agent 正在工作的位置），
/// 无需点击即可看到每一步工具调用的状态与结果；行内可展开技术详情。
///
/// 取代旧的悬浮胶囊——胶囊把执行过程藏在一层点击之后，透明度不足。
class ToolActivityTimeline extends StatefulWidget {
  const ToolActivityTimeline({
    super.key,
    required this.activities,
    required this.running,
    this.onConfirm,
    this.onReject,
    this.onReview,
    this.onRetry,
    this.onOpenResults,
    this.compact = false,
  });

  final List<ToolActivity> activities;
  final bool running;

  /// Top-of-chat mode keeps finished/failed history to a single summary row.
  /// Running and confirmation-required items remain expanded for actionability.
  final bool compact;
  final void Function(ToolActivity activity)? onConfirm;
  final void Function(ToolActivity activity)? onReject;
  final void Function(ToolActivity activity)? onReview;
  final void Function(ToolActivity activity)? onRetry;
  final VoidCallback? onOpenResults;

  @override
  State<ToolActivityTimeline> createState() => _ToolActivityTimelineState();
}

class _ToolActivityTimelineState extends State<ToolActivityTimeline> {
  /// 完成后条目较多时默认收起明细，避免长轨迹在消息流里占满一屏；
  /// 运行中始终完整展示，用户能实时看到最新一步。

  /// 展开时的最大高度：内联位置不能无限增高，超出部分内部滚动。
  static const double _expandedMaxHeight = 280;

  /// 顶部 Dock（compact）最多直接展示的最近条目数，更早的进「查看全部」。
  /// Dock 本身已经在一个滚动容器里，这里不能再嵌一层内部滚动：以前两层
  /// 滚动嵌套，最后一条会被裁掉、怎么滑也看不到。
  static const int _compactVisibleCount = 3;

  /// null = 跟随默认（运行中或短轨迹展开、长轨迹完成后收起）；
  /// 用户手动切换后锁定，新一轮运行开始时重置。
  bool? _expandedOverride;

  @override
  void didUpdateWidget(covariant ToolActivityTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.running && !oldWidget.running) _expandedOverride = null;
  }

  /// compact 模式下直接展示的条目：最近 [_compactVisibleCount] 条，外加所有
  /// 「等待确认」的条目（需要用户操作，不能被折叠进「查看全部」）。
  List<ToolActivity> get _compactRows {
    final all = widget.activities;
    if (all.length <= _compactVisibleCount) return all;
    final start = all.length - _compactVisibleCount;
    return [
      for (var index = 0; index < all.length; index++)
        if (index >= start || all[index].status == '等待确认') all[index],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final desktop = DesktopTheme.maybeOf(context);
    final policy = TranscriptViewPolicy.forTimeline(
        running: widget.running,
        compact: widget.compact,
        count: widget.activities.length,
        needsApproval:
            widget.activities.any((activity) => activity.status == '等待确认'));
    final collapsible = policy.toolsCollapsible;
    final expanded =
        policy.forceToolsOpen || (_expandedOverride ?? policy.toolsExpanded);
    final inner = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(context, collapsible: collapsible, expanded: expanded),
          NexusExpandSection(
            expanded: expanded,
            child: widget.compact
                ? _compactList(context)
                : ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxHeight: _expandedMaxHeight),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final activity in widget.activities)
                            _row(context, activity),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
    if (desktop != null) {
      return Container(
        decoration: BoxDecoration(
          color: desktop.sidebar,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: desktop.border),
        ),
        child: inner,
      );
    }
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: inner,
    );
  }

  /// compact：只渲染最近几条，高度天然有界；更早的条目通过「查看全部」在
  /// 底部抽屉里完整查看。
  Widget _compactList(BuildContext context) {
    final rows = _compactRows;
    final hidden = widget.activities.length - rows.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final activity in rows) _row(context, activity),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: TextButton.icon(
              key: const ValueKey('tool-activity-show-all'),
              onPressed: () => _showAllSheet(context),
              icon: const Icon(Icons.unfold_more_rounded, size: 16),
              label: Text('查看全部 ${widget.activities.length} 条'),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
      ],
    );
  }

  void _showAllSheet(BuildContext context) {
    HapticFeedback.selectionClick();
    // 打开时的快照：抽屉是独立路由，不随 Dock 实时刷新。
    final activities = List<ToolActivity>.of(widget.activities);
    showNexusSheet<void>(
      context: context,
      maxHeightRatio: 0.85,
      builder: (sheetContext) => Column(
        key: const ValueKey('tool-activity-all-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
            child: Text(
              '全部执行步骤（${activities.length}）',
              style: Theme.of(sheetContext)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
              children: [
                for (final activity in activities) _row(sheetContext, activity),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(
    BuildContext context, {
    required bool collapsible,
    required bool expanded,
  }) {
    final theme = Theme.of(context);
    final semantic = AppTheme.semanticOf(context);
    final summary = _ToolSummary.from(widget.activities);
    final text = widget.running ? _liveSummary : _completedSummary(summary);

    if (widget.running) {
      final hasPending = widget.activities.any((a) => a.status == '等待确认');
      return NexusExecutionStatus(
        state: hasPending
            ? NexusExecutionState.waitingForUser
            : NexusExecutionState.running,
        label: _liveSummary,
        compact: false,
        onViewDetails: collapsible
            ? () {
                HapticFeedback.selectionClick();
                setState(() => _expandedOverride = !expanded);
              }
            : null,
      );
    }

    return InkWell(
      onTap: collapsible
          ? () {
              HapticFeedback.selectionClick();
              setState(() => _expandedOverride = !expanded);
            }
          : null,
      borderRadius: BorderRadius.circular(MobileTheme.controlRadius(context)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Row(children: [
          Icon(
            summary.unknown > 0
                ? Icons.help_outline_rounded
                : summary.failed > 0
                    ? Icons.error_outline_rounded
                    : Icons.verified_outlined,
            size: 15,
            color: summary.unknown > 0
                ? semantic.warning
                : summary.failed > 0
                    ? theme.colorScheme.error
                    : semantic.success,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              collapsible && !expanded ? '$text（点击展开）' : text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (widget.onOpenResults != null)
            IconButton(
              tooltip: '查看执行结果',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              onPressed: widget.onOpenResults,
              icon: const Icon(Icons.inventory_2_outlined, size: 15),
            ),
          if (collapsible)
            SpringTurns(
              turns: expanded ? 0.5 : 0.0,
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: semantic.textMuted,
              ),
            ),
        ]),
      ),
    );
  }

  int get runningCount =>
      widget.activities.where((a) => a.status == '执行中').length;
  int get pendingCount =>
      widget.activities.where((a) => a.status == '等待确认').length;

  String get _liveSummary {
    final current = widget.activities.lastOrNull;
    if (current == null) return '准备执行';
    return switch (current.status) {
      '等待确认' => '等待确认 ${current.call.name}',
      '执行中' => '正在执行 ${current.call.name}',
      _ => '已完成 ${widget.activities.length} 项工具',
    };
  }

  String _completedSummary(_ToolSummary summary) {
    if (summary.unknown > 0) return '有 ${summary.unknown} 项结果待核验';
    if (summary.failed > 0) return '${summary.failed} 项未完成，查看原因';
    if (summary.applied > 0) return '${summary.applied} 项操作已执行';
    return '${widget.activities.length} 项工具已完成';
  }

  String _actionOf(ToolActivity activity) =>
      const ToolHumanizer().summaryOf(activity.call) ?? '执行一项工具操作';

  String _resultTitle(ToolActivity activity) {
    final action = _actionOf(activity);
    if (activity.status == '执行中') return '正在处理：$action';
    if (activity.status == '等待确认') return '需要你的确认：$action';
    if (activity.effect == ToolEffect.unknown) return '需要核验：$action';
    if (activity.status == '执行失败' || activity.ok == false) {
      return '未完成：$action';
    }
    if (activity.status == '已完成' || activity.ok == true) {
      return '已完成：$action';
    }
    return '准备处理：$action';
  }

  String _resultSubtitle(ToolActivity activity) {
    if (activity.effect == ToolEffect.unknown) {
      return '执行状态无法确认，请先检查目标状态再继续。';
    }
    if (activity.status == '等待确认') return '确认后才会执行此操作。';
    if (activity.status == '执行中') return '正在执行，完成后会在这里显示结果。';
    if (activity.status == '执行失败' || activity.ok == false) {
      return '操作没有完成。展开可查看技术详情。';
    }
    if (activity.status == '已完成' || activity.ok == true) {
      return '操作结果已记录。';
    }
    return '等待开始执行。';
  }

  Widget _row(BuildContext context, ToolActivity a) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final semantic = AppTheme.semanticOf(context);
    final running = a.status == '执行中';
    final done = a.status == '已完成';
    final pending = a.status == '等待确认';
    final failed = a.status == '执行失败';
    final args = a.call.arguments.toString();
    final effect = a.effect;
    final effectLabel = switch (effect) {
      ToolEffect.applied => '已执行',
      ToolEffect.unknown => '待核验',
      ToolEffect.none => '未执行',
      null => null,
    };
    final effectTone = switch (effect) {
      ToolEffect.applied => NexusBadgeTone.success,
      ToolEffect.unknown => NexusBadgeTone.warning,
      ToolEffect.none => NexusBadgeTone.neutral,
      null => NexusBadgeTone.neutral,
    };

    Widget? trailingWidget;
    if (a.compressed) {
      trailingWidget = const NexusStatusBadge(
        label: '已压缩',
        tone: NexusBadgeTone.neutral,
      );
    } else if (effectLabel != null) {
      trailingWidget = NexusStatusBadge(
        label: effectLabel,
        tone: effectTone,
      );
    } else if (pending) {
      trailingWidget = const NexusStatusBadge(
        label: '待确认',
        tone: NexusBadgeTone.warning,
      );
    } else if (running) {
      trailingWidget = const NexusStatusBadge(
        label: '执行中',
        tone: NexusBadgeTone.brand,
        showDot: true,
      );
    }

    final (IconData leadIcon, Color leadColor) = running
        ? (Icons.sync_rounded, MobileTheme.brand(context))
        : done
            ? (Icons.check_circle_outline, semantic.success)
            : failed
                ? (Icons.cancel_outlined, theme.colorScheme.error)
                : pending
                    ? (Icons.error_outline, semantic.warning)
                    : (Icons.radio_button_unchecked, semantic.textMuted);

    return NexusDisclosure(
      headerPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      leading: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: leadColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Icon(leadIcon, size: 15, color: leadColor),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _resultTitle(a),
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 2),
          Text(
            _resultSubtitle(a),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style:
                theme.textTheme.bodySmall?.copyWith(color: semantic.textMuted),
          ),
          if (_hasInlineActions(a, pending: pending, failed: failed)) ...[
            const SizedBox(height: 6),
            _inlineActions(
              context,
              a,
              pending: pending,
              failed: failed,
            ),
          ],
        ],
      ),
      trailing: trailingWidget,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '技术详情',
              style: theme.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          if (effect == ToolEffect.unknown)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('结果无法确认，请先检查目标状态再重试。'),
              ),
            ),
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color:
                  isDark ? AppPalette.terminalBg : AppPalette.terminalSurface,
              borderRadius: BorderRadius.circular(AppTokens.radiusControl),
              border: Border.all(
                color: isDark
                    ? AppPalette.terminalBorder
                    : AppPalette.lightHairline,
                width: 0.8,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '[Terminal Execution: ${a.call.name}]',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: AppTokens.fontSizeBadge,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.terminalTextMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '工具: ${a.call.name}\n参数: $args',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: AppTokens.fontSizeSubcaption,
                    color: AppPalette.terminalText,
                  ),
                ),
                if (!a.compressed &&
                    a.result != null &&
                    a.result!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    a.result!,
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: AppTokens.fontSizeBadge,
                      color: AppPalette.terminalTextMuted,
                      height: 1.4,
                    ),
                  ),
                ],
                if (a.compressed &&
                    a.originalResult != null &&
                    a.originalResult!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '原始结果',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: AppTokens.fontSizeMetricSmall,
                      fontWeight: FontWeight.w600,
                      color: semantic.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    a.originalResult!,
                    maxLines: 12,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: AppTokens.fontSizeBadge,
                      color: theme.colorScheme.onSurface,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                const Divider(height: 1, color: AppPalette.terminalBorder),
                const SizedBox(height: 6),
                Builder(
                  builder: (context) {
                    final statusColor = running
                        ? (isDark
                            ? AppPalette.darkBrandHover
                            : MobileTheme.brand(context))
                        : (done
                            ? (isDark
                                ? AppPalette.darkSuccess
                                : AppPalette.lightSuccess)
                            : (failed
                                ? (isDark
                                    ? AppPalette.darkDanger
                                    : AppPalette.lightDanger)
                                : (isDark
                                    ? AppPalette.darkWarning
                                    : AppPalette.lightWarning)));
                    return Row(
                      children: [
                        Text(
                          'Status: ${running ? "Running" : (done ? "Success" : (failed ? "Failed" : "Pending"))}',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: AppTokens.fontSizeMetricSmall,
                            fontWeight: FontWeight.w500,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _hasInlineActions(
    ToolActivity activity, {
    required bool pending,
    required bool failed,
  }) {
    final retryable =
        failed || activity.ok == false || activity.effect == ToolEffect.unknown;
    final completed = activity.status == '已完成' || activity.ok == true;
    return (pending &&
            (widget.onConfirm != null ||
                widget.onReject != null ||
                widget.onReview != null)) ||
        (retryable && widget.onRetry != null) ||
        (completed && widget.onOpenResults != null);
  }

  Widget _inlineActions(
    BuildContext context,
    ToolActivity activity, {
    required bool pending,
    required bool failed,
  }) {
    final retryable =
        failed || activity.ok == false || activity.effect == ToolEffect.unknown;
    final completed = activity.status == '已完成' || activity.ok == true;
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (pending && widget.onConfirm != null)
            FilledButton.tonalIcon(
              onPressed: () => widget.onConfirm!(activity),
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('确认执行'),
            ),
          if (pending && widget.onReject != null)
            OutlinedButton.icon(
              onPressed: () => widget.onReject!(activity),
              icon: const Icon(Icons.close_rounded, size: 16),
              label: const Text('拒绝'),
            ),
          if (pending && widget.onReview != null)
            TextButton.icon(
              onPressed: () => widget.onReview!(activity),
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: const Text('查看详情'),
            ),
          if (retryable && widget.onRetry != null)
            OutlinedButton.icon(
              onPressed: () => widget.onRetry!(activity),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('重试'),
            ),
          if (completed && widget.onOpenResults != null)
            TextButton.icon(
              key: ValueKey('tool-activity-open-results-${activity.call.id}'),
              onPressed: widget.onOpenResults,
              icon: const Icon(Icons.inventory_2_outlined, size: 16),
              label: const Text('查看产出结果'),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolSummary {
  const _ToolSummary({
    required this.applied,
    required this.unknown,
    required this.failed,
  });

  final int applied;
  final int unknown;
  final int failed;

  factory _ToolSummary.from(Iterable<ToolActivity> activities) {
    var applied = 0;
    var unknown = 0;
    var failed = 0;
    for (final activity in activities) {
      if (activity.effect == ToolEffect.applied) applied++;
      if (activity.effect == ToolEffect.unknown) unknown++;
      if (activity.status == '执行失败') failed++;
    }
    return _ToolSummary(applied: applied, unknown: unknown, failed: failed);
  }
}
