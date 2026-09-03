import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

import 'package:mobile_agent/application/account_services.dart';
import 'package:mobile_agent/application/billing_api.dart';

// 内存版 secure storage，便于测试账号/权益持久化
class _InMemorySecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> _store = {};
  @override
  Future<void> write({required String key, required String value, required Map<String, String> options}) async => _store[key] = value;
  @override
  Future<String?> read({required String key, required Map<String, String> options}) async => _store[key];
  @override
  Future<void> delete({required String key, required Map<String, String> options}) async => _store.remove(key);
  @override
  Future<bool> containsKey({required String key, required Map<String, String> options}) async => _store.containsKey(key);
  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) async => Map.of(_store);
  @override
  Future<void> deleteAll({required Map<String, String> options}) async => _store.clear();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late EntitlementService entitlement;
  late AccountService account;

  setUp(() {
    FlutterSecureStoragePlatform.instance = _InMemorySecureStorage();
    final api = BillingApi(baseUrl: 'http://test');
    entitlement = EntitlementService(storage: const FlutterSecureStorage());
    account = AccountService(api: api, storage: const FlutterSecureStorage());
  });

  test('EntitlementService 默认非 Pro，托管 Key 后变 Pro', () async {
    expect(await entitlement.isPro(), isFalse);
    expect(await entitlement.managedKey(), isNull);
    await entitlement.grantManagedKey('nkx_test_key');
    expect(await entitlement.isPro(), isTrue);
    expect(await entitlement.managedKey(), 'nkx_test_key');
    await entitlement.revoke();
    expect(await entitlement.isPro(), isFalse);
  });

  test('EntitlementService 权益边界（免费 vs Pro）', () async {
    expect(entitlement.maxSessions(isPro: false), 3);
    expect(entitlement.maxSessions(isPro: true), 99);
    expect(entitlement.canUseMcp(isPro: false), isFalse);
    expect(entitlement.canUseMcp(isPro: true), isTrue);
    expect(entitlement.canUseRag(isPro: false), isFalse);
    expect(entitlement.canUseRag(isPro: true), isTrue);
    expect(entitlement.attachmentLimit(isPro: false), 3);
    expect(entitlement.attachmentLimit(isPro: true), 20);
    expect(entitlement.allowedModels(isPro: true), isEmpty);
    expect(entitlement.allowedModels(isPro: false), isNotEmpty);
  });

  test('AccountService 会话持久化往返', () async {
    expect(await account.restoreSession(), isNull);
    await account.saveSession(const AccountSession(userId: 7, apiKey: 'k', access: 'a', refresh: 'r'));
    final s = await account.restoreSession();
    expect(s!.userId, 7);
    expect(s.access, 'a');
    expect(s.refresh, 'r');
    await account.clearSession();
    expect(await account.restoreSession(), isNull);
  });

  test('RemoteConfigService 缓存兜底 + 类型读取', () async {
    final api = BillingApi(baseUrl: 'http://localhost:1'); // 拉取会失败 → 用默认
    final rc = RemoteConfigService(api: api);
    await rc.refresh();
    expect(rc.isLoaded, isFalse); // 网络失败未加载
    expect(rc.boolFlag('x', true), true);
    expect(rc.intFlag('y', 5), 5);
    expect(rc.stringFlag('z', 'd'), 'd');
  });

  test('默认后端地址解析', () {
    final url = defaultBackendBaseUrl(override: null);
    expect(url, isNotEmpty);
  });
}
