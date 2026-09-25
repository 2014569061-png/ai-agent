import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../motion/motion_intensity.dart';
import '../motion/motion_preferences.dart';
import '../motion/motion_tier.dart';
import '../motion/nexus_motion.dart';
import '../theme/app_palette.dart';

/// 按压光感（M4）：以触点为中心的径向光斑。
///
/// 参数：touch-down 立即出现，[NexusMotion.instant] 升到峰值；抬起或取消后
/// [NexusMotion.base] 淡出。半径 = 参照区域短边 × [radiusFactor]。
/// 深色：白色中心 α [darkAlpha]，`BlendMode.plus`；浅色：品牌色中心 α
/// [lightAlpha]，正常混合（浅色卡片是纯白底，softLight / 白光都不可见）。
abstract final class NexusTouchLight {
  static const double radiusFactor = 0.9;
  static const double darkAlpha = 0.14;
  static const double lightAlpha = 0.08;

  static const InteractiveInkFeatureFactory lightFactory =
      _NexusTouchLightFactory(dark: false);
  static const InteractiveInkFeatureFactory darkFactory =
      _NexusTouchLightFactory(dark: true);

  /// 当前是否允许绘制光斑：完整动效 + 当前档位预算允许。
  static bool enabled(BuildContext context) =>
      MotionPreferences.levelOf(context) == MotionLevel.full &&
      MotionBudget.of(context).touchLight;

  /// S1：强度增益下的光斑 α 上限（鲜明档深色 0.28 / 浅色 0.16）。
  static const double maxBoostedAlpha = 0.3;

  static Color colorFor({required bool dark, double gain = 1}) => dark
      ? Colors.white
          .withValues(alpha: (darkAlpha * gain).clamp(0.0, maxBoostedAlpha))
      : AppPalette.brand
          .withValues(alpha: (lightAlpha * gain).clamp(0.0, maxBoostedAlpha));

  /// S1：光斑半径随强度放大（鲜明档 ×1.3）。
  static double radiusFor(Size size, {double gain = 1}) =>
      size.shortestSide * amplify(radiusFactor, gain, 0.3);

  static final Map<(bool, double), InteractiveInkFeatureFactory> _factories =
      {};

  /// 按（深浅色, 强度）取工厂；同一组合复用同一实例，主题缓存才能命中。
  static InteractiveInkFeatureFactory factoryFor(
      {required bool dark, double gain = 1}) {
    if (gain == 1) return dark ? darkFactory : lightFactory;
    return _factories[(dark, gain)] ??=
        _NexusTouchLightFactory(dark: dark, gain: gain);
  }

  static Paint paintFor({
    required bool dark,
    required Offset center,
    required double radius,
    required double strength,
    double gain = 1,
  }) {
    final color = colorFor(dark: dark, gain: gain);
    final peak = color.withValues(alpha: color.a * strength.clamp(0.0, 1.0));
    return Paint()
      ..blendMode = dark ? BlendMode.plus : BlendMode.srcOver
      ..shader = RadialGradient(
        colors: [peak, peak.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
  }
}

/// 把子树里 InkWell 的水波纹替换为 [NexusTouchLight]。
///
/// 低端档、reduced、off 下改为 [NoSplash]：只保留系统的静态高亮反馈。
/// 替换后的 [ThemeData] 按「原主题 × 工厂」缓存，避免每张卡片每次重建都复制主题。
class NexusTouchLightScope extends StatelessWidget {
  const NexusTouchLightScope({super.key, required this.child});

  final Widget child;

  static final Expando<Map<InteractiveInkFeatureFactory, ThemeData>> _cache =
      Expando<Map<InteractiveInkFeatureFactory, ThemeData>>();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final factory = !NexusTouchLight.enabled(context)
        ? NoSplash.splashFactory
        : NexusTouchLight.factoryFor(
            dark: theme.brightness == Brightness.dark,
            gain: MotionTierScope.gainOf(context),
          );
    if (identical(theme.splashFactory, factory)) return child;
    final perTheme =
        _cache[theme] ??= <InteractiveInkFeatureFactory, ThemeData>{};
    final data = perTheme[factory] ??= theme.copyWith(splashFactory: factory);
    return Theme(data: data, child: child);
  }
}

class _NexusTouchLightFactory extends InteractiveInkFeatureFactory {
  const _NexusTouchLightFactory({required this.dark, this.gain = 1});

  final bool dark;
  final double gain;

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) {
    return _NexusTouchLightInk(
      controller: controller,
      referenceBox: referenceBox,
      position: position,
      dark: dark,
      gain: gain,
      textDirection: textDirection,
      rectCallback: rectCallback,
      borderRadius: borderRadius,
      customBorder: customBorder,
      onRemoved: onRemoved,
    );
  }
}

class _NexusTouchLightInk extends InteractiveInkFeature {
  _NexusTouchLightInk({
    required MaterialInkController controller,
    required super.referenceBox,
    required Offset position,
    required bool dark,
    double gain = 1,
    required TextDirection textDirection,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    super.customBorder,
    super.onRemoved,
  })  : _position = position,
        _dark = dark,
        _gain = gain,
        _textDirection = textDirection,
        _borderRadius = borderRadius ?? BorderRadius.zero,
        _clipCallback = rectCallback ?? (() => Offset.zero & referenceBox.size),
        super(
          controller: controller,
          color: NexusTouchLight.colorFor(dark: dark, gain: gain),
        ) {
    _strength = AnimationController(
      vsync: controller.vsync,
      duration: NexusMotion.instant,
      reverseDuration: NexusMotion.base,
    )
      ..addListener(controller.markNeedsPaint)
      ..addStatusListener(_handleStatus)
      ..forward();
    controller.addInkFeature(this);
  }

  final Offset _position;
  final bool _dark;
  final double _gain;
  final TextDirection _textDirection;
  final BorderRadius _borderRadius;
  final RectCallback _clipCallback;
  late final AnimationController _strength;
  bool _released = false;

  void _release() {
    if (_released) return;
    _released = true;
    _strength.reverse();
  }

  void _handleStatus(AnimationStatus status) {
    if (_released && status == AnimationStatus.dismissed) dispose();
  }

  @override
  void confirm() => _release();

  @override
  void cancel() => _release();

  @override
  void dispose() {
    _strength.dispose();
    super.dispose();
  }

  @override
  void paintFeature(Canvas canvas, Matrix4 transform) {
    final t = NexusMotion.curveStandard.transform(_strength.value);
    if (t <= 0) return;
    final radius = NexusTouchLight.radiusFor(referenceBox.size, gain: _gain);
    paintInkCircle(
      canvas: canvas,
      transform: transform,
      paint: NexusTouchLight.paintFor(
        dark: _dark,
        center: _position,
        radius: radius,
        strength: t,
        gain: _gain,
      ),
      center: _position,
      radius: radius,
      textDirection: _textDirection,
      customBorder: customBorder,
      borderRadius: _borderRadius,
      clipCallback: _clipCallback,
    );
  }
}

/// [NexusPressable] 的前景光斑：跟随手指位置。
class NexusPressLightPainter extends CustomPainter {
  NexusPressLightPainter({
    required this.strength,
    required this.position,
    required this.dark,
    this.borderRadius,
    this.gain = 1,
  }) : super(repaint: Listenable.merge([strength, position]));

  final Animation<double> strength;
  final ValueListenable<Offset?> position;
  final bool dark;
  final BorderRadius? borderRadius;

  /// S1 强度增益（1 = 原始参数）。
  final double gain;

  @override
  void paint(Canvas canvas, Size size) {
    final center = position.value;
    final t = NexusMotion.curveStandard.transform(strength.value);
    if (center == null || t <= 0) return;
    final rect = Offset.zero & size;
    canvas.save();
    if (borderRadius != null) {
      canvas.clipRRect(borderRadius!.toRRect(rect));
    } else {
      canvas.clipRect(rect);
    }
    final radius = NexusTouchLight.radiusFor(size, gain: gain);
    canvas.drawCircle(
      center,
      radius,
      NexusTouchLight.paintFor(
        dark: dark,
        center: center,
        radius: radius,
        strength: t,
        gain: gain,
      ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant NexusPressLightPainter oldDelegate) =>
      oldDelegate.strength != strength ||
      oldDelegate.position != position ||
      oldDelegate.dark != dark ||
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.gain != gain;
}
