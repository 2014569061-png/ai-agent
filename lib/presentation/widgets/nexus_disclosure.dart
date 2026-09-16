import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../motion/motion_preferences.dart';
import '../motion/nexus_motion.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// 统一可折叠展开组件（用于推理过程、技术错误、工具输出、日志详情等）
class NexusDisclosure extends StatefulWidget {
  final Widget title;
  final Widget child;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;
  final Widget? leading;
  final Widget? trailing;
  final Widget? trailingActions;
  final String? semanticLabel;
  final EdgeInsetsGeometry? headerPadding;
  final EdgeInsetsGeometry? contentPadding;
  final Duration? duration;
  final BoxDecoration? decoration;

  const NexusDisclosure({
    super.key,
    required this.title,
    required this.child,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
    this.leading,
    this.trailing,
    this.trailingActions,
    this.semanticLabel,
    this.headerPadding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.contentPadding = const EdgeInsets.fromLTRB(12, 0, 12, 10),
    this.duration,
    this.decoration,
  });

  @override
  State<NexusDisclosure> createState() => _NexusDisclosureState();
}

class _NexusDisclosureState extends State<NexusDisclosure>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late final AnimationController _controller;
  late final Animation<double> _iconTurns;
  late final Animation<double> _heightFactor;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _controller = AnimationController(
      duration: widget.duration ?? NexusMotion.base,
      vsync: this,
    );
    _iconTurns = _controller.drive(
      Tween<double>(begin: 0.0, end: 0.25).chain(
        CurveTween(curve: NexusMotion.curveStandard),
      ),
    );
    _heightFactor = _controller.drive(
      CurveTween(curve: NexusMotion.curveStandard),
    );

    if (_isExpanded) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant NexusDisclosure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration ?? NexusMotion.base;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleExpansion() {
    HapticFeedback.selectionClick();
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
      widget.onExpansionChanged?.call(_isExpanded);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    final shouldReduce = MotionPreferences.shouldReduceMotion(context);
    if (shouldReduce) {
      _controller.duration = Duration.zero;
    }

    final effectiveSemanticLabel = widget.semanticLabel ??
        (_isExpanded ? '已展开内容，点击收起' : '已收起内容，点击展开');

    return Container(
      decoration: widget.decoration,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _isExpanded,
            label: effectiveSemanticLabel,
            child: InkWell(
              onTap: _toggleExpansion,
              borderRadius: BorderRadius.circular(AppTokens.radiusControl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppTokens.kMinTouchTarget, // 确保最小 48dp 触控区
                ),
                child: Padding(
                  padding: widget.headerPadding ??
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      if (widget.leading != null) ...[
                        widget.leading!,
                        const SizedBox(width: 8),
                      ],
                      Expanded(child: widget.title),
                      if (widget.trailingActions != null) ...[
                        widget.trailingActions!,
                        const SizedBox(width: 4),
                      ],
                      if (widget.trailing != null)
                        widget.trailing!
                      else
                        RotationTransition(
                          turns: _iconTurns,
                          child: Icon(
                            Icons.keyboard_arrow_right_rounded,
                            size: 18,
                            color: textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ClipRect(
            child: AnimatedBuilder(
              animation: _controller.view,
              builder: (context, _) {
                final heightFactor = _heightFactor.value;
                if (heightFactor == 0.0 && !_isExpanded) {
                  return const SizedBox.shrink();
                }
                return Align(
                  alignment: Alignment.topLeft,
                  heightFactor: heightFactor,
                  child: Padding(
                    padding: widget.contentPadding ??
                        const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: widget.child,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
