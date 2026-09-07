import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

class ImmersiveSurface extends StatelessWidget {
  const ImmersiveSurface({
    super.key,
    required this.child,
    this.level = ImmersiveMaterialLevel.regular,
    this.borderRadius,
    this.padding,
    this.margin,
    this.showGlow = false,
    this.blur = true,
    this.gradient,
    this.boxShadow,
  });

  final Widget child;
  final ImmersiveMaterialLevel level;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool showGlow;
  final bool blur;

  /// 提供时替代纯色填充；颜色需自带透明度以透出模糊背景。
  final Gradient? gradient;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.circular(AppTokens.cardRadius);
    final base = isDark ? AppTheme.darkElevated : AppTheme.lightElevated;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final enabled = blur && !MediaQuery.of(context).disableAnimations;
    final shadow =
        boxShadow ?? (showGlow ? AppTheme.floatingShadow(isDark) : null);
    final content = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null
            ? base.withValues(alpha: AppTokens.surfaceOpacity(level, isDark))
            : null,
        gradient: gradient,
        borderRadius: radius,
        border: Border.all(color: border.withValues(alpha: .78)),
      ),
      child: child,
    );

    final surface = ClipRRect(
      borderRadius: radius,
      child: enabled
          ? BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: AppTokens.blurSigma(level),
                sigmaY: AppTokens.blurSigma(level),
              ),
              child: content,
            )
          : content,
    );

    // 阴影必须画在裁剪层之外，否则会被 ClipRRect 裁掉只剩玻璃后的残影。
    return shadow == null
        ? surface
        : DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: shadow,
            ),
            child: surface,
          );
  }
}
