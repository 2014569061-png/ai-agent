import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// L4：记录最近一次按下位置，让弹窗「从点击处长出来」。
///
/// 通过 [GestureBinding] 的全局指针路由被动监听，不参与手势竞争、不改调用方。
/// 只采信 [freshness] 内的按下；更早的（例如由定时器弹出的对话框）回落到居中。
abstract final class NexusTapOrigin {
  /// 约 1.5s（三个长按判定时长）。
  static final Duration freshness = kLongPressTimeout * 3;

  static Offset? _position;
  static Duration? _at;
  static bool _installed = false;
  static final Stopwatch _watch = Stopwatch()..start();

  /// 可注入时钟（测试用）。
  static Duration Function() clock = _defaultClock;
  static Duration _defaultClock() => _watch.elapsed;

  /// 幂等安装全局监听；应用根部构建时调用一次即可。
  static void ensureInstalled() {
    if (_installed) return;
    _installed = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_route);
  }

  static void _route(PointerEvent event) {
    if (event is PointerDownEvent) record(event.position);
  }

  static void record(Offset position) {
    _position = position;
    _at = clock();
  }

  /// 最近一次仍然「新鲜」的按下位置（全局坐标），否则 null。
  static Offset? recent() {
    final at = _at;
    if (at == null || clock() - at > freshness) return null;
    return _position;
  }

  static void reset() {
    _position = null;
    _at = null;
    clock = _defaultClock;
  }

  /// 把全局点换算为 [size]（全屏）内的 [Alignment]，超出范围时夹紧。
  static Alignment alignmentIn(Size size, Offset? point) {
    if (point == null || size.isEmpty) return Alignment.center;
    return Alignment(
      (point.dx / size.width * 2 - 1).clamp(-1.0, 1.0),
      (point.dy / size.height * 2 - 1).clamp(-1.0, 1.0),
    );
  }
}
