import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/database/runtime_maintenance_store.dart';
import '../infrastructure/mcp/mcp_legacy_migration.dart';
import '../infrastructure/files/vault_exporter.dart';
import '../infrastructure/providers/provider_config_store.dart';
import 'chat_controller.dart';
import 'data_maintenance_service.dart';
import 'providers.dart';
import 'reminder_service.dart';
import '../domain/reminder.dart';
import '../infrastructure/notifications/notification_service.dart';
export '../domain/runtime_data_scope.dart' show RuntimeDataRevoked;
export 'data_maintenance_service.dart' show DataMaintenanceRefreshFailure;

/// All user-facing destructive data operations enter through this application
/// boundary. Vault's existing SQLite/file/secret compensation stays unchanged.
class DataMaintenanceActions {
  DataMaintenanceActions({
    required this.database,
    required this.refresh,
    ProviderConfigStore? providerStore,
    this.maintenance = const DataMaintenanceService(),
  }) : providerStore = providerStore ?? ProviderConfigStore();

  final Future<AppDatabase> Function() database;
  final Future<void> Function() refresh;
  final ProviderConfigStore providerStore;
  final DataMaintenanceService maintenance;

  Future<T> _perform<T>(Future<T> Function(AppDatabase) action) async {
    final db = await database();
    return maintenance.maintain(db, () => action(db), refresh: refresh);
  }

  Future<RuntimeRecoveryStatus> recoveryStatus() async =>
      RuntimeMaintenanceStore(await database()).inspectRecovery();

  Future<void> recoverInterrupted() async =>
      maintenance.recoverInterrupted(await database(), refresh: refresh);

  Future<VaultRestoreReport> restore(Map<String, dynamic> json) =>
      _perform((db) async {
        final report =
            await restoreVault(db, json, providerStore: providerStore);
        await _reconcileReminders(db);
        return report;
      });

  Future<String> importEncrypted(Uint8List bytes, String password) =>
      _perform((db) async {
        final result = await importVaultBytes(db, bytes, password,
            providerStore: providerStore);
        await _reconcileReminders(db);
        return result;
      });

  Future<void> _reconcileReminders(AppDatabase db) async {
    final reminders = await ReminderService(db, delivery: null).list();
    await NotificationService.instance.reconcileReminderNotifications({
      for (final r in reminders)
        if (r.status == ReminderStatus.scheduled ||
            r.status == ReminderStatus.snoozed)
          'reminder:${r.id}@${r.version}',
    });
  }

  Future<void> clear() => _perform((db) async {
        await db.transaction(() async {
          await db.clearAllUserData();
          await db.clearMcpServers();
          await McpLegacyMigration.markComplete(db);
        });
        await providerStore.clearAll();
        await NotificationService.instance.reconcileReminderNotifications({});
        final prefs = await SharedPreferences.getInstance();
        await Future.wait([
          prefs.remove('settings.backup.auto'),
          prefs.remove('settings.backup.last_time'),
          // Prevent the legacy MCP migration from recreating deleted servers.
          prefs.remove('mcp.servers'),
        ]);
      });
}

final dataMaintenanceActionsProvider = Provider<DataMaintenanceActions>((ref) {
  return DataMaintenanceActions(
    database: () => ref.read(databaseProvider.future),
    providerStore: ref.read(providerConfigStoreProvider),
    refresh: () async {
      await ref.read(mcpToolProvider).dispose();
      ref.invalidate(mcpToolProvider);
      ref.invalidate(mcpServiceProvider);
      ref.invalidate(providerConfigStoreProvider);
      ref.invalidate(toolTrustStoreProvider);
      await ref
          .read(chatControllerProvider.notifier)
          .reloadAfterDataMaintenance();
    },
  );
});
