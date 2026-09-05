import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../domain/models.dart';
import 'provider_config.dart';

/// Provider 配置存储：负责 Base URL / Model / API Key 的本地持久化。
///
/// web 上 `FlutterSecureStorage` 默认走 IndexedDB，在浏览器隐私模式 /
/// Safari ITP 等场景会被禁用并静默失败，导致 API Key 看起来"丢了"。
/// 这里根据 [kIsWeb] 自动选择后端：web 用 SharedPreferences（localStorage），
/// 其他平台继续用 Keychain / Keystore。
class ProviderConfigStore {
  ProviderConfigStore({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _baseUrlKey = 'provider.base_url';
  static const _modelKey = 'provider.model';
  static const _apiKeyKey = 'provider.api_key';
  static const _profilesKey = 'provider.profiles';
  static const _activeKey = 'provider.active';
  static const _defaultBaseUrl = 'https://api.openai.com/v1';
  static const _defaultModel = 'gpt-4o-mini';

  final FlutterSecureStorage _secureStorage;

  /// web 上共享一份 SharedPreferences 后端的 Map，方便本地读写 API Key。
  /// 非 web 平台返回 null，继续走 secureStorage。
  SharedPreferencesAsync? _prefsAsync;

  Future<SharedPreferencesAsync?> _prefsBackend() async {
    if (!kIsWeb) return null;
    _prefsAsync ??= SharedPreferencesAsync();
    return _prefsAsync;
  }

  Future<String?> _readKey(String key) async {
    final backend = await _prefsBackend();
    if (backend != null) return backend.getString(key);
    return _secureStorage.read(key: key);
  }

  Future<void> _writeKey(String key, String value) async {
    final backend = await _prefsBackend();
    if (backend != null) {
      await backend.setString(key, value);
      return;
    }
    await _secureStorage.write(key: key, value: value);
  }

  Future<void> _deleteKey(String key) async {
    final backend = await _prefsBackend();
    if (backend != null) {
      await backend.remove(key);
      return;
    }
    await _secureStorage.delete(key: key);
  }

  Future<ProviderConfig> load() async {
    final profiles = await loadAll();
    if (profiles.isNotEmpty) {
      return profiles.firstWhere((p) => p.id == _activeId,
          orElse: () => profiles.first);
    }
    final preferences = await SharedPreferences.getInstance();
    return ProviderConfig(
      baseUrl: preferences.getString(_baseUrlKey) ?? _defaultBaseUrl,
      model: preferences.getString(_modelKey) ?? _defaultModel,
      apiKey: await _readKey(_apiKeyKey) ?? '',
    );
  }

  String? _activeId;

  Future<List<ProviderConfig>> loadAll() async {
    final preferences = await SharedPreferences.getInstance();
    _activeId = preferences.getString(_activeKey);
    final raw = preferences.getString(_profilesKey);
    if (raw == null) return [];
    final ids = (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    final result = <ProviderConfig>[];
    for (final item in ids) {
      final id = item['id'] as String? ?? 'default';
      result.add(ProviderConfig(
        id: id,
        name: item['name'] as String? ?? id,
        baseUrl: item['baseUrl'] as String? ?? _defaultBaseUrl,
        model: item['model'] as String? ?? _defaultModel,
        type: _parseType(item['type'] as String?),
        apiKey: await _readKey('provider.api_key.$id') ?? '',
        reasoningEffort: _parseEffort(item['reasoningEffort'] as String?),
        contextTokens: (item['contextTokens'] as num?)?.toInt() ??
            ProviderConfig.defaultContextTokens,
      ));
    }
    return result;
  }

  Map<String, dynamic> _profileMeta(ProviderConfig item) => {
        'id': item.id,
        'name': item.name,
        'baseUrl': item.baseUrl.trim(),
        'model': item.model.trim(),
        'type': item.type.name,
        'reasoningEffort': item.reasoningEffort.name,
        'contextTokens': item.contextTokens,
      };

  ProviderType _parseType(String? name) =>
      ProviderType.values.firstWhere((t) => t.name == name,
          orElse: () => ProviderType.openaiCompatible);

  ReasoningEffort _parseEffort(String? name) => ReasoningEffort.values
      .firstWhere((e) => e.name == name, orElse: () => ReasoningEffort.medium);

  Future<void> save(ProviderConfig config) async {
    final preferences = await SharedPreferences.getInstance();
    final profiles = await loadAll();
    final updated = [...profiles.where((item) => item.id != config.id), config];
    await preferences.setString(
        _profilesKey,
        jsonEncode(updated.map(_profileMeta).toList()));
    await preferences.setString(_activeKey, config.id);
    await preferences.setString(_baseUrlKey, config.baseUrl.trim());
    await preferences.setString(_modelKey, config.model.trim());
    await _writeKey('provider.api_key.${config.id}', config.apiKey.trim());
    await _writeKey(_apiKeyKey, config.apiKey.trim());
  }

  /// 保险箱恢复：整体重建 Provider 配置与密钥。与逐条 [save] 不同，
  /// 这里以备份文件为准整表覆盖，activeId 指定恢复后激活的配置。
  Future<void> restoreProfiles(List<ProviderConfig> configs,
      {String? activeId}) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
        _profilesKey, jsonEncode(configs.map(_profileMeta).toList()));
    for (final item in configs) {
      await _writeKey('provider.api_key.${item.id}', item.apiKey.trim());
    }
    final active = activeId == null
        ? configs.isEmpty
            ? null
            : configs.first
        : configs.where((item) => item.id == activeId).firstOrNull;
    if (active == null) return;
    await preferences.setString(_activeKey, active.id);
    await preferences.setString(_baseUrlKey, active.baseUrl.trim());
    await preferences.setString(_modelKey, active.model.trim());
    await _writeKey(_apiKeyKey, active.apiKey.trim());
  }

  Future<void> clearKey() => _deleteKey(_apiKeyKey);

  Future<String> readToolKey(String name) async =>
      await _readKey('tool.api_key.$name') ?? '';

  Future<void> saveToolKey(String name, String value) async {
    await _writeKey('tool.api_key.$name', value.trim());
  }
}
