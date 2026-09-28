import 'package:flutter/material.dart';

import '../motion/nexus_haptics.dart';
import '../motion/nexus_spring.dart';

/// L6：单选分段控件，[SegmentedButton] 的轻量替身（同名参数，单选）。
///
/// 选中指示器是一块滑动的药丸：两条边各由一根弹簧驱动——运动方向上的
/// 前沿用 snappy 先到，后沿用 smooth 跟上，于是滑动途中自然「拉伸」，
/// 到位后收回原宽。切换时给一次 selection 触感。
class NexusSegmentedButton<T> extends StatefulWidget {
  const NexusSegmentedButton({
    super.key,
    required this.segments,
    required this.selected,
    this.onSelectionChanged,
    this.showSelectedIcon = true,
    this.emptySelectionAllowed = false,
    this.multiSelectionEnabled = false,
    this.style,
  }) : assert(!multiSelectionEnabled, 'NexusSegmentedButton 只支持单选');

  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>>? onSelectionChanged;

  /// 与 [SegmentedButton] 保持参数兼容；指示器本身已表达选中，不再额外画勾。
  final bool showSelectedIcon;
  final bool emptySelectionAllowed;
  final bool multiSelectionEnabled;

  /// 兼容参数（外观由本控件统一，忽略）。
  final ButtonStyle? style;

  static const double height = 40;
  static const double inset = 3;

  @override
  State<NexusSegmentedButton<T>> createState() =>
      _NexusSegmentedButtonState<T>();
}

class _NexusSegmentedButtonState<T> extends State<NexusSegmentedButton<T>>
    with TickerProviderStateMixin {
  late final SpringController _left;
  late final SpringController _right;
  int _index = -1;

  int get _selectedIndex => widget.segments
      .indexWhere((segment) => widget.selected.contains(segment.value));

  @override
  void initState() {
    super.initState();
    _index = _selectedIndex;
    final start = _index < 0 ? 0.0 : _index.toDouble();
    _left = SpringController(vsync: this, value: start);
    _right = SpringController(vsync: this, value: start + 1);
  }

  @override
  void didUpdateWidget(covariant NexusSegmentedButton<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _selectedIndex;
    if (next == _index) return;
    final previous = _index;
    _index = next;
    if (next < 0) return;
    final lead = NexusSpringPolicy.resolve(context, NexusSprings.snappy,
        listen: false);
    final trail = NexusSpringPolicy.resolve(context, NexusSprings.smooth,
        listen: false);
    if (previous < 0) {
      _left.jumpTo(next.toDouble());
      _right.jumpTo(next + 1.0);
      return;
    }
    final movingRight = next > previous;
    _left.animateTo(next.toDouble(), spring: movingRight ? trail : lead);
    _right.animateTo(next + 1.0, spring: movingRight ? lead : trail);
  }

  @override
  void dispose() {
    _left.dispose();
    _right.dispose();
    super.dispose();
  }

  void _select(ButtonSegment<T> segment) {
    final onChanged = widget.onSelectionChanged;
    if (onChanged == null || !segment.enabled) return;
    if (widget.selected.contains(segment.value)) {
      if (widget.emptySelectionAllowed) onChanged(<T>{});
      return;
    }
    NexusHaptics.selection(context);
    onChanged(<T>{segment.value});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final enabled = widget.onSelectionChanged != null;
    final count = widget.segments.length;
    final radius = BorderRadius.circular(NexusSegmentedButton.height / 2);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        height: NexusSegmentedButton.height,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: radius,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final segment = count == 0 ? 0.0 : width / count;
            return Stack(
              children: [
                if (_index >= 0)
                  AnimatedBuilder(
                    animation: Listenable.merge([_left, _right]),
                    builder: (context, _) {
                      const inset = NexusSegmentedButton.inset;
                      final left = _left.value * segment + inset;
                      final right = _right.value * segment - inset;
                      return Positioned(
                        left: left,
                        width: (right - left).clamp(0.0, width),
                        top: inset,
                        bottom: inset,
                        child: DecoratedBox(
                          key: const ValueKey('nexus_segment_indicator'),
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer,
                            borderRadius: radius,
                          ),
                        ),
                      );
                    },
                  ),
                Row(
                  children: [
                    for (var i = 0; i < count; i++)
                      Expanded(child: _buildSegment(context, i, textTheme)),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSegment(BuildContext context, int i, TextTheme textTheme) {
    final scheme = Theme.of(context).colorScheme;
    final segment = widget.segments[i];
    final selected = i == _index;
    final color = !segment.enabled
        ? scheme.onSurface.withValues(alpha: 0.38)
        : (selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant);
    Widget content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (segment.icon != null) ...[
          IconTheme.merge(
            data: IconThemeData(color: color, size: 18),
            child: segment.icon!,
          ),
          if (segment.label != null) const SizedBox(width: 6),
        ],
        if (segment.label != null)
          Flexible(
            child: DefaultTextStyle.merge(
              style: (textTheme.labelLarge ?? const TextStyle())
                  .copyWith(color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              child: segment.label!,
            ),
          ),
      ],
    );
    if (segment.tooltip != null) {
      content = Tooltip(message: segment.tooltip, child: content);
    }
    return Semantics(
      button: true,
      selected: selected,
      enabled: segment.enabled && widget.onSelectionChanged != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _select(segment),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Center(child: content),
        ),
      ),
    );
  }
}
