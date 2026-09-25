import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../motion/motion_intensity.dart';
import '../motion/motion_lifecycle.dart';
import '../motion/motion_preferences.dart';
import '../motion/motion_tier.dart';
import '../motion/nexus_motion.dart';
import '../theme/app_palette.dart';
import 'light_dust_field.dart';

/// M7 环境光晕：空状态页背后两团缓慢变化的柔光（品牌色 + 冷蓝）。
///
/// * 分档只读 [MotionBudget]：high 漂移 + 呼吸，mid 只呼吸，low 静态双层，
///   reduced 静态单层（只画主色），off 不绘制。
/// * 用 [NexusMotion.ambientGlowTick]（50ms，约 20fps）的 Timer 驱动重绘，
///   不用逐帧 Ticker：光晕变化极慢，20fps 看不出台阶，且上层玻璃不必每帧重采样。
/// * 只有挂了 [MotionTierScope]（真实 App）时才循环；独立 widget 测试里
///   一律静态，避免 `pumpAndSettle` 因持续调度帧而超时。
/// * 接入 [MotionLifecycle]：后台、页面被遮挡（TickerMode 关闭）时停止 Timer。
/// * M8 光尘粒子（[LightDustSystem]）叠在光晕之上，由同一个 Timer 推进。
/// * 纯 `RadialGradient` 绘制，不用 blur 滤镜；α 上限 [AmbientGlowPainter.maxAlpha]。
class AmbientGlow extends StatefulWidget {
  const AmbientGlow({super.key});

  @override
  State<AmbientGlow> createState() => _AmbientGlowState();
}

class _AmbientGlowState extends State<AmbientGlow>
    with MotionLifecycle<AmbientGlow> {
  /// 已流逝的动画时间（秒）。按 Timer 步进累加，与真实时钟无关，测试可复现。
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  Timer? _timer;
  MotionBudget? _budget;
  bool _hasTierScope = false;

  /// M8 光尘：只在光晕循环时存在，与光晕共用同一个时钟。
  LightDustSystem? _dust;

  bool get _wantsLoop {
    final budget = _budget;
    if (budget == null || !budget.ambientGlow) return false;
    return _hasTierScope &&
        decorativeMotionActive &&
        (budget.ambientDrift || budget.ambientBreathing);
  }

  @visibleForTesting
  bool get isLooping => _timer?.isActive ?? false;

  @visibleForTesting
  LightDustSystem? get debugDust => _dust;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _budget = MotionBudget.of(context);
    _hasTierScope = MotionTierScope.maybeOf(context) != null;
    _syncTimer();
  }

  @override
  void onMotionActivityChanged() => _syncTimer();

  void _syncTimer() {
    if (_wantsLoop) {
      _timer ??= Timer.periodic(NexusMotion.ambientGlowTick, _onTick);
    } else {
      _timer?.cancel();
      _timer = null;
    }
    _syncDust();
  }

  void _syncDust() {
    final count = _wantsLoop ? (_budget?.particleCount ?? 0) : 0;
    final gain = _budget?.gain ?? 1;
    final sizeGain = amplify(1, gain, 0.5);
    if (count == (_dust?.count ?? 0) &&
        (count == 0 || _dust?.sizeGain == sizeGain)) {
      return;
    }
    // S1：粒子随强度变大、变亮（鲜明档半径 ×1.5、α ×1.6）。
    _dust = count > 0
        ? LightDustSystem(
            count: count,
            sizeGain: sizeGain,
            alphaGain: amplify(1, gain, 0.6),
          )
        : null;
  }

  void _onTick(Timer _) {
    final period = NexusMotion.ambientGlowPeriod.inMicroseconds /
        Duration.microsecondsPerSecond;
    final step = NexusMotion.ambientGlowTick.inMicroseconds /
        Duration.microsecondsPerSecond;
    _dust?.step(step);
    // 按周期取模，长时间运行也不会累积浮点误差。
    _time.value = (_time.value + step) % period;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final budget = _budget ?? MotionBudget.of(context);
    if (!budget.ambientGlow) return const SizedBox.shrink();
    final animated = _wantsLoop;
    final dust = _dust;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gain = budget.gain;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: AmbientGlowPainter(
                  time: _time,
                  drift: animated && budget.ambientDrift,
                  breathing: animated && budget.ambientBreathing,
                  singleLayer: budget.level == MotionLevel.reduced,
                  // S1：深色背景对比度余量大，α 可放大（鲜明 ×1.8）；浅色模式
                  // 已贴近 4.5 对比度红线，α 不放大，改为扩大光团与漂移幅度。
                  alphaGain: isDark ? amplify(1, gain, 0.8) : 1,
                  radiusGain: amplify(1, gain, 0.25),
                  driftGain: amplify(1, gain, 0.5),
                ),
              ),
              if (dust != null)
                CustomPaint(
                  painter: LightDustPainter(
                    system: dust,
                    isDark: isDark,
                    repaint: _time,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 光晕绘制器。公开给测试读取参数与 α。
class AmbientGlowPainter extends CustomPainter {
  AmbientGlowPainter({
    required this.time,
    required this.drift,
    required this.breathing,
    required this.singleLayer,
    this.alphaGain = 1,
    this.radiusGain = 1,
    this.driftGain = 1,
  }) : super(repaint: time);

  final ValueListenable<double> time;
  final bool drift;
  final bool breathing;
  final bool singleLayer;

  /// S1 强度增益：α、半径、漂移幅度的倍率（1 = 原始参数）。
  final double alphaGain;
  final double radiusGain;
  final double driftGain;

  /// 对比度护栏：任何一层的 α 都不超过这个值。
  static const double maxAlpha = 0.12;
  static const double primaryAlpha = 0.10;
  static const double secondaryAlpha = 0.08;

  /// 亮度呼吸幅度（±15%）。
  static const double breathingAmplitude = 0.15;

  /// 半径占宽度的比例。
  static const double radiusFactor = 0.7;

  static const Color primaryColor = AppPalette.brand;
  static const Color secondaryColor = Color(0xFF3AA0FF);

  /// 时间 [t]（秒）下的呼吸系数，范围 [1 - 0.15, 1 + 0.15]。
  static double breathFactor(double t, {required bool breathing}) {
    if (!breathing) return 1;
    return 1 + breathingAmplitude * math.sin(_omega * t);
  }

  /// 时间 [t]（秒）下主光晕的 Lissajous 漂移（1:2 频率比），模长 ≤ 漂移上限。
  static Offset driftOffset(double t, {required bool drift}) {
    if (!drift) return Offset.zero;
    final a = NexusMotion.ambientGlowDrift;
    return Offset(
      a * 0.75 * math.sin(_omega * t),
      a * 0.5 * math.sin(2 * _omega * t + math.pi / 4),
    );
  }

  /// 时间 [t]（秒）下两层的 α：[主色, 辅色]。均被钳制到 [maxAlpha]。
  ///
  /// [gain] 为 S1 强度倍率，α 与上限同比放大（只在深色模式下大于 1）。
  static List<double> layerAlphas(double t,
      {required bool breathing, bool singleLayer = false, double gain = 1}) {
    final k = breathFactor(t, breathing: breathing);
    final cap = maxAlpha * gain;
    return [
      (primaryAlpha * k * gain).clamp(0.0, cap),
      if (!singleLayer) (secondaryAlpha * k * gain).clamp(0.0, cap),
    ];
  }

  static double get _omega =>
      2 *
      math.pi /
      (NexusMotion.ambientGlowPeriod.inMicroseconds /
          Duration.microsecondsPerSecond);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = time.value;
    final alphas = layerAlphas(t,
        breathing: breathing, singleLayer: singleLayer, gain: alphaGain);
    final offset = driftOffset(t, drift: drift) * driftGain;
    final radius = size.width * radiusFactor * radiusGain;
    final rect = Offset.zero & size;

    _paintLayer(
      canvas,
      rect,
      center: Offset(size.width * 0.34, size.height / 3) + offset,
      radius: radius,
      color: primaryColor,
      alpha: alphas[0],
    );
    if (alphas.length > 1) {
      _paintLayer(
        canvas,
        rect,
        // 辅光反向、减幅运动，两团光相互错动而不是整体平移。
        center: Offset(size.width * 0.70, size.height * 0.26) - offset * 0.6,
        radius: radius * 0.85,
        color: secondaryColor,
        alpha: alphas[1],
      );
    }
  }

  void _paintLayer(
    Canvas canvas,
    Rect rect, {
    required Offset center,
    required double radius,
    required Color color,
    required double alpha,
  }) {
    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment(
          (center.dx - rect.center.dx) / (rect.width / 2),
          (center.dy - rect.center.dy) / (rect.height / 2),
        ),
        radius: radius / rect.shortestSide,
        colors: [
          color.withValues(alpha: alpha),
          color.withValues(alpha: alpha * 0.45),
          color.withValues(alpha: 0),
        ],
        stops: const [0, 0.45, 1],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(AmbientGlowPainter oldDelegate) =>
      oldDelegate.time != time ||
      oldDelegate.drift != drift ||
      oldDelegate.breathing != breathing ||
      oldDelegate.singleLayer != singleLayer ||
      oldDelegate.alphaGain != alphaGain ||
      oldDelegate.radiusGain != radiusGain ||
      oldDelegate.driftGain != driftGain;
}
