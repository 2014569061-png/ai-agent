import 'package:flutter/widgets.dart';

import '../theme/app_appearance_controller.dart';
import '../widgets/liquid_glass.dart';
import 'motion_preferences.dart';
import 'nexus_motion.dart';

/// 列表错开入场（M3）：整个列表共用一个 [AnimationController]，
/// 每一项通过 [NexusStaggeredItem] 取自己的 `Interval` 切片。
///
/// * 挂载时播放一次；刷新、筛选、重建都不会重播；
/// * 只对前 [NexusMotion.listStaggerMaxItems] 项生效，滚动中新出现的项直接显示；
/// * 玻璃模式只位移，`GlassIntensity.flat` 时才叠加淡入（玻璃放进 Opacity
///   缓冲区会闪烁）；
/// * reduced / off：直接显示，不创建 ticker。
class NexusStaggeredEntrance extends StatefulWidget {
  const NexusStaggeredEntrance({super.key, required this.child});

  final Widget child;

  /// 列表整体时长：最后一项的错开延迟 + 单项时长。
  static Duration get totalDuration =>
      NexusMotion.listStagger * (NexusMotion.listStaggerMaxItems - 1) +
      NexusMotion.listItem;

  @override
  State<NexusStaggeredEntrance> createState() => _NexusStaggeredEntranceState();
}

class _NexusStaggeredEntranceState extends State<NexusStaggeredEntrance>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  bool _fade = false;
  bool _resolved = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolved) return;
    _resolved = true;
    if (MotionPreferences.levelOf(context, listen: false) != MotionLevel.full) {
      return;
    }
    _fade =
        AppAppearanceController.resolvedGlassIntensity == GlassIntensity.flat;
    _controller = AnimationController(
      vsync: this,
      duration: NexusStaggeredEntrance.totalDuration,
    )..forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return widget.child;
    return _StaggerScope(
      animation: controller,
      fade: _fade,
      child: widget.child,
    );
  }
}

class _StaggerScope extends InheritedWidget {
  const _StaggerScope({
    required this.animation,
    required this.fade,
    required super.child,
  });

  final Animation<double> animation;
  final bool fade;

  @override
  bool updateShouldNotify(_StaggerScope oldWidget) =>
      animation != oldWidget.animation || fade != oldWidget.fade;
}

/// 列表中的一项。没有外层 [NexusStaggeredEntrance]、`index` 超过上限、
/// 或者入场已经结束时，直接返回 [child]。
class NexusStaggeredItem extends StatefulWidget {
  const NexusStaggeredItem({
    super.key,
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  /// 起始位移（逻辑像素）。
  static const double offsetY = 12;

  /// 把 `itemBuilder` 包一层：第 i 项自动成为 `NexusStaggeredItem(index: i)`。
  static IndexedWidgetBuilder wrap(IndexedWidgetBuilder builder) =>
      (context, index) => NexusStaggeredItem(
            index: index,
            child: builder(context, index),
          );

  @override
  State<NexusStaggeredItem> createState() => _NexusStaggeredItemState();
}

class _NexusStaggeredItemState extends State<NexusStaggeredItem> {
  Animation<double>? _progress;
  bool _fade = false;
  bool _resolved = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 只在挂载时决定是否参与入场，结构在整个生命周期内保持不变。
    if (_resolved) return;
    _resolved = true;
    if (widget.index >= NexusMotion.listStaggerMaxItems) return;
    final scope = context.getInheritedWidgetOfExactType<_StaggerScope>();
    if (scope == null || scope.animation.isCompleted) return;
    final total = NexusStaggeredEntrance.totalDuration.inMicroseconds;
    final start =
        (NexusMotion.listStagger * widget.index).inMicroseconds / total;
    final end = start + NexusMotion.listItem.inMicroseconds / total;
    _fade = scope.fade;
    _progress = CurvedAnimation(
      parent: scope.animation,
      curve:
          Interval(start, end.clamp(0.0, 1.0), curve: NexusMotion.curveEnter),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    if (progress == null) return widget.child;
    return AnimatedBuilder(
      animation: progress,
      child: widget.child,
      builder: (context, child) {
        final t = progress.value;
        Widget result = Transform.translate(
          offset: Offset(0, NexusStaggeredItem.offsetY * (1 - t)),
          child: child,
        );
        if (_fade) {
          result = Opacity(
            opacity: t,
            alwaysIncludeSemantics: true,
            child: result,
          );
        }
        return result;
      },
    );
  }
}
