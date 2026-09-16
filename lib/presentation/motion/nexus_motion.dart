import 'package:flutter/widgets.dart';
import '../theme/app_tokens.dart';
import 'motion_preferences.dart';

/// NEXUS 统一动效系统标准定义
abstract final class NexusMotion {
  // --- 标准时间常量 (不受 Context 约束的物理值) ---
  /// 即时反馈 (90ms): 按压、图标切换、选中态
  static const Duration instant = AppTokens.durationInstant;

  /// 控件状态 (150ms): 按钮、Chip、输入框、筛选切换
  static const Duration fast = AppTokens.durationFast;

  /// 容器变化 (220ms): 展开、浮层、页面推进进入
  static const Duration base = AppTokens.durationBase;

  /// 内容布局 (300ms): 大段内容展开、复杂面板切换
  static const Duration expand = AppTokens.durationExpand;

  /// 容器退出与返回 (150ms): 弹窗关闭、返回上一页
  static const Duration exit = Duration(milliseconds: 150);

  // --- 标准曲线 ---
  /// 统一缓动曲线: easeOutCubic
  static const Curve curveStandard = AppTokens.curveStandard;

  /// 退出缓动曲线
  static const Curve curveExit = Curves.easeInCubic;

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
        position: Tween<Offset>(begin: beginOffset, end: Offset.zero).animate(curved),
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
