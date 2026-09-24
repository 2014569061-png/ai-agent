import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/terminal/linux_runtime.dart';
import 'package:mobile_agent/infrastructure/tools/command_tool.dart';

void main() {
  test('reports unsupported cancellation without hiding the running job',
      () async {
    final directory = await Directory.systemTemp.createTemp('nexus-job-mgmt-');
    addTearDown(() => directory.delete(recursive: true));
    final runtime = _HoldRuntime();
    final service = TerminalCommandService(
      workspacePath: directory.path,
      runtime: runtime,
    );

    final first = await service.startJob(command: 'pwd');
    final second = await service.startJob(command: 'ls');
    expect(service.listJobs(), hasLength(2));

    expect(await service.cancelJob(first.jobId), isFalse);
    final jobs = {for (final job in service.listJobs()) job.jobId: job};
    expect(jobs[first.jobId]!.completed, isFalse);
    expect(jobs[second.jobId]!.completed, isFalse);
    expect(runtime.stopCount, 0,
        reason: '停止作业 A 不能 stop() 整个 runtime，以免误杀作业 B');
  });

  test('cancels only the selected detached job', () async {
    final directory = await Directory.systemTemp.createTemp('nexus-job-stop-');
    addTearDown(() => directory.delete(recursive: true));
    final runtime = _DetachedHoldRuntime();
    final service = TerminalCommandService(
      workspacePath: directory.path,
      runtime: runtime,
    );

    final first = await service.startJob(command: 'pwd');
    final second = await service.startJob(command: 'ls');
    expect(await service.cancelJob(first.jobId), isTrue);

    final jobs = {for (final job in service.listJobs()) job.jobId: job};
    expect(jobs[first.jobId]!.completed, isTrue);
    expect(jobs[first.jobId]!.exitCode, 130);
    expect(jobs[second.jobId]!.completed, isFalse);
    expect(runtime.stoppedPids, [1]);
  });
}

class _HoldRuntime implements LinuxRuntimeAdapter {
  final _pending = <Completer<CommandResult>>[];
  int stopCount = 0;

  void completeAll() {
    for (final pending in _pending) {
      if (!pending.isCompleted) {
        pending.complete(const CommandResult(output: 'done', exitCode: 0));
      }
    }
  }

  @override
  LinuxRuntimeKind get kind => LinuxRuntimeKind.hostProcess;

  @override
  bool get supportsShellSyntax => true;

  @override
  bool get supportsInterpreterEvaluation => true;

  @override
  bool get isRunning => _pending.any((item) => !item.isCompleted);

  @override
  Future<LinuxRuntimeInfo> inspect() async => const LinuxRuntimeInfo(
        kind: LinuxRuntimeKind.hostProcess,
        label: 'test',
        available: true,
        detail: 'ok',
      );

  @override
  Future<CommandResult> run(
    LinuxCommandRequest request, {
    required String workingDirectory,
    required Duration timeout,
  }) {
    final completer = Completer<CommandResult>();
    _pending.add(completer);
    return completer.future;
  }

  @override
  void stop() {
    stopCount++;
  }
}

class _DetachedHoldRuntime
    implements LinuxRuntimeAdapter, DetachedLinuxRuntimeAdapter {
  final _pending = <int, Completer<CommandResult>>{};
  final _owners = <int, String>{};
  final stoppedPids = <int>[];
  var _nextPid = 1;

  @override
  LinuxRuntimeKind get kind => LinuxRuntimeKind.hostProcess;

  @override
  bool get supportsShellSyntax => true;

  @override
  bool get supportsInterpreterEvaluation => true;

  @override
  bool get isRunning => _pending.values.any((item) => !item.isCompleted);

  @override
  Future<LinuxRuntimeInfo> inspect() async => const LinuxRuntimeInfo(
        kind: LinuxRuntimeKind.hostProcess,
        label: 'test',
        available: true,
        detail: 'ok',
      );

  @override
  Future<CommandResult> run(
    LinuxCommandRequest request, {
    required String workingDirectory,
    required Duration timeout,
  }) async =>
      throw StateError('tracked jobs should use startDetached');

  @override
  Future<DetachedCommandHandle?> startDetached(
    LinuxCommandRequest request, {
    required String workingDirectory,
    required Duration timeout,
    required String ownerToken,
    required String logPath,
  }) async {
    final pid = _nextPid++;
    final completion = Completer<CommandResult>();
    _pending[pid] = completion;
    _owners[pid] = ownerToken;
    return DetachedCommandHandle(
      pid: pid,
      logPath: logPath,
      completion: completion.future,
    );
  }

  @override
  Future<bool> verifyDetached(int pid, String ownerToken) async =>
      _owners[pid] == ownerToken && _pending[pid]?.isCompleted == false;

  @override
  Future<bool> stopDetached(int pid, String ownerToken) async {
    if (!await verifyDetached(pid, ownerToken)) return false;
    stoppedPids.add(pid);
    _pending[pid]!.complete(
      const CommandResult(output: 'cancelled', exitCode: 130),
    );
    return true;
  }

  @override
  void stop() {}
}
