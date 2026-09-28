import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'motion_preferences.dart';
import 'nexus_spring.dart';

/// 图标 / 小部件的状态形变（L1）：新图标以 [NexusSprings.bouncy] 从 0.5 弹到
/// 1.0 并带轻微旋转，旧图标同时缩小淡出。reduced 下只淡入淡出，off 下直接切换。
abstract final class NexusMorph {
  static const double _fromScale = 0.5;
  static const double _fromTurns = -0.08;

  static Duration duration(BuildContext context) =>
      switch (MotionPreferences.levelOf(context)) {
        MotionLevel.off => Duration.zero,
        MotionLevel.reduced => NexusSprings.settleOf(NexusSprings.reduced),
        MotionLevel.full => NexusSprings.settleOf(NexusSprings.bouncy),
      };

  static AnimatedSwitcherTransitionBuilder transition(BuildContext context) {
    if (MotionPreferences.levelOf(context) != MotionLevel.full) {
      return (child, animation) =>
          FadeTransition(opacity: animation, child: child);
    }
    final pop = NexusSprings.curveOf(NexusSprings.bouncy, allowOvershoot: true);
    return (child, animation) {
      final curved = CurvedAnimation(parent: animation, curve: pop);
      return FadeTransition(
        opacity:
            CurvedAnimation(parent: animation, curve: const Interval(0, 0.5)),
        child: ScaleTransition(
          scale: Tween<double>(begin: _fromScale, end: 1).animate(curved),
          child: RotationTransition(
            turns: Tween<double>(begin: _fromTurns, end: 0).animate(curved),
            child: child,
          ),
        ),
      );
    };
  }

  /// 同一位置叠放新旧图标，避免尺寸不同时跳动。
  static Widget layout(Widget? current, List<Widget> previous) => Stack(
        alignment: Alignment.center,
        children: [...previous, if (current != null) current],
      );
}

/// 状态切换时形变的图标：`MorphIcon(copied ? Icons.check : Icons.copy)`。
class MorphIcon extends StatelessWidget {
  const MorphIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  final IconData icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: NexusMorph.duration(context),
        transitionBuilder: NexusMorph.transition(context),
        layoutBuilder: NexusMorph.layout,
        child: Icon(
          icon,
          key: ValueKey<IconData>(icon),
          size: size,
          color: color,
          semanticLabel: semanticLabel,
        ),
      );
}

/// 弹簧旋转（L1）：替代 [AnimatedRotation]，展开箭头翻转时带 5% 回弹。
class SpringTurns extends StatelessWidget {
  const SpringTurns({
    super.key,
    required this.turns,
    required this.child,
    this.spring,
  });

  final double turns;
  final Widget child;
  final SpringDescription? spring;

  @override
  Widget build(BuildContext context) => SpringValue(
        value: turns,
        spring: spring ?? NexusSprings.bouncy,
        child: child,
        builder: (context, t, child) =>
            Transform.rotate(angle: t * 2 * math.pi, child: child),
      );
}
