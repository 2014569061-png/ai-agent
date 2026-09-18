import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/liquid_glass.dart';

abstract final class AppAppearanceController {
  static const glassKey = 'settings.theme.glass_intensity';
  static const effectsKey = 'settings.theme.immersive_effects';
  static const fontScaleKey = 'settings.font_scale';
  static final glassIntensity = ValueNotifier<double>(.8);
  static final effects = ValueNotifier<String>('full');
  static final fontScale = ValueNotifier<double>(1.0);

  /// Mobile devices have the widest performance range. Keep the initial
  /// composition to one inexpensive blur pass there; people can still select
  /// full liquid glass explicitly from Appearance settings. Desktop and web
  /// retain the richer default because they are not the low-end target path.
  static double get defaultGlassIntensity => kIsWeb ||
          (defaultTargetPlatform != TargetPlatform.android &&
              defaultTargetPlatform != TargetPlatform.iOS)
      ? .8
      : .45;

  static GlassIntensity get resolvedGlassIntensity {
    final v = glassIntensity.value;
    if (v <= 0.1) return GlassIntensity.flat;
    if (v <= 0.5) return GlassIntensity.frosted;
    return GlassIntensity.liquid;
  }

  static Future<void> load([SharedPreferences? shared]) async {
    final prefs = shared ?? await SharedPreferences.getInstance();
    glassIntensity.value =
        (prefs.getDouble(glassKey) ?? defaultGlassIntensity).clamp(0.0, 1.0);
    effects.value = prefs.getString(effectsKey) ?? 'full';
    fontScale.value = (prefs.getDouble(fontScaleKey) ?? 1.0).clamp(0.88, 1.28);
  }

  static Future<void> setGlass(double value) async {
    glassIntensity.value = value.clamp(0.0, 1.0);
    await (await SharedPreferences.getInstance())
        .setDouble(glassKey, glassIntensity.value);
  }

  static Future<void> setGlassIntensityMode(GlassIntensity mode) async {
    final val = switch (mode) {
      GlassIntensity.flat => 0.0,
      GlassIntensity.frosted => 0.45,
      GlassIntensity.liquid => 0.85,
    };
    await setGlass(val);
  }

  static Future<void> setEffects(String value) async {
    effects.value = value;
    await (await SharedPreferences.getInstance()).setString(effectsKey, value);
  }

  static Future<void> setFontScale(double value) async {
    fontScale.value = value.clamp(0.88, 1.28);
    await (await SharedPreferences.getInstance())
        .setDouble(fontScaleKey, fontScale.value);
  }
}
