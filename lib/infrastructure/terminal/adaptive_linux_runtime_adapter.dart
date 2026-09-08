import 'linux_runtime.dart';

/// Selects the first available runtime and can move to the next Adapter when
/// a native runtime cannot start on a particular device/ROM.
class AdaptiveLinuxRuntimeAdapter implements LinuxRuntimeAdapter {
  AdaptiveLinuxRuntimeAdapter(this._candidates);

  final List<LinuxRuntimeAdapter> _candidates;
  LinuxRuntimeAdapter? _selected;
  int _nextCandidate = 0;
  Future<LinuxRuntimeInfo>? _inspection;

  @override
  LinuxRuntimeKind get kind =>
      _selected?.kind ??
      (_candidates.isEmpty
          ? LinuxRuntimeKind.androidShell
          : _candidates.first.kind);

  @override
  bool get supportsShellSyntax => _selected?.supportsShellSyntax ?? true;

  @override
  bool get supportsInterpreterEvaluation =>
      _selected?.supportsInterpreterEvaluation ?? true;

  @override
  bool get isRunning => _selected?.isRunning ?? false;

  @override
  Future<LinuxRuntimeInfo> inspect() {
    final inspection = _inspection;
    if (inspection != null) return inspection;
    final future = _selectAvailable();
    _inspection = future;
    return future;
  }

  @override
  Future<CommandResult> run(
    LinuxCommandRequest request, {
    required String workingDirectory,
    required Duration timeout,
  }) async {
    final runtime = await _ensureSelected();
    if (runtime == null) {
      return const CommandResult(
        output: '没有可用的 Linux Runtime。',
        exitCode: 127,
      );
    }

    final result = await runtime.run(
      request,
      workingDirectory: workingDirectory,
      timeout: timeout,
    );
    if (!_shouldFallback(runtime, result)) return result;

    _selected = null;
    _inspection = null;
    final next = await _ensureSelected();
    if (next == null) return result;
    return next.run(
      request,
      workingDirectory: workingDirectory,
      timeout: timeout,
    );
  }

  @override
  void stop() {
    _selected?.stop();
  }

  Future<LinuxRuntimeAdapter?> _ensureSelected() async {
    if (_selected != null) return _selected;
    await _selectAvailable();
    return _selected;
  }

  Future<LinuxRuntimeInfo> _selectAvailable() async {
    LinuxRuntimeInfo? last;
    while (_nextCandidate < _candidates.length) {
      final candidate = _candidates[_nextCandidate++];
      try {
        final info = await candidate.inspect();
        last = info;
        if (info.available) {
          _selected = candidate;
          return info;
        }
      } catch (error) {
        last = LinuxRuntimeInfo(
          kind: candidate.kind,
          label: candidate.kind.name,
          available: false,
          detail: 'Runtime 检测失败：$error',
        );
      }
    }

    return last ??
        const LinuxRuntimeInfo(
          kind: LinuxRuntimeKind.androidShell,
          label: 'Linux Runtime',
          available: false,
          detail: '没有配置任何运行时。',
        );
  }

  bool _shouldFallback(LinuxRuntimeAdapter runtime, CommandResult result) {
    return runtime.kind == LinuxRuntimeKind.builtinProot &&
        result.exitCode == 127 &&
        result.output.startsWith('[builtin-proot]');
  }
}
