import 'dart:async';

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';

import 'morph_icon.dart';
import 'nexus_spring.dart';

/// L7：数字滚动。值变化时，变化的字符上下滚入（增大向上、减小向下），
/// 未变化的字符不动；长度不同则整段滚动。静止时就是一个普通 [Text]。
class RollingText extends StatefulWidget {
  const RollingText(this.value, {super.key, this.style});

  final String value;
  final TextStyle? style;

  @override
  State<RollingText> createState() => _RollingTextState();
}

class _RollingTextState extends State<RollingText>
    with SingleTickerProviderStateMixin {
  late final SpringController _t = SpringController(vsync: this, value: 1);
  String? _old;
  double _dir = 1;

  static num? _number(String s) {
    final digits = RegExp(r'-?\d+(\.\d+)?').firstMatch(s.replaceAll(',', ''));
    return digits == null ? null : num.tryParse(digits.group(0)!);
  }

  @override
  void didUpdateWidget(covariant RollingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == oldWidget.value) return;
    final spring =
        NexusSpringPolicy.resolve(context, NexusSprings.bouncy, listen: false);
    if (spring == null) {
      _old = null;
      _t.jumpTo(1);
      return;
    }
    final a = _number(oldWidget.value), b = _number(widget.value);
    _dir = (a != null && b != null && b < a) ? -1 : 1;
    _old = oldWidget.value;
    _t.jumpTo(0);
    _t.animateTo(1, spring: spring);
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  Widget _roll(String? from, String to, double t) {
    Widget text(String s) => Text(s, style: widget.style);
    return ClipRect(
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (from != null)
            FractionalTranslation(
              translation: Offset(0, -_dir * t),
              child:
                  Opacity(opacity: (1 - t).clamp(0.0, 1.0), child: text(from)),
            ),
          FractionalTranslation(
            translation: Offset(0, _dir * (1 - t)),
            child: text(to),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _t,
        builder: (context, _) {
          final old = _old;
          final t = _t.value;
          if (old == null || (!_t.isAnimating && t >= 1)) {
            return Text(widget.value, style: widget.style);
          }
          final now = widget.value;
          if (old.length != now.length) return _roll(old, now, t);
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < now.length; i++)
                old[i] == now[i]
                    ? Text(now[i], style: widget.style)
                    : _roll(old[i], now[i], t),
            ],
          );
        },
      );
}

/// L7：内容变化时轻弹一下（0.86 → 1，bouncy 回弹），用于状态徽章等。
class PopOnChange extends StatefulWidget {
  const PopOnChange({super.key, required this.trigger, required this.child});

  final Object? trigger;
  final Widget child;

  @override
  State<PopOnChange> createState() => _PopOnChangeState();
}

class _PopOnChangeState extends State<PopOnChange>
    with SingleTickerProviderStateMixin {
  SpringController? _scale;

  @override
  void didUpdateWidget(covariant PopOnChange oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger == oldWidget.trigger) return;
    final spring =
        NexusSpringPolicy.resolve(context, NexusSprings.bouncy, listen: false);
    if (spring == null) return;
    final c = _scale ??= SpringController(vsync: this, value: 1);
    c.jumpTo(0.86);
    c.animateTo(1, spring: spring);
  }

  @override
  void dispose() {
    _scale?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _scale;
    if (c == null) return widget.child;
    return AnimatedBuilder(
      animation: c,
      child: widget.child,
      builder: (context, child) =>
          Transform.scale(scale: c.value, child: child),
    );
  }
}

/// L7：复制按钮——点按后图标形变为 ✓，约 2 秒后形变回来。
class CopyFeedbackButton extends StatefulWidget {
  const CopyFeedbackButton({
    super.key,
    required this.onCopy,
    this.icon = Icons.copy_outlined,
    this.color,
    this.iconSize = 18,
    this.tooltip = '复制',
    this.visualDensity = VisualDensity.compact,
    this.padding = EdgeInsets.zero,
    this.constraints = const BoxConstraints(minWidth: 48, minHeight: 48),
  });

  final VoidCallback onCopy;
  final IconData icon;
  final Color? color;
  final double iconSize;
  final String tooltip;
  final VisualDensity visualDensity;
  final EdgeInsetsGeometry padding;
  final BoxConstraints constraints;

  /// 约 2 秒（复用手势常量，避免新增 Duration 字面量）。
  static final Duration resetAfter = kLongPressTimeout * 4;

  @override
  State<CopyFeedbackButton> createState() => _CopyFeedbackButtonState();
}

class _CopyFeedbackButtonState extends State<CopyFeedbackButton> {
  bool _copied = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
        visualDensity: widget.visualDensity,
        iconSize: widget.iconSize,
        padding: widget.padding,
        constraints: widget.constraints,
        tooltip: _copied ? '已复制' : widget.tooltip,
        onPressed: () {
          widget.onCopy();
          _timer?.cancel();
          setState(() => _copied = true);
          _timer = Timer(CopyFeedbackButton.resetAfter, () {
            if (mounted) setState(() => _copied = false);
          });
        },
        icon: MorphIcon(
          _copied ? Icons.check_rounded : widget.icon,
          color: widget.color,
        ),
      );
}
