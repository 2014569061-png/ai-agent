import '../../theme/mobile_theme.dart';
import 'package:flutter/material.dart';

import '../../../domain/context_insights.dart';
import '../../../domain/models.dart';
import '../../../domain/session_metrics.dart';
import '../../../infrastructure/background_service.dart';
import '../../dashboard/widgets/token_numbers.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';
import '../../theme/desktop_theme.dart';
import '../../widgets/desktop_reading_column.dart';
import '../../../application/chat_controller.dart' show ToolActivity;
import 'context_budget_bar.dart';

class SessionMetricsHud extends StatelessWidget {
  const SessionMetricsHud({
    super.key,
    required this.messages,
    required this.totalSteps,
    required this.toolActivities,
    required this.running,
    required this.onTap,
    this.onCompress,
    this.contextSnapshot,
    this.inline = false,
  });

  final List<ChatMessage> messages;
  final int totalSteps;
  final List<ToolActivity> toolActivities;
  final bool running;
  final VoidCallback onTap;

  /// 上下文接近上限时的快捷压缩入口。为 null 时条上不出现该操作。
  final VoidCallback? onCompress;
  final ContextSnapshot? contextSnapshot;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final metrics = SessionMetrics.from(
      messages: messages,
      steps: totalSteps,
      toolExecutionMs: toolActivities.fold<int>(
        0,
        (sum, activity) => sum + activity.executionMs,
      ),
    );
    if (metrics.isEmpty) return const SizedBox.shrink();
    final bar = ValueListenableBuilder<BackgroundConfig>(
      valueListenable: BackgroundService.bgNotifier,
      builder: (context, background, _) => SessionMetricsBar(
        metrics: metrics,
        onImageBackground: background.mode != 'default',
        summaryLabel:
            running ? '运行详情 · 第 $totalSteps 步' : '会话详情 · ${metrics.rounds} 轮',
        maxGroups: 1,
        onTap: onTap,
        onCompress: onCompress,
        contextSnapshot: contextSnapshot,
        inline: inline,
      ),
    );
    if (inline) return bar;
    return DesktopReadingColumn(
        child: Padding(
      padding: EdgeInsets.symmetric(
          horizontal: DesktopTheme.maybeOf(context) != null ? 16 : 12),
      child: bar,
    ));
  }
}

/// 会话级指标条（对标 DeepSeek 输入区上方的指标胶囊）。
///
/// 设计约束：
/// * **有数据才出现**——空会话或纯聊天（无工具调用、只有一轮）直接不渲染，
///   避免在首页制造噪音。
/// * **按优先级裁切**——手机宽度放不下 9 项，按「轮·步 > LLM·工具 > 缓存命中 >
///   输入·输出 > 首 token·速率」的顺序保留，其余进详情弹层。
/// * **背景自适应**——自定义聊天背景图下切深色半透明底，否则白底指标条
///   压在图片上不可读。
/// * 所有数值使用等宽数字（tabular figures），流式刷新时不跳动。
class SessionMetricsBar extends StatelessWidget {
  const SessionMetricsBar({
    super.key,
    required this.metrics,
    this.onTap,
    this.onCompress,
    this.onImageBackground = false,
    this.maxGroups,
    this.summaryLabel,
    this.contextSnapshot,
    this.inline = false,
  });

  final SessionMetrics metrics;
  final VoidCallback? onTap;

  /// 上下文预算达到 warning 及以上时显示的快捷压缩入口。
  final VoidCallback? onCompress;

  /// 是否浮在自定义聊天背景图上。为 true 时切深色半透明底。
  final bool onImageBackground;

  /// 强制限制分组数量（键盘弹出等紧凑场景传 2）。
  final int? maxGroups;
  final String? summaryLabel;
  final ContextSnapshot? contextSnapshot;
  final bool inline;

  /// 分组优先级顺序固定，裁切时从尾部丢弃。
  List<_Group> _buildGroups() {
    final groups = <_Group>[
      const _Group([
        _Segment('rounds', isValue: true),
        _Segment('轮'),
        _Segment('·'),
        _Segment('steps', isValue: true),
        _Segment('步'),
      ]),
      const _Group([
        _Segment('LLM'),
        _Segment('llm', isValue: true),
        _Segment('·'),
        _Segment('工具'),
        _Segment('tool', isValue: true),
      ]),
      if (metrics.cacheHitRate != null)
        const _Group([
          _Segment('缓存命中'),
          _Segment('cache', isValue: true),
        ]),
      if (metrics.totalTokens > 0)
        const _Group([
          _Segment('输入'),
          _Segment('in', isValue: true),
          _Segment('·'),
          _Segment('输出'),
          _Segment('out', isValue: true),
        ]),
      if (metrics.avgTtft != null || metrics.tokensPerSecond > 0)
        const _Group([
          _Segment('首 token'),
          _Segment('ttft', isValue: true),
          _Segment('·'),
          _Segment('rate', isValue: true, accent: true),
        ]),
    ];
    return groups;
  }

  String _text(_Segment segment) {
    switch (segment.key) {
      case 'rounds':
        return '${metrics.rounds}';
      case 'steps':
        return '${metrics.steps}';
      case 'llm':
        return formatDurationLabel(metrics.llmTime);
      case 'tool':
        return formatDurationLabel(metrics.toolTime);
      case 'cache':
        return formatPercent(metrics.cacheHitRate);
      case 'in':
        return '${formatCompact(metrics.promptTokens)} tok';
      case 'out':
        return '${formatCompact(metrics.completionTokens)} tok';
      case 'ttft':
        return metrics.avgTtft == null
            ? '--'
            : formatDurationLabel(metrics.avgTtft);
      case 'rate':
        return formatRate(metrics.tokensPerSecond);
      default:
        return segment.key;
    }
  }

  int _limitFor(double width) {
    if (maxGroups != null) return maxGroups!;
    if (width >= 560) return 5;
    if (width >= 420) return 4;
    if (width >= 340) return 3;
    return 2;
  }

  /// 只有预算达到 warning 及以上、且调用方提供了压缩回调时才显示快捷入口。
  ///
  /// 返回 `attention` / `normal` / 无快照时为 null——避免在预算健康时
  /// 用一条永远点不动的操作占位。
  ContextBudgetLevel? _compressLevel() {
    if (onCompress == null) return null;
    final level = contextSnapshot?.budgetLevel;
    if (level == ContextBudgetLevel.warning ||
        level == ContextBudgetLevel.critical) {
      return level;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final desktop = DesktopTheme.maybeOf(context);
    final onImage = onImageBackground;

    final bg = desktop?.sidebar ??
        (onImage
            ? AppPalette.darkCanvas.withValues(alpha: 0.72)
            : (isDark ? AppPalette.darkSurface : Colors.white));
    final border = desktop?.border ??
        (onImage
            ? Colors.transparent
            : (isDark ? AppPalette.darkHairline : AppPalette.lightHairline));
    final labelColor = desktop?.muted ??
        (onImage
            ? AppPalette.darkTextFaint
            : (isDark ? AppPalette.darkTextFaint : AppPalette.lightTextMuted));
    final valueColor = desktop?.text ??
        (onImage
            ? AppPalette.darkText
            : (isDark ? AppPalette.darkText : AppPalette.lightText));
    final compressLevel = _compressLevel();
    final barRadius =
        BorderRadius.circular(desktop != null ? 8 : AppTokens.radiusPill);

    if (summaryLabel != null) {
      final pill = Container(
        margin: inline ? EdgeInsets.zero : const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: barRadius,
          border: Border.all(color: border, width: 1.0),
        ),
        constraints: const BoxConstraints(minHeight: 30),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: MobileTheme.brand(context),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                summaryLabel!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppTokens.fontSizeCaption,
                  fontWeight: FontWeight.w500,
                  color: desktop != null ? labelColor : valueColor,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: 15, color: labelColor),
          ],
        ),
      );
      if (onTap == null) return pill;
      return InkWell(
        onTap: onTap,
        borderRadius: barRadius,
        child: pill,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final groups = _buildGroups();
        final limit = _limitFor(constraints.maxWidth);
        final visible = groups.take(limit).toList();
        final hidden = groups.length - visible.length;

        final content = Container(
          margin: inline ? EdgeInsets.zero : const EdgeInsets.only(bottom: 6),
          padding: EdgeInsets.symmetric(
              horizontal: 10, vertical: desktop != null ? 5 : 5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: barRadius,
            border: Border.all(color: border, width: 1.0),
          ),
          constraints: const BoxConstraints(minHeight: 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (summaryLabel != null)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: MobileTheme.brand(context),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(summaryLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: AppTokens.fontSizeCaption,
                          fontWeight: FontWeight.w500,
                          color: desktop != null ? labelColor : valueColor)),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded,
                      size: 15, color: labelColor),
                ])
              else
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final group in visible)
                      _buildGroup(group, labelColor, valueColor),
                    if (hidden > 0)
                      Text(
                        '+$hidden',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: labelColor,
                        ),
                      ),
                  ],
                ),
              if (contextSnapshot != null &&
                  (summaryLabel == null ||
                      contextSnapshot!.budgetLevel ==
                          ContextBudgetLevel.warning ||
                      contextSnapshot!.budgetLevel ==
                          ContextBudgetLevel.critical)) ...[
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: ContextBudgetBar.fromParts(
                        key: const ValueKey('session-metrics-context-budget'),
                        parts: contextSnapshot!.parts,
                        limit: contextSnapshot!.contextWindow,
                        reservedOutputTokens:
                            contextSnapshot!.reservedOutputTokens,
                        fallbackRatio: contextSnapshot!.ratio,
                        fallbackColor:
                            contextBudgetColor(contextSnapshot!.budgetLevel),
                        height: 5,
                      ),
                    ),
                    if (compressLevel != null) ...[
                      const SizedBox(width: 8),
                      _CompressAction(
                        urgent: compressLevel == ContextBudgetLevel.critical,
                        onTap: onCompress!,
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        );

        if (onTap == null) return content;
        return InkWell(
          onTap: onTap,
          borderRadius: barRadius,
          child: content,
        );
      },
    );
  }

  Widget _buildGroup(_Group group, Color labelColor, Color valueColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        for (final segment in group.segments)
          Padding(
            padding: EdgeInsets.only(right: segment.key == '·' ? 0 : 3),
            child: Text(
              _text(segment),
              style: TextStyle(
                fontSize: 11,
                fontWeight: segment.isValue ? FontWeight.w500 : FontWeight.w400,
                fontFamily: segment.isValue ? AppTokens.fontFamilyMono : null,
                fontFeatures: segment.isValue
                    ? const [FontFeature.tabularFigures()]
                    : null,
                color: segment.accent
                    ? AppPalette.success
                    : (segment.isValue ? valueColor : labelColor),
              ),
            ),
          ),
      ],
    );
  }
}

class _Segment {
  const _Segment(this.key, {this.isValue = false, this.accent = false});
  final String key;
  final bool isValue;
  final bool accent;
}

class _Group {
  const _Group(this.segments);
  final List<_Segment> segments;
}

/// 指标条上的快捷压缩入口。
///
/// 设计约束：
/// * 只在预算达到 warning 及以上时出现，平时不占位；
/// * 视觉上必须与「点整条打开指标面板」区分开，所以用独立的实心胶囊，
///   并自带 InkWell 抢占点击（外层 InkWell 不会同时触发）；
/// * 文案固定为「压缩上下文」而不是图标——这是不可逆感知较强的操作，
///   用户需要看清它要做什么。
class _CompressAction extends StatelessWidget {
  const _CompressAction({required this.urgent, required this.onTap});

  final bool urgent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = urgent ? AppPalette.danger : AppPalette.warning;
    return Semantics(
      button: true,
      label: '压缩上下文',
      child: Tooltip(
        message: '压缩较早的工具结果，聊天记录不受影响',
        child: Material(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.compress_rounded, size: 13, color: color),
                  const SizedBox(width: 4),
                  Text(
                    '压缩上下文',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
