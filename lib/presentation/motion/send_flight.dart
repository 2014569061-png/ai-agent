import 'package:flutter/material.dart';

import 'motion_preferences.dart';
import 'nexus_spring.dart';

/// 一次「发送飞出」（L2）：记录发送瞬间输入框在屏幕上的位置。
@immutable
class SendFlight {
  const SendFlight({required this.source, required this.at});

  /// 输入框（文字区域）的全局矩形。
  final Rect source;

  /// 发起时刻（[SendFlightBus.clock]）。
  final Duration at;
}

/// 输入框与消息列表之间的一次性通道（L2）。
///
/// 输入框点击发送时 [launch]，新用户气泡首次构建时 [claim]；超过 [window]
/// 未被认领（发送失败、被拦截、只排队未上屏）即作废，气泡退回普通升起动画。
/// 只传位置不传内容，不触碰业务状态。
abstract final class SendFlightBus {
  static const Duration window = Duration(milliseconds: 900);

  /// 可在测试中替换的时钟。
  static Duration Function() clock = _now;
  static Duration _now() =>
      Duration(microseconds: DateTime.now().microsecondsSinceEpoch);

  static SendFlight? _pending;

  static void launch(Rect source) =>
      _pending = SendFlight(source: source, at: clock());

  /// 从输入框的 [context] 取全局矩形并发起；未挂载或动效非完整档时忽略。
  static void launchFrom(BuildContext? context) {
    if (context == null ||
        MotionPreferences.levelOf(context, listen: false) != MotionLevel.full) {
      return;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    launch(box.localToGlobal(Offset.zero) & box.size);
  }

  /// 认领并清空；过期返回 null。
  static SendFlight? claim() {
    final pending = _pending;
    _pending = null;
    if (pending == null || clock() - pending.at > window) return null;
    return pending;
  }

  static bool get hasPending => _pending != null;

  /// 输入框销毁时作废未认领的飞行，避免泄漏到之后出现的气泡。
  static void cancel() => _pending = null;

  @visibleForTesting
  static void reset() {
    _pending = null;
    clock = _now;
  }
}

/// 新用户气泡的「落地」（L2，FLIP）：首帧不可见地完成布局并测量自身位置，
/// 随后从输入框底边弹簧（[NexusSprings.bouncy]）飞到自己的位置，同时从 0.94
/// 放大到 1。位移异常（向下飞或超过 [maxTravel]）时直接显示。
/// L2：标记"真正的气泡"。放在用户气泡外层；位于 [SendFlightLanding] 之下时，
/// 落地动画以它的矩形 / 颜色 / 圆角作为形变终点；否则原样透传。
class SendFlightAnchor extends StatefulWidget {
  const SendFlightAnchor({
    super.key,
    required this.color,
    required this.borderRadius,
    required this.child,
  });

  final Color color;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  State<SendFlightAnchor> createState() => _SendFlightAnchorState();
}

class _SendFlightAnchorState extends State<SendFlightAnchor> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.getInheritedWidgetOfExactType<_SendFlightScope>()?.landing._anchor =
        this;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _SendFlightScope extends InheritedWidget {
  const _SendFlightScope({required this.landing, required super.child});

  final _SendFlightLandingState landing;

  @override
  bool updateShouldNotify(_SendFlightScope oldWidget) => false;
}

/// L2 发送飞出落地：输入框矩形（幽灵胶囊）以 bouncy 弹簧收缩形变为气泡矩形，
/// 气泡内容随底边竖直飞入并在后半程淡入接棒——文字始终按最终宽度排版，不重排。
class SendFlightLanding extends StatefulWidget {
  const SendFlightLanding({
    super.key,
    required this.flight,
    required this.child,
    this.onLanded,
  });

  final SendFlight flight;
  final Widget child;
  final VoidCallback? onLanded;

  static const double startScale = 0.94;
  static const double maxTravel = 640;
  static const Key contentKey = ValueKey('send_flight_content');
  static const Key ghostKey = ValueKey('send_flight_ghost');

  @override
  State<SendFlightLanding> createState() => _SendFlightLandingState();
}

class _SendFlightLandingState extends State<SendFlightLanding>
    with SingleTickerProviderStateMixin {
  static const Animation<double> _landed = AlwaysStoppedAnimation<double>(0);
  static const BorderRadius _fallbackRadius =
      BorderRadius.all(Radius.circular(20));

  _SendFlightAnchorState? _anchor;
  SpringController? _spring;
  bool _measured = false;
  Rect? _source;
  Rect _target = Rect.zero;
  Color? _ghostColor;
  BorderRadius _ghostRadius = _fallbackRadius;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  Rect? _localRect(RenderBox own, RenderObject? other) {
    if (other is! RenderBox || !other.attached || !other.hasSize) return null;
    final topLeft = own.globalToLocal(other.localToGlobal(Offset.zero));
    return topLeft & other.size;
  }

  void _measure() {
    if (!mounted) return;
    final own = context.findRenderObject();
    final spring =
        NexusSpringPolicy.resolve(context, NexusSprings.bouncy, listen: false);
    Rect? target;
    Rect? source;
    if (own is RenderBox && own.attached && own.hasSize) {
      target = _localRect(own, _anchor?.context.findRenderObject()) ??
          Offset.zero & own.size;
      final src = widget.flight.source;
      source = Rect.fromPoints(
          own.globalToLocal(src.topLeft), own.globalToLocal(src.bottomRight));
    }
    final dy = (source?.bottom ?? 0) - (target?.bottom ?? 0);
    setState(() {
      _measured = true;
      if (target == null ||
          source == null ||
          dy <= 0 ||
          dy > SendFlightLanding.maxTravel ||
          spring == null) {
        return;
      }
      _target = target;
      _source = source;
      final anchor = _anchor?.widget;
      _ghostColor = anchor?.color ?? Theme.of(context).colorScheme.primary;
      _ghostRadius = anchor?.borderRadius ?? _fallbackRadius;
      _spring = SpringController(vsync: this, value: 1);
    });
    final controller = _spring;
    if (controller == null) {
      widget.onLanded?.call();
      return;
    }
    controller.animateTo(0, spring: spring).orCancel.then(
          (_) => widget.onLanded?.call(),
          onError: (Object _) {},
        );
  }

  @override
  void dispose() {
    _spring?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SendFlightScope(
        landing: this,
        child: AnimatedBuilder(
          animation: _spring ?? _landed,
          child: widget.child,
          builder: (context, child) {
            final source = _source;
            final t = (_spring ?? _landed).value;
            final ct = t.clamp(0.0, 1.0);
            final flying = source != null && t != 0;
            // 允许 t 轻微越过 0（bouncy 回弹），矩形随之外推形成回弹感。
            final rect = flying ? Rect.lerp(_target, source, t)! : Rect.zero;
            final radius = flying
                ? BorderRadius.lerp(
                    _ghostRadius, BorderRadius.circular(source.height / 2), ct)!
                : _ghostRadius;
            final contentOpacity = !_measured
                ? 0.0
                : flying
                    ? (1 - (ct - 0.2) / 0.45).clamp(0.0, 1.0)
                    : 1.0;
            final ghostOpacity =
                flying ? ((ct - 0.08) / 0.3).clamp(0.0, 1.0) : 0.0;
            final scale = 1 - (1 - SendFlightLanding.startScale) * ct;
            return Stack(
              clipBehavior: Clip.none,
              fit: StackFit.passthrough,
              children: [
                Opacity(
                  key: SendFlightLanding.contentKey,
                  opacity: contentOpacity,
                  child: Transform.translate(
                    offset:
                        Offset(0, flying ? rect.bottom - _target.bottom : 0),
                    child: Transform.scale(
                      scale: scale,
                      alignment: Alignment.bottomRight,
                      child: child,
                    ),
                  ),
                ),
                Positioned.fromRect(
                  rect: rect,
                  child: IgnorePointer(
                    child: Opacity(
                      key: SendFlightLanding.ghostKey,
                      opacity: ghostOpacity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _ghostColor,
                          borderRadius: radius,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
}
