import 'package:flutter/material.dart';

import '../theme/app_appearance_controller.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import 'glass_surface.dart';
import 'nexus_surface.dart';

/// 统一的内容分段卡片 (SectionCard)
/// 遵循极简表面策略：实色 surface 与 1px hairline 边框。
/// 当指定 [glass: true] 时，在非 flat 质感模式下平滑升级为液态玻璃卡片。
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.margin = EdgeInsets.zero,
    this.padding,
    this.solid = true,
    this.glass,
    this.role = GlassRole.content,
    this.variant = GlassVariant.regular,
    this.borderRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry? padding;
  final bool solid;
  final bool? glass;
  final GlassRole role;
  final GlassVariant variant;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(AppTokens.radiusCard);
    final intensity = AppAppearanceController.resolvedGlassIntensity;
    final shouldUseGlass = (glass ?? true) && intensity != GlassIntensity.flat;

    if (shouldUseGlass) {
      return GlassSurface(
        role: role,
        variant: variant,
        intensity: intensity,
        borderRadius: radius,
        margin: margin,
        padding: padding,
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      );
    }

    if (solid) {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      // 卡片用纯白底 + hairline 描边；浅灰 surface 只用于悬停 / 分组底，
      // 避免「灰底 + 灰边框」在纯白画布上读成凹陷或禁用态。
      final base = isDark ? AppPalette.darkSurface : AppPalette.lightCanvas;
      final border =
          isDark ? AppPalette.darkHairline : AppPalette.lightHairline;

      return Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          color: base,
          borderRadius: radius,
          border: Border.all(
            color: border,
            width: 1.0,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      );
    }

    return NexusSurface(
      margin: margin,
      padding: padding,
      level: SurfaceLevel.regular,
      borderRadius: radius,
      child: child,
    );
  }
}
