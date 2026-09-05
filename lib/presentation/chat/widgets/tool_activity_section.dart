import 'package:flutter/material.dart';

import '../../../application/chat_controller.dart';
import '../../theme/app_tokens.dart';
import '../../../presentation/widgets/tool_call_card.dart';

/// 工具执行明细折叠卡：运行时默认展开当前执行中的工具卡片。
class ToolActivitySection extends StatelessWidget {
  const ToolActivitySection({
    super.key,
    required this.activities,
    required this.running,
  });

  final List<ToolActivity> activities;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 2.0),
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.smallControlRadius)),
        child: ExpansionTile(
          title: Text(
            '工具执行明细 (${activities.length})',
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          childrenPadding: const EdgeInsets.only(bottom: 8.0),
          children: activities
              .map((activity) => ToolCallCard(
                    activity: activity,
                    initiallyExpanded: running && activity.status == '执行中',
                  ))
              .toList(),
        ),
      ),
    );
  }
}
