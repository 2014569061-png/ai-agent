import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class AppAppearanceController {
  static const glassKey = 'settings.theme.glass_intensity';
  static const effectsKey = 'settings.theme.immersive_effects';
  static final glassIntensity = ValueNotifier<double>(.8);
  static final effects = ValueNotifier<String>('full');

  static Future<void> load([SharedPreferences? shared]) async {
    final prefs = shared ?? await SharedPreferences.getInstance();
    glassIntensity.value = (prefs.getDouble(glassKey) ?? .8).clamp(0.0, 1.0);
    effects.value = prefs.getString(effectsKey) ?? 'full';
  }

  static Future<void> setGlass(double value) async {
    glassIntensity.value = value.clamp(0.0, 1.0);
    await (await SharedPreferences.getInstance())
        .setDouble(glassKey, glassIntensity.value);
  }

  static Future<void> setEffects(String value) async {
    effects.value = value;
    await (await SharedPreferences.getInstance()).setString(effectsKey, value);
  }
}
