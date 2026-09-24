import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';
import '../theme/app_tokens.dart';
import 'motion_preferences.dart';

/// NEXUS 统一动效系统标准定义
abstract final class NexusMotion {
  // --- 标准时间常量 (不受 Context 约束的物理值) ---
  /// 即时反馈 (100ms): 按压、图标切换、选中态
  static const Duration instant = AppTokens.durationInstant;

  /// 控件状态 (150ms): 按钮、Chip、输入框、筛选切换
  static const Duration fast = AppTokens.durationFast;

  /// 容器变化 (220ms): 局部展开、浮层、内容切换
  static const Duration base = AppTokens.durationBase;

  /// 内容布局 (300ms): 大段内容展开、复杂面板切换
  static const Duration expand = AppTokens.durationExpand;

  /// 页面进入：新元素需要更长的末尾减速来建立空间关系。
  static const Duration page = AppTokens.durationPage;

  /// 整屏层级转场进入时长（配合 [NexusSpringCurve] 使用）
  static const Duration pageSpring = AppTokens.durationPageSpring;

  /// 首屏入场（M2）：单元素时长、槽位错开、reduced 淡入时长。
  static const Duration entrance = AppTokens.durationEntrance;
  static const Duration entranceStagger = AppTokens.entranceStagger;
  static const Duration reducedEntrance = AppTokens.durationReducedEntrance;

  /// 列表错开入场（M3）。
  static const Duration listItem = AppTokens.durationListItem;
  static const Duration listStagger = AppTokens.listStagger;
  static const int listStaggerMaxItems = AppTokens.listStaggerMaxItems;

  /// 发送反馈（M5）：光圈 280ms、用户气泡升起 320ms、发送按钮回弹 320ms。
  static const Duration sendRipple = AppTokens.durationSendRipple;
  static const Duration bubbleRise = AppTokens.durationBubbleRise;
  static const Duration pressRelease = AppTokens.durationPressRelease;

  /// 流式回复（M6）：首个 token 到达时正文淡入 180ms。
  static const Duration answerReveal = AppTokens.durationAnswerReveal;

  /// 空状态环境光晕（M7）：12s 周期、50ms 重绘间隔、漂移 ≤ 24dp。
  static const Duration ambientGlowPeriod = AppTokens.ambientGlowPeriod;
  static const Duration ambientGlowTick = AppTokens.ambientGlowTick;
  static const double ambientGlowDrift = AppTokens.ambientGlowDrift;

  /// 思考中 / 执行中（M9）。
  static const Duration shimmerSweep = AppTokens.shimmerSweep;
  static const Duration shimmerGap = AppTokens.shimmerGap;
  static const double glowRingSpread = AppTokens.glowRingSpread;
  static const Duration glowRingCollapse = AppTokens.glowRingCollapse;

  /// 发送按钮按下后的缩放。
  static const double sendPressedScale = 0.9;

  /// 发送按钮松手：轻弹弹簧，保留过冲。
  static final Curve curveSendRelease =
      NexusSpringCurve(springLively, allowOvershoot: true);

  /// 用户气泡升起：离手弹簧（阻尼比 0.825，几乎无过冲）。
  static final Curve curveBubbleRise = NexusSpringCurve(springRelease);

  /// 非聊天列表的滚动物理：弹性过界（聊天列表保持平台默认）。
  static const ScrollPhysics listPhysics =
      BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  /// 页面退出：已在视线中的元素应更快离场，减少等待感。
  static const Duration pageExit = AppTokens.durationPageExit;

  /// 底部 Sheet 的完整进入 / 回弹时长。
  static const Duration sheet = AppTokens.durationSheet;

  /// 用户主动将聊天列表滚动到最新消息。
  static const Duration scrollToTarget = Duration(milliseconds: 260);

  /// 新消息完成后，聊天列表轻量跟随尾部。
  static const Duration tailFollow = Duration(milliseconds: 180);

  /// 聊天列表滚动使用的减速曲线。
  static const Curve curveScroll = Curves.easeOutCubic;

  /// 容器退出与返回。
  static const Duration exit = AppTokens.durationPageExit;

  // --- 标准曲线 ---
  /// 同屏状态变化：cubic-bezier(0.40, 0.00, 0.20, 1.00)
  static const Curve curveStandard = AppTokens.curveStandard;

  /// 新元素进场：cubic-bezier(0.00, 0.00, 0.20, 1.00)
  static const Curve curveEnter = AppTokens.curveDecelerate;

  /// 已在视线中的元素退场：cubic-bezier(0.00, 0.00, 0.00, 1.00)
  static const Curve curveExit = AppTokens.curveAccelerate;

  /// 底部抽屉进场：高阻尼弹簧减速曲线 (HarmonyOS ArkUI 风格)
  static const Curve curveSheetEnter = Cubic(0.16, 1.0, 0.3, 1.0);

  /// 高响应交互：cubic-bezier(0.20, 0.00, 0.20, 1.00) (HarmonyOS ArkUI 风格，用于分段器、Tab 连续切换)
  static const Curve curveResponsive = Cubic(0.2, 0.0, 0.2, 1.0);

  /// 手势未达到阈值时的克制回弹，避免全局动画出现果冻感。
  static const Curve curveSpring = Curves.easeOutBack;

  /// 连续循环呼吸曲线：平滑双向正弦过渡 (用于状态胶囊、执行中呼吸灯)
  static const Curve curveBreathing = Curves.easeInOutSine;

  // --- 弹簧 Token（物理曲线，时长由参数与初速度自动决定，可随时打断衔接）---
  // 换算：stiffness = (2π / response)²，damping = 2 · ratio · √(mass · stiffness)。
  // 思路参考 HarmonyOS 弹性曲线（responsiveSpringMotion / springMotion /
  // interpolatingSpring），数值为本项目独立换算，不引用其代码。

  /// 跟手：response 0.15s、阻尼比 0.86。用于按压、拖拽、侧滑返回的跟手阶段。
  static const SpringDescription springFollow =
      SpringDescription(mass: 1, stiffness: 1754.6, damping: 72.05);

  /// 离手：response 0.55s、阻尼比 0.825。用于松手回弹、气泡升起、整屏转场。
  static const SpringDescription springRelease =
      SpringDescription(mass: 1, stiffness: 130.5, damping: 18.85);

  /// 轻弹：stiffness 128、damping 12（阻尼比约 0.53，约 4% 过冲）。用于发送按钮回弹。
  static const SpringDescription springLively =
      SpringDescription(mass: 1, stiffness: 128, damping: 12);

  /// 构建一个从 [from] 到 [to] 的弹簧模拟，供 `AnimationController.animateWith` 使用。
  static SpringSimulation spring(
    SpringDescription description, {
    double from = 0,
    double to = 1,
    double velocity = 0,
  }) =>
      SpringSimulation(
        description,
        from,
        to,
        velocity,
        tolerance: const Tolerance(distance: 0.001, velocity: 0.01),
      );

  // --- 考虑无障碍「减少动态效果」后的自适应时间 ---
  static Duration durationInstant(BuildContext context) =>
      MotionPreferences.adjustDuration(context, instant);

  static Duration durationFast(BuildContext context) =>
      MotionPreferences.adjustDuration(context, fast);

  static Duration durationBase(BuildContext context) =>
      MotionPreferences.adjustDuration(context, base);

  static Duration durationExpand(BuildContext context) =>
      MotionPreferences.adjustDuration(context, expand);

  static Duration durationExit(BuildContext context) =>
      MotionPreferences.adjustDuration(context, exit);

  // --- 通用动画构建器 ---
  /// 平滑淡入转场
  static Widget fadeTransition(
    BuildContext context,
    Animation<double> animation,
    Widget child, {
    Curve curve = curveStandard,
  }) {
    if (MotionPreferences.shouldReduceMotion(context)) {
      return child;
    }
    final curved = CurvedAnimation(parent: animation, curve: curve);
    return FadeTransition(opacity: curved, child: child);
  }

  /// 浅位移 + 淡入转场 (默认沿 Y 轴向上或沿 X 轴向左位移微距)
  static Widget slideFadeTransition(
    BuildContext context,
    Animation<double> animation,
    Widget child, {
    Offset beginOffset = const Offset(0, 0.05),
    Curve curve = curveStandard,
  }) {
    if (MotionPreferences.shouldReduceMotion(context)) {
      return child;
    }
    final curved = CurvedAnimation(parent: animation, curve: curve);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position:
            Tween<Offset>(begin: beginOffset, end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }

  /// 统一尺寸展开过渡 (通常搭配 AnimatedSize 或 SizeTransition)
  static Widget sizeTransition(
    BuildContext context,
    Animation<double> animation,
    Widget child, {
    Axis axis = Axis.vertical,
    Curve curve = curveStandard,
  }) {
    if (MotionPreferences.shouldReduceMotion(context)) {
      return child;
    }
    final curved = CurvedAnimation(parent: animation, curve: curve);
    return SizeTransition(
      sizeFactor: curved,
      axis: axis,
      child: child,
    );
  }
}

/// 把弹簧模拟归一化成定长 [Curve]，供必须给定时长的场景使用（例如路由转场）。
///
/// 取弹簧最后一次离开终值 ±0.5% 范围的时刻 T 作为总时长，
/// `f(t) = x(t·T) / x(T)`，并钳制在 [0, 1]：整屏转场不允许越界，
/// 越界会在屏幕边缘露出下层页面。
class NexusSpringCurve extends Curve {
  /// [allowOvershoot] 为 false（默认）时输出限制在 0..1，适合透明度、路由等
  /// 不允许越界的属性；为 true 时保留弹簧过冲，只用于缩放等可越界的属性。
  NexusSpringCurve(this.description, {this.allowOvershoot = false})
      : _simulation = SpringSimulation(description, 0, 1, 0) {
    _settle = _settleTime(_simulation);
    _end = _simulation.x(_settle);
  }

  final SpringDescription description;
  final bool allowOvershoot;
  final SpringSimulation _simulation;
  late final double _settle;
  late final double _end;

  /// 弹簧从静止走到稳定所需的物理时长（秒），便于测试与调参。
  double get settleSeconds => _settle;

  @override
  double transformInternal(double t) {
    final value = _simulation.x(t * _settle) / _end;
    return allowOvershoot ? value : value.clamp(0.0, 1.0);
  }

  static double _settleTime(SpringSimulation simulation) {
    const tolerance = 0.005;
    var last = 0.0;
    for (var ms = 1; ms <= 5000; ms++) {
      final t = ms / 1000;
      if ((simulation.x(t) - 1).abs() >= tolerance) last = t;
    }
    return last + 0.001;
  }
}
