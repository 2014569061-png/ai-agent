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
