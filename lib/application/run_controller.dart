import '../domain/models.dart';
import 'run_approval_scope.dart';
import 'dart:async';
import '../domain/tool_result.dart';

/// Agent 单次运行的生命周期控制器。
///
/// steering 只在 turn 边界被消费；pause 会通过 [onPauseInterrupt] 立即中断
/// 正在流式输出的模型请求（只中断这一轮，不取消整个 run），正在执行的工具
/// 则在当前命令结束后停下；cancel 才会触发取消回调并清空队列。
class AgentRunController {
  AgentRunController({void Function()? onCancel}) : _onCancel = onCancel;

  final void Function()? _onCancel;
  final List<String> _steering = <String>[];
  final Set<String> _compressionToolCallIds = <String>{};
  Completer<void>? _resumeCompleter;
  final Completer<void> _cancelCompleter = Completer<void>();
  bool _paused = false;
  bool _cancelled = false;
  bool _sealed = false;
  int _controlRevision = 0;

  Future<RunApprovalScope?> Function(ToolCall, ToolRisk, int)? _openApproval;
  final Set<String> _planTrustedTools = {};
  bool isPlanToolTrusted(String tool) => _planTrustedTools.contains(tool);
  void rememberPlanTool(int version, String tool) {
    if (_durableVersion == version) _planTrustedTools.add(tool);
  }

  Future<RunApprovalScope?> openApproval(
          ToolCall call, ToolRisk risk, int? version) async =>
      version == null ? null : _openApproval?.call(call, risk, version);
  int? _durableVersion;
  Future<void> Function()? _synchronizeDurable;
  Future<bool> Function(int)? _verifyDurable;
  Future<ToolResult?> Function(int, String)? _claimDurable;
  Future<ToolResult> Function(int, String, ToolResult)? _settleDurable;
  Future<bool> Function()? _finishDurable;
  final Set<Future<dynamic>> _pendingPersistence = {};
  Completer<void> _revisionChanged = Completer<void>();
  int? get durablePlanRevision => _durableVersion;
  bool get hasDurableFence => _synchronizeDurable != null;
  void attachDurableFence(
      {required int version,
      required Future<RunApprovalScope?> Function(ToolCall, ToolRisk, int)
          openApproval,
      required Future<void> Function() synchronize,
      required Future<bool> Function(int) verify,
      required Future<ToolResult?> Function(int, String) claim,
      required Future<ToolResult> Function(int, String, ToolResult) settle,
      required Future<bool> Function() finish}) {
    _durableVersion = version;
    _openApproval = openApproval;
    _synchronizeDurable = synchronize;
    _verifyDurable = verify;
    _claimDurable = claim;
    _settleDurable = settle;
    _finishDurable = finish;
  }

  void _notifyRevisionChange() {
    final old = _revisionChanged;
    _revisionChanged = Completer<void>();
    if (!old.isCompleted) old.complete();
  }

  void setDurableVersion(int version) {
    if (_durableVersion != version) {
      _durableVersion = version;
      _planTrustedTools.clear();
      _notifyRevisionChange();
    }
  }

  Future<void> whenRevisionChanges(int local, int? durable) =>
      local != controlRevision ||
              durable != durablePlanRevision ||
              isCancelled ||
              isSealed
          ? Future<void>.value()
          : _revisionChanged.future;
  void trackPersistence(Future<dynamic> operation) {
    _pendingPersistence.add(operation);
    unawaited(operation.whenComplete(() {
      _pendingPersistence.remove(operation);
    }).catchError((Object _) {}));
  }

  Future<void> waitForPersistence() async {
    while (_pendingPersistence.isNotEmpty) {
      await Future.wait(_pendingPersistence.toList());
    }
  }

  Future<void> synchronize() async {
    await waitForPersistence();
    await _synchronizeDurable?.call();
  }

  Future<bool> verifyDurableRevision(int? version) async => version == null
      ? !hasDurableFence
      : version == _durableVersion &&
          (await _verifyDurable?.call(version) ?? false);
  Future<ToolResult?> claimDurableDispatch(int? version, String callId) async =>
      version == null ? null : _claimDurable?.call(version, callId);
  Future<ToolResult> settleDurableDispatch(
          int? version, String callId, ToolResult result) async =>
      version == null
          ? result
          : (await _settleDurable?.call(version, callId, result) ?? result);

  /// Used only after other continuation hooks have declined to continue.
  Future<List<String>> drainDurableSteeringOrSeal() async {
    while (!_cancelled && !_sealed) {
      await checkpoint();
      if (_cancelled || _sealed) return const [];
      if (_steering.isNotEmpty) return drainSteering();
      final finished = await _finishDurable?.call() ?? true;
      if (finished) {
        seal();
        return const [];
      }
      await synchronize();
      if (_steering.isEmpty && !_paused && !_cancelled) {
        // A non-current owner or an unsettled dispatch cannot claim completion.
        throw StateError('Persistent run completion was not confirmed');
      }
    }
    return const [];
  }

  /// Local turn generation; not a persisted plan-version/remote-ownership claim.
  int get controlRevision => _controlRevision;

  bool get isPaused => _paused;
  bool get isCancelled => _cancelled;
  bool get isSealed => _sealed;
  bool get canSteer => !_cancelled && !_sealed;
  List<String> get pendingSteering => List.unmodifiable(_steering);
  Future<void> get whenCancelled => _cancelCompleter.future;

  /// 暂停时的即时中断钩子。执行器只在模型流式请求期间注册、请求结束即清空；
  /// 工具执行期间不注册，正在跑的命令会先跑完，再停在下一个检查点。
  void Function()? onPauseInterrupt;

  /// 在当前 turn 仍可继续时追加一条用户补充指令。
  bool steer(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty || !canSteer) return false;
    _controlRevision++;
    _notifyRevisionChange();
    _steering.add(normalized);
    return true;
  }

  bool queueCompression(Iterable<String> toolCallIds) {
    if (!canSteer) return false;
    final ids = toolCallIds.where((id) => id.trim().isNotEmpty).toSet();
    if (ids.isEmpty) return false;
    _compressionToolCallIds.addAll(ids);
    return true;
  }

  Set<String> drainCompressionToolCallIds() {
    if (!canSteer || _compressionToolCallIds.isEmpty) return const {};
    final ids = Set<String>.of(_compressionToolCallIds);
    _compressionToolCallIds.clear();
    return ids;
  }

  /// 暂停：立即中断正在流式输出的模型请求（若已注册 [onPauseInterrupt]）；
  /// 正在执行的工具不被打断，会在下一个检查点停下。
  bool pause() {
    if (_cancelled || _sealed || _paused) return false;
    _paused = true;
    _resumeCompleter ??= Completer<void>();
    onPauseInterrupt?.call();
    return true;
  }

  /// 唤醒 pause 检查点；重复 resume 是幂等操作。
  bool resume() {
    if (_cancelled || _sealed || !_paused) return false;
    _paused = false;
    final completer = _resumeCompleter;
    _resumeCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
    return true;
  }

  /// 取消运行并唤醒所有等待中的检查点。
  bool cancel() {
    if (_cancelled || _sealed) return false;
    _cancelled = true;
    _notifyRevisionChange();
    _paused = false;
    onPauseInterrupt = null;
    _steering.clear();
    _compressionToolCallIds.clear();
    final completer = _resumeCompleter;
    _resumeCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
    if (!_cancelCompleter.isCompleted) _cancelCompleter.complete();
    _onCancel?.call();
    return true;
  }

  /// 运行结束后封存控制器，后续 steering 不得污染已完成的 run。
  void seal() {
    if (_sealed) return;
    _sealed = true;
    _notifyRevisionChange();
    onPauseInterrupt = null;
    _steering.clear();
    _compressionToolCallIds.clear();
    _paused = false;
    final completer = _resumeCompleter;
    _resumeCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  /// 在模型请求、工具调用前的安全检查点等待恢复或取消。
  Future<void> checkpoint() async {
    await synchronize();
    while (_paused && !_cancelled && !_sealed) {
      final completer = _resumeCompleter ??= Completer<void>();
      if (hasDurableFence) {
        await Future.any<void>([
          completer.future,
          Future<void>.delayed(const Duration(milliseconds: 400))
        ]);
        await synchronize();
      } else {
        await completer.future;
      }
    }
  }

  /// 在下一次请求前或工具批次结束时消费排队的 steering，不封存整个 run。
  /// 开始运行前已排队的指令直接进入首个请求，不额外发起一轮模型调用。
  List<String> drainSteering() {
    if (_cancelled || _sealed || _steering.isEmpty) return const [];
    final pending = List<String>.of(_steering);
    _steering.clear();
    return pending;
  }

  /// 在模型准备结束当前 turn 时原子地消费队列；没有新指令则封存 run。
  ///
  /// 该方法用于解决“插话恰好落在完成边界”的竞态：队列为空时立刻封存，
  /// 之后到达的 steering 会被拒绝，不会在已完成的 run 上偷偷启动新一轮。
  List<String> pollSteeringOrSeal() {
    if (_cancelled || _sealed) return const [];
    if (_steering.isEmpty) {
      seal();
      return const [];
    }
    final pending = List<String>.of(_steering);
    _steering.clear();
    return pending;
  }
}
