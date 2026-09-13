import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../application/chat_controller.dart';
import '../../../domain/tool_result.dart';
import '../../../infrastructure/tools/tool_humanizer.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/immersive_surface.dart';

/// 工具执行内联时间线：直接出现在消息流尾部（Agent 正在工作的位置），
/// 无需点击即可看到每一步工具调用的状态与结果；行内可展开技术详情。
///
/// 取代旧的悬浮胶囊——胶囊把执行过程藏在一层点击之后，透明度不足。
class ToolActivityTimeline extends StatefulWidget {
  const ToolActivityTimeline({
    super.key,
    required this.activities,
    required this.running,
  });

  final List<ToolActivity> activities;
  final bool running;

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
    final collapsible = _collapsible;
    final expanded = _expandedOverride ?? (!collapsible || widget.running);
    return ImmersiveSurface(
      level: ImmersiveMaterialLevel.thin,
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
          if (widget.running)
            const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2))
          else
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
    final effectColor = switch (effect) {
      ToolEffect.applied => semantic.success,
      ToolEffect.unknown => semantic.warning,
      ToolEffect.none => semantic.textMuted,
      null => semantic.textMuted,
    };
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: Material(
        type: MaterialType.transparency,
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          minTileHeight: 40,
          leading: running
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(
                  done
                      ? Icons.check_circle_outline
                      : failed
                          ? Icons.cancel_outlined
                          : pending
                              ? Icons.error_outline
                              : Icons.radio_button_unchecked,
                  size: 18,
                  color: done
                      ? semantic.success
                      : failed
                          ? theme.colorScheme.error
                          : pending
                              ? semantic.warning
                              : semantic.textMuted,
                ),
          title: Text(_resultTitle(a),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500)),
          subtitle: Text(_resultSubtitle(a),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: semantic.textMuted)),
          trailing: effectLabel != null
              ? Text(effectLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: effectColor, fontWeight: FontWeight.w500))
              : pending
                  ? Text('待确认',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: semantic.warning))
                  : null,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text('技术详情',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w500)),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('工具: ${a.call.name}\n参数: $args',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontFamily: 'monospace')),
            ),
            const SizedBox(height: 4),
            if (a.code != null && a.code!.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('结果码: ${a.code}',
                    style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace', color: effectColor)),
              ),
            if (effect == ToolEffect.unknown)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('结果无法确认，请先检查目标状态再重试。'),
                ),
              ),
            if (a.code != null && a.code!.isNotEmpty) const SizedBox(height: 4),
            if (a.result != null && a.result!.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '输出: ${a.result}',
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontFamily: 'monospace'),
                ),
              ),
          ],
        ),
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
