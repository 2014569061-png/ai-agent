import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../infrastructure/database/app_database.dart';
import '../infrastructure/database/database_provider.dart';
import '../infrastructure/mcp/mcp_tool_provider.dart';
import '../infrastructure/providers/model_route.dart';
import '../infrastructure/providers/provider_config_store.dart';
import '../infrastructure/providers/tool_trust_store.dart';
import 'mcp_service.dart';
import 'nexus_guard.dart';
import 'log_service.dart';
import 'session_log/legacy_import.dart';
import 'session_log/session_event_store.dart';
import 'session_log/session_log_maintenance.dart';
import 'session_log/session_log_settings.dart';

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
///
/// 首次打开后在后台做一次会话日志维护，不阻塞启动：给中断的运行封口；
/// 双写开启时再导入旧会话，并对最近的会话做影子比对（不一致只记日志）。
final databaseProvider = FutureProvider<AppDatabase>((ref) async {
  final db = await DatabaseProvider.instance.database;
  final store = DriftSessionEventStore(db);
  // 不能 ref.read(logServiceProvider)：它 watch 了本 provider，会形成依赖环。
  final logs = LogService(Future.value(db));
  unawaited(SessionLogMaintenance.runOnStartup(
    store,
    extraSteps: [
      if (SessionLogSettings.dualWrite) ...[
        () => LegacySessionImporter(db, store).importPending(),
        () async {
          for (final mismatch
              in await SessionLogShadowCheck.compareRecent(db, store)) {
            await logs.warning('Session log shadow mismatch',
                category: 'session_log', detail: mismatch.toJson());
          }
          return null;
        },
      ],
    ],
    onError: (error, stackTrace) => NexusGuard.silently<void>(
        'sessionLog.startupMaintenance',
        () => Error.throwWithStackTrace(error, stackTrace)),
  ));
  return db;
});

/// Provider 配置存储注入点（可在测试中 override）。
/// 模型路由能力；将来的远端路由（例如桌面端转发）在这里接入。
final modelRouterProvider =
    Provider<ModelRouter>((ref) => ModelRouter.standard);

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
