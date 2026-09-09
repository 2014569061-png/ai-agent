import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:workmanager/workmanager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../application/headless_executor.dart';
import '../../application/scheduled_task_service.dart';
import '../database/app_database.dart';
import '../notifications/notification_service.dart';
import '../providers/provider_config_store.dart';
import '../files/vault_exporter_io.dart';
import '../sync/sync_service.dart';

/// C5 定时任务的后台入口（WorkManager 回调）。
/// 在独立 isolate 中打开数据库、取到点任务、无 UI 运行 Agent、写入结果并弹通知。
@pragma('vm:entry-point')
void scheduledTaskCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (kIsWeb) return true;
    AppDatabase? db;
    try {
      db = await openAppDatabase();
      await _runAutomaticBackup(db);
      final due = await ScheduledTaskService().dueTasks(db, DateTime.now());
      if (due.isEmpty) return true;
      final config = await ProviderConfigStore().load();
      await NotificationService.instance.init();
      final usedNotificationIds = <int>{};
      for (final task in due) {
        String? systemPrompt;
        if (task.agentId != null) {
          systemPrompt = (await db.findAgent(task.agentId!))?.systemPrompt;
        }
        String result;
        try {
          // 单任务超时护栏：避免某个卡死的 Agent 拖垮整批任务，
          // 超出 WorkManager 的 10 分钟预算导致整批被系统 kill。
          result = await HeadlessExecutor.run(
            db: db,
            config: config,
            prompt: task.prompt,
            systemPrompt: systemPrompt,
          ).timeout(const Duration(minutes: 2));
        } on TimeoutException {
          result = '任务执行超时（超过 2 分钟），已中止';
        }
        await db.saveScheduledTask(task.copyWith(
          lastResult: Value<String?>(result),
          updatedAt: DateTime.now(),
        ));
        final preview =
            result.length > 60 ? '${result.substring(0, 60)}…' : result;
        // 同一批内保证通知 id 不碰撞（String.hashCode 理论上有碰撞可能，
        // 碰撞会导致不同任务的通知互相覆盖）。
        var notifId = task.id.hashCode & 0x7fffffff;
        while (usedNotificationIds.contains(notifId)) {
          notifId = (notifId + 1) & 0x7fffffff;
        }
        usedNotificationIds.add(notifId);
        await NotificationService.instance.show(
          id: notifId,
          title: '定时任务 · ${task.name}',
          body: preview.isEmpty ? '任务完成' : preview,
        );
      }
    } catch (error, stack) {
      // 后台执行失败不再静默：记录日志便于排查（下次周期仍会重试）。
      debugPrint('定时任务后台执行失败: $error\n$stack');
    } finally {
      try {
        await db?.close();
      } catch (_) {}
    }
    return true;
  });
}

Future<void> _runAutomaticBackup(AppDatabase db) async {
  final prefs = await SharedPreferences.getInstance();
  if (!(prefs.getBool('settings.backup.auto') ?? false)) return;
  final last = DateTime.tryParse(
    prefs.getString('settings.backup.last_time') ?? '',
  );
  if (last != null && DateTime.now().difference(last).inHours < 24) return;

  final snapshot = jsonEncode(await buildVaultJson(db));
  final encrypted = await SyncService().encryptString(snapshot);
  final dir = await getApplicationDocumentsDirectory();
  final backupDir = Directory(p.join(dir.path, 'backups'));
  await backupDir.create(recursive: true);
  final path = p.join(
    backupDir.path,
    'nexus-auto-${DateTime.now().millisecondsSinceEpoch}.nexusauto',
  );
  await File(path).writeAsString(encrypted, flush: true);
  await prefs.setString(
    'settings.backup.last_time',
    DateTime.now().toIso8601String(),
  );
}
