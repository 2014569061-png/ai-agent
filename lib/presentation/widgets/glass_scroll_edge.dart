import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// A subtle edge transition that keeps floating glass controls legible while
/// scrollable content passes underneath them.
class GlassScrollEdge extends StatefulWidget {
  const GlassScrollEdge({
    super.key,
    required this.child,
    this.showTop = true,
    this.showBottom = true,
    this.height = 28,
    this.color,
    this.enabled = true,
  });

  final Widget child;
  final bool showTop;
  final bool showBottom;
  final double height;
  final Color? color;
  final bool enabled;

  @override
  State<GlassScrollEdge> createState() => _GlassScrollEdgeState();
}

class _GlassScrollEdgeState extends State<GlassScrollEdge> {
  bool _hasScrollableContent = false;
  bool _showTopEdge = false;
  bool _showBottomEdge = false;

  bool _onNotification(ScrollNotification notification) {
    if (!widget.enabled || notification.metrics.axis != Axis.vertical) {
      return false;
    }

    final metrics = notification.metrics;
    final hasScrollableContent = metrics.maxScrollExtent > 0.5;
    final showTopEdge = metrics.pixels > 1.0;
    final showBottomEdge = metrics.pixels < metrics.maxScrollExtent - 1.0;
    if (_hasScrollableContent != hasScrollableContent ||
        _showTopEdge != showTopEdge ||
        _showBottomEdge != showBottomEdge) {
      setState(() {
        _hasScrollableContent = hasScrollableContent;
        _showTopEdge = showTopEdge;
        _showBottomEdge = showBottomEdge;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = widget.color ??
        (isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 180);

    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (widget.showTop)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: widget.height,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _hasScrollableContent && _showTopEdge ? 1 : 0,
                  duration: duration,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          baseColor.withValues(alpha: 0.92),
                          baseColor.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (widget.showBottom)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: widget.height,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _hasScrollableContent && _showBottomEdge ? 1 : 0,
                  duration: duration,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          baseColor.withValues(alpha: 0.0),
                          baseColor.withValues(alpha: 0.92),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
