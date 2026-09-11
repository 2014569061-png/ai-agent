import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../../application/error_humanizer.dart';

import 'immersive_surface.dart';
import '../theme/app_tokens.dart';
import 'glass_chip.dart';
import '../chat/widgets/capsule_top_bar.dart';

enum ToastTone { neutral, success, warning, danger }

extension _ToneStyle on ToastTone {
  IconData? get icon => switch (this) {
        ToastTone.neutral => null,
        ToastTone.success => Icons.check_circle_rounded,
        ToastTone.warning => Icons.warning_amber_rounded,
        ToastTone.danger => Icons.error_outline_rounded,
      };
  Color accent(bool isDark) => switch (this) {
        ToastTone.neutral =>
          isDark ? AppPalette.darkText : AppPalette.lightText,
        ToastTone.success => AppPalette.success,
        ToastTone.warning => AppPalette.warning,
        ToastTone.danger => AppPalette.danger,
      };
}

class FloatingCapsuleAction {
  const FloatingCapsuleAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.dismissOnTap = true,
  });
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool dismissOnTap;
}

/// 全局居中靠上的悬浮 Toast。
///
/// 替代默认 [SnackBar]（从底部弹出）—— 用 [OverlayEntry] 自行定位：
/// 水平居中、垂直位于顶部安全区下方 88px，渐出消失。
/// 多次调用会替换上一条，不堆叠。
class FloatingToast {
  FloatingToast._();

  static const _displayDuration = Duration(seconds: 3);
  static const _animationDuration = Duration(milliseconds: 220);
  static const _toolCapsuleHeight = 32.0;
  static const _topOffset =
      (4.0 + kCapsuleTopBarHeight) + 8.0 + _toolCapsuleHeight + 8.0;
  static const _maxWidth = 480.0;
  static const _horizontalPadding = 24.0;

  static _ToastEntryController? _current;

  /// 显示一条悬浮 Toast；context 一般来自调用方。
  static void show(
    BuildContext context,
    String message, {
    ToastTone tone = ToastTone.neutral,
    String? detail,
    List<FloatingCapsuleAction>? actions,
    bool? persistent,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _current?._dismiss();
    final isPersistent =
        persistent ?? (tone == ToastTone.warning || tone == ToastTone.danger);

    final controller = _ToastEntryController(
      overlay: overlay,
      message: message,
      tone: tone,
      actions: actions ?? const [],
      persistent: isPersistent,
      displayDuration: _displayDuration,
      animationDuration: _animationDuration,
    );
    _current = controller;
    controller._show();
  }

  /// 错误便捷入口：自动 humanize + 自动「复制详情」chip + 常驻。
  static void error(
    BuildContext context,
    String summary, {
    String? rawDetail,
    VoidCallback? onFeedback,
  }) {
    final h = humanizeError(summary);

    // 如果外部传入了已经 humanize 过的 summary，我们再次 humanize 可能得到不同的结果
    // 根据 spec: "自动 humanize + 自动「复制详情」chip + 常驻"
    // 以及接线要求："接线统一走 humanizeError(raw).summary 取人话文案、原始串进 rawDetail 供复制"
    final actualSummary = h.summary;
    final actualRaw = rawDetail ?? summary;

    final actions = <FloatingCapsuleAction>[
      FloatingCapsuleAction(
        label: '复制',
        icon: Icons.copy_rounded,
        onPressed: () {
          Clipboard.setData(ClipboardData(text: actualRaw));
        },
      ),
      if (onFeedback != null)
        FloatingCapsuleAction(
          label: '反馈问题',
          onPressed: onFeedback,
        ),
    ];
    show(
      context,
      actualSummary,
      tone: ToastTone.danger,
      detail: actualRaw,
      actions: actions,
      persistent: true,
    );
  }
}

class _ToastEntryController {
  _ToastEntryController({
    required this.overlay,
    required this.message,
    required this.tone,
    required this.actions,
    required this.persistent,
    required this.displayDuration,
    required this.animationDuration,
  });

  final OverlayState overlay;
  final String message;
  final ToastTone tone;
  final List<FloatingCapsuleAction> actions;
  final bool persistent;
  final Duration displayDuration;
  final Duration animationDuration;

  OverlayEntry? _entry;
  Timer? _timer;
  AnimationController? _animController;
  bool _dismissed = false;

  void _show() {
    final entry = OverlayEntry(
        builder: (context) => _ToastView(
              message: message,
              tone: tone,
              actions: actions,
              persistent: persistent,
              animationDuration: animationDuration,
              topOffset: FloatingToast._topOffset,
              maxWidth: FloatingToast._maxWidth,
              horizontalPadding: FloatingToast._horizontalPadding,
              onCreated: (c) => _animController = c,
              onDismiss: _dismiss,
            ));
    _entry = entry;
    overlay.insert(entry);

    if (!persistent) {
      _timer = Timer(displayDuration, _dismiss);
    }
  }

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    _timer?.cancel();
    final anim = _animController;
    final entry = _entry;
    if (anim == null || entry == null || !entry.mounted) {
      entry?.remove();
      if (FloatingToast._current == this) FloatingToast._current = null;
      return;
    }
    anim.reverse().then((_) {
      entry.remove();
      if (FloatingToast._current == this) FloatingToast._current = null;
    });
  }
}

class _ToastView extends StatefulWidget {
  const _ToastView({
    required this.message,
    required this.tone,
    required this.actions,
    required this.persistent,
    required this.animationDuration,
    required this.topOffset,
    required this.maxWidth,
    required this.horizontalPadding,
    required this.onCreated,
    required this.onDismiss,
  });

  final String message;
  final ToastTone tone;
  final List<FloatingCapsuleAction> actions;
  final bool persistent;
  final Duration animationDuration;
  final double topOffset;
  final double maxWidth;
  final double horizontalPadding;
  final ValueChanged<AnimationController> onCreated;
  final VoidCallback onDismiss;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    _fade =
        CurvedAnimation(parent: _controller, curve: AppTokens.curveStandard);
    _slide = Tween(
      begin: const Offset(0, -.12),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _controller, curve: AppTokens.curveStandard));

    widget.onCreated(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onAction(FloatingCapsuleAction action) {
    action.onPressed();
    if (action.dismissOnTap) {
      widget.onDismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    final topSafe = MediaQuery.of(context).padding.top;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? AppTheme.darkSemantic.onGlass : AppTheme.lightSemantic.onGlass;

    return Positioned(
      top: topSafe + widget.topOffset,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: widget.maxWidth),
              child: Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
                child: Material(
                  color: Colors.transparent,
                  child: Semantics(
                    liveRegion: widget.persistent,
                    label: widget.message,
                    child: GestureDetector(
                      onTap: widget.persistent ? null : widget.onDismiss,
                      behavior: widget.persistent
                          ? HitTestBehavior.translucent
                          : HitTestBehavior.opaque,
                      child: ImmersiveSurface(
                        level: ImmersiveMaterialLevel.thick,
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusPill),
                        padding: EdgeInsets.fromLTRB(
                            16, 10, widget.persistent ? 8 : 16, 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.tone != ToastTone.neutral) ...[
                              Icon(widget.tone.icon,
                                  size: 18, color: widget.tone.accent(isDark)),
                              const SizedBox(width: 10),
                            ],
                            Flexible(
                              child: Text(
                                widget.message,
                                style: TextStyle(
                                    color: textColor,
                                    fontSize: 13,
                                    height: 1.4,
                                    fontWeight: FontWeight.w500),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.actions.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Wrap(
                                  spacing: 8,
                                  children: [
                                    for (final a in widget.actions)
                                      GlassChip(
                                        label: a.label,
                                        icon: a.icon,
                                        onPressed: () => _onAction(a),
                                      )
                                  ],
                                ),
                              ),
                            if (widget.persistent)
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: '关闭',
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: widget.onDismiss,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
