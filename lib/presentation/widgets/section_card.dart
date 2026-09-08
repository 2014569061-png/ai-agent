import 'package:flutter/material.dart';

import 'immersive_surface.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// 统一的内容分段卡片 (SectionCard)
/// 遵循三档表面策略之「A. 内容层」：默认采用近实色 elevated 面与轻边框，
/// 避免在长列表、任务列表、设置页中每个卡片都重复执行高斯模糊 BackdropFilter。
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.margin = EdgeInsets.zero,
    this.padding,
    this.solid = true,
    this.borderRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry? padding;
  final bool solid;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(AppTokens.cardRadius);

    if (solid) {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      final base = isDark ? AppTheme.darkElevated : AppTheme.lightElevated;
      final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;

      return Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          color: base.withValues(alpha: isDark ? 0.88 : 0.94),
          borderRadius: radius,
          border: Border.all(
            color: border.withValues(alpha: isDark ? 0.75 : 0.8),
            width: 0.9,
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

    return ImmersiveSurface(
      margin: margin,
      padding: padding,
      level: ImmersiveMaterialLevel.regular,
      borderRadius: radius,
      child: child,
    );
  }
}

