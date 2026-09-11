import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../markdown/math_block.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';

/// 思考过程折叠块（对标 DeepSeek）。
///
/// 收起态是一行极简文案 + 右侧小箭头：
///     已思考（用时 6 秒）  ›
/// 点击该行（含箭头）展开思考正文；箭头旋转 90° 指向下方。
///
/// 时长来自 `ChatMessage.reasoningDuration`（首个思考 token → 首个正文 token），
/// 不能用 TTFT 代替——思考流本身会产出 token，TTFT 落在思考的**开始**处。
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
    // 时长一旦结算说明思考已结束。思考中途 duration 仍为 null，
    // 此时必须显示「正在思考…」，不能显示「已思考」。
    if (d == null) return widget.streaming ? '正在思考…' : '已思考';
    // 不足 1 秒时按 1 秒展示，避免出现「用时 0 秒」这种看起来像坏掉的状态。
    final seconds = d.inSeconds < 1 ? 1 : d.inSeconds;
    if (seconds < 60) return '已思考（用时 $seconds 秒）';
    return '已思考（用时 ${seconds ~/ 60} 分 ${seconds % 60} 秒）';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final surface = isDark ? AppPalette.darkSurface : AppPalette.lightSurface;
    final hairline =
        isDark ? AppPalette.darkHairline : AppPalette.lightHairline;

    final hasReasoning = widget.reasoning.trim().isNotEmpty;
    final thinking = widget.streaming && widget.duration == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _expanded = !_expanded);
          },
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (thinking) ...[
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: const BoxDecoration(
                      color: AppPalette.brand,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
                Text(
                  _label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    height: 1.55,
                    color: textMuted,
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _expanded ? 0.25 : 0.0,
                  duration: AppTokens.durationBase,
                  curve: AppTokens.curveStandard,
                  child: Icon(
                    Icons.keyboard_arrow_right_rounded,
                    size: 14,
                    color: textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hasReasoning)
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                  border: Border.all(color: hairline, width: 1.0),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: MathMarkdown(
                    data: widget.reasoning,
                    selectable: true,
                    textColor: textMuted,
                    styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                      p: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: textMuted,
                        height: 1.55,
                      ),
                      blockSpacing: 8,
                      code: TextStyle(
                        fontSize: 12,
                        fontFamily: 'JetBrains Mono',
                        color: textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: AppTokens.durationBase,
            firstCurve: AppTokens.curveStandard,
            secondCurve: AppTokens.curveStandard,
            sizeCurve: AppTokens.curveStandard,
          ),
      ],
    );
  }
}
