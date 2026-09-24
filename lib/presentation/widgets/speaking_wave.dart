import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../motion/motion_lifecycle.dart';
import '../motion/motion_preferences.dart';
import '../motion/motion_tier.dart';
import '../motion/nexus_motion.dart';

/// M10 声波条：朗读中（TTS）的节奏提示，也可复用于以后的语音输入。
///
/// * 默认是**伪波形**：TTS 插件不提供音量电平，4 根条按各自周期
///   （600 / 720 / 900 / 800ms）往复，相位依次错开 120ms，曲线 `curveBreathing`。
///   它只表示「正在发声」，不代表真实音量。
/// * 传入 [level]（0–1 的音量电平）时切换为真实电平驱动，不再自带循环；
///   以后接入语音输入时直接复用。
/// * reduced / off：显示静态喇叭图标。
/// * 与 M7 一致：只有挂了 [MotionTierScope]（真实 App）时伪波形才循环；
///   独立 widget 测试里显示静态条，避免 `pumpAndSettle` 超时。
/// * 接入 [MotionLifecycle]：后台或页面被遮挡时停止。
class SpeakingWave extends StatefulWidget {
  const SpeakingWave({super.key, this.color, this.level});

  final Color? color;

  /// 真实音量电平（0–1）。为空时使用伪波形。
  final ValueListenable<double>? level;

  static const int barCount = 4;
  static const double barWidth = 2.5;
  static const double barGap = 2;
  static const double minBarHeight = 4;
  static const double maxBarHeight = 14;

  /// 每根条的往复周期（ms）与相位错开（ms）。
  static const List<int> barPeriodsMs = [600, 720, 900, 800];
  static const int phaseStepMs = 120;

  /// 所有周期的最小公倍数，循环一整轮后无缝衔接。
  static const Duration loopDuration = NexusMotion.speakingWaveLoop;

  /// 真实电平模式下各条的权重，让波形有高低错落。
  static const List<double> levelWeights = [0.6, 1.0, 0.8, 0.5];

  static Size get size => const Size(
        barCount * barWidth + (barCount - 1) * barGap,
        maxBarHeight,
      );

  /// 伪波形：时间 [ms] 时第 [i] 根条的高度。
  static double pseudoHeight(int i, double ms) {
    final period = barPeriodsMs[i];
    var local = ((ms - i * phaseStepMs) % period) / period;
    if (local < 0) local += 1;
    // 三角波 0→1→0，再套呼吸曲线。
    final tri = local < 0.5 ? local * 2 : (1 - local) * 2;
    final k = NexusMotion.curveBreathing.transform(tri);
    return minBarHeight + (maxBarHeight - minBarHeight) * k;
  }

  /// 真实电平：第 [i] 根条的高度。
  static double levelHeight(int i, double level) {
    final v = level.clamp(0.0, 1.0) * levelWeights[i];
    return minBarHeight + (maxBarHeight - minBarHeight) * v;
  }

  @override
  State<SpeakingWave> createState() => _SpeakingWaveState();
}

class _SpeakingWaveState extends State<SpeakingWave>
    with SingleTickerProviderStateMixin, MotionLifecycle<SpeakingWave> {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SpeakingWave.loopDuration,
  );
  bool _hasTierScope = false;

  bool get _wantsLoop =>
      widget.level == null && _hasTierScope && decorativeMotionActive;

  @visibleForTesting
  bool get isLooping => _controller.isAnimating;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _hasTierScope = MotionTierScope.maybeOf(context) != null;
    _sync();
  }

  @override
  void didUpdateWidget(covariant SpeakingWave oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void onMotionActivityChanged() => _sync();

  void _sync() {
    if (_wantsLoop) {
      if (!_controller.isAnimating) _controller.repeat();
    } else if (_controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? IconTheme.of(context).color!;
    if (MotionPreferences.shouldReduceMotion(context)) {
      return ExcludeSemantics(
        child: Icon(Icons.volume_up_rounded, size: 18, color: color),
      );
    }
    final level = widget.level;
    final Listenable repaint = level ?? _controller;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: SpeakingWave.size,
          painter: SpeakingWavePainter(
            repaint: repaint,
            color: color,
            heightOf: level != null
                ? (i) => SpeakingWave.levelHeight(i, level.value)
                : _wantsLoop
                    ? (i) => SpeakingWave.pseudoHeight(
                          i,
                          _controller.value *
                              SpeakingWave.loopDuration.inMilliseconds,
                        )
                    : (i) => SpeakingWave.pseudoHeight(
                          i,
                          // 静态时取一个高低错落的固定帧。
                          SpeakingWave.barPeriodsMs[i] * 0.3 +
                              i * SpeakingWave.phaseStepMs,
                        ),
          ),
        ),
      ),
    );
  }
}

class SpeakingWavePainter extends CustomPainter {
  SpeakingWavePainter({
    required Listenable repaint,
    required this.color,
    required this.heightOf,
  }) : super(repaint: repaint);

  final Color color;
  final double Function(int index) heightOf;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const w = SpeakingWave.barWidth;
    for (var i = 0; i < SpeakingWave.barCount; i++) {
      final h = heightOf(i);
      final x = i * (w + SpeakingWave.barGap);
      final top = (size.height - h) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top, w, h),
          const Radius.circular(w / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(SpeakingWavePainter oldDelegate) => true;
}

/// 把「正在朗读的消息索引」映射成某一条消息的「是否在朗读」。
///
/// 按 (源, 索引) 判等：消息列表的气泡缓存以 listenable 作为比较键，
/// 每次 build 新建实例也不会让缓存失效。
@immutable
class SpeakingAtIndex implements ValueListenable<bool> {
  const SpeakingAtIndex(this.source, this.index);

  final ValueListenable<int?> source;
  final int index;

  @override
  bool get value => source.value == index;

  @override
  void addListener(VoidCallback listener) => source.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => source.removeListener(listener);

  @override
  bool operator ==(Object other) =>
      other is SpeakingAtIndex &&
      identical(other.source, source) &&
      other.index == index;

  @override
  int get hashCode => Object.hash(identityHashCode(source), index);
}
