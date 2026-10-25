import 'change_review.dart';
import '../domain/models.dart';
import '../domain/tool_result.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/database/run_plan_store.dart';
import '../infrastructure/tools/command_tool.dart';
import 'agent_loop/agent_loop_hooks.dart';
import 'development_loop_finalizer.dart';
import 'verification_execution_guard.dart';
import 'verification_repair_service.dart';

/// Verification and bounded repair stay in the original run/AgentExecutor loop.
class DevelopmentRunCompletion {
  DevelopmentRunCompletion(
      {required this.db,
      required this.taskId,
      required this.runId,
      required this.workspacePath,
      required this.terminalFactory,
      required this.repairEnabled,
      required this.canContinue,
      this.onVerifying,
      DevelopmentLoopFinalizer? finalizer})
      : _finalizer = finalizer ?? DevelopmentLoopFinalizer();
  final DevelopmentLoopFinalizer _finalizer;
  final AppDatabase db;
  final String taskId, runId, workspacePath;
  final Future<TerminalCommandService?> Function() terminalFactory;
  final Future<bool> Function() repairEnabled;
  final bool Function() canContinue;
  final void Function()? onVerifying;
  DevelopmentLoopFinalizeResult? latest;
  bool verificationRequested = false;
  static const repairTools = {
    'read_file',
    'list_directory',
    'search_files',
    'repo_map',
    'edit_file',
    'apply_patch',
    'write_file'
  };
  Future<TurnContinuation?>? _pending;
  Future<TurnContinuation?> call(TurnStoppingContext context) {
    final future = _call(context);
    _pending = future;
    return future;
  }

  /// The executor reports errors. The lifecycle owner must join owned cleanup
  /// before releasing its workspace lease, including cancellation races.
  Future<void> drain() async {
    try {
      await _pending;
    } catch (_) {/* Reported by the executor. */}
  }

  Future<TurnContinuation?> _call(TurnStoppingContext context) async {
    latest = null;
    verificationRequested = false;
    try {
      return await _run(context);
    } on VerificationDispatchRevoked {
      return null;
    }
  }

  Future<TurnContinuation?> _run(TurnStoppingContext context) async {
    bool valid() => canContinue() && (context.canContinue?.call() ?? true);
    final store = RunPlanStore(db);
    final head = await store.head(taskId);
    if (!valid() ||
        head == null ||
        head.token.runId != runId ||
        !await store.isCurrent(head.token)) {
      return null;
    }
    final token = head.token;
    final dispatch = PersistedVerificationDispatch(
        store: store,
        token: token,
        prefix: '__completion/${context.step}',
        canContinue: valid);
    final terminal = await dispatch.run('prepare-terminal', terminalFactory,
        effectOf: (service) =>
            service == null ? ToolEffect.none : ToolEffect.applied);
    if (!valid() || !await store.isCurrent(token)) return null;
    verificationRequested = terminal != null;
    if (verificationRequested) onVerifying?.call();
    VerificationRepairRequest? pendingRepair;
    final allowRepair = await repairEnabled();
    final finalized = await _finalizer.finalize(
        db: db,
        taskId: taskId,
        runId: runId,
        planVersion: token.version,
        workspacePath: workspacePath,
        terminal: terminal,
        runVerification: verificationRequested,
        executionGuard: dispatch,
        canContinue: valid,
        deferRepair: true,
        repair: allowRepair
            ? (request) async {
                pendingRepair = request;
                return false;
              }
            : null);
    if (!valid() || !await store.isCurrent(token)) return null;
    latest = finalized;
    final repair = pendingRepair;
    if (repair == null) {
      if (verificationRequested &&
          finalized.review.files.isNotEmpty &&
          !finalized.verified) {
        // Never seal a successful head when the required verification failed.
        throw DevelopmentCompletionUnverified(
            finalized.verificationSkipReason ?? finalized.review.mark.label);
      }
      return null;
    }
    return TurnContinuation([
      ChatMessage(role: MessageRole.user, parts: [
        MessagePart.text(
            '继续修复当前验证失败，仍属于同一任务和计划。只使用允许的文件读取/编辑工具，不运行终端命令；不得删除、削弱或跳过检查。\n\n${const VerificationRepairService().promptFor(repair)}')
      ])
    ], keepAssistantText: false, allowedToolNames: repairTools);
  }
}

class DevelopmentCompletionUnverified implements Exception {
  const DevelopmentCompletionUnverified(this.reason);
  final String reason;
  @override
  String toString() => '系统验证未通过：$reason';
}
