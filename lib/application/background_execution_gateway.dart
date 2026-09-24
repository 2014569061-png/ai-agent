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
    this.heartbeatInterval = const Duration(seconds: 30),
    this.heartbeatFailureLimit = 3,
  })  : _tasks = tasks ?? TaskService(),
        _leases = leases ?? const ExecutionLeaseService();

  final TaskService _tasks;
  final ExecutionLeaseService _leases;

  /// 租约 TTL 是 2 分钟。默认 30 秒跳一次，连续失败 3 次就停，
  /// 避免数据库抖动后租约过期、另一个任务开始写同一工作区。
  final Duration heartbeatInterval;
  final int heartbeatFailureLimit;

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
    var leaseClosed = false;
    var consecutiveHeartbeatFailures = 0;
    final activeCancellation = cancellationToken ?? AgentCancellationToken();
    final activeCancelToken = cancelToken ?? CancelToken();
    void abandonLease(String reason) {
      if (leaseClosed) return;
      activeCancellation.cancel();
      if (!activeCancelToken.isCancelled) {
        activeCancelToken.cancel(reason);
      }
    }

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
      leaseHeartbeat = Timer.periodic(heartbeatInterval, (_) {
        final current = lease;
        if (current == null || leaseClosed) return;
        unawaited(_refreshLease(
          db,
          current,
          onLost: () => abandonLease('工作区租约已失效，已停止当前任务'),
          onFailure: () {
            if (leaseClosed) return;
            consecutiveHeartbeatFailures++;
            if (consecutiveHeartbeatFailures >= heartbeatFailureLimit) {
              abandonLease('工作区租约心跳连续失败，已停止当前任务');
            }
          },
          onSuccess: () => consecutiveHeartbeatFailures = 0,
        ));
      });
    }
    try {
      if (keepAlive) {
        try {
          foregroundStarted =
              await ForegroundService.instance.start(text: '开发任务恢复执行中');
        } catch (_) {
          // 前台服务只是防止长任务被系统回收；启动失败后仍继续执行，真正的任务
          // 结果由 task/run 状态记录，保活能力失败不能反过来中断任务本身。
        }
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
                cancellationToken: activeCancellation,
                cancelToken: activeCancelToken,
                approveTool: approveTool,
                approvalMode: approvalMode,
              );
      return await runner();
    } finally {
      leaseClosed = true;
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

  Future<void> _refreshLease(
    AppDatabase db,
    ExecutionLease lease, {
    required void Function() onLost,
    required void Function() onFailure,
    required void Function() onSuccess,
  }) async {
    try {
      final kept = await _leases.heartbeat(db: db, lease: lease);
      if (!kept) {
        onLost();
        return;
      }
      onSuccess();
    } catch (_) {
      // 单次失败不能变成未处理异常，但连续失败必须停掉当前 run。
      // 否则 2 分钟租约过期后，另一个任务会在本任务还写文件时拿到租约。
      onFailure();
    }
  }
}
