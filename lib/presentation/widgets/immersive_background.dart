import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// 降级为纯色画布背景，移除所有渐变与模糊
class ImmersiveBackground extends StatelessWidget {
  const ImmersiveBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas,
      child: child,
    );
  }
}
