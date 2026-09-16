import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/tools/command_tool.dart';

void main() {
  test('canceling job A does not complete job B', () async {
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

    await service.cancelJob(first.jobId);
    final jobs = {for (final job in service.listJobs()) job.jobId: job};
    expect(jobs[first.jobId]!.completed, isTrue);
    expect(jobs[first.jobId]!.exitCode, 130);
    expect(jobs[second.jobId]!.completed, isFalse);
    expect(runtime.stopCount, 0,
        reason: '停止作业 A 不能 stop() 整个 runtime，以免误杀作业 B');
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
