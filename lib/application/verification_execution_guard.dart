import '../domain/tool_result.dart';
import '../infrastructure/database/run_plan_store.dart';

/// Middleware for the original verification service, not a second command engine.
abstract interface class VerificationExecutionGuard {
  Future<T> run<T>(String phase, Future<T> Function() action,
      {ToolEffect Function(T)? effectOf});
}

class VerificationDispatchRevoked implements Exception {
  const VerificationDispatchRevoked();
  @override
  String toString() => '验证所属运行或计划已变化，未派发后续步骤';
}

class PersistedVerificationDispatch implements VerificationExecutionGuard {
  PersistedVerificationDispatch(
      {required this.store,
      required this.token,
      required this.prefix,
      this.canContinue});
  final RunPlanStore store;
  final RunPlanToken token;
  final String prefix;
  final bool Function()? canContinue;
  int _sequence = 0;
  @override
  Future<T> run<T>(String phase, Future<T> Function() action,
      {ToolEffect Function(T)? effectOf}) async {
    if (canContinue != null && !canContinue!()) {
      throw const VerificationDispatchRevoked();
    }
    final callId = '$prefix/${++_sequence}/$phase';
    if (await store.claim(token, callId) != RunDispatchClaim.granted) {
      throw const VerificationDispatchRevoked();
    }
    if (canContinue != null && !canContinue!()) {
      await store.settle(token, callId, ToolEffect.none);
      throw const VerificationDispatchRevoked();
    }
    late T value;
    try {
      value = await action();
    } catch (_) {
      // Settling a fact is allowed after a correction; it never changes the new head.
      await store.settle(token, callId, ToolEffect.unknown);
      rethrow;
    }
    if (!await store.settle(
        token, callId, effectOf?.call(value) ?? ToolEffect.applied)) {
      throw StateError('验证步骤已越过边界，但结算未确认；请核实后再继续');
    }
    return value;
  }
}
