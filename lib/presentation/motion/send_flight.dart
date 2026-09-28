import 'package:flutter/widgets.dart';

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

  @override
  State<SendFlightLanding> createState() => _SendFlightLandingState();
}

class _SendFlightLandingState extends State<SendFlightLanding>
    with SingleTickerProviderStateMixin {
  static const Animation<double> _landed = AlwaysStoppedAnimation<double>(0);

  SpringController? _spring;
  Offset _delta = Offset.zero;
  bool _measured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted) return;
    final box = context.findRenderObject();
    var dy = 0.0;
    if (box is RenderBox && box.attached && box.hasSize) {
      final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
      dy = widget.flight.source.bottom - bottom;
    }
    final spring =
        NexusSpringPolicy.resolve(context, NexusSprings.bouncy, listen: false);
    setState(() {
      _measured = true;
      if (dy <= 0 || dy > SendFlightLanding.maxTravel || spring == null) {
        return;
      }
      _delta = Offset(0, dy);
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
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _spring ?? _landed,
        child: widget.child,
        builder: (context, child) {
          final t = (_spring ?? _landed).value;
          final scale =
              1 - (1 - SendFlightLanding.startScale) * t.clamp(0.0, 1.0);
          return Opacity(
            opacity: _measured ? 1 : 0,
            child: Transform.translate(
              offset: _delta * t,
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.bottomRight,
                child: child,
              ),
            ),
          );
        },
      );
}
