import 'package:flutter/material.dart';

import '../theme/app_appearance_controller.dart';
import '../theme/app_palette.dart';
import 'liquid_glass.dart';

/// 画布背景：纯色画布基底，在开启液态玻璃时提供中性微色阶渐变，
/// 为浮动玻璃面板提供物理光影折射基底，同时消灭彩色光斑对卡片边界对比度的干扰。
class NexusBackground extends StatelessWidget {
  const NexusBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canvasColor = isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas;
    final intensity = AppAppearanceController.resolvedGlassIntensity;

    if (intensity == GlassIntensity.flat) {
      return ColoredBox(
        color: canvasColor,
        child: child,
      );
    }

    // 中性微渐变底色 (Neutral Ambient Gradient)：
    // 在深浅模式下提供中性、克制的微色彩梯度，为 LiquidGlass 的透镜折射提供物理光影基底，
    // 同时消除多色光斑导致的对比度剧烈波动（浅色 #FAFBFC → #F4F6F9，深色 #141722 → #0F121C）。
    final gradientColors = isDark
        ? const [
            Color(0xFF141722), // 顶端深冷中性底
            Color(0xFF0F121C), // 底端中性幽夜
          ]
        : const [
            Color(0xFFFAFBFC), // 顶端清爽中性冷白
            Color(0xFFF4F6F9), // 底端中性淡灰
          ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: canvasColor,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradientColors,
        ),
      ),
      child: child,
    );
  }
}
