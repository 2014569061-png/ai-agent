import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the application language selected in Settings.
abstract final class AppLocaleController {
  static const key = 'settings.language';
  static final locale = ValueNotifier<Locale?>(null);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    locale.value = _parse(prefs.getString(key));
  }

  static Future<void> setCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, code);
    locale.value = _parse(code);
  }

  static Locale? _parse(String? code) {
    switch (code) {
      case 'zh':
        return const Locale('zh');
      case 'en':
        return const Locale('en');
      default:
        return null;
    }
  }
}
