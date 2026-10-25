import 'verification_execution_guard.dart';
import '../infrastructure/database/run_plan_store.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/tools/command_tool.dart';
import '../infrastructure/tools/workspace_tools.dart';
import 'change_review.dart';
import 'development_verification.dart';
import 'project_kind.dart';
import 'run_audit_report.dart';
import 'task_service.dart';
import 'task_summary.dart';
import 'task_template_service.dart';
import 'workspace_snapshot.dart';
import 'verification_repair_service.dart';

class DevelopmentLoopFinalizeResult {
  const DevelopmentLoopFinalizeResult({
    required this.review,
    required this.verified,
    this.verification,
    this.verificationSkipReason,
  });

  final ChangeReview review;
  final bool verified;
  final DevelopmentVerificationResult? verification;

  /// 有文件变更但没有执行验证时，说明原因（未授权、未选择工作区、任务类型
  /// 不要求，或验证本身抛错）。为 null 表示本次没有需要说明的跳过。
  final String? verificationSkipReason;
}

/// After an Agent run, persist this-task diffs and optional verification.
class DevelopmentLoopFinalizer {
  DevelopmentLoopFinalizer({
    TaskService? taskService,
    ChangeReviewService? reviews,
    WorkspaceSnapshotService? snapshots,
    DevelopmentVerificationService? verification,
  })  : _taskService = taskService ?? TaskService(),
        _reviews = reviews ?? const ChangeReviewService(),
        _snapshots = snapshots ?? const WorkspaceSnapshotService(),
        _verification = verification ?? DevelopmentVerificationService();

  final TaskService _taskService;
  final ChangeReviewService _reviews;
  final WorkspaceSnapshotService _snapshots;
  final DevelopmentVerificationService _verification;

  static const mutatingOperations = {
    'create',
    'write',
    'edit',
    'delete',
    'move',
    'write_file',
    'edit_file',
    'apply_patch',
    'delete_file',
    'move_file',
  };

  Future<DevelopmentLoopFinalizeResult> finalize({
    required AppDatabase db,
    required String taskId,
    required String runId,
    int? planVersion,
    VerificationExecutionGuard? executionGuard,
    required String workspacePath,
    TerminalCommandService? terminal,
    bool runVerification = false,
    bool deferRepair = false,
    bool Function()? canContinue,
    Future<bool> Function(VerificationRepairRequest request)? repair,
  }) async {
    DevelopmentLoopFinalizeResult stale() =>
        const DevelopmentLoopFinalizeResult(
            review: ChangeReview(
                files: [], mark: ChangeVerificationMark.unverified),
            verified: false,
            verificationSkipReason: '运行或计划已变化，旧收尾未推进当前任务');
    final head = await RunPlanStore(db).head(taskId);
    final version = planVersion ??
        (head?.token.runId == runId ? head?.token.version : null);
    if (head != null &&
        head.state != 'queued' &&
        (head.token.runId != runId ||
            head.pendingControls ||
            (version != null && head.token.version != version) ||
            const {'interrupted', 'cancelled'}.contains(head.state))) {
      return stale();
    }
    final task = await db.findTask(taskId);
    if (task == null) return stale();
    final info = _taskService.describe(task);
    final progress = await _taskService.progress(db, taskId);
    final snapshot = progress['workspaceSnapshot'] is Map
        ? WorkspaceSnapshot.fromJson(
            Map<String, dynamic>.from(progress['workspaceSnapshot'] as Map))
        : WorkspaceSnapshot(capturedAt: DateTime.now(), files: const {});

    final events = await db.eventsForRun(runId, limit: 400);
    final audit = RunAuditReport.fromEvents(events);
    final metadata = [
      for (final entry in audit.entries)
        if (entry.effect == 'applied' ||
            entry.metadata['fileOperation'] == true)
          {
            ...entry.metadata,
            if (entry.path != null) 'path': entry.path,
            'operation': entry.operation,
          },
    ];
    var review = await _snapshots.reviewFromAudit(
      workspacePath: workspacePath,
      snapshot: snapshot,
      auditMetadata: metadata,
    );
    final recoveryEvent = metadata.reversed
        .where((entry) =>
            entry['transactionStatus'] == 'needs_recovery' ||
            entry['transactionStatus'] == 'recovered')
        .firstOrNull;
    final needsPatchRecovery =
        recoveryEvent?['transactionStatus'] == 'needs_recovery' ||
            await WorkspaceSandbox(workspacePath).patchJournal.hasPending();
    if (needsPatchRecovery ||
        (review.files.isEmpty && snapshot.files.isNotEmpty)) {
      review = await _snapshots.reviewFromSnapshot(
        workspacePath: workspacePath,
        snapshot: snapshot,
      );
    }

    DevelopmentVerificationResult? verification;
    final template = TaskTemplateService().findByType(info.type);
    final implementsChanges = template?.implementsChanges == true ||
        info.type.contains('implement') ||
        info.type.contains('bug_fix') ||
        info.type.contains('release_check');
    final shouldVerify = runVerification &&
        !needsPatchRecovery &&
        terminal != null &&
        workspacePath.trim().isNotEmpty &&
        implementsChanges &&
        review.files.isNotEmpty;
    // 跳过自动验证时必须留下原因。这一层是「人在环路」的收口：terminal 只在
    // 调用方已经拿到用户授权后才非空，所以此处不是绕过审批，而是把「因为没
    // 授权所以没验证」如实记进任务摘要，避免后续把它读成「已验证」。
    String? verificationSkipReason;
    // Reserve an attempt before invoking the model. Repeated finalization after
    // a crash must not grant the same run another repair budget.
    final repairAttempts = <Map<String, dynamic>>[
      if (progress['verificationRepairRunId'] == runId &&
          progress['verificationRepairAttempts'] is List)
        for (final entry in progress['verificationRepairAttempts'] as List)
          if (entry is Map) Map<String, dynamic>.from(entry),
    ];
    if (!shouldVerify && review.files.isNotEmpty) {
      verificationSkipReason = needsPatchRecovery
          ? '跨文件补丁回滚存在冲突，需先读取确认并恢复，暂停自动验证和修复'
          : !runVerification
              ? '本轮收尾未请求自动验证'
              : terminal == null
                  ? '自动验证需要终端授权，本轮未获得授权'
                  : workspacePath.trim().isEmpty
                      ? '未选择工作区，无法执行验证'
                      : '任务类型不产出需要验证的代码变更';
    }
    if (shouldVerify) {
      try {
        final plan =
            await _verification.planFor(workspacePath, includeBuild: false);
        verification = await _verification.run(
          service: terminal,
          executionGuard: executionGuard,
          workspacePath: workspacePath,
          plan: plan,
          canContinue: canContinue,
        );
        if (deferRepair) {
          for (final previous in repairAttempts) {
            if (previous['status'] == 'deferred') {
              previous['status'] =
                  verification.success ? 'completed' : 'failed';
            }
          }
        }
        const repairs = VerificationRepairService();
        for (var attempt = repairAttempts.length + 1;
            repair != null && !verification!.success;
            attempt++) {
          if (canContinue != null && !canContinue()) break;
          final request = repairs.fromFailedPlan(
            plan: verification.plan,
            workspacePath: workspacePath,
            summary: TaskSummary(
                version: 1,
                goal: info.prompt,
                modifiedFiles: review.files.map((file) => file.path).toList(),
                acceptance: template?.acceptanceRules ?? const []),
            diff: review.files.map((file) => file.diff).join('\n'),
            attempt: attempt,
          );
          if (request == null || !repairs.canAutoRetry(request)) break;
          final record = <String, dynamic>{
            'attempt': attempt,
            'reason': request.reason,
            'command': request.command,
            'status': 'running'
          };
          repairAttempts.add(record);
          await _taskService.updateProgress(db, taskId,
              runId: runId,
              planVersion: version,
              phase: 'repairing',
              extra: {
                'verificationRepairAttempts': repairAttempts,
                'verificationRepairRunId': runId
              });
          // The previous checks predate the next edit and cannot validate it.
          if (!deferRepair) verification = null;
          var repaired = false;
          try {
            repaired = await repair(request);
            record['status'] = repaired
                ? 'completed'
                : deferRepair
                    ? 'deferred'
                    : 'failed';
          } catch (_) {
            record['status'] = 'failed';
          } finally {
            review = await _snapshots.reviewFromSnapshot(
                workspacePath: workspacePath, snapshot: snapshot);
          }
          if (!repaired || (canContinue != null && !canContinue())) {
            verificationSkipReason =
                deferRepair ? '修复将由原执行循环继续，尚未重新验证' : '修复未完成或已停止，修改后的文件尚未重新验证';
            break;
          }
          // Rerun every original check, including previously passing ones.
          verification = await _verification.run(
              service: terminal,
              executionGuard: executionGuard,
              workspacePath: workspacePath,
              plan: plan,
              canContinue: canContinue);
        }
        if (verification != null) {
          review = _reviews.withVerification(review, verification);
          if (!verification.success &&
              !verification.plan.steps.any(
                  (step) => step.status == VerificationStepStatus.failed)) {
            verificationSkipReason = '没有实际通过的必需检查，不能判定验证通过';
          }
        }
      } catch (error) {
        verificationSkipReason = '验证执行失败：$error';
        review = ChangeReview(
          files: review.files,
          mark: ChangeVerificationMark.unverified,
          linesAdded: review.linesAdded,
          linesRemoved: review.linesRemoved,
        );
      }
    }

    final previousSummary = progress['taskSummary'] is Map
        ? TaskSummary.fromJson(
            Map<String, dynamic>.from(progress['taskSummary'] as Map))
        : null;
    final passed = [
      for (final step in verification?.plan.steps ?? const <VerificationStep>[])
        if (step.status == VerificationStepStatus.passed) step.title,
    ];
    final failed = [
      for (final step in verification?.plan.steps ?? const <VerificationStep>[])
        if (step.status == VerificationStepStatus.failed)
          '${step.title}${step.error == null ? '' : '：${step.error}'}',
    ];
    final summary = TaskSummary(
      version: (previousSummary?.version ?? 0) + 1,
      goal: previousSummary?.goal.isNotEmpty == true
          ? previousSummary!.goal
          : info.title,
      acceptance: previousSummary?.acceptance.isNotEmpty == true
          ? previousSummary!.acceptance
          : (TaskTemplateService().findByType(info.type)?.acceptanceRules ??
              const []),
      modifiedFiles: [
        for (final file in review.files) file.path,
      ],
      passedChecks: passed,
      openIssues: [
        ...failed,
        if (needsPatchRecovery) '跨文件补丁需要恢复；请检查审计记录中的冲突文件及备份，不能视为完成。',
        if (verificationSkipReason != null) '未验证：$verificationSkipReason',
      ],
      evidence: [
        if (verification?.artifact?.relativePath != null)
          verification!.artifact!.relativePath,
        if (verification?.artifact?.sha256 != null)
          'sha256=${verification!.artifact!.sha256}',
      ],
      runId: runId,
      eventSequence: events.length,
      fileVersions: {
        for (final file in review.files) file.path: file.operation,
      },
      staleChecks: previousSummary?.staleChecks ?? const [],
    );
    await _taskService.updateProgress(
      db,
      taskId,
      runId: runId,
      planVersion: version,
      phase: (progress['phase'] ?? info.status ?? 'review').toString(),
      extra: {
        'verificationRepairAttempts': repairAttempts,
        'verificationRepairRunId': runId,
        'changeReview': review.toJson(),
        'verificationPlan': verification?.plan.toJson(),
        'executedSteps': [
          for (final step
              in verification?.plan.steps ?? const <VerificationStep>[])
            if (step.status == VerificationStepStatus.passed ||
                step.status == VerificationStepStatus.failed)
              step.id,
        ],
        'taskSummary': summary.toJson(),
        'workspaceAccessible': true,
        if (info.projectKind != null) 'projectKind': info.projectKind!.id,
      },
    );
    final after = await RunPlanStore(db).head(taskId);
    if (after != null &&
        after.state != 'queued' &&
        (after.token.runId != runId ||
            after.pendingControls ||
            (version != null && after.token.version != version) ||
            const {'interrupted', 'cancelled'}.contains(after.state))) {
      return stale();
    }
    return DevelopmentLoopFinalizeResult(
      review: review,
      verified: verification?.success ?? false,
      verification: verification,
      verificationSkipReason: verificationSkipReason,
    );
  }
}
