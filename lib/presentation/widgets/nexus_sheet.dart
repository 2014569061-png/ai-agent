import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import '../l10n/app_strings.dart';
import '../motion/motion_preferences.dart';
import '../motion/nexus_motion.dart';
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
  late final AnimationController _settleController;
  var _dragFraction = 0.0;
  var _settleFrom = 0.0;
  var _settleTo = 0.0;

  @override
  void initState() {
    super.initState();
    _settleController = AnimationController(
      vsync: this,
      duration: NexusMotion.base,
    )..addListener(() {
        final t = NexusMotion.curveSpring.transform(_settleController.value);
        setState(
            () => _dragFraction = ui.lerpDouble(_settleFrom, _settleTo, t)!);
      });
  }

  @override
  void dispose() {
    _settleController.dispose();
    super.dispose();
  }

  bool _onDrag(_SheetDragNotification notification) {
    if (!widget.isBottomDocked) return false;
    if (!notification.isEnd) {
      if (notification.delta <= 0 && _dragFraction <= 0) return true;
      _settleController.stop();
      final height = MediaQuery.sizeOf(context).height;
      setState(() {
        _dragFraction = (_dragFraction + notification.delta / height)
            .clamp(0.0, 0.42)
            .toDouble();
      });
      return true;
    }

    final velocity = notification.velocity!;
    final shouldDismiss = _dragFraction > 0.18 || velocity > 900;
    if (shouldDismiss) {
      Navigator.of(context).maybePop();
    } else if (MotionPreferences.shouldReduceMotion(context)) {
      _settleController.stop();
      setState(() => _dragFraction = 0.0);
    } else {
      _settleFrom = _dragFraction;
      _settleTo = 0.0;
      _settleController.forward(from: 0);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final entering = CurvedAnimation(
      parent: widget.animation,
      curve: NexusMotion.curveSheetEnter,
      reverseCurve: NexusMotion.curveExit,
    );
    return NotificationListener<_SheetDragNotification>(
      onNotification: _onDrag,
      child: AnimatedBuilder(
        animation: entering,
        child: widget.child,
        builder: (context, child) {
          final dismissalProgress = widget.isBottomDocked
              ? (_dragFraction / 0.42).clamp(0.0, 1.0)
              : 0.0;
          final barrierOpacity = entering.value * (1.0 - dismissalProgress);
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
                ScaleTransition(
                  scale: Tween<double>(begin: 0.95, end: 1.0).animate(entering),
                  child: child,
                ),
              ],
            );
          }
          // Keep the glass surface outside Opacity so BackdropFilter samples
          // the scene directly. Only the separate barrier fades with drag.
          final offset = (1 - entering.value) * 0.18 + _dragFraction;
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
      final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1.0).animate(curve),
        child: child,
      );
    },
  );
}
