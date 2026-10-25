import '../theme/mobile_theme.dart';
import 'package:flutter/material.dart';

import '../motion/motion_intensity.dart';
import '../motion/motion_lifecycle.dart';
import '../motion/motion_tier.dart';
import '../motion/nexus_motion.dart';

/// M9 文字流光：一段线性渐变高光从左到右扫过文字。
///
/// * 扫过 [NexusMotion.shimmerSweep]（1600ms，`curveStandard`），间隔
///   [NexusMotion.shimmerGap]（400ms）；mid 档整体放慢 1.5 倍。
/// * 高光带宽为文字宽度的 40%，用 `srcATop` 只叠加在字形上，不改变布局。
/// * 分档读 [MotionBudget.shimmer]：high / mid 开；low、reduced、off 关。
/// * 与 M7 一致：只有挂了 [MotionTierScope]（真实 App）时才循环，
///   独立 widget 测试里保持静态，避免 `pumpAndSettle` 超时。
/// * 接入 [MotionLifecycle]：后台或页面被遮挡时停止。
///
/// 包装结构始终存在：关闭时直接返回 child，开启时加一层 ShaderMask。
class ShimmerText extends StatefulWidget {
  const ShimmerText({
    super.key,
    required this.child,
    this.enabled = true,
    this.highlightColor,
  });

  final Widget child;

  /// 业务侧开关（例如只在「思考中」时开启）。
  final bool enabled;

  /// 高光颜色；默认浅色用品牌色，深色用 90% 白。
  final Color? highlightColor;

  /// 高光带宽（占文字宽度的比例）。
  static const double bandWidth = 0.4;

  @override
  State<ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<ShimmerText>
    with SingleTickerProviderStateMixin, MotionLifecycle<ShimmerText> {
  late final AnimationController _controller = AnimationController(vsync: this);
  MotionBudget? _budget;
  bool _hasTierScope = false;

  bool get _wantsShimmer =>
      widget.enabled &&
      _hasTierScope &&
      decorativeMotionActive &&
      (_budget?.shimmer ?? false);

  @visibleForTesting
  bool get isShimmering => _controller.isAnimating;

  /// 一个完整周期（扫过 + 间隔，已乘档位倍率）。
  @visibleForTesting
  Duration? get cycle => _controller.duration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _budget = MotionBudget.of(context);
    _hasTierScope = MotionTierScope.maybeOf(context) != null;
    _sync();
  }

  @override
  void didUpdateWidget(covariant ShimmerText oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void onMotionActivityChanged() => _sync();

  void _sync() {
    if (_wantsShimmer) {
      final scale = _budget!.shimmerPeriodScale;
      final cycle = (NexusMotion.shimmerSweep + NexusMotion.shimmerGap) * scale;
      if (_controller.duration != cycle) {
        _controller.duration = cycle;
        if (_controller.isAnimating) _controller.repeat();
      }
      if (!_controller.isAnimating) _controller.repeat();
    } else if (_controller.isAnimating || _controller.value != 0) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_wantsShimmer) return widget.child;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gain = _budget?.gain ?? 1;
    // S1：深色高光随强度提亮（0.9 → 1.0），高光带加宽（鲜明档 0.4 → 0.5）。
    final highlight = widget.highlightColor ??
        (isDark
            ? Colors.white.withValues(alpha: (0.9 * gain).clamp(0.0, 1.0))
            : MobileTheme.brand(context));
    final band = amplify(ShimmerText.bandWidth, gain, 0.25);
    final sweep = NexusMotion.shimmerSweep.inMicroseconds;
    final sweepFraction =
        sweep / (sweep + NexusMotion.shimmerGap.inMicroseconds);
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final raw = _controller.value / sweepFraction;
        // 间隔期把高光移到文字之外，保持 ShaderMask 结构不变。
        final t = raw >= 1 ? 1.0 : NexusMotion.curveStandard.transform(raw);
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => shimmerGradient(highlight, t, band: band)
              .createShader(Offset.zero & bounds.size),
          child: child,
        );
      },
    );
  }
}

/// 进度 [t]（0→1）时的高光渐变：高光中心从 -0.2 移动到 1.2（相对文字宽度），
/// 保证起止时刻高光都完全在文字之外。
LinearGradient shimmerGradient(Color highlight, double t,
    {double band = ShimmerText.bandWidth}) {
  final center = -band / 2 + t * (1 + band);
  return LinearGradient(
    colors: [
      highlight.withValues(alpha: 0),
      highlight,
      highlight.withValues(alpha: 0),
    ],
    stops: [0.5 - band / 2, 0.5, 0.5 + band / 2],
    transform: _SlideGradient(center - 0.5),
  );
}

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.fraction);

  /// 平移量（相对宽度）。
  final double fraction;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * fraction, 0, 0);
}
