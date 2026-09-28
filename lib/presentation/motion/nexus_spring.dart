import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'motion_preferences.dart';
import 'motion_tier.dart';
import 'nexus_motion.dart';

/// 灵动动效 v2 的弹簧 Token（L0）。
///
/// 所有交互动画统一由弹簧驱动：时长来自物理参数，可随时打断并**保留速度**。
/// 参数用「响应时间 response（无阻尼周期）+ 阻尼比 ratio」描述，换算为
/// `stiffness = (2π / response)²`、`damping = 2 · ratio · √stiffness`（mass = 1）。
///
/// | Token | response | ratio | 过冲 | 落定 | 用途 |
/// |---|---|---|---|---|---|
/// | [snappy] | 0.22s | 0.86 | ≈0.5% | ≈0.17s | 按压、开关、选中 |
/// | [bouncy] | 0.28s | 0.69 | ≈5% | ≈0.31s | 弹出、回弹、图标切换 |
/// | [smooth] | 0.30s | 0.92 | ≈0.1% | ≈0.28s | 形变、尺寸、弹层、页面 |
/// | [release] | 0.30s | 0.52 | ≈15% | ≈0.44s | 按压松手回弹（L1） |
abstract final class NexusSprings {
  static SpringDescription fromResponse(double response, double ratio) {
    final omega = 2 * math.pi / response;
    return SpringDescription(
      mass: 1,
      stiffness: omega * omega,
      damping: 2 * ratio * omega,
    );
  }

  /// 按压、开关、选中：几乎不过冲，干脆。
  static final SpringDescription snappy = fromResponse(0.22, 0.86);

  /// 弹出、松手回弹、图标切换：约 5% 过冲。
  static final SpringDescription bouncy = fromResponse(0.28, 0.69);

  /// 形变、尺寸变化、弹层与页面：无明显过冲。
  static final SpringDescription smooth = fromResponse(0.30, 0.92);

  /// 按压松手回弹（L1）：偏软、过冲约 15%（相对压缩深度），让元素「弹回来」。
  static final SpringDescription release = fromResponse(0.30, 0.52);

  /// 减少动态效果：临界阻尼、更短，无过冲。
  static final SpringDescription reduced = fromResponse(0.18, 1.0);

  /// 阻尼比 ζ = c / (2√(mk))。
  static double ratioOf(SpringDescription s) =>
      s.damping / (2 * math.sqrt(s.mass * s.stiffness));

  static final Map<SpringDescription, SpringDescription> _critical =
      Map.identity();

  /// 同刚度、阻尼比提升到 1（去掉过冲），结果按实例缓存。
  static SpringDescription critical(SpringDescription s) {
    if (ratioOf(s) >= 1) return s;
    return _critical[s] ??= SpringDescription(
      mass: s.mass,
      stiffness: s.stiffness,
      damping: 2 * math.sqrt(s.mass * s.stiffness),
    );
  }

  static final Map<SpringDescription, NexusSpringCurve> _curves =
      Map.identity();
  static final Map<SpringDescription, NexusSpringCurve> _overshootCurves =
      Map.identity();

  /// 把弹簧换成固定时长曲线（供 AnimatedSize 等只接受 Curve 的 API）。
  static NexusSpringCurve curveOf(SpringDescription s,
          {bool allowOvershoot = false}) =>
      allowOvershoot
          ? (_overshootCurves[s] ??= NexusSpringCurve(s, allowOvershoot: true))
          : (_curves[s] ??= NexusSpringCurve(s));

  /// 弹簧从 0 到 1 的落定时长。
  static Duration settleOf(SpringDescription s) =>
      Duration(microseconds: (curveOf(s).settleSeconds * 1000000).round());
}

/// 按当前动效等级 / 档位把弹簧 Token 解析为实际使用的弹簧。
///
/// - full + high / mid：原样
/// - full + low：去掉过冲（[NexusSprings.critical]）
/// - reduced：[NexusSprings.reduced]
/// - off：`null`，调用方直接跳到终值
abstract final class NexusSpringPolicy {
  static SpringDescription? resolve(
    BuildContext context,
    SpringDescription spring, {
    bool listen = true,
  }) {
    final level = MotionPreferences.levelOf(context, listen: listen);
    return resolveFor(
        level, MotionTierScope.of(context, listen: listen), spring);
  }

  static SpringDescription? resolveFor(
    MotionLevel level,
    MotionTier tier,
    SpringDescription spring,
  ) =>
      switch (level) {
        MotionLevel.off => null,
        MotionLevel.reduced => NexusSprings.reduced,
        MotionLevel.full =>
          tier == MotionTier.low ? NexusSprings.critical(spring) : spring,
      };
}

/// 可打断、保留速度的弹簧驱动器（L0）。
///
/// 包装一个无界 [AnimationController]：每次 [animateTo] 都从**当前值与当前速度**
/// 出发重新求解弹簧，所以连续快速点按、动画中途反向都不会跳变或重新起步。
/// 拖拽松手时把手势速度传给 [velocity]，停止位置就会跟随甩动力度。
class SpringController extends Animation<double>
    with AnimationLocalListenersMixin, AnimationLocalStatusListenersMixin {
  SpringController({required TickerProvider vsync, double value = 0})
      : _controller =
            AnimationController.unbounded(vsync: vsync, value: value) {
    _controller
      ..addListener(notifyListeners)
      ..addStatusListener(notifyStatusListeners);
  }

  final AnimationController _controller;
  double _target = 0;

  @override
  double get value => _controller.value;

  @override
  AnimationStatus get status => _controller.status;

  /// 当前速度（单位 / 秒）；静止时为 0。
  double get velocity => _controller.isAnimating ? _controller.velocity : 0;

  double get target => _target;
  @override
  bool get isAnimating => _controller.isAnimating;

  /// 以 [spring] 弹向 [target]。[spring] 为 null（动效关闭）时直接跳到终值。
  /// [velocity] 缺省时沿用当前速度，实现无缝衔接。
  TickerFuture animateTo(
    double target, {
    required SpringDescription? spring,
    double? velocity,
  }) {
    _target = target;
    if (spring == null) {
      _controller.value = target;
      return TickerFuture.complete();
    }
    return _controller.animateWith(
      NexusMotion.spring(
        spring,
        from: _controller.value,
        to: target,
        velocity: velocity ?? this.velocity,
      ),
    );
  }

  /// 立即设置数值并停止动画（拖拽跟手时使用）。
  void jumpTo(double value) {
    _target = value;
    _controller.value = value;
  }

  void stop() => _controller.stop();

  @override
  void didRegisterListener() {}

  @override
  void didUnregisterListener() {}

  void dispose() {
    _controller.dispose();
    clearListeners();
    clearStatusListeners();
  }
}

/// 隐式弹簧数值（L0）：[value] 变化时以弹簧平滑过渡，中途变化保留速度。
///
/// ```dart
/// SpringValue(
///   value: pressed ? 0.96 : 1,
///   spring: NexusSprings.bouncy,
///   builder: (context, scale, child) =>
///       Transform.scale(scale: scale, child: child),
///   child: card,
/// )
/// ```
class SpringValue extends StatefulWidget {
  const SpringValue({
    super.key,
    required this.value,
    required this.builder,
    this.spring,
    this.child,
    this.onSettled,
  });

  final double value;

  /// 缺省为 [NexusSprings.smooth]。
  final SpringDescription? spring;
  final ValueWidgetBuilder<double> builder;
  final Widget? child;

  /// 每次到达目标值后回调（打断不回调）。
  final VoidCallback? onSettled;

  @override
  State<SpringValue> createState() => _SpringValueState();
}

class _SpringValueState extends State<SpringValue>
    with SingleTickerProviderStateMixin {
  late final SpringController _spring =
      SpringController(vsync: this, value: widget.value);

  @override
  void didUpdateWidget(covariant SpringValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == _spring.target) return;
    final spring = NexusSpringPolicy.resolve(
      context,
      widget.spring ?? NexusSprings.smooth,
      listen: false,
    );
    _spring.animateTo(widget.value, spring: spring).orCancel.then(
          (_) => widget.onSettled?.call(),
          onError: (Object _) {},
        );
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _spring,
        child: widget.child,
        builder: (context, child) =>
            widget.builder(context, _spring.value, child),
      );
}

/// 弹簧版 [AnimatedSize]（L0）：尺寸变化用 [NexusSprings.smooth] 曲线，
/// 按动效等级自动缩短或关闭。适合流式输出、卡片展开等高度变化。
class SpringAnimatedSize extends StatelessWidget {
  const SpringAnimatedSize({
    super.key,
    required this.child,
    this.spring,
    this.alignment = Alignment.topCenter,
    this.clipBehavior = Clip.hardEdge,
  });

  final Widget child;
  final SpringDescription? spring;
  final AlignmentGeometry alignment;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final resolved =
        NexusSpringPolicy.resolve(context, spring ?? NexusSprings.smooth);
    if (resolved == null) return child;
    return AnimatedSize(
      duration: NexusSprings.settleOf(resolved),
      curve: NexusSprings.curveOf(resolved),
      alignment: alignment,
      clipBehavior: clipBehavior,
      child: child,
    );
  }
}
