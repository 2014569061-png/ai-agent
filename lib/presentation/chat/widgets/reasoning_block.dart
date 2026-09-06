import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../markdown/math_block.dart';

/// G1 思考过程紧凑块:指标 Pill 与"思考"chip 同行(右对齐),点击在下方
/// 展开/收起思考内容——不再以常驻大卡抢占消息头部空间。
class ReasoningCompactBlock extends StatefulWidget {
  const ReasoningCompactBlock({super.key, required this.reasoning, this.leading});

  final String reasoning;
  final Widget? leading;

  @override
  State<ReasoningCompactBlock> createState() => _ReasoningCompactBlockState();
}

class _ReasoningCompactBlockState extends State<ReasoningCompactBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (widget.leading != null) widget.leading!,
            const Spacer(),
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.brandGradientEnd.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.psychology_outlined,
                      size: 13, color: AppTheme.brandGradientEnd),
                  const SizedBox(width: 4),
                  Text('思考 ${widget.reasoning.length} 字',
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant)),
                  AnimatedRotation(
                    turns: _expanded ? .5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(Icons.expand_more_rounded,
                        size: 14, color: theme.colorScheme.outline),
                  ),
                ]),
              ),
            ),
          ],
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(
                    color: AppTheme.brandGradientEnd.withValues(alpha: 0.8),
                    width: 3,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: MathMarkdown(
                    data: widget.reasoning,
                    selectable: true,
                    textColor: theme.colorScheme.onSurfaceVariant,
                    styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                      p: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                      blockSpacing: 6,
                    ),
                  ),
                ),
              ),
            ),
          ),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 180),
        ),
      ],
    );
  }
}
