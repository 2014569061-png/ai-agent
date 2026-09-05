import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 生物识别应用锁。指纹/面容解锁，开关存 SharedPreferences。
class AppLockService {
  static const _prefsKey = 'app_lock_enabled';
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, enabled);
  }

  /// 设备是否具备可用生物识别（指纹/面容）。
  Future<bool> canUseBiometrics() async {
    try {
      return await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: '请验证身份以解锁 NEXUS Agent',
        // biometricOnly=false：设备无指纹/面容时回退系统 PIN/密码，
        // 避免用户被锁死无法进入应用。
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}

final appLockServiceProvider =
    Provider<AppLockService>((ref) => AppLockService());
