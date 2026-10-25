import 'agent_loop/agent_loop_hooks.dart';
import '../domain/unique_id.dart';
import '../infrastructure/providers/model_route.dart';
import 'modules/module_host.dart';
import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;

import '../domain/models.dart';
import '../infrastructure/background/foreground_service.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/providers/provider_config.dart';
import 'agent_executor.dart';
import 'data_maintenance_service.dart';
import 'execution_lease_service.dart';
import 'headless_executor.dart';
import 'modules/run_profile.dart';
import 'task_service.dart';
import 'run_recovery_safety.dart';

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
    String? runId,
    ModelRouter? modelRouter,
    ModuleHost? modules,
    Future<TurnContinuation?> Function(TurnStoppingContext)? beforeFinish,
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
    RunProfile profile = RunProfile.background,
    Future<HeadlessRunResult> Function()? execute,
    WorkspaceLeaseGuard? leaseGuard,
    int? totalTokenBudget,
  }) async {
    if (runId != null && (runId.trim().isEmpty || runId.length > 256)) {
      throw ArgumentError('Invalid run identity');
    }
    final executionRunId = runId ?? UniqueId.generate('run');
    final activeCancellation = cancellationToken ?? AgentCancellationToken();
    final activeCancelToken = cancelToken ?? CancelToken();
    return const DataMaintenanceService().run(db, () async {
      // Before lease acquisition, status changes, custom runners or model calls.
      if (taskId != null) {
        await const RunRecoverySafety().requireSafe(db, taskId,
            initialHistory: initialHistory);
      }
      var foregroundStarted = false;
      unawaited(activeCancellation.whenCancelled.then((_) {
        activeCancelToken.cancel('任务已取消');
      }));
      final borrowed = leaseGuard != null;
      if (taskId != null &&
          workspacePath != null &&
          workspacePath.trim().isNotEmpty) {
        if (borrowed) {
          await leaseGuard!.validate(
              database: db, workspacePath: workspacePath, taskId: taskId);
        } else {
          leaseGuard = await WorkspaceLeaseGuard.open(
              db: db,
              workspacePath: workspacePath,
              taskId: taskId,
              runId: executionRunId,
              service: _leases,
              interval: heartbeatInterval,
              failureLimit: heartbeatFailureLimit,
              onLost: () {
                activeCancellation.cancel();
                activeCancelToken.cancel('工作区租约失效，已停止任务');
              });
        }
      } else if (borrowed) {
        throw const ExecutionLeaseConflict('借用租约需要任务和工作区');
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
                  totalTokenBudget: totalTokenBudget,
                  topP: topP,
                  initialHistory: initialHistory,
                  cancellationToken: activeCancellation,
                  cancelToken: activeCancelToken,
                  approveTool: approveTool,
                  approvalMode: approvalMode,
                  taskId: taskId,
                  runId: executionRunId,
                  modelRouter: modelRouter,
                  modules: modules,
                  beforeFinish: beforeFinish,
                  profile: profile,
                );
        return await runner();
      } finally {
        try {
          if (!borrowed) await leaseGuard?.close();
        } finally {
          if (foregroundStarted) {
            await ForegroundService.instance.stop();
          }
        }
      }
    }, cancel: () {
      activeCancellation.cancel();
      activeCancelToken.cancel('数据维护');
    });
  }
}
