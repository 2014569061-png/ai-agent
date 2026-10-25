import 'package:flutter/material.dart';

import '../theme/desktop_theme.dart';
import '../theme/mobile_theme.dart';

/// 画布背景：纯色画布基底，在开启液态玻璃时提供中性微色阶渐变，
/// 为浮动玻璃面板提供物理光影折射基底，同时消灭彩色光斑对卡片边界对比度的干扰。
class NexusBackground extends StatelessWidget {
  const NexusBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final desktop = DesktopTheme.maybeOf(context);
    if (desktop != null) return ColoredBox(color: desktop.canvas, child: child);
    return MobileCanvas(child: child);
  }
}
