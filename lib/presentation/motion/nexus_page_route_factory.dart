import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_tokens.dart';
import '../widgets/nexus_background.dart';
import 'motion_intensity.dart';
import 'motion_preferences.dart';
import 'motion_tier.dart';
import 'nexus_motion.dart';
import 'nexus_spring.dart';
import 'tap_origin.dart';

/// 页面层级转场表现形式
enum RoutePresentation {
  /// 详情页（从列表进入）：整屏左右位移 + 下层视差暗化。
  detail,

  /// 设置/配置类页面：同 detail（上下层级关系一致）。
  settings,

  /// 工作台/全屏工作区：同 detail。
  workspace,

  /// 纯淡入（下层保持不动、透出）。
  fade,
}

/// NEXUS 统一页面转场路由（整屏「左右位移遮罩」）。
///
/// 设计思路借鉴 HarmonyOS 的层级转场：上下层级页面左右位移、不单帧切换、
/// 曲线优先弹簧。参数为本项目独立制定：
///
/// | 角色 | 进入（push） | 返回（pop） |
/// | --- | --- | --- |
/// | 上层 | translateX 100% → 0，[NexusMotion.springRelease] 归一化曲线，350ms | 0 → 100%，250ms 标准曲线 |
/// | 下层 | translateX 0 → −30%（视差）+ 暗化 α 0 → 0.12 | 反向 |
///
/// 下层动画通过 [delegatedTransition] 交给下层路由执行，因此即使下层是
/// `MaterialApp.home` 生成的 MaterialPageRoute 也能同步让位；下层同为
/// [NexusPageRoute] 时（Flutter 不会把相同的 delegatedTransition 交给它），
/// 由它自己在 [buildTransitions] 里根据 secondaryAnimation 执行同一套动画。
///
/// 性能契约（见 `test/route_transition_paint_test.dart`）：
/// * 转场期间下层以**快照**参与绘制，只改 transform，不逐帧重录；
/// * 返回期间上层同样替换为快照；
/// * 转场结束后恢复真实绘制；稳态下下层由 Flutter 默认的 opaque 机制停绘。
class NexusPageRoute<T> extends PageRouteBuilder<T> {
  final RoutePresentation presentation;

  /// 栈中上一层（next route）是否是会让本页让位的整屏位移路由。
  ///
  /// 只在得知新的上层时更新；上层被移除（null）时保持原值——此时
  /// secondaryAnimation 已是 dismissed，保持原值不会产生任何效果，
  /// 反而能避免返回动画进行中被提前关掉导致的跳变。
  bool _yieldsToNext = false;

  NexusPageRoute({
    required WidgetBuilder builder,
    super.settings,
    this.presentation = RoutePresentation.detail,
    super.fullscreenDialog,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionDuration:
              _getTransitionDuration(presentation, entering: true),
          reverseTransitionDuration:
              _getTransitionDuration(presentation, entering: false),
          // BackdropFilter 在 Opacity 临时缓冲区中可能产生闪烁；这里关闭
          // Flutter 内置的路由快照，快照统一由本文件的 [_SnapshotWhile] 控制。
          allowSnapshotting: false,
        ) {
    // L5：详情页从被点击的卡片 / 行「展开」而来（容器变换）。
    if (presentation == RoutePresentation.detail && !fullscreenDialog) {
      originRect = captureOrigin();
    }
  }

  /// L5 容器变换起点（全局坐标）；null 时退回整屏左右位移。
  Rect? originRect;

  bool get _morphs => originRect != null;

  /// 按最近一次新鲜的按下位置命中测试当前布局，取「像卡片 / 行」的最内层盒子：
  /// 高 ≥ 44、宽 ≥ 96，且面积不超过屏幕一半（再往外就是整页容器了）。
  /// 找不到合适的盒子时，从按下点附近 48×48 的小方块展开。
  static Rect? captureOrigin() {
    final point = NexusTapOrigin.recent();
    if (point == null) return null;
    // 构建 / 布局进行中布局可能是脏的，不做命中测试。
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      return null;
    }
    try {
      return _hitOrigin(point);
    } catch (_) {
      return null;
    }
  }

  static Rect? _hitOrigin(Offset point) {
    final binding = WidgetsBinding.instance;
    final view = binding.platformDispatcher.implicitView ??
        (binding.platformDispatcher.views.isEmpty
            ? null
            : binding.platformDispatcher.views.first);
    if (view == null) return null;
    final screen = view.physicalSize / view.devicePixelRatio;
    final result = HitTestResult();
    binding.hitTestInView(result, point, view.viewId);
    for (final entry in result.path) {
      final target = entry.target;
      if (target is! RenderBox || !target.attached || !target.hasSize) {
        continue;
      }
      final size = target.size;
      if (size.width * size.height > screen.width * screen.height * 0.5) {
        break;
      }
      if (size.height < 44 || size.width < 96) continue;
      return target.localToGlobal(Offset.zero) & size;
    }
    return Rect.fromCenter(center: point, width: 48, height: 48);
  }

  /// 进入方向的弹簧曲线（离手弹簧归一化 + 钳制不越界）。
  static final Curve enterCurve = NexusSpringCurve(NexusMotion.springRelease);

  /// L5 容器变换曲线：smooth 弹簧（无过冲，形变不晃）。
  static final Curve containerCurve = NexusSprings.curveOf(NexusSprings.smooth);

  /// 下层视差位移比例（相对屏宽）。
  static const double parallaxFraction = 0.3;

  /// 下层暗化遮罩最大不透明度。
  static const double dimOpacity = 0.12;

  bool get _slides => presentation != RoutePresentation.fade;

  @override
  DelegatedTransitionBuilder? get delegatedTransition => _morphs
      ? _delegatedDimTransition
      : (_slides ? _delegatedSecondaryTransition : null);

  /// 容器变换时下层不视差位移，只暗化（卡片原地「长成」新页面）。
  static Widget? _delegatedDimTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    bool allowSnapshotting,
    Widget? child,
  ) {
    final content = child ?? const SizedBox.shrink();
    if (secondaryAnimation.isDismissed ||
        MotionPreferences.shouldReduceMotion(context)) {
      return content;
    }
    return Stack(
      fit: StackFit.passthrough,
      children: [
        _SnapshotWhile(
          animation: secondaryAnimation,
          when: (status) =>
              status == AnimationStatus.forward ||
              status == AnimationStatus.reverse,
          child: content,
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: FadeTransition(
              opacity: secondaryAnimation,
              child: ColoredBox(
                color: Colors.black.withValues(alpha: dimOpacity),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static Widget? _delegatedSecondaryTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    bool allowSnapshotting,
    Widget? child,
  ) =>
      buildSecondaryTransition(
        context,
        secondaryAnimation,
        child ?? const SizedBox.shrink(),
      );

  @override
  void didChangeNext(Route<dynamic>? nextRoute) {
    super.didChangeNext(nextRoute);
    if (nextRoute == null) return;
    _yieldsToNext =
        nextRoute is NexusPageRoute && nextRoute._slides && !nextRoute._morphs;
  }

  @override
  Duration get transitionDuration =>
      _effectiveDuration(super.transitionDuration);

  @override
  Duration get reverseTransitionDuration =>
      _effectiveDuration(super.reverseTransitionDuration);

  Duration _effectiveDuration(Duration base) {
    final routeContext = navigator?.context;
    return routeContext == null
        ? base
        : MotionPreferences.adjustDuration(routeContext, base, listen: false);
  }

  void _syncDurations() {
    controller?.duration = transitionDuration;
    controller?.reverseDuration = reverseTransitionDuration;
  }

  @override
  TickerFuture didPush() {
    _syncDurations();
    return super.didPush();
  }

  @override
  bool didPop(T? result) {
    _syncDurations();
    return super.didPop(result);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final primary = _buildPrimaryTransition(context, animation, child);
    if (!_yieldsToNext) return primary;
    return buildSecondaryTransition(context, secondaryAnimation, primary);
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

  static Duration _getTransitionDuration(
    RoutePresentation presentation, {
    required bool entering,
  }) {
    if (presentation == RoutePresentation.fade) {
      return entering ? NexusMotion.base : NexusMotion.pageExit;
    }
    return entering ? NexusMotion.pageSpring : NexusMotion.page;
  }

  Widget _buildPrimaryTransition(
    BuildContext context,
    Animation<double> animation,
    Widget child,
  ) {
    // 页面自带不透明画布底（与根 NexusBackground 同一套视觉）：
    // 玻璃档下 Scaffold 背景是透明的，没有这层底，位移过程中上下两层内容会
    // 叠在一起，玻璃面板还会把下层文字折射进卡片。
    // RepaintBoundary 让位移只改 layer transform，不触发子树重绘。
    final canvasChild = RepaintBoundary(
      child: NexusBackground(child: child),
    );

    final level = MotionPreferences.levelOf(context);
    if (level == MotionLevel.off) return canvasChild;
    if (level == MotionLevel.reduced || !_slides) {
      // 减少动态效果 / fade 档：只做透明度（fade 档靠上层淡出让下层透出，
      // 快照会让玻璃失去实时采样，所以不包快照）。
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: NexusMotion.curveStandard,
        ),
        child: canvasChild,
      );
    }

    if (_morphs) {
      return _ContainerMorph(
        animation: _FollowGesture(
          parent: animation,
          curved: CurvedAnimation(
            parent: animation,
            curve: containerCurve,
            reverseCurve: NexusMotion.curveStandard,
          ),
          gesture: () => navigator?.userGestureInProgress ?? false,
        ),
        origin: originRect!,
        child: _SnapshotWhile(
          animation: animation,
          when: (status) => status == AnimationStatus.reverse,
          child: canvasChild,
        ),
      );
    }

    return _SnapshotWhile(
      animation: animation,
      // 只在返回期间快照：push 时页面是新的，第一帧必须真实绘制。
      when: (status) => status == AnimationStatus.reverse,
      child: SlideTransition(
        // L5：系统返回手势进行中按手指进度线性跟手，不走曲线。
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(_FollowGesture(
          parent: animation,
          curved: CurvedAnimation(
            parent: animation,
            curve: enterCurve,
            reverseCurve: NexusMotion.curveStandard,
          ),
          gesture: () => navigator?.userGestureInProgress ?? false,
        )),
        child: _LeadingEdgeShadow(child: canvasChild),
      ),
    );
  }

  /// 下层让位动画：视差位移 + 暗化遮罩，整段以快照参与绘制。
  ///
  /// 公开给 [delegatedTransition] 与测试使用。
  static Widget buildSecondaryTransition(
    BuildContext context,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (secondaryAnimation.isDismissed ||
        MotionPreferences.shouldReduceMotion(context)) {
      return child;
    }
    final budget = MotionBudget.of(context);
    // S1：视差与暗化随强度放大（鲜明档 30% → 45%、0.12 → 0.22）。
    final parallax = amplify(parallaxFraction, budget.gain, 0.5);
    final dim = amplify(dimOpacity, budget.gain, 0.85);
    final curved = CurvedAnimation(
      parent: secondaryAnimation,
      curve: enterCurve,
      reverseCurve: NexusMotion.curveStandard,
    );
    Widget result = _SnapshotWhile(
      animation: secondaryAnimation,
      when: (status) =>
          status == AnimationStatus.forward ||
          status == AnimationStatus.reverse,
      child: child,
    );
    if (budget.routeParallax) {
      result = SlideTransition(
        position: Tween<Offset>(
          begin: Offset.zero,
          end: Offset(-parallax, 0),
        ).animate(curved),
        child: result,
      );
    }
    return Stack(
      fit: StackFit.passthrough,
      children: [
        result,
        Positioned.fill(
          child: IgnorePointer(
            child: FadeTransition(
              opacity: curved,
              child: ColoredBox(
                color: Colors.black.withValues(alpha: dim),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 上层页面左缘的柔和投影，让位移中的上下层级更清晰。
/// 投影位于页面左边界之外，页面就位后自然移出屏幕，无需额外动画。
class _LeadingEdgeShadow extends StatelessWidget {
  const _LeadingEdgeShadow({required this.child});

  final Widget child;

  static const double _width = 16;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final alpha = isDark ? 0.20 : 0.08;
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned(
          left: -_width,
          top: 0,
          bottom: 0,
          width: _width,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [
                    Colors.black.withValues(alpha: alpha),
                    Colors.black.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 在 [when] 成立期间，用一张快照替代整棵子树参与绘制。
///
/// 转场期间页面只被平移，内容变化在视觉上不可见，逐帧重录是纯浪费。
/// 这里把「子树」换成「一张已经拍好的图」，让每帧只剩 layer 的 transform
/// 变化。条件不成立时（稳态）必须关掉，否则页面内容会被永久冻结。
///
/// `SnapshotMode.permissive`：遇到平台视图时自动退回普通绘制而不是抛异常。
class _SnapshotWhile extends StatefulWidget {
  const _SnapshotWhile({
    required this.animation,
    required this.when,
    required this.child,
  });

  final Animation<double> animation;
  final bool Function(AnimationStatus status) when;
  final Widget child;

  @override
  State<_SnapshotWhile> createState() => _SnapshotWhileState();
}

class _SnapshotWhileState extends State<_SnapshotWhile> {
  final SnapshotController _controller = SnapshotController();

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_onStatus);
    _sync();
  }

  @override
  void didUpdateWidget(covariant _SnapshotWhile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeStatusListener(_onStatus);
      widget.animation.addStatusListener(_onStatus);
    }
    _sync();
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_onStatus);
    _controller.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus _) => _sync();

  void _sync() {
    final allow = widget.when(widget.animation.status);
    if (_controller.allowSnapshotting == allow) return;
    // 每次重新开启都丢弃旧快照，保证拍到的是当前内容。
    if (allow) _controller.clear();
    _controller.allowSnapshotting = allow;
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

/// 手势返回进行中直接使用控制器的线性进度（页面跟手），否则走 [curved]。
class _FollowGesture extends Animation<double>
    with AnimationWithParentMixin<double> {
  _FollowGesture({
    required this.parent,
    required this.curved,
    required this.gesture,
  });

  @override
  final Animation<double> parent;
  final Animation<double> curved;
  final bool Function() gesture;

  @override
  double get value => gesture() ? parent.value : curved.value;
}

/// L5 容器变换：页面按全屏布局，缩放到起点矩形的宽度绘制并裁到矩形高度，
/// 矩形与圆角随进度插值到全屏；前 35% 叠一层表面色面纱淡出，
/// 让「卡片」先长大、内容再显现。不使用 Opacity（玻璃 BackdropFilter 会闪）。
class _ContainerMorph extends StatelessWidget {
  const _ContainerMorph({
    required this.animation,
    required this.origin,
    required this.child,
  });

  final Animation<double> animation;
  final Rect origin;
  final Widget child;

  static const double veilEnd = 0.35;

  @override
  Widget build(BuildContext context) {
    final veil = Theme.of(context).colorScheme.surface;
    return LayoutBuilder(
      builder: (context, constraints) {
        final full = Offset.zero & constraints.biggest;
        return AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) {
            // 落定后结构保持不变（只是数值归位），避免页面在转场结束时被重建。
            final t = animation.value;
            final done = t >= 1;
            final rect = done ? full : Rect.lerp(origin, full, t)!;
            final scale =
                done || full.width == 0 ? 1.0 : rect.width / full.width;
            final radius =
                ui.lerpDouble(AppTokens.radiusCard, 0, t.clamp(0.0, 1.0))!;
            final veilAlpha = (1 - t / veilEnd).clamp(0.0, 1.0);
            return Stack(
              children: [
                Positioned.fromRect(
                  rect: rect,
                  child: ClipRRect(
                    clipBehavior: done ? Clip.none : Clip.antiAlias,
                    borderRadius: BorderRadius.circular(done ? 0 : radius),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        OverflowBox(
                          alignment: Alignment.topLeft,
                          minWidth: full.width,
                          maxWidth: full.width,
                          minHeight: full.height,
                          maxHeight: full.height,
                          child: Transform.scale(
                            scale: scale,
                            alignment: Alignment.topLeft,
                            child: child,
                          ),
                        ),
                        if (veilAlpha > 0)
                          IgnorePointer(
                            child: ColoredBox(
                              color: veil.withValues(alpha: veilAlpha),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
