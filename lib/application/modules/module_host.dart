import '../agent_executor.dart' show AgentEvent;
import '../agent_loop/agent_loop_hooks.dart';
import 'agent_module.dart';
import 'run_profile.dart';

typedef ModuleErrorHandler = void Function(
    String moduleId, Object error, StackTrace stackTrace);

/// 为每次运行挂载适用的模块，并把它们的钩子合并交给执行器。
///
/// 模块失败只影响它自己：挂载、事件观察、收尾中抛出的异常交给 [onError]，
/// 不会中断运行或影响其他模块。
class ModuleHost {
  const ModuleHost(this.modules, {this.onError});

  static const empty = ModuleHost([]);

  final List<AgentModule> modules;
  final ModuleErrorHandler? onError;

  Future<ModuleSession> open(RunScope scope) async {
    final attached = <_Attached>[];
    for (final module in modules) {
      try {
        if (!module.appliesTo(scope)) continue;
        final attachment = await module.attach(scope);
        if (attachment != null) attached.add(_Attached(module.id, attachment));
      } on Object catch (error, stackTrace) {
        onError?.call(module.id, error, stackTrace);
      }
    }
    return ModuleSession._(scope, attached, onError);
  }
}

/// 一次运行中已挂载的模块集合。
class ModuleSession {
  ModuleSession._(this.scope, this._attached, this._onError)
      : hooks = _attached.fold(
            AgentLoopHooks.empty, (merged, a) => merged.merge(a.attachment.hooks));

  final RunScope scope;
  final List<_Attached> _attached;
  final ModuleErrorHandler? _onError;
  var _finished = false;

  /// 按模块注册顺序合并的钩子，直接交给 AgentExecutor。
  final AgentLoopHooks hooks;

  List<String> get moduleIds =>
      [for (final a in _attached) a.id];

  bool get finished => _finished;

  void observe(AgentEvent event) {
    if (_finished) return;
    for (final a in _attached) {
      final onEvent = a.attachment.onEvent;
      if (onEvent == null) continue;
      try {
        onEvent(event);
      } on Object catch (error, stackTrace) {
        _onError?.call(a.id, error, stackTrace);
      }
    }
  }

  /// 逆序收尾；重复调用无操作。
  Future<void> finish(RunOutcome outcome) async {
    if (_finished) return;
    _finished = true;
    for (final a in _attached.reversed) {
      final onFinish = a.attachment.onFinish;
      if (onFinish == null) continue;
      try {
        await onFinish(outcome);
      } on Object catch (error, stackTrace) {
        _onError?.call(a.id, error, stackTrace);
      }
    }
  }
}

final class _Attached {
  const _Attached(this.id, this.attachment);
  final String id;
  final ModuleAttachment attachment;
}
