import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color bg;
    Color fg;

    switch (tone) {
      case NexusBadgeTone.brand:
        bg = isDark ? AppPalette.darkBrandSoft : AppPalette.lightBrandSoft;
        fg = AppPalette.brand;
        break;
      case NexusBadgeTone.success:
        bg = isDark ? AppPalette.darkSuccessSoft : AppPalette.lightSuccessSoft;
        fg = AppPalette.success;
        break;
      case NexusBadgeTone.warning:
        bg = isDark ? AppPalette.darkWarningSoft : AppPalette.lightWarningSoft;
        fg = AppPalette.warning;
        break;
      case NexusBadgeTone.danger:
        bg = isDark ? AppPalette.darkDangerSoft : AppPalette.lightDangerSoft;
        fg = AppPalette.danger;
        break;
      case NexusBadgeTone.neutral:
        bg = isDark ? AppPalette.darkSurfaceHover : AppPalette.lightSurfaceHover;
        fg = isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
        break;
    }

    Widget content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
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
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: fg,
              height: 1.2,
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        child: content,
      );
    }
    return content;
  }
}
