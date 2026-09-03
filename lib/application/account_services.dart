import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'billing_api.dart';

/// 权益判定（§4.1）。单例，secure storage 持久化。
///
/// 核心规则：检测到已配置的托管 Key（登入后端账号即下发）即 Pro。
/// 拦截点（侵入最小）：模型选择器过滤 / 新建会话计数 / MCP+RAG 入口隐藏。
class EntitlementService {
  EntitlementService({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static const _hasProKey = 'nexus.has_pro_key';
  static const _managedKey = 'nexus.managed_key';

  final FlutterSecureStorage _storage;

  /// 是否 Pro（存在已配置托管 Key）。
  Future<bool> isPro() async => (await _storage.read(key: _hasProKey)) == 'true';

  /// 托管 Key（代理请求用）。Pro 才有效。
  Future<String?> managedKey() => _storage.read(key: _managedKey);

  /// 登入/充值后写入托管 Key → 触发 Pro。
  Future<void> grantManagedKey(String key) async {
    await _storage.write(key: _managedKey, value: key);
    await _storage.write(key: _hasProKey, value: 'true');
  }

  /// 注销/登出时清除。
  Future<void> revoke() async {
    await _storage.delete(key: _managedKey);
    await _storage.delete(key: _hasProKey);
  }

  /// 免费用户可用的模型子集（gpt-4o-mini 档）。
  Set<String> allowedModels({required bool isPro}) => isPro
      ? {}
      : {'gpt-4o-mini', 'deepseek-chat'};

  /// 会话并发上限（免费 3 / Pro 不限）。
  int maxSessions({required bool isPro}) => isPro ? 99 : 3;

  bool canUseMcp({required bool isPro}) => isPro;
  bool canUseRag({required bool isPro}) => isPro;

  /// 附件上限（免费 3 个 / Pro 20 个）。
  int attachmentLimit({required bool isPro}) => isPro ? 20 : 3;
}

/// 账号服务：注册/登录/会话持久化/设备管理/注销。
class AccountService {
  AccountService({required this.api, FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static const _access = 'nexus.account_access';
  static const _refresh = 'nexus.account_refresh';
  static const _userId = 'nexus.account_user_id';

  final BillingApi api;
  final FlutterSecureStorage _storage;

  Future<AccountSession?> restoreSession() async {
    final access = await _storage.read(key: _access);
    if (access == null || access.isEmpty) return null;
    final refresh = await _storage.read(key: _refresh) ?? '';
    final userId = int.tryParse(await _storage.read(key: _userId) ?? '') ?? 0;
    return AccountSession(userId: userId, apiKey: '', access: access, refresh: refresh);
  }

  Future<void> saveSession(AccountSession s) async {
    await _storage.write(key: _access, value: s.access);
    await _storage.write(key: _refresh, value: s.refresh);
    await _storage.write(key: _userId, value: s.userId.toString());
  }

  Future<void> clearSession() async {
    for (final k in [_access, _refresh, _userId]) {
      await _storage.delete(key: k);
    }
  }

  Future<String> accessTokenOrThrow() async {
    final s = await restoreSession();
    if (s == null) throw Exception('not logged in');
    return s.access;
  }
}

/// 远程配置（Feature Flag）服务（§4.5）。启动拉取，本地缓存 + 过期兜底。
class RemoteConfigService {
  RemoteConfigService({required this.api});

  final BillingApi api;
  Map<String, dynamic> _cache = const {};
  bool _loaded = false;

  /// 拉取并缓存；失败时用上次缓存兜底。
  Future<void> refresh({String appVersion = '0.0.0'}) async {
    try {
      _cache = await api.fetchConfig(appVersion: appVersion);
      _loaded = true;
    } catch (_) {
      // 离线兜底：保留上次缓存
    }
  }

  bool get isLoaded => _loaded;
  Map<String, dynamic> get all => _cache;

  dynamic flag(String key, [dynamic fallback]) => _cache[key] ?? fallback;
  bool boolFlag(String key, [bool fallback = false]) => _cache[key] as bool? ?? fallback;
  int intFlag(String key, [int fallback = 0]) => (_cache[key] as num?)?.toInt() ?? fallback;
  String stringFlag(String key, [String fallback = '']) => _cache[key] as String? ?? fallback;
}

/// 后端地址解析（默认本地；生产经远程配置覆盖）。
String defaultBackendBaseUrl({String? override}) {
  if (override != null && override.isNotEmpty) return override;
  const fromEnv = String.fromEnvironment('NEXUS_BACKEND');
  if (fromEnv.isNotEmpty) return fromEnv;
  return 'http://10.0.2.2:8787'; // Android 模拟器访问宿主
}
