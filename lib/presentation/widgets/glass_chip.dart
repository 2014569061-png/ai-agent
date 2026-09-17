import 'package:flutter/material.dart';
import '../theme/app_appearance_controller.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import 'glass_surface.dart';

/// 液态玻璃 Chip，在 flat 模式下平滑降级为平面 Chip（白底/暗底 + 1px hairline + radiusPill）
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
    final intensity = AppAppearanceController.resolvedGlassIntensity;
    final isGlass = intensity != GlassIntensity.flat;
    final pillRadius = BorderRadius.circular(AppTokens.radiusPill);

    final chipBody = ConstrainedBox(
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
    );

    if (isGlass) {
      return GlassSurface(
        role: GlassRole.control,
        variant: selected ? GlassVariant.prominent : GlassVariant.clear,
        intensity: intensity,
        borderRadius: pillRadius,
        tint: selected
            ? (isDark
                ? AppPalette.darkBrandSoft.withValues(alpha: 0.80)
                : AppPalette.lightBrandSoft.withValues(alpha: 0.85))
            : (isDark
                ? AppPalette.darkSurface.withValues(alpha: 0.32)
                : AppPalette.lightCanvas.withValues(alpha: 0.28)),
        borderColor: selected ? AppPalette.brand.withValues(alpha: 0.6) : null,
        gloss: selected ? 0.60 : 0.45,
        onTap: onPressed,
        interactive: onPressed != null,
        child: chipBody,
      );
    }

    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: pillRadius,
        side: BorderSide(color: border, width: 1.0),
      ),
      child: InkWell(
        borderRadius: pillRadius,
        onTap: onPressed,
        child: chipBody,
      ),
    );
  }
}
