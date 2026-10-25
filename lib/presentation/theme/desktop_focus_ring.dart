import 'package:flutter/material.dart';

import 'app_tokens.dart';
import 'desktop_theme.dart';

/// 桌面工作区高对比度键盘焦点指示外圈 (Focus Ring)
///
/// 符合 WCAG 2.1 规范（2.4.7 Focus Visible），在获得键盘焦点时
/// 呈现 2px 高对比外圈轮廓，支持动态 Reduce Motion 降级。
class DesktopFocusRing extends StatefulWidget {
  const DesktopFocusRing({
    super.key,
    required this.child,
    this.focusNode,
    this.borderRadius = DesktopTheme.radius,
    this.outlineWidth = 2.0,
    this.outlineOffset = 2.0,
    this.semanticLabel,
    this.onTap,
  });

  final Widget child;
  final FocusNode? focusNode;
  final double borderRadius;
  final double outlineWidth;
  final double outlineOffset;
  final String? semanticLabel;
  final VoidCallback? onTap;

  @override
  State<DesktopFocusRing> createState() => _DesktopFocusRingState();
}

class _DesktopFocusRingState extends State<DesktopFocusRing> {
  FocusNode? _internalNode;
  FocusNode get _effectiveNode => widget.focusNode ?? (_internalNode ??= FocusNode());

  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _effectiveNode.addListener(_handleFocusChanged);
    _focused = _effectiveNode.hasFocus;
  }

  @override
  void didUpdateWidget(DesktopFocusRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      (oldWidget.focusNode ?? _internalNode)?.removeListener(_handleFocusChanged);
      _effectiveNode.addListener(_handleFocusChanged);
      _focused = _effectiveNode.hasFocus;
    }
  }

  @override
  void dispose() {
    _effectiveNode.removeListener(_handleFocusChanged);
    _internalNode?.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (mounted && _focused != _effectiveNode.hasFocus) {
      setState(() => _focused = _effectiveNode.hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = DesktopTheme.maybeOf(context);
    final accentColor = theme?.accent ?? Theme.of(context).colorScheme.primary;
    final reduce = DesktopTheme.reduceMotion(context);
    final duration = reduce ? Duration.zero : AppTokens.durationInstant;

    Widget content = Focus(
      focusNode: _effectiveNode,
      child: widget.child,
    );

    if (widget.onTap != null) {
      content = GestureDetector(
        onTap: widget.onTap,
        child: content,
      );
    }

    if (widget.semanticLabel != null) {
      content = Semantics(
        label: widget.semanticLabel,
        button: widget.onTap != null,
        focused: _focused,
        child: content,
      );
    }

    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius + widget.outlineOffset),
        border: Border.all(
          color: _focused ? accentColor : Colors.transparent,
          width: widget.outlineWidth,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(widget.outlineOffset),
        child: content,
      ),
    );
  }
}
