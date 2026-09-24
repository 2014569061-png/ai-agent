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
import '../domain/unique_id.dart';

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
        final startedAt = DateTime.now();
        var runStatus = 'success';
        var runResult = '';
        var runRecorded = false;
        try {
          final agent =
              task.agentId == null ? null : await db.findAgent(task.agentId!);
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
          final execution = BackgroundExecutionGateway()
              .run(
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
              )
              .then((result) => result.text);
          String result;
          try {
            result = await execution.timeout(const Duration(minutes: 2));
          } on TimeoutException {
            cancellationToken.cancel();
            cancelToken.cancel('scheduled task timeout');
            try {
              await execution;
            } catch (_) {
              // 超时后已经取消、并且结果已经定下，这里再 await 一次只是等它退出；
              // 退出时抛错不影响上面的结论，也没有补救动作。
            }
            result = '任务执行超时（超过 2 分钟），已中止';
            runStatus = 'timeout';
          } catch (error, stack) {
            debugPrint('定时任务 ${task.id} 执行失败: $error\n$stack');
            result = '任务执行失败：$error';
            runStatus = 'failed';
          }
          final completedAt = DateTime.now();
          runResult = result;
          await db.saveScheduledTask(task.copyWith(
            lastResult: Value<String?>(result),
            lastRunAt: Value<DateTime?>(completedAt),
            updatedAt: completedAt,
          ));
          await _recordScheduledTaskRun(
            db,
            task: task,
            status: runStatus,
            result: runResult,
            startedAt: startedAt,
            completedAt: completedAt,
          );
          runRecorded = true;
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
          if (!runRecorded) {
            runStatus = 'failed';
            runResult = '任务执行失败：$error';
            final completedAt = DateTime.now();
            try {
              await db.saveScheduledTask(task.copyWith(
                lastResult: Value<String?>(runResult),
                lastRunAt: Value<DateTime?>(completedAt),
                updatedAt: completedAt,
              ));
              await _recordScheduledTaskRun(
                db,
                task: task,
                status: runStatus,
                result: runResult,
                startedAt: startedAt,
                completedAt: completedAt,
              );
            } catch (recordError, recordStack) {
              debugPrint(
                '定时任务 ${task.id} 失败记录写入失败: '
                '$recordError\n$recordStack',
              );
            }
          }
        }
      }
    } catch (error, stack) {
      // 后台执行失败不再静默：记录日志便于排查（下次周期仍会重试）。
      debugPrint('定时任务后台执行失败: $error\n$stack');
    } finally {
      try {
        await db?.close();
      } catch (_) {
        // 收尾时关闭临时数据库：失败最多留下一个已打开的连接，随即被进程回收，
        // 没有可采取的动作，也不该影响本次执行已经写入的结果。
      }
    }
    return true;
  });
}

Future<void> _recordScheduledTaskRun(
  AppDatabase db, {
  required ScheduledTask task,
  required String status,
  required String result,
  required DateTime startedAt,
  required DateTime completedAt,
}) async {
  await db.insertAuditLog(AuditLogsCompanion.insert(
    id: UniqueId.generate('scheduled_run', now: completedAt),
    type: 'scheduled_task_run',
    detail: jsonEncode({
      'taskId': task.id,
      'taskName': task.name,
      'status': status,
      'startedAt': startedAt.toIso8601String(),
      'completedAt': completedAt.toIso8601String(),
      'durationMs': completedAt.difference(startedAt).inMilliseconds,
      // Execution results remain local and bounded so history is useful
      // without letting an agent response grow the audit database without limit.
      'result': result.length > 4000 ? result.substring(0, 4000) : result,
      'truncated': result.length > 4000,
    }),
    decision: Value(status),
    risk: const Value('background'),
    createdAt: completedAt,
  ));
}

Future<void> _runAutomaticBackup(AppDatabase db) async {
  final prefs = await SharedPreferences.getInstance();
  if (!(prefs.getBool('settings.backup.auto') ?? false)) return;
  final last = DateTime.tryParse(
    prefs.getString('settings.backup.last_time') ?? '',
  );
  if (last != null && DateTime.now().difference(last).inHours < 24) return;

  final snapshot = await encodeVaultJson(await buildVaultJson(db));
  final encrypted = await LocalCryptoService().encryptString(snapshot);
  final dir = await getApplicationDocumentsDirectory();
  final backupDir = Directory(p.join(dir.path, 'backups'));
  await backupDir.create(recursive: true);
  await publishAutomaticBackup(backupDir, encrypted);
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
    } catch (_) {
      // 备份保留策略是尽力而为：删不掉旧备份只会多占磁盘，下次触发时会再试
      // 一次，不该因此让整个备份流程失败。
    }
  }
}

Future<String?> createAutomaticBackupNow(AppDatabase db) async {
  final snapshot = await encodeVaultJson(await buildVaultJson(db));
  final encrypted = await LocalCryptoService().encryptString(snapshot);
  final dir = await getApplicationDocumentsDirectory();
  final backupDir = Directory(p.join(dir.path, 'backups'));
  await backupDir.create(recursive: true);
  final path = await publishAutomaticBackup(backupDir, encrypted);
  await pruneAutomaticBackups(backupDir);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    'settings.backup.last_time',
    DateTime.now().toIso8601String(),
  );
  return path;
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
