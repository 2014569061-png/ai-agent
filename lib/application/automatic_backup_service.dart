import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data_maintenance_service.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/files/local_crypto_service.dart';
import '../infrastructure/files/vault_exporter_io.dart';

/// Platform-independent due check shared by WorkManager and the live desktop
/// process. A missed interval is coalesced into one snapshot, never replayed.
Future<String?> runDueAutomaticBackup(AppDatabase db,
    {DateTime Function()? clock}) {
  return const DataMaintenanceService().run(db, () async {
    final prefs = await SharedPreferences.getInstance();
    // Another isolate (or the settings page) may have changed the switch/stamp.
    await prefs.reload();
    if (!(prefs.getBool('settings.backup.auto') ?? false)) return null;
    final last =
        DateTime.tryParse(prefs.getString('settings.backup.last_time') ?? '');
    final now = (clock ?? DateTime.now)();
    if (last != null && now.difference(last) < const Duration(hours: 24)) {
      return null;
    }
    return _createAutomaticBackup(db, prefs, clock ?? DateTime.now);
  });
}

Future<String?> createAutomaticBackupNow(AppDatabase db) {
  return const DataMaintenanceService().run(db, () async {
    final prefs = await SharedPreferences.getInstance();
    return _createAutomaticBackup(db, prefs, DateTime.now);
  });
}

Future<String> _createAutomaticBackup(
    AppDatabase db, SharedPreferences prefs, DateTime Function() clock) async {
  final snapshot = await encodeVaultJson(await buildVaultJson(db));
  final encrypted = await LocalCryptoService().encryptString(snapshot);
  final dir = await getApplicationDocumentsDirectory();
  final backupDir = Directory(p.join(dir.path, 'backups'));
  await backupDir.create(recursive: true);
  final path = await publishAutomaticBackup(backupDir, encrypted);
  await pruneAutomaticBackups(backupDir);
  // No frequency stamp is advanced on snapshot/encryption/publication failure.
  await prefs.setString('settings.backup.last_time', clock().toIso8601String());
  return path;
}

const automaticBackupRetention = 8;

Future<void> pruneAutomaticBackups(Directory backupDir,
    {int keep = automaticBackupRetention}) async {
  if (keep < 1 || !await backupDir.exists()) return;
  final files = backupDir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.nexusauto'))
      .toList()
    ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  for (final file in files.skip(keep)) {
    try {
      await file.delete();
    } catch (_) {
      // 备份保留策略是尽力而为：删不掉旧备份只会多占磁盘，下次触发时会再试
      // 一次，不该因此让整个备份流程失败。
    }
  }
}

/// A backup is discoverable only after its complete encrypted payload is flushed.
/// Unique staging names also prevent same-millisecond backup collisions.
Future<String> publishAutomaticBackup(
    Directory directory, String encrypted) async {
  if (utf8.encode(encrypted).length > VaultLimits.maxCipherBytes) {
    throw const FormatException('加密备份超过容量上限');
  }
  await directory.create(recursive: true);
  final staging = await directory.createTemp('.nexus-pending-');
  try {
    final file = File(p.join(staging.path, 'payload'));
    await file.writeAsString(encrypted, flush: true);
    final target = p.join(directory.path,
        'nexus-auto-${DateTime.now().microsecondsSinceEpoch}-${p.basename(staging.path)}.nexusauto');
    await file.rename(target);
    return target;
  } finally {
    await staging.delete(recursive: true);
  }
}
