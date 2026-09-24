import 'package:flutter/material.dart';

import '../motion/motion_preferences.dart';
import '../motion/nexus_motion.dart';
import 'nexus_touch_light.dart';

/// NEXUS 统一的按下反馈容器。
///
/// 按下反馈必须在 touch-down 发生时立即出现，不能等到 onTap 执行后才变化。
/// 该组件负责轻微缩放与跟随手指的按压光斑（M4），不附加语义，调用方仍可
/// 保留自己的 Semantics / Tooltip。低端档、reduced、off 下不画光斑。
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

class _NexusPressableState extends State<NexusPressable>
    with SingleTickerProviderStateMixin {
  var _pressed = false;
  late final AnimationController _light = AnimationController(
    vsync: this,
    duration: NexusMotion.instant,
    reverseDuration: NexusMotion.base,
  );
  final ValueNotifier<Offset?> _lightPosition = ValueNotifier<Offset?>(null);

  @override
  void dispose() {
    _light.dispose();
    _lightPosition.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
    if (!value) _light.reverse();
  }

  void _onDown(Offset localPosition, bool lightEnabled) {
    _setPressed(true);
    if (!lightEnabled) return;
    _lightPosition.value = localPosition;
    _light.forward();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null && widget.onLongPress == null) {
      return widget.child;
    }

    final reduceMotion = MotionPreferences.shouldReduceMotion(context);
    final scale = reduceMotion || !_pressed ? 1.0 : widget.pressedScale;
    final lightEnabled = NexusTouchLight.enabled(context);

    // 包装结构始终存在（档位降级时只是不再画光斑），避免子树被重新挂载。
    final content = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerMove: (event) {
        if (_pressed && lightEnabled) {
          _lightPosition.value = event.localPosition;
        }
      },
      child: CustomPaint(
        foregroundPainter: lightEnabled
            ? NexusPressLightPainter(
                strength: _light,
                position: _lightPosition,
                dark: Theme.of(context).brightness == Brightness.dark,
                borderRadius: widget.borderRadius,
              )
            : null,
        child: widget.child,
      ),
    );

    return GestureDetector(
      behavior: widget.behavior,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (details) => _onDown(details.localPosition, lightEnabled),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: scale,
        duration: reduceMotion
            ? Duration.zero
            : (_pressed ? NexusMotion.instant : NexusMotion.fast),
        curve: _pressed ? Curves.easeOutCubic : NexusMotion.curveSpring,
        child: content,
      ),
    );
  }
}
