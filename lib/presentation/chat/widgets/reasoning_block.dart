import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../markdown/math_block.dart';

/// 思考过程折叠区：默认收起，浅色底与正文区分，避免抢占用户注意力。
class ReasoningBlock extends StatelessWidget {
  const ReasoningBlock({super.key, required this.reasoning});

  final String reasoning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: const Color(0xFF9333EA).withValues(alpha: 0.8),
            width: 3,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9333EA).withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          leading: const Icon(Icons.psychology_outlined, size: 18),
          title: const Text('思考过程',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          subtitle: Text('${reasoning.length} 字',
              style: TextStyle(fontSize: 10, color: theme.colorScheme.outline)),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: MathMarkdown(
                data: reasoning,
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
          ],
        ),
      ),
    );
  }
}
