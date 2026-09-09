import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemeController {
  AppThemeController._();

  static final mode = ValueNotifier<ThemeMode>(ThemeMode.system);

  static Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString('app.theme_mode');
    mode.value = switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static Future<void> setMode(ThemeMode newMode) async {
    mode.value = newMode;
    final preferences = await SharedPreferences.getInstance();
    final str = switch (newMode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await preferences.setString('app.theme_mode', str);
  }

  static Future<void> setDayMode(bool enabled) async {
    await setMode(enabled ? ThemeMode.light : ThemeMode.dark);
  }
}
