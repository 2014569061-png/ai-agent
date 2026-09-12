import 'package:flutter/material.dart';

import '../../../domain/session_metrics.dart';
import '../../dashboard/widgets/token_numbers.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';

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
    this.onImageBackground = false,
    this.maxGroups,
  });

  final SessionMetrics metrics;
  final VoidCallback? onTap;

  /// 是否浮在自定义聊天背景图上。为 true 时切深色半透明底。
  final bool onImageBackground;

  /// 强制限制分组数量（键盘弹出等紧凑场景传 2）。
  final int? maxGroups;

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

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onImage = onImageBackground;

    final bg = onImage
        ? AppPalette.darkCanvas.withValues(alpha: 0.72)
        : (isDark ? AppPalette.darkSurface : AppPalette.lightSurface);
    final border = onImage
        ? Colors.transparent
        : (isDark ? AppPalette.darkHairline : AppPalette.lightHairline);
    final labelColor = onImage
        ? AppPalette.darkTextFaint
        : (isDark ? AppPalette.darkTextFaint : AppPalette.lightTextMuted);
    final valueColor = onImage
        ? AppPalette.darkText
        : (isDark ? AppPalette.darkText : AppPalette.lightText);

    return LayoutBuilder(
      builder: (context, constraints) {
        final groups = _buildGroups();
        final limit = _limitFor(constraints.maxWidth);
        final visible = groups.take(limit).toList();
        final hidden = groups.length - visible.length;

        final content = Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppTokens.radiusCard),
            border: Border.all(color: border, width: 1.0),
          ),
          child: Wrap(
            spacing: 14,
            runSpacing: 5,
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
        );

        if (onTap == null) return content;
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
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
                fontFamily: segment.isValue ? 'JetBrains Mono' : null,
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
