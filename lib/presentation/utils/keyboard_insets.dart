import 'package:flutter/widgets.dart';

/// 当前键盘弹出的逻辑高度（0 表示键盘未弹出）。
///
/// ⚠️ **不要改回 `MediaQuery.viewInsetsOf(context).bottom`**。
///
/// `Scaffold` 会消费底部 inset：凡是取到的 `context` 位于 **Scaffold body 之内**，
/// `MediaQuery.viewInsetsOf(context).bottom` 就 **恒为 0**。而这类遮蔽非常隐蔽——
/// 方法体里写的是 `MediaQuery.viewInsetsOf(context)`，看起来完全正确，
/// 但那个 `context` 实际是被 `LayoutBuilder` / `ValueListenableBuilder` /
/// `Consumer` 等 builder 回调参数**遮蔽**后的内层 context。
///
/// 实测（Flutter 3.47.2）：同一个页面里，
/// State 的 `build` context 读到 300，Scaffold body 内（含上述 builder 回调）读到 0；
/// 而同一处的 `MediaQuery.paddingOf(context).bottom` 仍是 34（**未被消费**），
/// 所以两者行为**不同**，不能一概而论。
///
/// 直接向 platform view 取值可以绕过这层作用域，在 Scaffold 内外都成立。
double keyboardInset(BuildContext context) {
  final view = View.of(context);
  return view.viewInsets.bottom / view.devicePixelRatio;
}

/// 键盘是否正在弹出。关于 `context` 归属的警告见 [keyboardInset]。
bool isKeyboardVisible(BuildContext context) => keyboardInset(context) > 0;
