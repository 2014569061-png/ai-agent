import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const first = ProviderConfig(
      id: 'first',
      baseUrl: 'https://first.invalid/v1',
      model: 'first-model',
      apiKey: 'FAKE-FIRST-KEY');
  const second = ProviderConfig(
      id: 'second',
      baseUrl: 'https://second.invalid/v1',
      model: 'second-model',
      apiKey: 'FAKE-SECOND-KEY');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('删除不存在的配置不清理旧格式迁移来源', () async {
    SharedPreferences.setMockInitialValues({
      'provider.base_url': first.baseUrl,
      'provider.model': first.model,
    });
    FlutterSecureStorage.setMockInitialValues(
        {'provider.api_key': first.apiKey});
    expect(await ProviderConfigStore().deleteProfile('missing'), isFalse);
    expect((await ProviderConfigStore().load()).apiKey, first.apiKey);
  });

  for (final active in ['first', 'missing', '']) {
    test('删除唯一配置清除兼容副本，即使 active 为 "$active"', () async {
      final store = ProviderConfigStore();
      await store.save(first);
      final prefs = await SharedPreferences.getInstance();
      if (active.isEmpty) {
        await prefs.remove('provider.active');
      } else {
        await prefs.setString('provider.active', active);
      }
      await store.deleteProfile(first.id);
      final fresh = ProviderConfigStore();
      expect(await fresh.loadAll(), isEmpty);
      final loaded = await fresh.load();
      expect(loaded.apiKey, isEmpty);
      expect(loaded.baseUrl, isNot(first.baseUrl));
      expect(loaded.model, isNot(first.model));
      for (final key in [
        'provider.active',
        'provider.base_url',
        'provider.model'
      ]) {
        expect(prefs.containsKey(key), isFalse);
      }
      final secrets = await const FlutterSecureStorage().readAll();
      expect(secrets.containsKey('provider.api_key'), isFalse);
      expect(secrets.containsKey('provider.api_key.first'), isFalse);
    });
  }

  test('删除活动配置切换到保留配置', () async {
    final store = ProviderConfigStore();
    await store.save(first);
    await store.save(second);
    await store.deleteProfile(second.id);
    final loaded = await ProviderConfigStore().load();
    expect(loaded.id, first.id);
    expect(loaded.apiKey, first.apiKey);
    expect(loaded.baseUrl, first.baseUrl);
    expect(await const FlutterSecureStorage().read(key: 'provider.api_key'),
        first.apiKey);
  });

  test('删除非活动配置保留当前配置', () async {
    final store = ProviderConfigStore();
    await store.save(first);
    await store.save(second);
    await store.deleteProfile(first.id);
    final loaded = await ProviderConfigStore().load();
    expect(loaded.id, second.id);
    expect(loaded.apiKey, second.apiKey);
  });

  test('无 profiles 的旧格式仍可加载，保存再删除不会复活', () async {
    SharedPreferences.setMockInitialValues({
      'provider.base_url': first.baseUrl,
      'provider.model': first.model,
    });
    FlutterSecureStorage.setMockInitialValues(
        {'provider.api_key': first.apiKey});
    final store = ProviderConfigStore();
    final legacy = await store.load();
    expect(legacy.apiKey, first.apiKey);
    expect(legacy.baseUrl, first.baseUrl);
    await store.save(legacy);
    await store.deleteProfile(legacy.id);
    expect((await ProviderConfigStore().load()).apiKey, isEmpty);
  });

  test('恢复配置和清空恢复仍清理所有旧副本', () async {
    final store = ProviderConfigStore();
    await store.save(first);
    await store.restoreProfiles([second], activeId: second.id);
    expect((await ProviderConfigStore().load()).apiKey, second.apiKey);
    expect(
        await const FlutterSecureStorage().read(key: 'provider.api_key.first'),
        isNull);
    await store.restoreProfiles([]);
    expect((await ProviderConfigStore().load()).apiKey, isEmpty);
    expect(await const FlutterSecureStorage().readAll(), isEmpty);
  });

  test('清除全部配置同时清除工具密钥', () async {
    final store = ProviderConfigStore();
    await store.save(first);
    await store.saveToolKey('tavily', 'FAKE-TOOL-KEY');
    await store.clearAll();
    expect(await ProviderConfigStore().loadAll(), isEmpty);
    expect((await ProviderConfigStore().load()).apiKey, isEmpty);
    expect(await store.readToolKey('tavily'), isEmpty);
    expect(await const FlutterSecureStorage().readAll(), isEmpty);
  });
}
