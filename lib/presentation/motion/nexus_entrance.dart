import 'package:flutter/widgets.dart';

import 'motion_preferences.dart';
import 'nexus_motion.dart';

/// 首屏入场编排（M2）：元素挂载时按槽位错开播放一次入场动画。
///
/// * 每个元素 [NexusMotion.entrance]，槽位之间错开 [NexusMotion.entranceStagger]；
/// * 只在 `initState` 播放，重建、键盘开合、返回页面都不会重播；
/// * [onceId] 非空时同一进程内只播一次（顶栏、输入框这类常驻外壳）；
/// * [fade] 为 false 时只做位移/缩放——子树含 `BackdropFilter`（玻璃）时必须
///   关闭，玻璃放进 Opacity 临时缓冲区会闪烁；
/// * reduced：只保留 [fade] 为 true 的元素的 120ms 淡入；off：直接显示；
/// * 播放结束后停止 ticker，稳态没有任何常驻动画成本。
class NexusEntrance extends StatefulWidget {
  const NexusEntrance({
    super.key,
    required this.child,
    this.slot = 0,
    this.offset = Offset.zero,
    this.scaleFrom = 1,
    this.fade = true,
    this.onceId,
    this.enabled = true,
  });

  final Widget child;

  /// 错开顺序（0 起）。
  final int slot;

  /// 起始位移（逻辑像素），终点为 0。
  final Offset offset;

  /// 起始缩放，终点为 1。
  final double scaleFrom;

  /// 是否做透明度渐入。
  final bool fade;

  /// 进程内只播放一次的标识。
  final String? onceId;

  /// 挂载时是否播放；只在挂载时读取一次，之后的变化被忽略。
  final bool enabled;

  static final Set<String> _played = <String>{};

  /// 测试用：清空「只播一次」记录。
  @visibleForTesting
  static void debugReset() => _played.clear();

  @override
  State<NexusEntrance> createState() => _NexusEntranceState();
}

class _NexusEntranceState extends State<NexusEntrance>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _progress;
  bool _reduced = false;

  /// 本进程已播过（onceId 去重）或已完成初始化判定。
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) {
      _resolved = true;
      return;
    }
    final id = widget.onceId;
    // 同一 onceId 已经播过：直接显示，不创建任何动画。
    if (id != null && !NexusEntrance._played.add(id)) _resolved = true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolved) return;
    _resolved = true;
    final level = MotionPreferences.levelOf(context, listen: false);
    if (level == MotionLevel.off) return;
    _reduced = level == MotionLevel.reduced;
    if (_reduced && !widget.fade) return;

    final stagger = NexusMotion.entranceStagger * widget.slot;
    final each = _reduced ? NexusMotion.reducedEntrance : NexusMotion.entrance;
    final total = _reduced ? each : stagger + each;
    final controller = AnimationController(vsync: this, duration: total);
    _controller = controller;
    _progress = CurvedAnimation(
      parent: controller,
      curve: _reduced
          ? NexusMotion.curveStandard
          : Interval(
              stagger.inMicroseconds / total.inMicroseconds,
              1,
              curve: NexusMotion.curveEnter,
            ),
    );
    controller.forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    if (progress == null) return widget.child;
    // 包装结构在整个生命周期内保持不变（结束后退化为恒等变换 / 不透明），
    // 否则子树会被重新挂载，输入框之类的状态（焦点、光标）会丢失。
    return AnimatedBuilder(
      animation: progress,
      child: widget.child,
      builder: (context, child) {
        final t = progress.value;
        final moving = !_reduced;
        Widget result = Transform.translate(
          offset: moving ? widget.offset * (1 - t) : Offset.zero,
          child: Transform.scale(
            scale: moving ? widget.scaleFrom + (1 - widget.scaleFrom) * t : 1,
            child: child,
          ),
        );
        // alwaysIncludeSemantics：透明度 0 的首帧也必须对读屏可见，
        // 否则入场期间读屏会找不到标题和操作。
        if (widget.fade) {
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
