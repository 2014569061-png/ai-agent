import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 统一淡入、缩放、展开/折叠的动效 helper。
/// 所有页面的过渡动画都应复用这里的曲线与时长，避免组件各自拼 Tween 造成节奏不统一。
/// 该组件遵循系统降级设置：当系统开启减少动效时自动退化为瞬时切换。
class ImmersiveMotion {
  ImmersiveMotion._();

  /// 内容淡入 + 轻微上移，用于浮层、卡片滑入。
  static Widget fadeIn({
    required Widget child,
    Key? key,
    Duration? duration,
    Curve? curve,
    double offset = 8,
  }) {
    return _ReducedAware(
      duration: duration ?? AppTokens.durationBase,
      curve: curve ?? AppTokens.curveStandard,
      builder: (context, animation, reduced, content) {
        final t = reduced ? 1.0 : animation.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * offset),
            child: content,
          ),
        );
      },
      child: child,
    );
  }

  /// 弹性缩放淡入，用于确认弹窗、模态层进入。
  static Widget scaleIn({
    required Widget child,
    Key? key,
    Duration? duration,
    Curve? curve,
    double begin = 0.92,
  }) {
    return _ReducedAware(
      duration: duration ?? AppTokens.durationModal,
      curve: curve ?? AppTokens.curveEnter,
      builder: (context, animation, reduced, content) {
        final t = reduced ? 1.0 : animation.value;
        return Opacity(
          opacity: t,
          child:
              Transform.scale(scale: begin + (1 - begin) * t, child: content),
        );
      },
      child: child,
    );
  }

  /// 展开/折叠的尺寸过渡外壳。直接包住会随内容尺寸变化的子树。
  static Widget expand({
    required Widget child,
    Key? key,
    Duration? duration,
    Curve? curve,
  }) {
    return AnimatedSize(
      key: key,
      duration: duration ?? AppTokens.durationExpand,
      curve: curve ?? AppTokens.curveExpand,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}

/// 感知系统减少动效设置，将动画退化为瞬时完成。
class _ReducedAware extends StatefulWidget {
  const _ReducedAware({
    required this.duration,
    required this.curve,
    required this.builder,
    required this.child,
  });

  final Widget child;
  final Duration duration;
  final Curve curve;
  final Widget Function(BuildContext, Animation<double>, bool, Widget) builder;

  @override
  State<_ReducedAware> createState() => _ReducedAwareState();
}

class _ReducedAwareState extends State<_ReducedAware>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduced) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return widget.builder(
      context,
      CurvedAnimation(parent: _controller, curve: widget.curve),
      reduced,
      widget.child,
    );
  }
}
