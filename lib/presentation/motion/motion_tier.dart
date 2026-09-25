import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'motion_intensity.dart';
import 'motion_preferences.dart';

/// 设备动效能力档位。
///
/// 与 [MotionLevel]（用户意愿：系统「移除动画」+ App 内设置）是两个独立维度：
/// 最终生效的装饰性动效预算 = min(用户意愿, 设备能力)，见 [MotionBudget]。
/// 位移 / 透明度这类廉价动效不受档位影响，只有粒子、光晕、流光等装饰层会降级。
enum MotionTier { low, mid, high }

/// 运行时动效档位控制器。
///
/// * 初始档：显示刷新率 ≥ 90Hz 判为 [MotionTier.high]，否则 [MotionTier.mid]。
/// * 运行时：统计最近 [sampleSize] 帧，UI 或 Raster 任一超过帧预算的占比
///   超过 [jankRatioThreshold] 就降一档。会话内**只降不升**，避免档位抖动
///   导致粒子数忽多忽少。运行时最低只降到 [MotionTier.mid]；low 只来自
///   外部限档（如纯扁平玻璃）。卡顿判定预算不低于 60Hz 的 16.7ms，
///   避免高刷设备因 8.3ms 预算被误降档。
/// * 启动后的前 [warmupFrames] 帧（着色器编译、首屏光栅化）不计入统计。
class MotionTierController extends ValueNotifier<MotionTier> {
  MotionTierController({
    MotionTier? initial,
    double? refreshRate,
    this.sampleSize = 120,
    this.jankRatioThreshold = 0.08,
    this.warmupFrames = 90,
  })  : refreshRate = _sanitizeRefreshRate(refreshRate ?? _readRefreshRate()),
        super(MotionTier.mid) {
    value = debugOverride ?? initial ?? tierForRefreshRate(this.refreshRate);
  }

  /// 应用级单例。由 `main.dart` 注入 [MotionTierScope]。
  static final MotionTierController app = MotionTierController();

  /// 调试 / 测试时强制档位；非空时忽略运行时降档。
  static MotionTier? debugOverride;

  MotionIntensity _intensity = MotionIntensity.subtle;

  /// 用户选择的动效强度（S1）。默认 [MotionIntensity.subtle]（即原始参数），
  /// App 启动时由设置同步；变化时通知依赖方重建。
  MotionIntensity get intensity => _intensity;
  set intensity(MotionIntensity value) {
    if (value == _intensity) return;
    _intensity = value;
    notifyListeners();
  }

  final double refreshRate;
  final int sampleSize;
  final double jankRatioThreshold;
  final int warmupFrames;

  int _seenFrames = 0;
  int _windowFrames = 0;
  int _windowJank = 0;
  bool _monitoring = false;

  /// 单帧预算（微秒）。60Hz ≈ 16667µs，120Hz ≈ 8333µs。
  int get frameBudgetMicros =>
      (Duration.microsecondsPerSecond / refreshRate).round();

  /// 卡顿判定用的预算：取帧预算与 60Hz 预算中较宽松的一个。
  static const int _minJankBudgetMicros = 16667;
  int get jankBudgetMicros => frameBudgetMicros > _minJankBudgetMicros
      ? frameBudgetMicros
      : _minJankBudgetMicros;

  bool get isMonitoring => _monitoring;

  static MotionTier tierForRefreshRate(double refreshRate) =>
      refreshRate >= 90 ? MotionTier.high : MotionTier.mid;

  /// 开始帧耗时监测（幂等）。已是最低档时无需监测。
  void startMonitoring() {
    if (_monitoring || value == MotionTier.low) return;
    _monitoring = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void stopMonitoring() {
    if (!_monitoring) return;
    _monitoring = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      recordFrame(timing.buildDuration, timing.rasterDuration);
    }
  }

  /// 记录一帧的 UI / Raster 耗时。公开给测试直接喂数据。
  @visibleForTesting
  void recordFrame(Duration build, Duration raster) {
    if (debugOverride != null || value == MotionTier.low) return;
    _seenFrames++;
    if (_seenFrames <= warmupFrames) return;
    _windowFrames++;
    final worst = build > raster ? build : raster;
    if (worst.inMicroseconds > jankBudgetMicros) _windowJank++;
    if (_windowFrames < sampleSize) return;
    final jankRatio = _windowJank / _windowFrames;
    _windowFrames = 0;
    _windowJank = 0;
    if (jankRatio > jankRatioThreshold) _downgrade();
  }

  void _downgrade() {
    // 运行时最低降到 mid：位移 / 透明度等廉价动效本就不受档位影响，
    // mid 只减半粒子并关闭光晕漂移，已足够减负。
    if (value == MotionTier.high) value = MotionTier.mid;
    stopMonitoring();
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }

  static double _readRefreshRate() {
    try {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isEmpty) return 60;
      return views.first.display.refreshRate;
    } catch (_) {
      return 60;
    }
  }

  static double _sanitizeRefreshRate(double value) =>
      value.isFinite && value >= 30 && value <= 240 ? value : 60;
}

/// 把 [MotionTierController] 暴露给整棵树（位于 Navigator 之上，路由与弹层都能读到）。
///
/// [cap] 用于外部强制上限：例如玻璃强度为「纯扁平」时，装饰层直接按
/// [MotionTier.low] 处理，与用户选择的朴素风格保持一致。
class MotionTierScope extends InheritedNotifier<MotionTierController> {
  const MotionTierScope({
    super.key,
    required MotionTierController controller,
    this.cap,
    required super.child,
  }) : super(notifier: controller);

  final MotionTier? cap;

  /// 未挂载 Scope（例如独立 widget 测试）时的默认档位。
  static const MotionTier fallback = MotionTier.mid;

  /// 与 [of] 相同，但未挂载 Scope 时返回 null。
  ///
  /// 持续循环的装饰层（如环境光晕）用它判断是否处于真实 App 中：
  /// 独立 widget 测试没有 Scope，循环会让 `pumpAndSettle` 无法结束。
  static MotionTier? maybeOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MotionTierScope>();
    if (scope == null) return null;
    return of(context);
  }

  /// 当前动效强度增益（未挂载 Scope 时为 1，即原始参数）。
  static double gainOf(BuildContext context, {bool listen = true}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<MotionTierScope>()
        : context.getInheritedWidgetOfExactType<MotionTierScope>();
    return scope?.notifier?.intensity.gain ?? 1;
  }

  static MotionTier of(BuildContext context, {bool listen = true}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<MotionTierScope>()
        : context.getInheritedWidgetOfExactType<MotionTierScope>();
    if (scope == null) return fallback;
    final tier = scope.notifier?.value ?? fallback;
    final cap = scope.cap;
    return cap != null && cap.index < tier.index ? cap : tier;
  }

  @override
  bool updateShouldNotify(MotionTierScope oldWidget) =>
      super.updateShouldNotify(oldWidget) || oldWidget.cap != cap;
}

/// 装饰性动效预算：合并 [MotionLevel]（用户意愿）与 [MotionTier]（设备能力）。
///
/// 新增的粒子 / 光晕 / 流光 / 光感组件只读这一个对象，不各自判断，
/// 以保证降级顺序一致：先关粒子 → 再简化光晕 → 最后关闭流光与光感。
@immutable
class MotionBudget {
  const MotionBudget._({
    required this.level,
    required this.tier,
    required this.particleCount,
    required this.ambientGlow,
    required this.ambientDrift,
    required this.ambientBreathing,
    required this.shimmer,
    required this.shimmerPeriodScale,
    required this.touchLight,
    required this.sendRipple,
    required this.routeParallax,
    this.gain = 1,
  });

  factory MotionBudget.resolve(MotionLevel level, MotionTier tier,
      {double gain = 1}) {
    // 粒子数随强度放大：鲜明档（gain 2）high 28 → 48、mid 14 → 24。
    int particles(int base) => amplify(base.toDouble(), gain, 0.7).round();
    if (level == MotionLevel.off) {
      return MotionBudget._(
        level: level,
        tier: tier,
        particleCount: 0,
        ambientGlow: false,
        ambientDrift: false,
        ambientBreathing: false,
        shimmer: false,
        shimmerPeriodScale: 1,
        touchLight: false,
        sendRipple: false,
        routeParallax: false,
        gain: gain,
      );
    }
    if (level == MotionLevel.reduced) {
      return MotionBudget._(
        level: level,
        tier: tier,
        particleCount: 0,
        ambientGlow: true,
        ambientDrift: false,
        ambientBreathing: false,
        shimmer: false,
        shimmerPeriodScale: 1,
        touchLight: false,
        sendRipple: false,
        routeParallax: false,
        gain: gain,
      );
    }
    return switch (tier) {
      MotionTier.high => MotionBudget._(
          level: level,
          tier: tier,
          particleCount: particles(28),
          ambientGlow: true,
          ambientDrift: true,
          ambientBreathing: true,
          shimmer: true,
          shimmerPeriodScale: 1,
          touchLight: true,
          sendRipple: true,
          routeParallax: true,
          gain: gain,
        ),
      MotionTier.mid => MotionBudget._(
          level: level,
          tier: tier,
          particleCount: particles(14),
          ambientGlow: true,
          ambientDrift: false,
          ambientBreathing: true,
          shimmer: true,
          shimmerPeriodScale: 1.5,
          touchLight: true,
          sendRipple: true,
          routeParallax: true,
          gain: gain,
        ),
      MotionTier.low => MotionBudget._(
          level: level,
          tier: tier,
          particleCount: 0,
          ambientGlow: true,
          ambientDrift: false,
          ambientBreathing: false,
          shimmer: false,
          shimmerPeriodScale: 1,
          touchLight: false,
          sendRipple: false,
          routeParallax: false,
          gain: gain,
        ),
    };
  }

  static MotionBudget of(BuildContext context, {bool listen = true}) =>
      MotionBudget.resolve(
        MotionPreferences.levelOf(context, listen: listen),
        MotionTierScope.of(context, listen: listen),
        gain: MotionTierScope.gainOf(context, listen: listen),
      );

  final MotionLevel level;
  final MotionTier tier;

  /// 光尘粒子数量；0 表示不挂载粒子层。
  final int particleCount;

  /// 是否绘制环境光晕（reduced 下为静态单层）。
  final bool ambientGlow;

  /// 光晕是否缓慢漂移（仅 high）。
  final bool ambientDrift;

  /// 光晕是否亮度呼吸。
  final bool ambientBreathing;

  /// 文字流光 / 边缘流光。
  final bool shimmer;

  /// 流光周期倍率（mid 档放慢，降低刷新压力）。
  final double shimmerPeriodScale;

  /// 按压「光随指动」高光。
  final bool touchLight;

  /// 发送按钮光圈扩散。
  final bool sendRipple;

  /// 页面转场下层视差（整屏转场方案）。
  final bool routeParallax;

  /// 动效强度增益（S1）：1 = 原始参数，2 = 鲜明。各效果按自身系数放大。
  final double gain;

  /// 是否存在任何需要持续刷新的装饰层。
  bool get hasContinuousDecoration =>
      particleCount > 0 || ambientDrift || ambientBreathing || shimmer;

  @override
  bool operator ==(Object other) =>
      other is MotionBudget &&
      other.level == level &&
      other.tier == tier &&
      other.gain == gain;

  @override
  int get hashCode => Object.hash(level, tier, gain);
}
