import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/tools/command_tool.dart';

void main() {
  test('startJob emits sequenced events and reconnects afterSequence',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('nexus-job-protocol-');
    addTearDown(() => directory.delete(recursive: true));
    final runtime = _ImmediateRuntime();
    final service = TerminalCommandService(
      workspacePath: directory.path,
      runtime: runtime,
      jobLogDirectory: Directory('${directory.path}${Platform.pathSeparator}logs'),
    );

    final handle = await service.startJob(
      command: 'pwd',
      taskId: 'task-1',
      runId: 'run-1',
    );
    expect(handle.taskId, 'task-1');
    expect(handle.logPath, isNotNull);

    final first = await service.watchJob(handle.jobId).toList();
    expect(first.first.type, 'started');
    expect(first.last.type, 'completed');
    expect(first.map((event) => event.sequence).toList(),
        [0, 1, 2]);

    final replay = await service
        .watchJob(handle.jobId, afterSequence: 0)
        .toList();
    expect(replay.first.sequence, 1);
    expect(File(handle.logPath!).existsSync(), isTrue);
    expect(service.listJobs().single.jobId, handle.jobId);
  });
}

class _ImmediateRuntime implements LinuxRuntimeAdapter {
  @override
  LinuxRuntimeKind get kind => LinuxRuntimeKind.hostProcess;

  @override
  bool get supportsShellSyntax => true;

  @override
  bool get supportsInterpreterEvaluation => true;

  @override
  bool get isRunning => false;

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
      const CommandResult(output: 'done', exitCode: 0);

  @override
  void stop() {}
}
