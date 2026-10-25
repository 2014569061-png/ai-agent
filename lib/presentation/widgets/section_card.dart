import 'package:flutter/material.dart';

import '../theme/app_appearance_controller.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../theme/desktop_theme.dart';
import 'glass_surface.dart';
import 'nexus_touch_light.dart';
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
    final desktop = DesktopTheme.maybeOf(context);
    if (desktop != null) {
      final radius =
          borderRadius ?? BorderRadius.circular(DesktopTheme.panelRadius);
      final paddedChild =
          padding == null ? child : Padding(padding: padding!, child: child);
      final litChild = NexusTouchLightScope(child: paddedChild);
      return Container(
        margin: margin,
        decoration: BoxDecoration(
          color: desktop.panel,
          borderRadius: radius,
          border: Border.all(color: desktop.border, width: 1.0),
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: litChild,
        ),
      );
    }
    final radius = borderRadius ?? BorderRadius.circular(24);
    final paddedChild =
        padding == null ? child : Padding(padding: padding!, child: child);
    // M4：卡片内所有 InkWell 的水波纹替换为按压光斑（按档位自动降级）。
    final litChild = NexusTouchLightScope(child: paddedChild);
    final intensity = AppAppearanceController.resolvedGlassIntensity;
    final shouldUseGlass = (glass ?? false) && intensity != GlassIntensity.flat;

    if (shouldUseGlass) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return GlassSurface(
        role: role,
        variant: variant,
        intensity: intensity,
        borderRadius: radius,
        margin: margin,
        borderColor:
            isDark ? AppPalette.darkHairline : AppPalette.lightHairline,
        tint: isDark
            ? AppPalette.darkSurface.withValues(alpha: 0.90)
            : Colors.white.withValues(alpha: 0.97),
        boxShadow: const [],
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: litChild,
        ),
      );
    }

    if (solid) {
      final theme = Theme.of(context);
      // 卡片用纯白底 + hairline 描边；padding 置于 Material 圆角裁切内部，避免圆角切到左上角首字。
      final base = theme.colorScheme.surface;
      final border = theme.colorScheme.outlineVariant;

      return Container(
        margin: margin,
        decoration: BoxDecoration(
          color: base,
          borderRadius: radius,
          border: Border.all(color: border.withValues(alpha: .45), width: .7),
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: litChild,
        ),
      );
    }

    return NexusSurface(
      margin: margin,
      padding: padding,
      level: SurfaceLevel.regular,
      borderRadius: radius,
      child: litChild,
    );
  }
}
