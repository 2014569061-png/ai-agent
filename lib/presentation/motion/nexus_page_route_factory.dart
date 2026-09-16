import 'package:flutter/material.dart';
import 'motion_preferences.dart';
import 'nexus_motion.dart';

/// 页面层级转场表现形式
enum RoutePresentation {
  /// 详情页（从列表进入）：fade + 16dp 水平平移，退出时轻微反向淡出
  detail,

  /// 设置/配置类页面：轻量淡入 + <=12dp 位移
  settings,

  /// 工作台/全屏工作区（沉浸式工作流）：轻量淡入
  workspace,

  /// 纯淡入
  fade,
}

/// NEXUS 统一页面转场路由
class NexusPageRoute<T> extends PageRouteBuilder<T> {
  final RoutePresentation presentation;

  NexusPageRoute({
    required WidgetBuilder builder,
    super.settings,
    this.presentation = RoutePresentation.detail,
    super.fullscreenDialog,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionDuration: _getTransitionDuration(presentation),
          reverseTransitionDuration: NexusMotion.exit,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return _buildTransition(
              context,
              animation,
              secondaryAnimation,
              child,
              presentation,
            );
          },
        );

  /// 详情页快捷构造函数
  factory NexusPageRoute.detail({
    required WidgetBuilder builder,
    RouteSettings? settings,
    bool fullscreenDialog = false,
  }) {
    return NexusPageRoute<T>(
      builder: builder,
      settings: settings,
      presentation: RoutePresentation.detail,
      fullscreenDialog: fullscreenDialog,
    );
  }

  /// 设置/配置页快捷构造函数
  factory NexusPageRoute.settingsPage({
    required WidgetBuilder builder,
    RouteSettings? settings,
    bool fullscreenDialog = false,
  }) {
    return NexusPageRoute<T>(
      builder: builder,
      settings: settings,
      presentation: RoutePresentation.settings,
      fullscreenDialog: fullscreenDialog,
    );
  }

  /// 全屏工作区快捷构造函数
  factory NexusPageRoute.workspace({
    required WidgetBuilder builder,
    RouteSettings? settings,
    bool fullscreenDialog = false,
  }) {
    return NexusPageRoute<T>(
      builder: builder,
      settings: settings,
      presentation: RoutePresentation.workspace,
      fullscreenDialog: fullscreenDialog,
    );
  }

  /// 纯淡入快捷构造函数
  factory NexusPageRoute.fade({
    required WidgetBuilder builder,
    RouteSettings? settings,
    bool fullscreenDialog = false,
  }) {
    return NexusPageRoute<T>(
      builder: builder,
      settings: settings,
      presentation: RoutePresentation.fade,
      fullscreenDialog: fullscreenDialog,
    );
  }

  static Duration _getTransitionDuration(RoutePresentation presentation) {
    switch (presentation) {
      case RoutePresentation.detail:
        return NexusMotion.base; // 220ms
      case RoutePresentation.settings:
        return NexusMotion.base; // 220ms
      case RoutePresentation.workspace:
        return NexusMotion.base; // 220ms
      case RoutePresentation.fade:
        return NexusMotion.fast; // 150ms
    }
  }

  static Widget _buildTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
    RoutePresentation presentation,
  ) {
    // 检查是否开启无障碍「减少动态效果」
    if (MotionPreferences.shouldReduceMotion(context)) {
      return child;
    }

    final curvedIn = CurvedAnimation(
      parent: animation,
      curve: NexusMotion.curveStandard,
      reverseCurve: NexusMotion.curveExit,
    );

    switch (presentation) {
      case RoutePresentation.detail:
        // 进入: 16dp 水平平移 + 淡入
        // 退出: 8dp 水平平移 + 淡出
        final slideIn = Tween<Offset>(
          begin: const Offset(16.0 / 360.0, 0.0),
          end: Offset.zero,
        ).animate(curvedIn);

        return SlideTransition(
          position: slideIn,
          child: FadeTransition(
            opacity: curvedIn,
            child: child,
          ),
        );

      case RoutePresentation.settings:
        // 设置页: 轻微 10dp 水平位移 + 淡入
        final slideIn = Tween<Offset>(
          begin: const Offset(10.0 / 360.0, 0.0),
          end: Offset.zero,
        ).animate(curvedIn);

        return SlideTransition(
          position: slideIn,
          child: FadeTransition(
            opacity: curvedIn,
            child: child,
          ),
        );

      case RoutePresentation.workspace:
      case RoutePresentation.fade:
        return FadeTransition(
          opacity: curvedIn,
          child: child,
        );
    }
  }
}
