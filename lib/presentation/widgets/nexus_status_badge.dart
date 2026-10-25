import 'package:flutter/material.dart';
import '../theme/app_status_colors.dart';
import '../theme/app_tokens.dart';
import '../motion/micro_interactions.dart';

/// 状态徽章语义色调
enum NexusBadgeTone {
  neutral,
  brand,
  success,
  warning,
  danger,
}

/// 小型语义状态徽章（用于卡片、列表项、服务连接状态）
class NexusStatusBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final NexusBadgeTone tone;
  final bool showDot;
  final VoidCallback? onTap;

  const NexusStatusBadge({
    super.key,
    required this.label,
    this.icon,
    this.tone = NexusBadgeTone.neutral,
    this.showDot = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppStatusColors.resolve(
        context,
        switch (tone) {
          NexusBadgeTone.neutral => AppStatusTone.neutral,
          NexusBadgeTone.brand => AppStatusTone.brand,
          NexusBadgeTone.success => AppStatusTone.success,
          NexusBadgeTone.warning => AppStatusTone.warning,
          NexusBadgeTone.danger => AppStatusTone.danger,
        });
    final bg = colors.background;
    final fg = colors.foreground;
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;

    Widget content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        border: highContrast ? Border.all(color: fg) : null,
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                color: fg,
                shape: BoxShape.circle,
              ),
            ),
          ] else if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
              child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: fg,
              height: 1.2,
            ),
          )),
        ],
      ),
    );

    content = PopOnChange(trigger: (label, tone), child: content);
    content =
        Tooltip(message: label, excludeFromSemantics: true, child: content);
    if (onTap != null) {
      return Semantics(
          button: true,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              child: Center(widthFactor: 1, heightFactor: 1, child: content),
            ),
          ));
    }
    return content;
  }
}
