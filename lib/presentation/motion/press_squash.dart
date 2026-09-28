import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'motion_preferences.dart';
import 'nexus_spring.dart';

/// 按压缩放档位（L1）：元素越大缩得越少，避免宽行边缘位移过大显得晃。
abstract final class NexusPressScale {
  /// 按钮、图标按钮、药丸标签。
  static const double button = 0.94;

  /// 卡片、磁贴、玻璃面板。
  static const double card = 0.97;

  /// 整行列表项（宽度接近屏宽）。
  static const double row = 0.985;
}

/// 共享的压缩 / 回弹驱动：按下用 [NexusSprings.snappy] 压缩，松手用
/// [NexusSprings.release] 回弹并轻微越过 1.0。弹簧控制器首次按下时才创建，
/// 列表里大量静止元素不占用 Ticker。reduced / off 下不缩放。
mixin _SquashDriver<T extends StatefulWidget> on State<T>, TickerProvider {
  SpringController? _spring;

  static const Animation<double> _still = AlwaysStoppedAnimation<double>(1);

  Animation<double> get squash => _spring ?? _still;

  bool _allowed() =>
      MotionPreferences.levelOf(context, listen: false) == MotionLevel.full;

  void squashTo(double scale) {
    if (!_allowed()) return;
    var spring = _spring;
    if (spring == null) {
      spring = _spring = SpringController(vsync: this, value: 1);
      setState(() {}); // 首次按下：AnimatedBuilder 换成真实的弹簧动画。
    }
    spring.animateTo(scale,
        spring: NexusSpringPolicy.resolve(context, NexusSprings.snappy,
            listen: false));
  }

  void releaseSquash() {
    final spring = _spring;
    if (spring == null || spring.target == 1) return;
    spring.animateTo(1,
        spring: NexusSpringPolicy.resolve(context, NexusSprings.release,
            listen: false));
  }

  @override
  void dispose() {
    _spring?.dispose();
    super.dispose();
  }

  Widget buildSquash(Widget child) => AnimatedBuilder(
        animation: squash,
        child: child,
        builder: (context, child) {
          final s = squash.value;
          return Transform.scale(
            scale: s,
            filterQuality: s == 1 ? null : FilterQuality.low,
            child: child,
          );
        },
      );
}

/// 手势中立的按压缩放（L1）：只监听指针，不参与手势竞技场，所以可以包在
/// InkWell / ListTile / 任意可点元素外面而不改变点击、长按与滚动行为。
/// 手指移动超过 [kTouchSlop]（开始滚动）即取消压缩。
class PressSquash extends StatefulWidget {
  const PressSquash({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = NexusPressScale.card,
  });

  final Widget child;
  final bool enabled;
  final double scale;

  @override
  State<PressSquash> createState() => _PressSquashState();
}

class _PressSquashState extends State<PressSquash>
    with SingleTickerProviderStateMixin, _SquashDriver {
  int? _pointer;
  Offset _origin = Offset.zero;

  void _down(PointerDownEvent event) {
    if (!widget.enabled || _pointer != null) return;
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    _pointer = event.pointer;
    _origin = event.position;
    squashTo(widget.scale);
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    if ((event.position - _origin).distance > kTouchSlop) _up(event);
  }

  void _up(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    releaseSquash();
  }

  @override
  void didUpdateWidget(covariant PressSquash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _pointer != null) {
      _pointer = null;
      releaseSquash();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: buildSquash(widget.child),
      );
}

/// 由外部按压状态驱动的缩放（L1），用于 Material 按钮的
/// `ButtonStyle.foregroundBuilder`（`WidgetState.pressed`）与 GlassSurface。
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.pressed,
    required this.child,
    this.scale = NexusPressScale.button,
  });

  final bool pressed;
  final Widget child;
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale>
    with SingleTickerProviderStateMixin, _SquashDriver {
  @override
  void didUpdateWidget(covariant PressScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pressed == oldWidget.pressed) return;
    if (widget.pressed) {
      squashTo(widget.scale);
    } else {
      releaseSquash();
    }
  }

  @override
  Widget build(BuildContext context) => buildSquash(widget.child);
}

/// 全局按钮按压样式（L1）：并入主题的各类按钮 style，所有 Filled / Elevated /
/// Outlined / Text / Icon 按钮的前景按下压缩、松手回弹。
abstract final class NexusPressStyle {
  static const ButtonStyle squash =
      ButtonStyle(foregroundBuilder: squashForeground);

  static Widget squashForeground(
    BuildContext context,
    Set<WidgetState> states,
    Widget? child,
  ) =>
      PressScale(
        pressed: states.contains(WidgetState.pressed),
        child: child ?? const SizedBox.shrink(),
      );

  /// 在已有样式上叠加按压缩放（保留调用方自定义的 foregroundBuilder）。
  static ButtonStyle apply(ButtonStyle style) => style.foregroundBuilder != null
      ? style
      : style.copyWith(foregroundBuilder: squashForeground);
}
