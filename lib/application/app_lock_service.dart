import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'log_service.dart';
import 'nexus_guard.dart';

/// 生物识别应用锁。指纹/面容解锁，开关使用安全存储（FlutterSecureStorage）防篡改。
class AppLockService {
  AppLockService({
    FlutterSecureStorage? secureStorage,
    LocalAuthentication? auth,
    void Function(String message, {Map<String, dynamic>? detail})? logger,
  })  : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _auth = auth ?? LocalAuthentication(),
        _logger = logger ?? _noopLogger;

  static const _prefsKey = 'app_lock_enabled';
  final FlutterSecureStorage _secureStorage;
  final LocalAuthentication _auth;

  /// 降级日志出口。默认不记录；应用内由 Provider 注入 [LogService.warning]。
  final void Function(String message, {Map<String, dynamic>? detail}) _logger;

  static void _noopLogger(String message, {Map<String, dynamic>? detail}) {}

  Future<bool> isEnabled() async {
    final String? secured;
    try {
      secured = await _secureStorage.read(key: _prefsKey);
    } catch (error, stackTrace) {
      // 读不到开关就不能证明锁是关的。安全存储异常时保持锁定，避免被当成关闭。
      NexusGuard.degradeCaught('appLock.readSecureFlag', error, stackTrace,
          logger: _logger);
      return true;
    }
    if (secured != null) {
      return secured == 'true';
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_prefsKey)) {
        final legacyVal = prefs.getBool(_prefsKey) ?? false;
        await _secureStorage.write(key: _prefsKey, value: legacyVal.toString());
        await prefs.remove(_prefsKey);
        return legacyVal;
      }
      return false;
    } catch (error, stackTrace) {
      // 旧设置也读不到时同样不能证明锁已关闭。
      NexusGuard.degradeCaught('appLock.readLegacyFlag', error, stackTrace,
          logger: _logger);
      return true;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    await _secureStorage.write(key: _prefsKey, value: enabled.toString());
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_prefsKey)) {
      await prefs.remove(_prefsKey);
    }
  }

  /// 设备是否具备可用生物识别（指纹/面容）。
  Future<bool> canUseBiometrics() async {
    try {
      return await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } catch (error, stackTrace) {
      NexusGuard.degradeCaught('appLock.canUseBiometrics', error, stackTrace,
          logger: _logger);
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
    } catch (error, stackTrace) {
      NexusGuard.degradeCaught('appLock.authenticate', error, stackTrace,
          logger: _logger);
      return false;
    }
  }
}

final appLockServiceProvider = Provider<AppLockService>((ref) =>
    AppLockService(logger: ref.watch(logServiceProvider).warning));
