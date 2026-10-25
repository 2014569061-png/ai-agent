import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show CancelToken;
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:workmanager/workmanager.dart';
import 'automatic_backup_service.dart';

// Compatibility for existing backup UI and callers.
export 'automatic_backup_service.dart'
    show
        automaticBackupRetention,
        createAutomaticBackupNow,
        pruneAutomaticBackups,
        publishAutomaticBackup,
        runDueAutomaticBackup;

import 'agent_executor.dart';
import 'background_execution_gateway.dart';
import 'headless_executor.dart';
import 'data_maintenance_service.dart';
import '../domain/models.dart';
import 'scheduled_task_service.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/notifications/notification_service.dart';
import '../infrastructure/providers/provider_config_store.dart';
import '../domain/unique_id.dart';
import 'modules/run_profile.dart';

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
        await runDueAutomaticBackup(db);
      } catch (error, stack) {
        debugPrint('自动备份失败，继续执行到期任务: $error\n$stack');
      }
      await runDueScheduledTasks(db);
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

/// Shared foreground/Android scheduler. Caller owns the database connection.
// Injection keeps scheduler behavior testable without live models or notifications.
typedef ScheduledTaskExecution = Future<HeadlessRunResult> Function(
  ScheduledTask task,
  AgentCancellationToken cancellationToken,
  CancelToken cancelToken,
);
typedef ScheduledTaskNotification = Future<void> Function({
  required int id,
  required String title,
  required String body,
});

/// One attempt per scheduled occurrence, including failures: no implicit replay
/// of potentially completed tools. A new attempt requires the next occurrence.
Future<void> runDueScheduledTasks(
  AppDatabase db, {
  ScheduledTaskExecution? execute,
  ScheduledTaskNotification? notify,
  Duration executionTimeout = const Duration(minutes: 2),
  Duration cancellationGrace = const Duration(seconds: 5),
}) async {
  return const DataMaintenanceService().run(db, () async {
    final due = await ScheduledTaskService().dueTasks(db, DateTime.now());
    if (due.isEmpty) return;
    final config = await ProviderConfigStore().load();
    if (notify == null) await NotificationService.instance.init();
    final usedNotificationIds = <int>{};
    for (final task in due) {
      final startedAt = DateTime.now();
      var runStatus = 'failed';
      HeadlessRunResult? outcome;
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
        final execution = execute != null
            ? const DataMaintenanceService().run(
                db,
                () => Future<HeadlessRunResult>.sync(
                    () => execute(task, cancellationToken, cancelToken)),
                cancel: () {
                cancellationToken.cancel();
                cancelToken.cancel('数据维护');
              })
            : BackgroundExecutionGateway().run(
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
                profile: RunProfile.scheduled,
              );
        String result;
        try {
          outcome = await execution.timeout(executionTimeout);
          runStatus = switch (outcome.status) {
            RunStatus.completed when outcome.error == null => 'success',
            RunStatus.paused || RunStatus.approvalRequired => 'paused',
            RunStatus.cancelled => 'cancelled',
            _ => 'failed',
          };
          final label = switch (runStatus) {
            'success' => '任务完成',
            'paused' => '任务已暂停',
            'cancelled' => '任务已取消',
            _ => '任务执行失败',
          };
          final details = [
            if (outcome.error?.isNotEmpty == true) outcome.error!,
            if (outcome.failureKind != null) '失败类型：${outcome.failureKind}',
            if (outcome.pauseReason != null)
              '暂停原因：${outcome.pauseReason!.name}',
            if (outcome.text.isNotEmpty) outcome.text,
          ].join('；');
          result = runStatus == 'success' && outcome.text.isNotEmpty
              ? outcome.text
              : details.isEmpty
                  ? label
                  : '$label：$details';
        } on TimeoutException {
          cancellationToken.cancel();
          cancelToken.cancel('scheduled task timeout');
          try {
            await execution.timeout(cancellationGrace);
          } catch (_) {
            // Cancellation is cooperative; never hang the entire batch on a tool
            // that ignores it. Late outcomes must not overwrite the timeout audit.
          }
          result = '任务执行超时，已请求中止';
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
          outcome: outcome,
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
        await (notify ?? NotificationService.instance.show)(
          id: notifId,
          title: '定时任务 · ${task.name}',
          body: preview,
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
  });
}

Future<void> _recordScheduledTaskRun(
  AppDatabase db, {
  required ScheduledTask task,
  required String status,
  required String result,
  HeadlessRunResult? outcome,
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
      if (outcome?.runId != null) 'runId': outcome!.runId,
      if (outcome != null) 'executionStatus': outcome.status.name,
      if (outcome?.error != null)
        'error': outcome!.error!.length > 4000
            ? outcome.error!.substring(0, 4000)
            : outcome.error,
      if (outcome?.failureKind != null) 'failureKind': outcome!.failureKind,
      if (outcome?.pauseReason != null)
        'pauseReason': outcome!.pauseReason!.name,
      'retryPolicy': 'next_scheduled_occurrence',
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
