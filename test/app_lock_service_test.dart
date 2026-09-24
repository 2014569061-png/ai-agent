import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_agent/application/app_lock_service.dart';

class _ThrowingSecureStorage extends FlutterSecureStoragePlatform {
  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    throw StateError('write failed');
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    throw StateError('read failed');
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    throw StateError('delete failed');
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async {
    throw StateError('contains failed');
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    throw StateError('readAll failed');
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    throw StateError('deleteAll failed');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('AppLockService initializes disabled by default', () async {
    final service = AppLockService();
    expect(await service.isEnabled(), false);
  });

  test('AppLockService persists enabled status in secure storage', () async {
    final service = AppLockService();
    await service.setEnabled(true);
    expect(await service.isEnabled(), true);

    await service.setEnabled(false);
    expect(await service.isEnabled(), false);
  });

  test('AppLockService migrates legacy SharedPreferences setting to secure storage', () async {
    SharedPreferences.setMockInitialValues({'app_lock_enabled': true});
    final service = AppLockService();

    expect(await service.isEnabled(), true);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('app_lock_enabled'), false);
  });

  test('isEnabled stays locked when secure storage read throws', () async {
    FlutterSecureStoragePlatform.instance = _ThrowingSecureStorage();
    final service = AppLockService();

    expect(await service.isEnabled(), isTrue);
  });

  test('setEnabled surfaces secure storage write failures', () async {
    FlutterSecureStoragePlatform.instance = _ThrowingSecureStorage();
    final service = AppLockService();

    expect(service.setEnabled(true), throwsA(isA<StateError>()));
  });
}
