import '../theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// 降级为平面的 Surface 容器组件。
/// 保留所有公开参数以保持向后兼容，内部不再渲染高斯模糊、渐变与彩色阴影。
class ImmersiveSurface extends StatelessWidget {
  const ImmersiveSurface({
    super.key,
    required this.child,
    @Deprecated('视觉规范已改为平面，该参数已忽略')
    this.level = ImmersiveMaterialLevel.regular,
    this.borderRadius,
    this.padding,
    this.margin,
    @Deprecated('视觉规范已改为平面，勿再传入')
    this.showGlow = false,
    @Deprecated('视觉规范已改为平面，勿再传入')
    this.blur = true,
    @Deprecated('视觉规范已改为平面，勿再传入')
    this.gradient,
    @Deprecated('视觉规范已改为平面，勿再传入')
    this.boxShadow,
  });

  final Widget child;
  final ImmersiveMaterialLevel level;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool showGlow;
  final bool blur;
  final Gradient? gradient;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.circular(AppTokens.radiusCard);
    final hairline =
        isDark ? AppPalette.darkHairline : AppPalette.lightHairline;

    // 旧的 level 表达「材质模糊档位」，现在改为表达「表面层级」：
    // 不是所有容器都长一样，否则界面失去主次节奏。
    late final Color fill;
    late final bool outlined;
    late final List<BoxShadow> shadows;

    switch (level) {
      case ImmersiveMaterialLevel.ultraThin:
      case ImmersiveMaterialLevel.thin:
        // 内嵌的次要面：浅灰底、无描边（聊天页输入区、工具活动条）
        fill = isDark ? AppPalette.darkCanvas : AppPalette.lightSurface;
        outlined = false;
        shadows = const [];
      case ImmersiveMaterialLevel.regular:
        // 卡片：纯白底 + hairline 描边
        fill = isDark ? AppPalette.darkSurface : AppPalette.lightCanvas;
        outlined = true;
        shadows = const [];
      case ImmersiveMaterialLevel.thick:
      case ImmersiveMaterialLevel.ultraThick:
        // 浮起面：白底 + 描边 + 浮层阴影（顶栏胶囊、Toast、底部弹层）
        fill = isDark ? AppPalette.darkSurface : AppPalette.lightCanvas;
        outlined = true;
        shadows = AppTheme.floatingShadow(isDark);
    }

    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: outlined ? Border.all(color: hairline, width: 1.0) : null,
        boxShadow: shadows,
      ),
      child: child,
    );
  }
}
