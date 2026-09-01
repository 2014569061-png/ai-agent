import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../infrastructure/database/app_database.dart';
import '../infrastructure/database/database_provider.dart';
import '../infrastructure/mcp/mcp_tool_provider.dart';
import '../infrastructure/providers/provider_config_store.dart';

/// 数据库注入点（可在测试中 override 为内存数据库）。
final databaseProvider = FutureProvider<AppDatabase>((ref) => DatabaseProvider.instance.database);

/// Provider 配置存储注入点（可在测试中 override）。
final providerConfigStoreProvider = Provider<ProviderConfigStore>((ref) => ProviderConfigStore());

/// MCP 连接管理注入点。随 ProviderScope 生命周期持有连接，
/// scope 销毁时统一关闭，避免会话间重复连接。
final mcpToolProvider = Provider<McpToolProvider>((ref) {
  final provider = McpToolProvider();
  ref.onDispose(provider.dispose);
  return provider;
});
