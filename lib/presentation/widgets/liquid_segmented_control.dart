import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_appearance_controller.dart';
import '../theme/app_palette.dart';
import 'glass_surface.dart';

/// 单个分段项定义
class LiquidSegment<T> {
  const LiquidSegment({
    required this.value,
    required this.label,
    this.icon,
    this.badge,
  });

  final T value;
  final String label;
  final IconData? icon;
  final Widget? badge;
}

/// iOS 27 概念级液态玻璃滑动分段选择器 (LiquidSegmentedControl)
///
/// 特性：
/// 1. **流体水滴表面张力拉伸 (Fluid Tension)**：滑动/切换时根据位移进度横向拉长变形，带果冻回弹；
/// 2. **SDF 透镜光学折射 (Lens Refraction)**：滑块划过底层文字时，底层文字在透镜边缘产生实时弧形折射与高光；
/// 3. **全档位平滑降级**：在 liquid 模式展现透镜折射，在 frosted 模式展现高斯磨砂，在 flat 模式降级为纯平面滑块；
/// 4. **轻量触感反馈**：切换时触发系统级微触感反馈。
class LiquidSegmentedControl<T> extends StatefulWidget {
  const LiquidSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelected,
    this.height = 38,
    this.borderRadius,
    this.margin,
    this.stretchEffect = true,
  }) : assert(segments.length >= 2, 'Segments must contain at least 2 items');

  final List<LiquidSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onSelected;
  final double height;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? margin;
  final bool stretchEffect;

  @override
  State<LiquidSegmentedControl<T>> createState() =>
      _LiquidSegmentedControlState<T>();
}

class _LiquidSegmentedControlState<T> extends State<LiquidSegmentedControl<T>>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _animation;

  double _fromIndex = 0;
  double _toIndex = 0;

  int get _selectedIndex {
    final idx = widget.segments.indexWhere((s) => s.value == widget.selected);
    return idx >= 0 ? idx : 0;
  }

  @override
  void initState() {
    super.initState();
    _fromIndex = _selectedIndex.toDouble();
    _toIndex = _fromIndex;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
  }

  @override
  void didUpdateWidget(covariant LiquidSegmentedControl<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      final newIndex = _selectedIndex.toDouble();
      if (newIndex != _toIndex) {
        _animateToIndex(newIndex);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateToIndex(double newIndex) {
    _fromIndex =
        ui.lerpDouble(_fromIndex, _toIndex, _animation.value) ?? _toIndex;
    _toIndex = newIndex;
    _controller.reset();
    _controller.forward();
  }

  void _onItemTap(int index) {
    if (index == _selectedIndex) return;
    HapticFeedback.selectionClick();
    widget.onSelected(widget.segments[index].value);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final intensity = AppAppearanceController.resolvedGlassIntensity;
    final isGlass = intensity != GlassIntensity.flat;

    final outerRadius =
        widget.borderRadius ?? BorderRadius.circular(widget.height / 2);
    final innerRadius = widget.borderRadius != null
        ? BorderRadius.circular(
            math.max(2.0, (widget.borderRadius!.topLeft.x - 2.0)))
        : BorderRadius.circular((widget.height - 6) / 2);

    final trackBg = isDark
        ? (isGlass
            ? AppPalette.darkSurface.withValues(alpha: 0.42)
            : AppPalette.darkCanvas)
        : (isGlass
            ? AppPalette.lightSurface.withValues(alpha: 0.54)
            : AppPalette.lightSurface);

    final hairline =
        isDark ? AppPalette.darkHairline : AppPalette.lightHairline;

    final count = widget.segments.length;
    final labelRow = Row(
      children: List.generate(count, (i) {
        final item = widget.segments[i];
        return Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _onItemTap(i),
            child: Center(
              child: _SegmentContent(
                segment: item,
                textColor:
                    isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted,
                isHighlighted: false,
              ),
            ),
          ),
        );
      }),
    );
    final activeSegment = widget.segments[_selectedIndex];
    final thumb = IgnorePointer(
      child: isGlass
          ? GlassSurface(
              role: GlassRole.control,
              variant: GlassVariant.clear,
              intensity: intensity,
              borderRadius: innerRadius,
              refraction: 14,
              edgeWidth: 16,
              gloss: 0.45,
              tint: isDark
                  ? AppPalette.darkSurface.withValues(alpha: 0.60)
                  : Colors.white.withValues(alpha: 0.68),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 4,
                  offset: const Offset(0, 1.5),
                ),
              ],
              borderColor: hairline,
              child: Center(
                child: _SegmentContent(
                  segment: activeSegment,
                  textColor:
                      isDark ? Colors.white : AppPalette.lightText,
                  isHighlighted: true,
                ),
              ),
            )
          : Container(
              decoration: BoxDecoration(
                color: isDark ? AppPalette.darkSurface : Colors.white,
                borderRadius: innerRadius,
                border: Border.all(color: hairline, width: 1.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Center(
                child: _SegmentContent(
                  segment: activeSegment,
                  textColor:
                      isDark ? Colors.white : AppPalette.lightText,
                  isHighlighted: true,
                ),
              ),
            ),
    );

    return Container(
      margin: widget.margin,
      height: widget.height,
      decoration: BoxDecoration(
        color: trackBg,
        borderRadius: outerRadius,
        border: Border.all(color: hairline, width: 1.0),
      ),
      padding: const EdgeInsets.all(3),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final segmentWidth = totalWidth / count;

          return AnimatedBuilder(
            animation: _controller,
            // The labels and glass thumb are stable children. Only the
            // Positioned geometry is rebuilt on each animation tick.
            child: thumb,
            builder: (context, child) {
              final t = _animation.value;
              final currentPos =
                  ui.lerpDouble(_fromIndex, _toIndex, t) ?? _toIndex;
              final distance = (_toIndex - _fromIndex).abs();

              // 流体水滴拉伸算法：在运动中期 (t ~ 0.5) 产生弹性拉长
              final progressSin = math.sin(_controller.value * math.pi);
              final stretch = widget.stretchEffect
                  ? (distance * 0.18 * progressSin).clamp(0.0, 0.35)
                  : 0.0;
              final stretchFactor = 1.0 + stretch;

              final thumbWidth = segmentWidth * stretchFactor;
              final thumbCenterX = segmentWidth * (currentPos + 0.5);
              final thumbLeft = (thumbCenterX - thumbWidth / 2)
                  .clamp(0.0, math.max(0.0, totalWidth - thumbWidth))
                  .toDouble();

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // 1. 底层：所有未激活项的文字/图标（供透镜滑块经过时产生真实折射）
                  labelRow,

                  // 2. 透镜层：带 SDF 边缘折射与流体张力拉伸的 LiquidGlass 滑块
                  Positioned(
                    left: thumbLeft,
                    top: 0,
                    bottom: 0,
                    width: thumbWidth,
                    child: child!,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _SegmentContent extends StatelessWidget {
  const _SegmentContent({
    required this.segment,
    required this.textColor,
    required this.isHighlighted,
  });

  final LiquidSegment segment;
  final Color textColor;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (segment.icon != null) ...[
          Icon(
            segment.icon,
            size: 14,
            color: isHighlighted ? AppPalette.brand : textColor,
          ),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            segment.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.w500,
              color: textColor,
            ),
          ),
        ),
        if (segment.badge != null) ...[
          const SizedBox(width: 4),
          segment.badge!,
        ],
      ],
    );
  }
}
