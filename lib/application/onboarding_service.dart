import 'package:shared_preferences/shared_preferences.dart';

/// 新手引导状态。首次启动进入引导，完成后置位 `onboarding_done`。
class OnboardingService {
  static const _prefsKey = 'onboarding_done';

  static Future<bool> isDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  static Future<void> markDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
  }
}
