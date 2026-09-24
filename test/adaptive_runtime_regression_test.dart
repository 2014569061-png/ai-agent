import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/terminal/adaptive_linux_runtime_adapter.dart';
import 'package:mobile_agent/infrastructure/terminal/linux_runtime.dart';

const _request = LinuxCommandRequest(
    commandLine: 'echo test',
    executable: 'echo',
    normalizedCommand: 'echo test',
    arguments: ['test']);
const _timeout = Duration(seconds: 2);

class _Runtime implements LinuxRuntimeAdapter, DetachedLinuxRuntimeAdapter {
  _Runtime({this.kind = LinuxRuntimeKind.androidShell, this.capable = true});
  @override
  final LinuxRuntimeKind kind;
  final bool capable;
  Completer<LinuxRuntimeInfo>? inspection;
  Completer<DetachedCommandHandle?>? detached;
  int inspections = 0;
  int executions = 0;
  int starts = 0;
  int stops = 0;
  String? stoppedOwner;
  CommandResult result = const CommandResult(output: 'ok', exitCode: 0);
  LinuxRuntimeInfo get info => LinuxRuntimeInfo(
      kind: kind, label: 'fake', available: true, detail: 'test');
  @override
  bool get supportsShellSyntax => capable;
  @override
  bool get supportsInterpreterEvaluation => capable;
  @override
  bool get isRunning => false;
  @override
  Future<LinuxRuntimeInfo> inspect() async {
    inspections++;
    return inspection == null ? info : await inspection!.future;
  }

  @override
  Future<CommandResult> run(LinuxCommandRequest request,
      {required String workingDirectory, required Duration timeout}) async {
    executions++;
    return result;
  }

  @override
  void stop() {
    stops++;
  }

  @override
  Future<DetachedCommandHandle?> startDetached(LinuxCommandRequest request,
      {required String workingDirectory,
      required Duration timeout,
      required String ownerToken,
      required String logPath}) async {
    starts++;
    return detached?.future;
  }

  @override
  Future<bool> verifyDetached(int pid, String ownerToken) async => true;
  @override
  Future<bool> stopDetached(int pid, String ownerToken) async {
    stoppedOwner = ownerToken;
    return true;
  }
}

void main() {
  test('capabilities are conservative before selection and precise afterwards',
      () async {
    final a = _Runtime();
    final b = _Runtime(capable: false);
    final adapter = AdaptiveLinuxRuntimeAdapter([a, b]);
    expect(adapter.supportsShellSyntax, isFalse);
    expect(adapter.supportsInterpreterEvaluation, isFalse);
    await adapter.inspect();
    expect(adapter.supportsShellSyntax, isTrue);
    expect(AdaptiveLinuxRuntimeAdapter([]).supportsShellSyntax, isFalse);
  });

  test('parallel inspection shares one candidate probe', () async {
    final candidate = _Runtime()..inspection = Completer<LinuxRuntimeInfo>();
    final adapter = AdaptiveLinuxRuntimeAdapter([candidate]);
    final first = adapter.inspect();
    final second = adapter.inspect();
    expect(identical(first, second), isTrue);
    candidate.inspection!.complete(candidate.info);
    await Future.wait([first, second]);
    expect(candidate.inspections, 1);
  });

  test('stop during inspection prevents foreground execution', () async {
    final candidate = _Runtime()..inspection = Completer<LinuxRuntimeInfo>();
    final adapter = AdaptiveLinuxRuntimeAdapter([candidate]);
    final result =
        adapter.run(_request, workingDirectory: '.', timeout: _timeout);
    adapter.stop();
    candidate.inspection!.complete(candidate.info);
    expect((await result).exitCode, 130);
    expect(candidate.executions, 0);
  });

  test('stop during fallback prevents the next runtime from executing',
      () async {
    final first = _Runtime(kind: LinuxRuntimeKind.builtinProot)
      ..result =
          const CommandResult(output: '[builtin-proot] missing', exitCode: 127);
    final next = _Runtime()..inspection = Completer<LinuxRuntimeInfo>();
    final adapter = AdaptiveLinuxRuntimeAdapter([first, next]);
    final result =
        adapter.run(_request, workingDirectory: '.', timeout: _timeout);
    await pumpEventQueue();
    adapter.stop();
    next.inspection!.complete(next.info);
    expect((await result).exitCode, 130);
    expect(next.executions, 0);
  });

  test('stop during detached startup compensates using the owner token',
      () async {
    final candidate = _Runtime()
      ..detached = Completer<DetachedCommandHandle?>();
    final adapter = AdaptiveLinuxRuntimeAdapter([candidate]);
    final result = adapter.startDetached(_request,
        workingDirectory: '.',
        timeout: _timeout,
        ownerToken: 'owner',
        logPath: 'test.log');
    await pumpEventQueue();
    expect(candidate.starts, 1);
    adapter.stop();
    candidate.detached!.complete(DetachedCommandHandle(
        pid: 42,
        completion:
            Future.value(const CommandResult(output: '', exitCode: 0))));
    expect(await result, isNull);
    expect(candidate.stoppedOwner, 'owner');
  });
}
