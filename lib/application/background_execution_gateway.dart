import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;

import '../domain/models.dart';
import '../infrastructure/background/foreground_service.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/providers/provider_config.dart';
import 'agent_executor.dart';
import 'execution_lease_service.dart';
import 'headless_executor.dart';
import 'project_service.dart';
import 'task_service.dart';

/// 恢复、定时任务和工作台验证共用的执行入口。
///
/// 所有无 UI 运行都经过同一租约与审批边界，避免 ChatController、
/// HeadlessExecutor 和 ScheduledTaskRunner 各自再起一套执行器。
class BackgroundExecutionGateway {
  BackgroundExecutionGateway({
    TaskService? tasks,
    ExecutionLeaseService? leases,
  })  : _tasks = tasks ?? TaskService(),
        _leases = leases ?? const ExecutionLeaseService();

  final TaskService _tasks;
  final ExecutionLeaseService _leases;

  Future<HeadlessRunResult> run({
    required AppDatabase db,
    required ProviderConfig config,
    required String prompt,
    String? taskId,
    String? systemPrompt,
    String? taskType,
    String? workspacePath,
    Iterable<String>? allowedToolNames,
    int maxSteps = 4,
    double temperature = 0.7,
    int maxTokens = 1024,
    double topP = 1.0,
    List<ChatMessage>? initialHistory,
    AgentCancellationToken? cancellationToken,
    CancelToken? cancelToken,
    ToolApprovalCallback? approveTool,
    ApprovalMode approvalMode = ApprovalMode.ask,
    bool keepAlive = false,
    Future<HeadlessRunResult> Function()? execute,
  }) async {
    ExecutionLease? lease;
    Timer? leaseHeartbeat;
    var foregroundStarted = false;
    if (taskId != null &&
        workspacePath != null &&
        workspacePath.trim().isNotEmpty) {
      lease = await _leases.acquire(
        db: db,
        resourceKey: ExecutionLeaseService.workspaceKey(
            ProjectService.canonicalizePath(workspacePath)),
        taskId: taskId,
        runId: taskId,
      );
      // Agent/tool runs can easily outlive the two-minute lease TTL. Refresh
      // it while the gateway owns the run so another task cannot write the
      // same workspace before this run finishes.
      leaseHeartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
        final current = lease;
        if (current == null) return;
        unawaited(_refreshLease(db, current));
      });
    }
    try {
      if (keepAlive) {
        try {
          foregroundStarted = await ForegroundService.instance
              .start(text: '开发任务恢复执行中')
              .timeout(const Duration(seconds: 2));
        } catch (_) {}
      }
      if (taskId != null) {
        await _tasks.updateStatus(db, taskId, 'running');
      }
      final runner = execute ??
          () => HeadlessExecutor.runDetailed(
                db: db,
                config: config,
                prompt: prompt,
                systemPrompt: systemPrompt,
                taskType: taskType,
                workspacePath: workspacePath,
                allowedToolNames: allowedToolNames,
                maxSteps: maxSteps,
                temperature: temperature,
                maxTokens: maxTokens,
                topP: topP,
                initialHistory: initialHistory,
                cancellationToken: cancellationToken,
                cancelToken: cancelToken,
                approveTool: approveTool,
                approvalMode: approvalMode,
              );
      return await runner();
    } finally {
      leaseHeartbeat?.cancel();
      if (lease != null) {
        await _leases.release(
          db: db,
          resourceKey: lease.resourceKey,
          ownerToken: lease.ownerToken,
        );
      }
      if (foregroundStarted) {
        await ForegroundService.instance.stop();
      }
    }
  }

  Future<void> _refreshLease(AppDatabase db, ExecutionLease lease) async {
    try {
      await _leases.heartbeat(db: db, lease: lease);
    } catch (_) {
      // A database shutdown or process restart is handled by the normal run
      // recovery path; a failed best-effort heartbeat must not become an
      // unhandled asynchronous error.
    }
  }
}
