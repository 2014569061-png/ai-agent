import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'nexus_spring.dart';

/// L3：高度以弹簧**连续追随**子组件（流式输出逐字增高）。
///
/// 与 [AnimatedSize] 不同：内容在动画途中再次变化时，从当前高度与当前速度
/// 无缝重解弹簧（[SpringController]），逐 token 增长不会一顿一顿地重新起步。
/// 始终顶部对齐；显示高度小于内容时裁剪底部。
///
/// [enabled] 为 false、动效关闭或首次布局时，高度直接等于内容高度。
class SpringFollowHeight extends StatefulWidget {
  const SpringFollowHeight({
    super.key,
    required this.child,
    this.enabled = true,
    this.spring,
  });

  final Widget child;
  final bool enabled;

  /// 缺省 [NexusSprings.smooth]（无过冲，避免正文上下晃）。
  final SpringDescription? spring;

  @override
  State<SpringFollowHeight> createState() => _SpringFollowHeightState();
}

class _SpringFollowHeightState extends State<SpringFollowHeight>
    with SingleTickerProviderStateMixin {
  late final SpringController _height = SpringController(vsync: this);

  @override
  void dispose() {
    _height.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spring = widget.enabled
        ? NexusSpringPolicy.resolve(
            context, widget.spring ?? NexusSprings.smooth)
        : null;
    return _SpringFollowHeightBox(
      controller: _height,
      spring: spring,
      child: widget.child,
    );
  }
}

class _SpringFollowHeightBox extends SingleChildRenderObjectWidget {
  const _SpringFollowHeightBox({
    required this.controller,
    required this.spring,
    super.child,
  });

  final SpringController controller;
  final SpringDescription? spring;

  @override
  RenderSpringFollowHeight createRenderObject(BuildContext context) =>
      RenderSpringFollowHeight(controller: controller, spring: spring);

  @override
  void updateRenderObject(
      BuildContext context, RenderSpringFollowHeight renderObject) {
    renderObject
      ..controller = controller
      ..spring = spring;
  }
}

/// [SpringFollowHeight] 的渲染层：布局时测得内容高度，变化时在帧后启动弹簧，
/// 期间以控制器数值作为自身高度。
class RenderSpringFollowHeight extends RenderProxyBox {
  RenderSpringFollowHeight({
    required SpringController controller,
    SpringDescription? spring,
  })  : _controller = controller,
        _spring = spring;

  SpringController _controller;
  SpringController get controller => _controller;
  set controller(SpringController value) {
    if (identical(value, _controller)) return;
    if (attached) _controller.removeListener(markNeedsLayout);
    _controller = value;
    if (attached) _controller.addListener(markNeedsLayout);
    markNeedsLayout();
  }

  SpringDescription? _spring;
  set spring(SpringDescription? value) {
    if (value == _spring) return;
    _spring = value;
    if (value == null) _pendingFrom = null;
    markNeedsLayout();
  }

  /// 上一次布局时的内容高度；null = 尚未布局过。
  double? _contentHeight;

  /// 已安排、尚未启动的动画起点（下一帧从这里弹向新高度）。
  double? _pendingFrom;
  bool _launchScheduled = false;
  bool _clipped = false;

  final LayerHandle<ClipRectLayer> _clipLayer = LayerHandle<ClipRectLayer>();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _controller.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    super.dispose();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    return constraints
        .constrain(child.getDryLayout(constraints.copyWith(minHeight: 0)));
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints.copyWith(minHeight: 0), parentUsesSize: true);
    final target = child.size.height;
    final previous = _contentHeight;
    _contentHeight = target;

    double shown;
    if (_spring == null || previous == null) {
      shown = target;
      if (_controller.isAnimating) {
        SchedulerBinding.instance
            .addPostFrameCallback((_) => _controller.jumpTo(target));
      }
    } else {
      if ((target - previous).abs() > 0.5) {
        // 静止时从旧高度起步；动画途中则沿当前值与速度重定目标。
        if (!_controller.isAnimating && _pendingFrom == null) {
          _pendingFrom = previous;
        }
        if (!_launchScheduled) {
          _launchScheduled = true;
          SchedulerBinding.instance.addPostFrameCallback((_) => _launch());
        }
      }
      shown = _pendingFrom ??
          (_controller.isAnimating || _launchScheduled
              ? _controller.value
              : target);
    }
    size = constraints.constrain(Size(child.size.width, shown.clamp(0, 1e9)));
    _clipped = size.height < target - 0.5;
  }

  void _launch() {
    _launchScheduled = false;
    final from = _pendingFrom;
    _pendingFrom = null;
    final target = _contentHeight;
    if (target == null || !attached) return;
    if (from != null && !_controller.isAnimating) _controller.jumpTo(from);
    _controller.animateTo(target, spring: _spring);
    markNeedsLayout();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    if (!_clipped) {
      _clipLayer.layer = null;
      super.paint(context, offset);
      return;
    }
    _clipLayer.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      super.paint,
      oldLayer: _clipLayer.layer,
    );
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      _clipped ? Offset.zero & size : null;
}
