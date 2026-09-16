import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../application/chat_controller.dart';
import '../../../domain/tool_result.dart';
import '../../../infrastructure/tools/tool_humanizer.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/nexus_disclosure.dart';
import '../../widgets/nexus_execution_status.dart';
import '../../widgets/nexus_status_badge.dart';
import '../../widgets/nexus_surface.dart';

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

  @override
  State<ToolActivityTimeline> createState() => _ToolActivityTimelineState();
}

class _ToolActivityTimelineState extends State<ToolActivityTimeline> {
  /// 完成后条目较多时默认收起明细，避免长轨迹在消息流里占满一屏；
  /// 运行中始终完整展示，用户能实时看到最新一步。
  static const int _collapsedThreshold = 8;

  /// 展开时的最大高度：内联位置不能无限增高，超出部分内部滚动。
  static const double _expandedMaxHeight = 280;

  /// null = 跟随默认（运行中或短轨迹展开、长轨迹完成后收起）；
  /// 用户手动切换后锁定，新一轮运行开始时重置。
  bool? _expandedOverride;

  @override
  void didUpdateWidget(covariant ToolActivityTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.running && !oldWidget.running) _expandedOverride = null;
  }

  bool get _collapsible => widget.activities.length > _collapsedThreshold;

  @override
  Widget build(BuildContext context) {
    final collapsible = widget.compact || _collapsible;
    final expanded = widget.compact
        ? (_expandedOverride ??
            (widget.running ||
                widget.activities.any((activity) => activity.status == '等待确认')))
        : (_expandedOverride ?? (!collapsible || widget.running));
    return NexusSurface(
      level: SurfaceLevel.thin,
      borderRadius: BorderRadius.circular(AppTokens.radiusControl),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(context, collapsible: collapsible, expanded: expanded),
            if (expanded)
              ConstrainedBox(
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
          ],
        ),
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
      borderRadius: BorderRadius.circular(AppTokens.radiusControl),
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
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurface),
            ),
          ),
          if (collapsible)
            Icon(
              expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: semantic.textMuted,
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
    if (effectLabel != null) {
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
        ? (Icons.sync_rounded, AppPalette.brand)
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
      leading: Icon(leadIcon, size: 18, color: leadColor),
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
              color: isDark ? AppPalette.terminalBg : const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark
                    ? AppPalette.terminalBorder
                    : const Color(0xFF334155),
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
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '工具: ${a.call.name}\n参数: $args',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    color: Color(0xFFE2E8F0),
                  ),
                ),
                if (a.result != null && a.result!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    a.result!,
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFFCBD5E1),
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                const Divider(height: 1, color: Color(0xFF1E293B)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      'Status: ${running ? "Running" : (done ? "Success" : (failed ? "Failed" : "Pending"))}',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: running
                            ? const Color(0xFF60A5FA)
                            : (done
                                ? const Color(0xFF34D399)
                                : (failed
                                    ? const Color(0xFFF87171)
                                    : const Color(0xFFFBBF24))),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: running
                            ? const Color(0xFF60A5FA)
                            : (done
                                ? const Color(0xFF34D399)
                                : (failed
                                    ? const Color(0xFFF87171)
                                    : const Color(0xFFFBBF24))),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
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
    return (pending &&
            (widget.onConfirm != null ||
                widget.onReject != null ||
                widget.onReview != null)) ||
        (retryable && widget.onRetry != null);
  }

  Widget _inlineActions(
    BuildContext context,
    ToolActivity activity, {
    required bool pending,
    required bool failed,
  }) {
    final retryable =
        failed || activity.ok == false || activity.effect == ToolEffect.unknown;
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
