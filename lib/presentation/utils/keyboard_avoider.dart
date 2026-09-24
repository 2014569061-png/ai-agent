import 'dart:async';
import 'dart:ui' show FlutterView;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/app_tokens.dart';

/// 可靠的键盘高度来源，修复聊天页「底部白块 / 输入框悬在半空」。
///
/// 根因：Scaffold 默认按 `viewInsets` 缩小整个 body；部分 ROM 在输入法动画被
/// 打断（切后台、快速失焦）后会残留一个过期的键盘 inset，body 就一直被压缩
/// 一个键盘高度，底部露出页面背景（白块），输入框悬在半空。
///
/// 做法：页面关闭 `Scaffold.resizeToAvoidBottomInset`，键盘高度只作用于底部
/// 输入区（[KeyboardSpacer]），由本组件给出「有效」键盘高度：
/// 1. 订阅 `didChangeMetrics` 与焦点变化，直接读取 platform view 的 inset；
/// 2. 有文本输入框获得焦点时如实跟随；
/// 3. 失焦后先跟随输入法收起动画，超过 [staleTimeout] 仍未归零即视为残留：
///    按 0 处理，并主动 `TextInput.hide` 让平台刷新 inset；
/// 4. 应用切到后台时释放输入焦点，避免回到前台时拿到过期 inset。
class KeyboardInsetScope extends StatefulWidget {
  const KeyboardInsetScope({super.key, required this.child});

  final Widget child;

  /// 失焦后仍报告键盘高度多久算作残留。
  static const Duration staleTimeout = AppTokens.durationImeSettle;

  /// 当前有效键盘高度（逻辑像素）；不在 scope 内时返回 null。
  /// 调用方会注册依赖，随键盘开合重建。
  static double? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_KeyboardInsetInherited>()
      ?.inset;

  @override
  State<KeyboardInsetScope> createState() => _KeyboardInsetScopeState();
}

class _KeyboardInsetScopeState extends State<KeyboardInsetScope>
    with WidgetsBindingObserver {
  FlutterView? _view;
  double _inset = 0;
  Timer? _staleTimer;
  bool _stale = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_recompute);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _view = View.of(context);
    _inset = _effectiveInset();
  }

  @override
  void dispose() {
    _staleTimer?.cancel();
    FocusManager.instance.removeListener(_recompute);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() => _recompute();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // 切后台时释放输入焦点：部分 ROM 在后台打断输入法动画后不会回报
        // inset 归零，回到前台时就会拿到过期的键盘高度。
        if (_hasTextFocus()) FocusManager.instance.primaryFocus?.unfocus();
      case AppLifecycleState.resumed:
        _recompute();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  static bool _hasTextFocus() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null || !focusContext.mounted) return false;
    return focusContext.widget is EditableText ||
        focusContext.findAncestorStateOfType<EditableTextState>() != null;
  }

  double _platformInset() {
    final view = _view;
    if (view == null) return 0;
    return view.viewInsets.bottom / view.devicePixelRatio;
  }

  double _effectiveInset() {
    final raw = _platformInset();
    if (raw <= 0 || _hasTextFocus()) {
      _clearStale();
      return raw > 0 ? raw : 0;
    }
    // 失焦但平台仍报告键盘高度：先跟随收起动画，超时仍未归零按残留处理。
    if (!_stale) {
      _staleTimer ??= Timer(KeyboardInsetScope.staleTimeout, _onStale);
    }
    return _stale ? 0 : raw;
  }

  void _clearStale() {
    _staleTimer?.cancel();
    _staleTimer = null;
    _stale = false;
  }

  void _onStale() {
    _staleTimer = null;
    if (!mounted) return;
    if (_platformInset() > 0 && !_hasTextFocus()) {
      _stale = true;
      // 让平台真正收起输入法并回报新的 inset；即使平台不回报，上面也已按 0
      // 处理，输入区不会继续悬空。
      unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    }
    _recompute();
  }

  void _recompute() {
    if (!mounted) return;
    final next = _effectiveInset();
    if (next != _inset) setState(() => _inset = next);
  }

  @override
  Widget build(BuildContext context) =>
      _KeyboardInsetInherited(inset: _inset, child: widget.child);
}

class _KeyboardInsetInherited extends InheritedWidget {
  const _KeyboardInsetInherited({required this.inset, required super.child});

  final double inset;

  @override
  bool updateShouldNotify(_KeyboardInsetInherited oldWidget) =>
      oldWidget.inset != inset;
}

/// 放在输入区最底部：键盘弹出时占位有效键盘高度，把输入区顶到键盘上方；
/// 键盘收起时占位底部安全区（手势条 / 导航栏）。只有它自己随键盘开合重建。
class KeyboardSpacer extends StatelessWidget {
  const KeyboardSpacer({super.key});

  @override
  Widget build(BuildContext context) {
    final keyboard = KeyboardInsetScope.maybeOf(context) ?? 0;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return SizedBox(height: keyboard > 0 ? keyboard : safeBottom);
  }
}
