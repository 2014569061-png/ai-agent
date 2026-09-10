import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../infrastructure/database/app_database.dart';
import '../infrastructure/database/database_provider.dart';
import '../infrastructure/mcp/mcp_tool_provider.dart';
import '../infrastructure/providers/provider_config_store.dart';
import '../infrastructure/providers/tool_trust_store.dart';
import 'mcp_service.dart';

/// Agent 网络重试参数。生产环境保留指数退避；测试或离线模式可注入零等待，
/// 避免把外部网络不可用误差放大成整组测试的长等待。
class AgentRetrySettings {
  const AgentRetrySettings({
    this.maxRetries = 3,
    this.retryBackoff = const Duration(seconds: 2),
  });

  final int maxRetries;
  final Duration retryBackoff;
}

final agentRetrySettingsProvider =
    Provider<AgentRetrySettings>((ref) => const AgentRetrySettings());

/// 数据库注入点（可在测试中 override 为内存数据库）。
final databaseProvider =
    FutureProvider<AppDatabase>((ref) => DatabaseProvider.instance.database);

/// Provider 配置存储注入点（可在测试中 override）。
final providerConfigStoreProvider =
    Provider<ProviderConfigStore>((ref) => ProviderConfigStore());

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
