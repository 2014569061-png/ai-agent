import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../motion/motion_preferences.dart';
import '../motion/nexus_haptics.dart';
import '../motion/nexus_motion.dart';
import '../motion/nexus_spring.dart';
import '../motion/tap_origin.dart';
import '../theme/app_appearance_controller.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import 'glass_surface.dart';
import 'nexus_surface.dart';

/// 统一的沉浸式现代底栏抽屉 (Modern Bottom Sheet) 入口。
/// 采用紧凑轻量底栏悬浮卡片形式呈现，避免全屏/大面积遮挡。
Future<T?> showNexusSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  bool showDragHandle = true,
  bool isBottomDocked = true,
  double? maxHeightRatio,
  Color? barrierColor,
  bool barrierDismissible = true,
  String? barrierLabel,
}) {
  final effectiveBarrierColor = barrierColor ??
      Colors.black.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.35 : 0.06,
      );
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel ?? AppStrings.closeDialog,
    barrierColor: effectiveBarrierColor,
    transitionDuration: MotionPreferences.adjustDuration(
        context, NexusMotion.sheet,
        listen: false),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final media = MediaQuery.sizeOf(dialogContext);
      final insetsBottom = MediaQuery.viewInsetsOf(dialogContext).bottom;
      final baseTheme = Theme.of(dialogContext);
      final isDark = baseTheme.brightness == Brightness.dark;
      final maxSheetHeight =
          media.height * (maxHeightRatio ?? (isBottomDocked ? 0.72 : 0.82));
      final sheetRadius = BorderRadius.circular(AppTokens.radiusModal);
      final intensity = AppAppearanceController.resolvedGlassIntensity;

      final innerContent = Theme(
        data: baseTheme.copyWith(
          dialogTheme: baseTheme.dialogTheme.copyWith(
            backgroundColor: Colors.transparent,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
          ),
        ),
        child: SafeArea(
          top: false,
          bottom: isBottomDocked,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showDragHandle && isBottomDocked)
                _SheetDragHandle(
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 4),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              Flexible(
                child: builder(dialogContext),
              ),
            ],
          ),
        ),
      );

      final surfaceWidget = intensity == GlassIntensity.flat
          ? NexusSurface(
              level: SurfaceLevel.ultraThick,
              borderRadius: sheetRadius,
              margin: EdgeInsets.zero,
              padding: EdgeInsets.zero,
              child: innerContent,
            )
          : GlassSurface(
              role: GlassRole.overlay,
              variant: GlassVariant.regular,
              intensity: intensity,
              borderRadius: sheetRadius,
              tint: isDark
                  ? AppPalette.darkSurface.withValues(alpha: 0.65)
                  : Colors.white.withValues(alpha: 0.78),
              blurSigma: 26,
              refraction: 18,
              edgeWidth: 24,
              gloss: 0.65,
              child: innerContent,
            );

      final sheetWidget = ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: maxSheetHeight,
        ),
        child: Material(
          color: Colors.transparent,
          child: surfaceWidget,
        ),
      );

      if (isBottomDocked) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              0,
              12,
              insetsBottom > 0 ? insetsBottom + 8 : 12,
            ),
            child: sheetWidget,
          ),
        );
      }

      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          child: sheetWidget,
        ),
      );
    },
    transitionBuilder: (context, anim, secAnim, child) {
      if (MotionPreferences.shouldReduceMotion(context)) {
        return child;
      }
      return _NexusSheetMotion(
        animation: anim,
        isBottomDocked: isBottomDocked,
        barrierColor: effectiveBarrierColor,
        barrierLabel: AppStrings.closeApprovalSheet,
        child: child,
      );
    },
  );
}

class _SheetDragNotification extends Notification {
  const _SheetDragNotification.update(this.delta) : velocity = null;
  const _SheetDragNotification.end(this.velocity) : delta = 0;

  final double delta;
  final double? velocity;

  bool get isEnd => velocity != null;
}

/// Keep dismissal gestures on the handle so scrolling content retains its own
/// gesture arena. The parent owns the actual translation and threshold logic.
class _SheetDragHandle extends StatelessWidget {
  const _SheetDragHandle({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) =>
          _SheetDragNotification.update(details.primaryDelta ?? 0)
              .dispatch(context),
      onVerticalDragEnd: (details) =>
          _SheetDragNotification.end(details.velocity.pixelsPerSecond.dy)
              .dispatch(context),
      child: child,
    );
  }
}

class _NexusSheetMotion extends StatefulWidget {
  const _NexusSheetMotion({
    required this.animation,
    required this.isBottomDocked,
    required this.barrierColor,
    required this.barrierLabel,
    required this.child,
  });

  final Animation<double> animation;
  final bool isBottomDocked;
  final Color barrierColor;
  final String barrierLabel;
  final Widget child;

  @override
  State<_NexusSheetMotion> createState() => _NexusSheetMotionState();
}

class _NexusSheetMotionState extends State<_NexusSheetMotion>
    with SingleTickerProviderStateMixin {
  /// 下拉关闭阈值（占屏高比例）与甩动速度阈值（px/s）。
  static const double dismissFraction = 0.18;
  static const double dismissVelocity = 900;

  /// 向上拖过静止位时的橡皮筋极限位移（px）。
  static const double rubberLimit = 36;

  /// 拖动位移（占屏高比例；负值 = 向上的橡皮筋区）。弹簧驱动，松手保留速度。
  late final SpringController _drag = SpringController(vsync: this);

  /// 手指累计位移（px，未经橡皮筋换算）。
  double _rawDrag = 0;
  bool _pastThreshold = false;

  double get _dragFraction => _drag.value;

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  double _screenHeight() => MediaQuery.sizeOf(context).height;

  /// 向下 1:1 跟手；向上越过静止位按橡皮筋衰减，越拉越紧。
  static double rubberBand(double raw) {
    if (raw >= 0) return raw;
    final x = -raw;
    return -rubberLimit * (1 - 1 / (x * 0.55 / rubberLimit + 1));
  }

  void _dragBy(double delta) {
    final height = _screenHeight();
    if (_drag.isAnimating) {
      // 接住回弹中的抽屉：从当前显示位置继续跟手。
      _rawDrag = _dragFraction * height;
      _drag.stop();
    }
    _rawDrag = (_rawDrag + delta).clamp(-height, height * 0.9);
    _drag.jumpTo(rubberBand(_rawDrag) / height);
    final past = _dragFraction > dismissFraction;
    if (past != _pastThreshold) {
      _pastThreshold = past;
      NexusHaptics.selection(context);
    }
  }

  void _release(double velocity) {
    final height = _screenHeight();
    _rawDrag = 0;
    _pastThreshold = false;
    final shouldDismiss =
        _dragFraction > dismissFraction || velocity > dismissVelocity;
    if (shouldDismiss) {
      Navigator.of(context).maybePop();
      return;
    }
    if (_dragFraction.abs() < 0.001 && velocity.abs() < 1) {
      _drag.jumpTo(0);
      return;
    }
    NexusHaptics.light(context);
    // 带着手指速度弹回静止位：bouncy 允许一次轻回弹（reduced / off 已降级）。
    _drag.animateTo(
      0,
      spring: NexusSpringPolicy.resolve(context, NexusSprings.bouncy,
          listen: false),
      velocity: velocity / height,
    );
  }

  bool _onDrag(_SheetDragNotification notification) {
    if (!widget.isBottomDocked) return false;
    if (notification.isEnd) {
      _release(notification.velocity!);
    } else {
      // 下拉 1:1 跟手；静止位继续上推进入橡皮筋区。
      _dragBy(notification.delta);
    }
    return true;
  }

  /// 内容滚到顶后继续下拉 → 转交给抽屉跟手；抽屉已下移时上滑先收回抽屉。
  bool _onScroll(ScrollNotification notification) {
    if (!widget.isBottomDocked || notification.depth != 0) return false;
    if (notification is OverscrollNotification &&
        notification.dragDetails != null &&
        notification.overscroll < 0) {
      _dragBy(-notification.overscroll);
    } else if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null &&
        _dragFraction > 0 &&
        (notification.scrollDelta ?? 0) > 0) {
      _dragBy(-(notification.scrollDelta ?? 0));
    } else if (notification is ScrollEndNotification &&
        _dragFraction.abs() > 0.001) {
      _release(notification.dragDetails?.velocity.pixelsPerSecond.dy ?? 0);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final spring = NexusSpringPolicy.resolve(context, NexusSprings.bouncy);
    final entering = CurvedAnimation(
      parent: widget.animation,
      // L4：入场按 bouncy 弹簧曲线，落位时带一次轻回弹。
      curve: spring == null
          ? NexusMotion.curveSheetEnter
          : NexusSprings.curveOf(spring, allowOvershoot: true),
      reverseCurve: NexusMotion.curveExit,
    );
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: NotificationListener<_SheetDragNotification>(
        onNotification: _onDrag,
        child: AnimatedBuilder(
          animation: Listenable.merge([entering, _drag]),
          child: widget.child,
          builder: (context, child) {
            final enter = entering.value;
            final dismissalProgress = widget.isBottomDocked
                ? (_dragFraction / 0.42).clamp(0.0, 1.0)
                : 0.0;
            final barrierOpacity =
                (enter * (1.0 - dismissalProgress)).clamp(0.0, 1.0);
            final sheetScale = 1.0 - dismissalProgress * 0.015;
            final barrier = Semantics(
              button: true,
              label: widget.barrierLabel,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                child: ColoredBox(
                  color: widget.barrierColor.withValues(alpha: 0),
                  child: Opacity(
                    opacity: barrierOpacity,
                    child: ColoredBox(color: widget.barrierColor),
                  ),
                ),
              ),
            );
            if (!widget.isBottomDocked) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  barrier,
                  Transform.scale(
                    scale: 0.95 + 0.05 * enter,
                    child: child,
                  ),
                ],
              );
            }
            // Keep the glass surface outside Opacity so BackdropFilter samples
            // the scene directly. Only the separate barrier fades with drag.
            final offset = (1 - enter) * 0.18 + _dragFraction;
            return Stack(
              fit: StackFit.expand,
              children: [
                barrier,
                FractionalTranslation(
                  translation: Offset(0, offset),
                  child: Transform.scale(
                    alignment: Alignment.bottomCenter,
                    scale: sheetScale,
                    child: child,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 统一的沉浸式毛玻璃对话框入口，替代不透明的 showDialog / AlertDialog 表面。
///
/// ⚠️ 这里**不能**把调用方的 `AlertDialog` 塞进 `NexusSurface` / `GlassSurface`
/// 这类「外壳」里。`AlertDialog` 内部走的是 `Dialog`，而 `Dialog` 的布局根节点
/// 是一个 `Align`（见 Flutter `material/dialog.dart`），它在父约束有界时
/// **必定撑满整个可用空间**——那是给 `showDialog` 用的、不可见的定位层。
/// 一旦外面套上有可见背景的外壳，外壳就会被它顶满：
/// 这正是「点『从模板新建』弹出一个占据整屏的白底对话框」的成因
/// （实测外壳被撑到 344.7×794.9，而卡片内容只有 264.7×201）。
///
/// 所以改为把玻璃膜色 / 圆角 / 高光描边**注入 dialogTheme**，
/// 让 `AlertDialog` 自己的卡片承担视觉，尺寸完全由内容决定。
/// 副作用：不再有 `BackdropFilter` 模糊，用半透明膜色 + 高光边表达玻璃质感。
Future<T?> showNexusDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  // 内容自带卡片外壳（AlertDialog / SimpleDialog）时为 true：
  // 玻璃视觉改为注入 dialogTheme，绝不能再套一层有可见背景的外壳。
  // 只有返回裸内容（例如 Padding + Column）时才需要本函数提供卡片背景。
  bool selfContained = true,
}) {
  // L4：记住触发这次弹窗的按下位置，对话框从那里长出来。
  NexusTapOrigin.ensureInstalled();
  final origin = NexusTapOrigin.recent();
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: AppStrings.closeDialog,
    barrierColor: barrierColor ??
        Colors.black.withValues(
            alpha:
                Theme.of(context).brightness == Brightness.dark ? 0.40 : 0.08),
    transitionDuration: MotionPreferences.adjustDuration(
        context, NexusMotion.sheet,
        listen: false),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final baseTheme = Theme.of(dialogContext);
      final isDark = baseTheme.brightness == Brightness.dark;
      final highContrast = MediaQuery.highContrastOf(dialogContext);
      final intensity = AppAppearanceController.resolvedGlassIntensity;
      final useGlass = intensity != GlassIntensity.flat;
      final dialogRadius = BorderRadius.circular(AppTokens.radiusModal);
      final canvas = isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas;

      // 膜层：玻璃档留出透明度让背后极光透出来，平面档用实心画布色。
      final tint = useGlass
          ? (isDark ? AppPalette.darkSurface : AppPalette.lightCanvas)
              .withValues(
              alpha: highContrast ? 0.96 : (isDark ? 0.88 : 0.92),
            )
          : canvas;
      // 描边：玻璃档用高光边，平面档用 hairline。
      final borderColor = useGlass
          ? (isDark
              ? Colors.white.withValues(alpha: 0.24)
              : Colors.white.withValues(alpha: 0.85))
          : (isDark ? AppPalette.darkHairline : AppPalette.lightHairline);
      final cardShape = RoundedRectangleBorder(
        borderRadius: dialogRadius,
        side: BorderSide(color: borderColor, width: 1.0),
      );

      if (selfContained) {
        return Theme(
          data: baseTheme.copyWith(
            dialogTheme: baseTheme.dialogTheme.copyWith(
              backgroundColor: tint,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: cardShape,
              // 与原来的外壳 padding 对齐：卡片宽度上限仍是「屏宽 - 48」，
              // 高度则完全由内容决定。
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            ),
          ),
          child: builder(dialogContext),
        );
      }

      // 裸内容分支：调用方只给内容，由本函数补卡片背景。
      // 这类内容没有 Dialog 外壳，不会撑满可用空间，外壳尺寸就等于内容尺寸。
      final innerContent = Theme(
        data: baseTheme.copyWith(
          dialogTheme: baseTheme.dialogTheme.copyWith(
            backgroundColor: Colors.transparent,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: const RoundedRectangleBorder(side: BorderSide.none),
          ),
        ),
        child: builder(dialogContext),
      );

      final surfaceWidget = useGlass
          ? GlassSurface(
              role: GlassRole.overlay,
              variant: GlassVariant.regular,
              intensity: intensity,
              borderRadius: dialogRadius,
              tint: tint,
              blurSigma: 26,
              refraction: 18,
              edgeWidth: 24,
              gloss: 0.65,
              child: innerContent,
            )
          : NexusSurface(
              level: SurfaceLevel.ultraThick,
              borderRadius: dialogRadius,
              margin: EdgeInsets.zero,
              padding: EdgeInsets.zero,
              child: innerContent,
            );

      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 280, maxWidth: 460),
            child: Material(
              color: Colors.transparent,
              child: surfaceWidget,
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, anim, secAnim, child) {
      if (MotionPreferences.shouldReduceMotion(context)) {
        return child;
      }
      return _NexusDialogMotion(
        animation: anim,
        origin: origin,
        // 玻璃外壳（非 selfContained）不能套 Opacity，否则 BackdropFilter 失效。
        fade: selfContained,
        child: child,
      );
    },
  );
}

/// L4 对话框入场：自点击位置以 bouncy 弹簧放大长出（带一次轻回弹），
/// 没有新鲜的点击位置时居中放大；退场沿原路收回。
class _NexusDialogMotion extends StatelessWidget {
  const _NexusDialogMotion({
    required this.animation,
    required this.origin,
    required this.fade,
    required this.child,
  });

  final Animation<double> animation;
  final Offset? origin;
  final bool fade;
  final Widget child;

  static const double fromTapScale = 0.72;
  static const double centeredScale = 0.92;

  @override
  Widget build(BuildContext context) {
    final spring = NexusSpringPolicy.resolve(context, NexusSprings.bouncy);
    final curve = CurvedAnimation(
      parent: animation,
      curve: spring == null
          ? Curves.easeOutCubic
          : NexusSprings.curveOf(spring, allowOvershoot: true),
      reverseCurve: NexusMotion.curveExit,
    );
    final fromTap = origin != null && fade;
    Widget result = ScaleTransition(
      alignment: NexusTapOrigin.alignmentIn(MediaQuery.sizeOf(context), origin),
      scale: Tween<double>(
        begin: fromTap ? fromTapScale : centeredScale,
        end: 1.0,
      ).animate(curve),
      child: child,
    );
    if (fade) {
      result = FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: const Interval(0, 0.45, curve: NexusMotion.curveEnter),
        ),
        child: result,
      );
    }
    return result;
  }
}
