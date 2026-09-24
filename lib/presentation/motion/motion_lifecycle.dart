import 'package:flutter/widgets.dart';
import 'motion_preferences.dart';

/// Decorative loops must stop, not merely disappear from the widget tree.
/// TickerMode handles covered/offstage routes; lifecycle handles backgrounding.
mixin MotionLifecycle<T extends StatefulWidget> on State<T> {
  late final AppLifecycleListener _motionLifecycle;
  bool _foreground = true;
  bool _allowed = false;
  bool _visible = true;
  bool _decorativeMotionActive = false;
  bool get decorativeMotionActive => _decorativeMotionActive;

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _motionLifecycle = AppLifecycleListener(onStateChange: (state) {
      _foreground = state == AppLifecycleState.resumed;
      _updateMotion(rebuild: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _allowed = MotionPreferences.allowDecorativeMotion(context);
    _visible = TickerMode.valuesOf(context).enabled;
    _updateMotion();
  }

  void _updateMotion({bool rebuild = false}) {
    if (!mounted) return;
    final active = _allowed && _visible && _foreground;
    if (active == _decorativeMotionActive) return;
    _decorativeMotionActive = active;
    onMotionActivityChanged();
    if (rebuild) setState(() {});
  }

  @protected
  void onMotionActivityChanged();

  @override
  void dispose() {
    _motionLifecycle.dispose();
    super.dispose();
  }
}
