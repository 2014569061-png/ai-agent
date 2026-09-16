import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../markdown/math_block.dart';
import '../../motion/motion_preferences.dart';
import '../../motion/nexus_motion.dart';
import '../../theme/app_palette.dart';

/// 思考过程折叠块（工程级 REASONING 卡片）。
///
/// 标头显示：REASONING [^] + 耗时统计 + 步数进度。
/// 点击可折叠或展开完整的思维链分析内容。
class ReasoningCompactBlock extends StatefulWidget {
  const ReasoningCompactBlock({
    super.key,
    required this.reasoning,
    this.duration,
    this.streaming = false,
  });

  final String reasoning;

  /// 思考耗时；为空时只显示「已思考」。
  final Duration? duration;

  /// 正在思考（尚未产出正文）。此时显示呼吸点 + 「正在思考…」。
  final bool streaming;

  @override
  State<ReasoningCompactBlock> createState() => _ReasoningCompactBlockState();
}

class _ReasoningCompactBlockState extends State<ReasoningCompactBlock> {
  bool _expanded = false;

  String get _label {
    final d = widget.duration;
    if (d == null) return widget.streaming ? '正在思考…' : '已思考';
    final seconds = d.inSeconds < 1 ? 1 : d.inSeconds;
    if (seconds < 60) return '已思考（用时 $seconds 秒）';
    return '已思考（用时 ${seconds ~/ 60} 分 ${seconds % 60} 秒）';
  }

  String _formatDuration(Duration? d) {
    if (d == null) return widget.streaming ? '计算中...' : '00:00:01';
    final totalSeconds = d.inSeconds < 1 ? 1 : d.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final hours = minutes ~/ 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final cardBg =
        isDark ? AppPalette.reasoningBgDark : AppPalette.reasoningBgLight;
    final cardBorder = isDark
        ? AppPalette.reasoningBorderDark
        : AppPalette.reasoningBorderLight;

    final hasReasoning = widget.reasoning.trim().isNotEmpty;
    final thinking = widget.streaming && widget.duration == null;
    final reduceMotion = MotionPreferences.shouldReduceMotion(context);
    final animDuration =
        reduceMotion ? Duration.zero : NexusMotion.durationBase(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cardBorder, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标头栏：REASONING [^] + 状态 + 耗时统计
          Semantics(
            button: true,
            expanded: _expanded,
            label: '思考过程：$_label，${_expanded ? '点击收起' : '点击展开'}',
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _expanded = !_expanded);
              },
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // At phone widths the status metadata is optional; keeping the
                    // label and disclosure affordance prevents the card from overflowing.
                    final compact = constraints.maxWidth < 320;
                    return Row(
                      children: [
                        if (thinking)
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: const BoxDecoration(
                              color: AppPalette.brand,
                              shape: BoxShape.circle,
                            ),
                          ),
                        Text(
                          'REASONING',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.06,
                            color: isDark
                                ? const Color(0xFF93C5FD)
                                : AppPalette.brand,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: textMuted,
                            ),
                          ),
                        ),
                        if (!compact) ...[
                          const SizedBox(width: 4),
                          if (thinking)
                            Flexible(
                              fit: FlexFit.loose,
                              child: Text(
                                'Step: 运行中',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                  color: isDark
                                      ? const Color(0xFF34D399)
                                      : AppPalette.success,
                                ),
                              ),
                            ),
                          const SizedBox(width: 4),
                          Text(
                            _formatDuration(widget.duration),
                            maxLines: 1,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10.5,
                              color: textMuted,
                            ),
                          ),
                        ],
                        const SizedBox(width: 4),
                        Text(
                          _expanded ? '[^]' : '[v]',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: textMuted,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          // 展开正文面板或收起时的简略预览
          if (hasReasoning)
            AnimatedSize(
              duration: animDuration,
              curve: NexusMotion.curveStandard,
              alignment: Alignment.topLeft,
              child: _expanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Divider(height: 1, color: cardBorder),
                          const SizedBox(height: 8),
                          _buildReasoningContent(context, theme, textMuted),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }

  Widget _buildReasoningContent(
      BuildContext context, ThemeData theme, Color textMuted) {
    final textStyle = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w400,
      color: textMuted,
      height: 1.5,
      fontFamily: 'monospace',
    );
    if (widget.streaming) {
      return SelectableText(widget.reasoning, style: textStyle);
    }
    return MathMarkdown(
      data: widget.reasoning,
      selectable: true,
      textColor: textMuted,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: textStyle,
        blockSpacing: 6,
        code: textStyle.copyWith(
          fontSize: 11.5,
          fontFamily: 'JetBrains Mono',
        ),
      ),
    );
  }
}
