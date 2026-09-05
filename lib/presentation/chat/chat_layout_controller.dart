import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controls the readable width of chat message bubbles.
abstract final class ChatLayoutController {
  static const adaptive = -1.0;
  static const customMin = .45;
  static const customMax = .95;
  static const customDefault = .75;
  static final widthFactor = ValueNotifier<double>(adaptive);

  static Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    widthFactor.value =
        _normalize(preferences.getDouble('chat.bubble_width') ?? adaptive);
  }

  static Future<void> setWidthFactor(double value) async {
    final normalized = _normalize(value);
    widthFactor.value = normalized;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble('chat.bubble_width', normalized);
  }

  static void updateWidthFactor(double value) {
    widthFactor.value = _normalize(value);
  }

  static double _normalize(double value) {
    if (value == adaptive) return adaptive;
    if (!value.isFinite) return adaptive;
    return value.clamp(customMin, customMax).toDouble();
  }
}
