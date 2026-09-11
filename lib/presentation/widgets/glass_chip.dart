import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// 降级为平面 Chip（白底/暗底 + 1px hairline + radiusPill）
class GlassChip extends StatelessWidget {
  const GlassChip({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.selected = false,
    this.minHeight = 36.0,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool selected;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hairline =
        isDark ? AppPalette.darkHairline : AppPalette.lightHairline;
    final normalBg = isDark ? AppPalette.darkSurface : AppPalette.lightCanvas;
    final selectedBg =
        isDark ? AppPalette.darkBrandSoft : AppPalette.lightBrandSoft;
    final normalTextColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    const selectedTextColor = AppPalette.brandOnSoft;

    final bg = selected ? selectedBg : normalBg;
    final border = selected ? selectedBg : hairline;
    final textColor = selected ? selectedTextColor : normalTextColor;

    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        side: BorderSide(color: border, width: 1.0),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: textColor),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    height: 1.4,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
