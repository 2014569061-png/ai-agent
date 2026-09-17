import 'package:flutter/material.dart';

import '../widgets/nexus_background.dart';
import 'motion_preferences.dart';
import 'nexus_motion.dart';

/// 页面层级转场表现形式
enum RoutePresentation {
  /// 详情页（从列表进入）：16dp 水平平移。
  detail,

  /// 设置/配置类页面：<=12dp 水平位移。
  settings,

  /// 工作台/全屏工作区（沉浸式工作流）：轻量水平位移。
  workspace,

  /// 纯淡入
  fade,
}

/// NEXUS 统一页面转场路由
class NexusPageRoute<T> extends PageRouteBuilder<T> {
  final RoutePresentation presentation;
  bool _firstFramePainted = false;

  NexusPageRoute({
    required WidgetBuilder builder,
    super.settings,
    this.presentation = RoutePresentation.detail,
    super.fullscreenDialog,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionDuration: _getTransitionDuration(presentation),
          // Keep both directions on the same fast page-transition rhythm.
          reverseTransitionDuration: _getTransitionDuration(presentation),
          // BackdropFilter 在 Opacity 临时缓冲区中可能产生闪烁；玻璃页面
          // 必须在转场期间保持实时绘制，不能使用路由快照。
          allowSnapshotting: false,
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

  /// 本路由是否在整段生命周期内遮挡下层。
  ///
  /// `fade` 档靠上层淡出让下层透出来，压住下层会变成「淡出到空白再跳出内容」，
  /// 所以这一类必须放行。其余档位都是「上层自带不透明画布底 + 位移只有
  /// 8~16dp」，转场期间下层在视觉上完全不可见。
  bool get _occludesUnderlyingRoute =>
      presentation != RoutePresentation.fade;

  /// 让下层路由停止绘制（**进入和返回都算**）。
  ///
  /// 玻璃档下 `scaffoldBackgroundColor` 是 `Colors.transparent`，画布由
  /// `MaterialApp.builder` 里的 `NexusBackground` 提供。转场期间 Flutter 默认会把
  /// 两层路由画在同一个 backdrop 上，于是：
  /// 1. 两层页面的内容直接叠在一起（用户看到的「两个画面重叠」）；
  /// 2. 玻璃面板采样到这个 backdrop，「卡片里能看到下层页面的文字」；
  /// 3. 整棵下层页面白画一遍，转场掉帧。
  ///
  /// `Overlay` 只在 `entry.opaque == true` 时跳过其下方所有 entry 的绘制，
  /// 而 `TransitionRoute` 只在动画 `completed` 时才置位、并在 forward/reverse
  /// 期间显式置回 false（见 Flutter `widgets/routes.dart` 的
  /// `_handleStatusChanged`）。这里补一个监听把这个置位维持住。
  ///
  /// **为什么返回方向也要压住**（这是返回掉帧的根因）：
  /// 下层在整个被遮挡期间从未被绘制，它的 `_needsPaint` 一直是脏的。一旦恢复，
  /// 第一帧就要把整棵下层页面重新光栅化——聊天页里包含全屏背景图、消息列表
  /// 和两处玻璃面板（`BackdropFilter` + 折射着色器），这一帧恰好还压着上层
  /// 退出动画的绘制，必然超预算。而这段时间下层画不画，视觉上完全一样：
  /// 上层自带不透明画布底，位移只有 8~16dp，露出的边缘与根背景同一张底。
  ///
  /// **为什么用 `animation.addListener` 就够**（不需要帧回调）：
  /// `_handleStatusChanged` 是在 `reverse()` 的同步栈里把标记置回 false 的，
  /// 而动画的第一次 tick 发生在下一帧的 transient 阶段——早于
  /// build/layout/paint。监听器在同一个 tick 里把标记纠正回来，这一帧的
  /// `_Theatre.skipCount` 就已经是正确的，不会有「白画一帧」。
  ///
  /// **为什么返回方向是「零绘制」而进入方向会多一次**：
  /// 下层刚被跳过的第一帧，它的 `RepaintBoundary` 还是上一帧的 attached 状态，
  /// 于是那次 `markNeedsPaint` 会走 `repaintCompositedChild` 真的重录一遍
  /// （结果不进入合成，因为此时它已不在 onstage 集合里）。从第二帧起它的
  /// layer 处于 detach 状态，后续一切 `markNeedsPaint` 都走
  /// `_skippedPaintingOnLayer`，不再产生任何绘制——返回方向正好整段都落在
  /// 这个状态里，所以整个返回动画一次绘制都不发生。
  /// 回归保护：`test/route_transition_paint_test.dart`。
  void _keepUnderlyingRouteHidden() {
    if (!_occludesUnderlyingRoute) return;
    if (overlayEntries.isEmpty) return;
    // Let the first push frame keep the previous route as a visual fallback.
    // The new page may not have recorded its first composited layer yet;
    // hiding the old route before that frame exposes a white flash.
    if (!_firstFramePainted) return;
    final entry = overlayEntries.first;
    if (entry.opaque) return;
    entry.opaque = true;
  }

  @override
  TickerFuture didPush() {
    final future = super.didPush();
    animation?.addListener(_keepUnderlyingRouteHidden);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (overlayEntries.isEmpty) return;
      _firstFramePainted = true;
      _keepUnderlyingRouteHidden();
    });
    return future;
  }

  @override
  void dispose() {
    animation?.removeListener(_keepUnderlyingRouteHidden);
    super.dispose();
  }

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
        return NexusMotion.fast; // 150ms
      case RoutePresentation.settings:
        return NexusMotion.fast; // 150ms
      case RoutePresentation.workspace:
        return NexusMotion.fast; // 150ms
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
    // 页面自带画布底，视觉与 MaterialApp.builder 里的根 NexusBackground 完全一致。
    //
    // 玻璃档下 Scaffold 背景是透明的（app_theme.dart 的 scaffoldBackgroundColor），
    // 页面本身没有任何不透明区域。转场期间只要还看得见下层，就会出现
    // 「两个画面重叠」——而且玻璃面板会把下层的文字折射进卡片里。
    //
    // 之前只靠「push 时让下层停止绘制」规避，但 pop 时下层必须继续绘制
    // （否则下层会直到转场结束才突然出现，反而是跳变），于是 pop 期间必然同框。
    // 给页面自己一个不透明底才是根本解：无论上下的绘制策略如何，视觉上都被遮住。
    // 因为底色与根背景同一套视觉，滑入滑出时露出的边缘也是同一张底，接缝不可见。
    // Keep the page as one composited layer.  During a reverse transition the
    // page is only translated; without this boundary Flutter repaints every
    // BackdropFilter and optical painter on every animation tick.
    final canvasChild = RepaintBoundary(
      child: NexusBackground(child: child),
    );

    // 检查是否开启无障碍「减少动态效果」
    if (MotionPreferences.shouldReduceMotion(context)) {
      return canvasChild;
    }

    // 返回方向：把整页替换成一张已光栅化的快照。
    //
    // 实测（见 `test/route_transition_paint_test.dart` 的「返回期上层快照」用例）
    // 返回期间本页如果内部还有活跃内容（流式增量、光标闪烁、指标条），
    // 每一帧都会被重绘一次：`[1,1,1,1,1,1,1,1,1,1]` ≈ 9~10 次全页重录；
    // 一个静态页面则是 `[0,0,...]`。差异全部来自页面自身内容变脏，而不是位移
    // ——`SlideTransition` 只改 layer 的 transform，本身不触发重绘。
    //
    // 也就是说这 10 次重录**在视觉上是完全不可见的**：页面在这段时间里只是
    // 被平移 8~16dp，它上一次录下来的 picture 依然有效。包快照后降到 1 次
    // （就是拍摄快照那一帧本身）。
    //
    // 为什么 `RepaintBoundary` 挡不住：边界只对**它上方**的调用者做缓存，子树内部
    // 变脏照样要重录。要真正跳过，必须在「子树 vs 图层」之间插一层图片。
    //
    // 为什么只在 reverse 期间开：
    // * push 时页面是新的，第一帧必须真实绘制才能拍出快照，开了也没有收益；
    // * 快照会冻结这段时间的页面内容（进度条不动、光标不闪），150ms 的退出期间
    //   用户看不出来，但绝不能在稳态下开着。
    // `SnapshotMode.permissive`：本项目 `lib/` 下没有任何平台视图（已核实无
    // `AndroidView` / `UiKitView` / `WebView`），但 permissive 会在遇到平台视图时
    // 自动退回普通绘制而不是抛异常，作为兜底更稳妥。
    return _SnapshotOnExit(
      animation: animation,
      child: switch (presentation) {
        RoutePresentation.detail => SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(16.0 / 360.0, 0.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: NexusMotion.curveStandard,
              reverseCurve: NexusMotion.curveExit,
            )),
            child: canvasChild,
          ),
        RoutePresentation.settings => SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(10.0 / 360.0, 0.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: NexusMotion.curveStandard,
              reverseCurve: NexusMotion.curveExit,
            )),
            child: canvasChild,
          ),
        RoutePresentation.workspace => SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(8.0 / 360.0, 0.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: NexusMotion.curveStandard,
              reverseCurve: NexusMotion.curveExit,
            )),
            child: canvasChild,
          ),
        // fade 档靠上层淡出让下层透出，快照会把「淡出」变成「一张图淡出」，
        // 视觉上等价，但玻璃面板在快照里会失去实时采样，所以放行。
        RoutePresentation.fade => canvasChild,
      },
    );
  }
}

/// 在动画反向（返回）期间，用一张快照替代整棵子树参与绘制。
///
/// 页面在返回期间只被平移，内容变化在视觉上不可见，逐帧重录是纯浪费。
/// 这里把「子树」换成「一张已经拍好的图」，让每帧只剩 layer 的 transform 变化。
///
/// 只在 `reverse` 期间启用：进入方向第一帧必须真实绘制，快照也无意义；
/// 稳态下必须关掉，否则页面内容会被永久冻结。
class _SnapshotOnExit extends StatefulWidget {
  const _SnapshotOnExit({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  State<_SnapshotOnExit> createState() => _SnapshotOnExitState();
}

class _SnapshotOnExitState extends State<_SnapshotOnExit> {
  final SnapshotController _controller = SnapshotController();

  @override
  void initState() {
    super.initState();
    widget.animation.addListener(_sync);
    _sync();
  }

  @override
  void didUpdateWidget(covariant _SnapshotOnExit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeListener(_sync);
      widget.animation.addListener(_sync);
    }
    _sync();
  }

  @override
  void dispose() {
    widget.animation.removeListener(_sync);
    _controller.dispose();
    super.dispose();
  }

  void _sync() {
    _controller.allowSnapshotting =
        widget.animation.status == AnimationStatus.reverse;
  }

  @override
  Widget build(BuildContext context) {
    return SnapshotWidget(
      controller: _controller,
      mode: SnapshotMode.permissive,
      child: widget.child,
    );
  }
}
