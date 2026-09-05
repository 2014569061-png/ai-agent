import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../infrastructure/database/app_database.dart';
import '../infrastructure/database/database_provider.dart';
import '../infrastructure/mcp/mcp_tool_provider.dart';
import '../infrastructure/providers/provider_config_store.dart';
import '../infrastructure/providers/tool_trust_store.dart';
import 'account_services.dart';
import 'billing_api.dart';
import 'mcp_service.dart';

/// 数据库注入点（可在测试中 override 为内存数据库）。
final databaseProvider =
    FutureProvider<AppDatabase>((ref) => DatabaseProvider.instance.database);

/// Provider 配置存储注入点（可在测试中 override）。
final providerConfigStoreProvider =
    Provider<ProviderConfigStore>((ref) => ProviderConfigStore());

/// 后端地址（可由编译期常量覆盖，测试中亦可 override）。
final backendBaseUrlProvider =
    Provider<String>((ref) => defaultBackendBaseUrl());

/// 后端 HTTP 客户端。
final billingApiProvider = Provider<BillingApi>(
    (ref) => BillingApi(baseUrl: ref.watch(backendBaseUrlProvider)));

/// 权益判定（托管 Key → Pro）。
final entitlementServiceProvider =
    Provider<EntitlementService>((ref) => EntitlementService());

/// 账号服务（注册/登录/会话/设备/注销）。
final accountServiceProvider = Provider<AccountService>(
    (ref) => AccountService(api: ref.watch(billingApiProvider)));

/// 远程配置（Feature Flag）服务。
final remoteConfigServiceProvider = Provider<RemoteConfigService>(
    (ref) => RemoteConfigService(api: ref.watch(billingApiProvider)));

/// 当前是否 Pro（是否存在已配置托管 Key）。
final isProProvider = FutureProvider<bool>(
    (ref) => ref.watch(entitlementServiceProvider).isPro());

/// 全局「始终允许」工具信任清单注入点。等待初值加载完成，避免写入覆盖竞态。
final toolTrustStoreProvider = FutureProvider<ToolTrustStore>((ref) async {
  final store = ToolTrustStore();
  await store.init();
  return store;
});

/// MCP 连接管理注入点。随 ProviderScope 生命周期持有连接，
/// scope 销毁时统一关闭，避免会话间重复连接。
final mcpToolProvider = Provider<McpToolProvider>((ref) {
  final provider = McpToolProvider();
  ref.onDispose(provider.dispose);
  return provider;
});

/// MCP 配置服务。所有页面与运行时均从此处读取 Drift 中的配置。
final mcpServiceProvider = Provider<McpService>((ref) => McpService(
      database: ref.read(databaseProvider.future),
    ));
