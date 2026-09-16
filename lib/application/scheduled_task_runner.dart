import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:workmanager/workmanager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'agent_executor.dart';
import 'background_execution_gateway.dart';
import 'scheduled_task_service.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/notifications/notification_service.dart';
import '../infrastructure/providers/provider_config_store.dart';
import '../infrastructure/files/vault_exporter_io.dart';
import '../infrastructure/files/local_crypto_service.dart';

/// C5 定时任务的后台入口（WorkManager 回调）。
/// 在独立 isolate 中打开数据库、取到点任务、无 UI 运行 Agent、写入结果并弹通知。
@pragma('vm:entry-point')
void scheduledTaskCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (kIsWeb) return true;
    AppDatabase? db;
    try {
      db = await openAppDatabase();
      try {
        await _runAutomaticBackup(db);
      } catch (error, stack) {
        debugPrint('自动备份失败，继续执行到期任务: $error\n$stack');
      }
      final due = await ScheduledTaskService().dueTasks(db, DateTime.now());
      if (due.isEmpty) return true;
      final config = await ProviderConfigStore().load();
      await NotificationService.instance.init();
      final usedNotificationIds = <int>{};
      for (final task in due) {
        try {
          final agent = task.agentId == null
              ? null
              : await db.findAgent(task.agentId!);
          final systemPrompt = agent?.systemPrompt;
          Set<String>? allowedToolNames;
          if (agent != null) {
            try {
              final decoded = jsonDecode(agent.enabledToolsJson);
              allowedToolNames = decoded is List
                  ? decoded.whereType<String>().toSet()
                  : <String>{};
            } catch (_) {
              // A corrupt permission record must fail closed in the
              // background instead of silently granting the default tools.
              allowedToolNames = <String>{};
            }
          }
          final cancellationToken = AgentCancellationToken();
          final cancelToken = CancelToken();
          final execution = BackgroundExecutionGateway().run(
            db: db,
            config: config,
            prompt: task.prompt,
            systemPrompt: systemPrompt,
            allowedToolNames: allowedToolNames,
            maxSteps: agent?.maxSteps ?? 4,
            temperature: agent?.temperature ?? 0.7,
            maxTokens: agent?.maxTokens ?? 1024,
            topP: agent?.topP ?? 1.0,
            cancellationToken: cancellationToken,
            cancelToken: cancelToken,
          ).then((result) => result.text);
          String result;
          try {
            result = await execution.timeout(const Duration(minutes: 2));
          } on TimeoutException {
            cancellationToken.cancel();
            cancelToken.cancel('scheduled task timeout');
            try {
              await execution;
            } catch (_) {}
            result = '任务执行超时（超过 2 分钟），已中止';
          } catch (error, stack) {
            debugPrint('定时任务 ${task.id} 执行失败: $error\n$stack');
            result = '任务执行失败：$error';
          }
          final completedAt = DateTime.now();
          await db.saveScheduledTask(task.copyWith(
            lastResult: Value<String?>(result),
            lastRunAt: Value<DateTime?>(completedAt),
            updatedAt: completedAt,
          ));
          final preview =
              result.length > 60 ? '${result.substring(0, 60)}…' : result;
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
        } catch (error, stack) {
          debugPrint('定时任务 ${task.id} 收尾失败: $error\n$stack');
        }
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
  final encrypted = await LocalCryptoService().encryptString(snapshot);
  final dir = await getApplicationDocumentsDirectory();
  final backupDir = Directory(p.join(dir.path, 'backups'));
  await backupDir.create(recursive: true);
  final path = p.join(
    backupDir.path,
    'nexus-auto-${DateTime.now().millisecondsSinceEpoch}.nexusauto',
  );
  await File(path).writeAsString(encrypted, flush: true);
  await pruneAutomaticBackups(backupDir);
  await prefs.setString(
    'settings.backup.last_time',
    DateTime.now().toIso8601String(),
  );
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
    } catch (_) {}
  }
}

Future<String?> createAutomaticBackupNow(AppDatabase db) async {
  final snapshot = jsonEncode(await buildVaultJson(db));
  final encrypted = await LocalCryptoService().encryptString(snapshot);
  final dir = await getApplicationDocumentsDirectory();
  final backupDir = Directory(p.join(dir.path, 'backups'));
  await backupDir.create(recursive: true);
  final path = p.join(
    backupDir.path,
    'nexus-auto-${DateTime.now().millisecondsSinceEpoch}.nexusauto',
  );
  await File(path).writeAsString(encrypted, flush: true);
  await pruneAutomaticBackups(backupDir);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    'settings.backup.last_time',
    DateTime.now().toIso8601String(),
  );
  return path;
}
