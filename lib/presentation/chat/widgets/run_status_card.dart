import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';

class RunStatusCard extends StatelessWidget {
  const RunStatusCard({
    super.key,
    required this.stage,
    required this.toolCount,
    required this.paused,
    required this.awaitingApproval,
    required this.onStop,
  });

  final String stage;
  final int toolCount;
  final bool paused;
  final bool awaitingApproval;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone =
        awaitingApproval || paused ? AppPalette.warning : AppPalette.brand;
    final surface = isDark ? AppPalette.darkSurface : AppPalette.lightSurface;
    final icon = awaitingApproval
        ? Icons.verified_user_outlined
        : paused
            ? Icons.pause_circle_outline
            : Icons.auto_awesome_outlined;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        border: Border.all(color: tone.withValues(alpha: .38)),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: tone),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(stage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                toolCount == 0 ? '正在准备执行' : '已调用 $toolCount 个工具',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppPalette.darkTextMuted
                      : AppPalette.lightTextMuted,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '停止执行',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.stop_circle_outlined),
          color: AppPalette.danger,
          onPressed: onStop,
        ),
      ]),
    );
  }
}
