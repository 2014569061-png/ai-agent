import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

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
///   导致粒子数忽多忽少。
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
    if (worst.inMicroseconds > frameBudgetMicros) _windowJank++;
    if (_windowFrames < sampleSize) return;
    final jankRatio = _windowJank / _windowFrames;
    _windowFrames = 0;
    _windowJank = 0;
    if (jankRatio > jankRatioThreshold) _downgrade();
  }

  void _downgrade() {
    value = switch (value) {
      MotionTier.high => MotionTier.mid,
      MotionTier.mid || MotionTier.low => MotionTier.low,
    };
    if (value == MotionTier.low) stopMonitoring();
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
  });

  factory MotionBudget.resolve(MotionLevel level, MotionTier tier) {
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
      );
    }
    return switch (tier) {
      MotionTier.high => MotionBudget._(
          level: level,
          tier: tier,
          particleCount: 28,
          ambientGlow: true,
          ambientDrift: true,
          ambientBreathing: true,
          shimmer: true,
          shimmerPeriodScale: 1,
          touchLight: true,
          sendRipple: true,
          routeParallax: true,
        ),
      MotionTier.mid => MotionBudget._(
          level: level,
          tier: tier,
          particleCount: 14,
          ambientGlow: true,
          ambientDrift: false,
          ambientBreathing: true,
          shimmer: true,
          shimmerPeriodScale: 1.5,
          touchLight: true,
          sendRipple: true,
          routeParallax: true,
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
        ),
    };
  }

  static MotionBudget of(BuildContext context, {bool listen = true}) =>
      MotionBudget.resolve(
        MotionPreferences.levelOf(context, listen: listen),
        MotionTierScope.of(context, listen: listen),
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

  /// 是否存在任何需要持续刷新的装饰层。
  bool get hasContinuousDecoration =>
      particleCount > 0 || ambientDrift || ambientBreathing || shimmer;

  @override
  bool operator ==(Object other) =>
      other is MotionBudget && other.level == level && other.tier == tier;

  @override
  int get hashCode => Object.hash(level, tier);
}
