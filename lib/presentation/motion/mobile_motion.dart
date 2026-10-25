import 'package:flutter/widgets.dart';

import 'motion_preferences.dart';

/// Restrained phone motion. Desktop keeps its independent spring vocabulary.
abstract final class MobileMotion {
  static const press = Duration(milliseconds: 100);
  static const control = Duration(milliseconds: 120);
  static const message = Duration(milliseconds: 180);
  static const panelEnter = Duration(milliseconds: 240);
  static const panelExit = Duration(milliseconds: 160);
  static const Curve curve = Cubic(0.2, 0, 0.2, 1);
  static const double messageLift = 6;

  static Duration duration(
    BuildContext context,
    Duration value, {
    bool listen = true,
  }) =>
      MotionPreferences.adjustDuration(
        context,
        value,
        reducedDuration: Duration.zero,
        listen: listen,
      );
}
