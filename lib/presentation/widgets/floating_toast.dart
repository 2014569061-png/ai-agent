import 'dart:async';

import 'package:flutter/material.dart';

/// 全局居中靠上的悬浮 Toast。
///
/// 替代默认 [SnackBar]（从底部弹出）—— 用 [OverlayEntry] 自行定位：
/// 水平居中、垂直位于顶部安全区下方 88px，3 秒后渐出消失。
/// 多次调用会替换上一条，不堆叠。
class FloatingToast {
  FloatingToast._();

  static const _displayDuration = Duration(seconds: 3);
  static const _animationDuration = Duration(milliseconds: 220);
  static const _topOffset = 88.0;
  static const _maxWidth = 480.0;
  static const _horizontalPadding = 24.0;

  static _ToastEntryController? _current;

  /// 显示一条悬浮 Toast；context 一般来自调用方。
  static void show(BuildContext context, String message) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _current?._dismiss();
    final controller = _ToastEntryController(
      overlay: overlay,
      message: message,
      displayDuration: _displayDuration,
      animationDuration: _animationDuration,
    );
    _current = controller;
    controller._show();
  }
}

/// 单个 Toast 实例的控制器（管理 OverlayEntry 的生命周期）。
class _ToastEntryController {
  _ToastEntryController({
    required this.overlay,
    required this.message,
    required this.displayDuration,
    required this.animationDuration,
  });

  final OverlayState overlay;
  final String message;
  final Duration displayDuration;
  final Duration animationDuration;

  OverlayEntry? _entry;
  Timer? _timer;
  AnimationController? _animController;
  bool _dismissed = false;

  void _show() {
    final entry = OverlayEntry(builder: (context) => _ToastView(
          message: message,
          animationDuration: animationDuration,
          topOffset: FloatingToast._topOffset,
          maxWidth: FloatingToast._maxWidth,
          horizontalPadding: FloatingToast._horizontalPadding,
          onCreated: (c) => _animController = c,
          onTap: _dismiss,
        ));
    _entry = entry;
    overlay.insert(entry);

    _timer = Timer(displayDuration, _dismiss);
  }

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    _timer?.cancel();
    final anim = _animController;
    final entry = _entry;
    if (anim == null || entry == null) {
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
    required this.animationDuration,
    required this.topOffset,
    required this.maxWidth,
    required this.horizontalPadding,
    required this.onCreated,
    required this.onTap,
  });

  final String message;
  final Duration animationDuration;
  final double topOffset;
  final double maxWidth;
  final double horizontalPadding;
  final ValueChanged<AnimationController> onCreated;
  final VoidCallback onTap;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    widget.onCreated(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topSafe = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topSafe + widget.topOffset,
      left: 0,
      right: 0,
      child: FadeTransition(
        opacity: _fade,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.maxWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  onTap: widget.onTap,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4)),
                      ],
                    ),
                    child: Text(
                      widget.message,
                      style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
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