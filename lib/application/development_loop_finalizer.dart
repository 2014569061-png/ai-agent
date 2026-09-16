import '../infrastructure/database/app_database.dart';
import '../infrastructure/tools/command_tool.dart';
import 'change_review.dart';
import 'development_verification.dart';
import 'project_kind.dart';
import 'run_audit_report.dart';
import 'task_service.dart';
import 'task_summary.dart';
import 'task_template_service.dart';
import 'workspace_snapshot.dart';

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
    'delete_file',
    'move_file',
  };

  Future<DevelopmentLoopFinalizeResult> finalize({
    required AppDatabase db,
    required String taskId,
    required String runId,
    required String workspacePath,
    TerminalCommandService? terminal,
    bool runVerification = false,
  }) async {
    final task = await db.findTask(taskId);
    final info = task == null ? null : _taskService.describe(task);
    final progress = await _taskService.progress(db, taskId);
    final snapshot = progress['workspaceSnapshot'] is Map
        ? WorkspaceSnapshot.fromJson(
            Map<String, dynamic>.from(progress['workspaceSnapshot'] as Map))
        : WorkspaceSnapshot(capturedAt: DateTime.now(), files: const {});

    final events = await db.eventsForRun(runId, limit: 400);
    final audit = RunAuditReport.fromEvents(events);
    final metadata = [
      for (final entry in audit.entries)
        if (entry.effect == 'applied' || entry.metadata['fileOperation'] == true)
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
    if (review.files.isEmpty && snapshot.files.isNotEmpty) {
      review = await _snapshots.reviewFromSnapshot(
        workspacePath: workspacePath,
        snapshot: snapshot,
      );
    }

    DevelopmentVerificationResult? verification;
    final template = TaskTemplateService().findByType(info?.type);
    final implementsChanges = template?.implementsChanges == true ||
        (info?.type.contains('implement') ?? false) ||
        (info?.type.contains('bug_fix') ?? false) ||
        (info?.type.contains('release_check') ?? false);
    final shouldVerify = runVerification &&
        terminal != null &&
        workspacePath.trim().isNotEmpty &&
        implementsChanges &&
        review.files.isNotEmpty;
    // 跳过自动验证时必须留下原因。这一层是「人在环路」的收口：terminal 只在
    // 调用方已经拿到用户授权后才非空，所以此处不是绕过审批，而是把「因为没
    // 授权所以没验证」如实记进任务摘要，避免后续把它读成「已验证」。
    String? verificationSkipReason;
    if (!shouldVerify && review.files.isNotEmpty) {
      verificationSkipReason = !runVerification
          ? '本轮收尾未请求自动验证'
          : terminal == null
              ? '自动验证需要终端授权，本轮未获得授权'
              : workspacePath.trim().isEmpty
                  ? '未选择工作区，无法执行验证'
                  : '任务类型不产出需要验证的代码变更';
    }
    if (shouldVerify) {
      try {
        verification = await _verification.run(
          service: terminal,
          workspacePath: workspacePath,
          plan: await _verification.planFor(workspacePath, includeBuild: false),
        );
        review = _reviews.withVerification(review, verification);
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
          : (info?.title ?? info?.prompt ?? ''),
      acceptance: previousSummary?.acceptance.isNotEmpty == true
          ? previousSummary!.acceptance
          : (TaskTemplateService().findByType(info?.type)?.acceptanceRules ??
              const []),
      modifiedFiles: [
        for (final file in review.files) file.path,
      ],
      passedChecks: passed,
      openIssues: [
        ...failed,
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
      phase: (progress['phase'] ?? info?.status ?? 'review').toString(),
      extra: {
        'changeReview': review.toJson(),
        if (verification != null) 'verificationPlan': verification.plan.toJson(),
        'executedSteps': [
          for (final step in verification?.plan.steps ?? const <VerificationStep>[])
            if (step.status == VerificationStepStatus.passed ||
                step.status == VerificationStepStatus.failed)
              step.id,
        ],
        'taskSummary': summary.toJson(),
        'workspaceAccessible': true,
        if (info?.projectKind != null) 'projectKind': info!.projectKind!.id,
      },
    );
    return DevelopmentLoopFinalizeResult(
      review: review,
      verified: verification?.success ?? false,
      verification: verification,
      verificationSkipReason: verificationSkipReason,
    );
  }
}
