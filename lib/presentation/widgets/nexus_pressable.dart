import 'package:flutter/material.dart';

import '../motion/motion_preferences.dart';
import '../motion/nexus_motion.dart';

/// NEXUS 统一的按下反馈容器。
///
/// 按下反馈必须在 touch-down 发生时立即出现，不能等到 onTap 执行后才变化。
/// 该组件只负责轻微缩放，不附加语义，调用方仍可保留自己的 Semantics / Tooltip。
class NexusPressable extends StatefulWidget {
  const NexusPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.97,
    this.borderRadius,
    this.behavior = HitTestBehavior.deferToChild,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final BorderRadius? borderRadius;
  final HitTestBehavior behavior;

  @override
  State<NexusPressable> createState() => _NexusPressableState();
}

class _NexusPressableState extends State<NexusPressable> {
  var _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null && widget.onLongPress == null) {
      return widget.child;
    }

    final reduceMotion = MotionPreferences.shouldReduceMotion(context);
    final scale = reduceMotion || !_pressed ? 1.0 : widget.pressedScale;

    return GestureDetector(
      behavior: widget.behavior,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: scale,
        duration: reduceMotion
            ? Duration.zero
            : (_pressed ? NexusMotion.instant : NexusMotion.fast),
        curve: _pressed ? Curves.easeOutCubic : NexusMotion.curveSpring,
        child: widget.child,
      ),
    );
  }
}
