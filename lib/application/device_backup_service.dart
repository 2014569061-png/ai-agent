import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../infrastructure/tools/android_backup_actions.dart';

/// 备份列表与内容检查的只读入口（写操作一律经 [DeviceActionRunner] 预览确认）。
class DeviceBackupCatalog {
  const DeviceBackupCatalog(
      {AndroidBackupBridge bridge = const AndroidBackupBridge()})
      : _bridge = bridge;

  final AndroidBackupBridge _bridge;

  Future<Map<String, dynamic>> listBackups() => _bridge.listBackups();

  Future<Map<String, dynamic>> inspectBackup(String backupId) =>
      _bridge.inspectBackup(backupId);
}

final deviceBackupCatalogProvider =
    Provider<DeviceBackupCatalog>((ref) => const DeviceBackupCatalog());
