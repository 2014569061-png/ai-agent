import '../theme/mobile_theme.dart';
import 'package:flutter/material.dart';
import '../motion/motion_preferences.dart';
import '../motion/nexus_haptics.dart';
import '../motion/nexus_motion.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../motion/press_squash.dart';
import '../motion/nexus_spring.dart';

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

  /// 展开时长。未指定时使用局部容器变化标准时长。
  final Duration? duration;

  /// 收起时长。收起不应与展开一样拖沓，默认使用快速反馈时长。
  final Duration? reverseDuration;
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
    this.headerPadding =
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.contentPadding = const EdgeInsets.fromLTRB(12, 0, 12, 10),
    this.duration,
    this.reverseDuration,
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
      reverseDuration: widget.reverseDuration ?? NexusMotion.fast,
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
    if (widget.duration != oldWidget.duration ||
        widget.reverseDuration != oldWidget.reverseDuration) {
      _controller
        ..duration = widget.duration ?? NexusMotion.base
        ..reverseDuration = widget.reverseDuration ?? NexusMotion.fast;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleExpansion() {
    NexusHaptics.selection(context);
    final expanding = !_isExpanded;
    setState(() => _isExpanded = expanding);
    if (MotionPreferences.shouldReduceMotion(context)) {
      _controller.value = expanding ? 1.0 : 0.0;
    } else if (expanding) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    widget.onExpansionChanged?.call(expanding);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    final shouldReduce = MotionPreferences.shouldReduceMotion(context);

    final effectiveSemanticLabel =
        widget.semanticLabel ?? (_isExpanded ? '已展开内容，点击收起' : '已收起内容，点击展开');

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
            child: PressSquash(
              scale: NexusPressScale.row,
              child: InkWell(
                onTap: _toggleExpansion,
                borderRadius:
                    BorderRadius.circular(MobileTheme.controlRadius(context)),
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
          ),
          ClipRect(
            child: AnimatedBuilder(
              animation: _controller.view,
              builder: (context, _) {
                final heightFactor = _heightFactor.value;
                if (heightFactor == 0.0 && !_isExpanded) {
                  return const SizedBox.shrink();
                }
                final content = Padding(
                  padding: widget.contentPadding ??
                      const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: widget.child,
                );

                return Align(
                  alignment: Alignment.topLeft,
                  heightFactor: heightFactor,
                  child: shouldReduce
                      ? content
                      : FractionalTranslation(
                          translation: Offset(
                            0.0,
                            (1.0 - heightFactor) * -0.05,
                          ),
                          child: Opacity(
                            opacity: 0.2 + heightFactor * 0.8,
                            child: content,
                          ),
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

/// Shared top-anchored size transition for sections whose header and content
/// are owned by different widgets. Callers provide an empty child when closed
/// to keep costly technical content out of the collapsed build.
class NexusExpandSection extends StatelessWidget {
  const NexusExpandSection({
    super.key,
    required this.expanded,
    required this.child,
    this.duration,
    this.reverseDuration,
    this.alignment = Alignment.topLeft,
  });

  final bool expanded;
  final Widget child;
  final Duration? duration;
  final Duration? reverseDuration;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MotionPreferences.shouldReduceMotion(context);
    final content = expanded ? child : const SizedBox.shrink();
    // reduced 直接切换：零时长 AnimatedSize 会在布局中重新标脏自身。
    if (reduceMotion) return content;
    // L3：展开 / 收起以 smooth 弹簧形变（工具卡、计划面板、思考过程、披露区共用）。
    return SpringAnimatedSize(alignment: alignment, child: content);
  }
}
