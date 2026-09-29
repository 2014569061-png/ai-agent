import '../agent_loop/agent_loop_hooks.dart';
import '../session_log/session_event_store.dart';
import '../session_log/session_log_settings.dart';
import '../session_log/session_recorder.dart';
import 'agent_module.dart';
import 'run_profile.dart';

/// 把运行写入会话日志（阶段 1 双写的模块化形态）。
///
/// 仅在双写开关打开、运行形态要求记录且有 [RunScope.sessionId] 时挂载。
class SessionLogModule implements AgentModule {
  SessionLogModule({
    required this.store,
    bool? enabled,
    this.onError,
  }) : _enabled = enabled;

  final SessionEventStore Function() store;
  final bool? _enabled;
  final void Function(Object error, StackTrace stackTrace)? onError;

  @override
  String get id => 'builtin.session-log';

  @override
  bool appliesTo(RunScope scope) =>
      (_enabled ?? SessionLogSettings.dualWrite) &&
      scope.profile.recordSession &&
      scope.sessionId != null;

  @override
  ModuleAttachment attach(RunScope scope) {
    final recorder = SessionRecorder(
      store: store(),
      conversationId: scope.sessionId!,
      runId: scope.runId,
      model: scope.model,
      onError: onError,
    )..start();
    return ModuleAttachment(
      hooks: AgentLoopHooks(requestObservers: [recorder.onRequest]),
      onEvent: recorder.observe,
      onFinish: (outcome) {
        // 事件流未给出终态就结束时封口；已结束则无操作。
        recorder.abort(outcome.abortReason ?? 'stream_ended_without_status');
        return recorder.flush();
      },
    );
  }
}
