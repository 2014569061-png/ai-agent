import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../theme/app_palette.dart';

/// M8 光尘粒子：空状态光晕附近缓慢上浮的细小光点。
///
/// 只负责「粒子状态 + 绘制」，不持有任何 Timer/Ticker：由 [AmbientGlow]
/// 用同一个 20fps 时钟推进，保证光晕与粒子共用一次重绘，不会因为两个
/// 独立时钟交错而把刷新率翻倍。
///
/// 粒子状态保存在一个 [Float32List] 里，推进与绘制过程零分配。
class LightDustSystem {
  LightDustSystem({
    required this.count,
    int seed = 7,
    this.sizeGain = 1,
    this.alphaGain = 1,
  })  : assert(count >= 0),
        _random = math.Random(seed),
        _data = Float32List(count * _stride);

  final int count;

  /// S1 强度倍率：粒子半径与 α 的放大系数（1 = 原始参数）。
  /// α 放大后仍钳制在 [maxBoostedAlpha] 以内。
  final double sizeGain;
  final double alphaGain;
  static const double maxBoostedAlpha = 0.72;
  final math.Random _random;
  final Float32List _data;
  Size _size = Size.zero;

  // 每个粒子 8 个 float：x, y, 上浮速度, 横摆相位, 已存活, 寿命, 半径, 峰值 α。
  static const int _stride = 8;
  static const int _x = 0, _y = 1, _vy = 2, _phase = 3;
  static const int _age = 4, _life = 5, _radius = 6, _alpha = 7;

  // 动效与专用画布规范见 docs/android-ui-style.md。
  static const double minRadius = 0.8, maxRadius = 2.2;
  static const double minAlpha = 0.15, maxAlpha = 0.45;
  static const double minLife = 4, maxLife = 7;
  static const double minSpeed = 6, maxSpeed = 14;
  static const double swayAmplitude = 4;
  static const double swayFrequency = 1.6; // rad/s
  static const double fadeFraction = 0.2;

  /// 顶部淡出带（dp）：粒子接近区域顶边时渐隐，不会「撞」到顶栏。
  static const double edgeFade = 24;

  /// 发射椭圆：中心 (0.5w, 0.34h)，半轴 (0.34w, 0.12h)，与光晕对齐。
  static Offset emitterCenter(Size s) => Offset(s.width * 0.5, s.height * 0.34);
  static Size emitterRadii(Size s) => Size(s.width * 0.34, s.height * 0.12);

  Size get size => _size;

  /// 区域尺寸变化时重新撒点；初始存活时间随机，避免所有粒子同时出生。
  void resize(Size size) {
    if (size == _size) return;
    _size = size;
    if (size.isEmpty) return;
    for (var i = 0; i < count; i++) {
      _spawn(i);
      final o = i * _stride;
      _data[o + _age] = _random.nextDouble() * _data[o + _life];
    }
  }

  void _spawn(int i) {
    final o = i * _stride;
    final center = emitterCenter(_size);
    final radii = emitterRadii(_size);
    // 椭圆内均匀取点。
    final r = math.sqrt(_random.nextDouble());
    final a = _random.nextDouble() * 2 * math.pi;
    _data[o + _x] = center.dx + radii.width * r * math.cos(a);
    _data[o + _y] = center.dy + radii.height * r * math.sin(a);
    _data[o + _vy] = _lerp(minSpeed, maxSpeed);
    _data[o + _phase] = _random.nextDouble() * 2 * math.pi;
    _data[o + _age] = 0;
    _data[o + _life] = _lerp(minLife, maxLife);
    _data[o + _radius] = _lerp(minRadius, maxRadius) * sizeGain;
    _data[o + _alpha] =
        (_lerp(minAlpha, maxAlpha) * alphaGain).clamp(0.0, maxBoostedAlpha);
  }

  double _lerp(double a, double b) => a + (b - a) * _random.nextDouble();

  /// 推进 [dt] 秒。寿命结束或飘出顶边的粒子在发射椭圆内重生。
  void step(double dt) {
    if (_size.isEmpty) return;
    for (var i = 0; i < count; i++) {
      final o = i * _stride;
      _data[o + _age] += dt;
      _data[o + _y] -= _data[o + _vy] * dt;
      if (_data[o + _age] >= _data[o + _life] || _data[o + _y] <= 0) {
        _spawn(i);
      }
    }
  }

  /// 第 [i] 个粒子当前位置（含横摆）。
  Offset positionOf(int i) {
    final o = i * _stride;
    final sway = swayAmplitude *
        math.sin(_data[o + _phase] + _data[o + _age] * swayFrequency);
    return Offset(_data[o + _x] + sway, _data[o + _y]);
  }

  double radiusOf(int i) => _data[i * _stride + _radius];

  /// 第 [i] 个粒子当前 α：寿命首尾各 20% 淡入淡出，接近顶边时再渐隐。
  double alphaOf(int i) {
    final o = i * _stride;
    final t = (_data[o + _age] / _data[o + _life]).clamp(0.0, 1.0);
    final fade = math.min(
      (t / fadeFraction).clamp(0.0, 1.0),
      ((1 - t) / fadeFraction).clamp(0.0, 1.0),
    );
    final edge = (_data[o + _y] / edgeFade).clamp(0.0, 1.0);
    return _data[o + _alpha] * fade * edge;
  }
}

/// 光尘绘制器：深色模式用 plus 叠加（发光感），浅色模式用 srcOver（保证对比度）。
class LightDustPainter extends CustomPainter {
  LightDustPainter({
    required this.system,
    required this.isDark,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final LightDustSystem system;
  final bool isDark;

  static const Color darkColor = Color(0xFFC9D4FF);
  static const Color lightColor = AppPalette.brand;

  BlendMode get blendMode => isDark ? BlendMode.plus : BlendMode.srcOver;
  Color get color => isDark ? darkColor : lightColor;

  final Paint _paint = Paint()..isAntiAlias = true;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    system.resize(size);
    canvas.save();
    // 粒子只画在空状态区域内，不会越界画到顶栏或输入框上。
    canvas.clipRect(Offset.zero & size);
    _paint.blendMode = blendMode;
    for (var i = 0; i < system.count; i++) {
      final a = system.alphaOf(i);
      if (a <= 0.004) continue;
      _paint.color = color.withValues(alpha: a);
      canvas.drawCircle(system.positionOf(i), system.radiusOf(i), _paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LightDustPainter oldDelegate) =>
      oldDelegate.system != system || oldDelegate.isDark != isDark;
}

/// 供测试读取的调试信息。
@visibleForTesting
List<double> debugDustAlphas(LightDustSystem s) =>
    [for (var i = 0; i < s.count; i++) s.alphaOf(i)];
