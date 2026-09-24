import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/infrastructure/tools/command_tool.dart';

void main() {
  late Directory root;
  late _Runtime runtime;
  late TerminalCommandService service;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('nexus-job-lifecycle-');
    runtime = _Runtime();
    service = TerminalCommandService(
        workspacePath: root.path,
        runtime: runtime,
        daemonPersistence:
            TerminalDaemonPersistence(filePath: '${root.path}/daemons.json'));
  });
  tearDown(() async {
    runtime.complete();
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      try {
        if (await root.exists()) await root.delete(recursive: true);
        return;
      } on FileSystemException {
        // Terminal persistence may be finishing its last asynchronous write.
      }
    }
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('completed jobs have a bounded retention window', () async {
    for (var i = 0; i < 53; i++) {
      final handle = await service.startJob(command: 'pwd');
      await service
          .watchJob(handle.jobId)
          .drain<void>()
          .timeout(const Duration(seconds: 3));
    }
    expect(service.listJobs().length, lessThanOrEqualTo(50));
    await service.pruneJobLogs();
    final logs = await Directory('${root.path}/.nexus/jobs').list().toList();
    expect(logs.whereType<File>().length, lessThanOrEqualTo(50));
  });

  test('job log persistence redacts commands and output, not live results',
      () async {
    runtime.output = 'fixture-private-output';
    final handle =
        await service.startJob(command: 'echo fixture-private-command');
    final events = await service.watchJob(handle.jobId).toList();
    expect(events.last.payload, contains('fixture-private-output'));
    final log = await File(handle.logPath!).readAsString();
    expect(log, isNot(contains('fixture-private-output')));
    expect(log, isNot(contains('fixture-private-command')));
  });

  test('closing a session preserves the running async result handle', () async {
    runtime.pending = Completer<CommandResult>();
    final session = await service.openSession();
    final started = await service.executeSession(
        sessionId: session.id, command: 'pwd', asynchronous: true);
    final id = started.data!['jobId'] as String;
    await service.closeSession(session.id);
    final pending = await service.readAsyncResult(jobId: id);
    expect(pending.ok, isTrue);
    expect(pending.data?['running'], isTrue);
    runtime.complete();
    final events =
        await service.watchJob(id).toList().timeout(const Duration(seconds: 3));
    expect(events.first.type, 'started');
    expect(events.last.type, 'completed');
    expect((await service.readAsyncResult(jobId: id)).data?['output'], 'done');
  });

  test('a non-detached daemon is not stopped by killing the whole runtime',
      () async {
    runtime.pending = Completer<CommandResult>();
    final session = await service.openSession();
    final started =
        await service.startDaemon(sessionId: session.id, command: 'pwd');
    final result =
        await service.stopDaemon(started.data!['daemonId'] as String);
    expect(result.ok, isFalse);
    expect(result.code, ToolCodes.outcomeUnknown);
    expect(result.effect, ToolEffect.none);
    expect(runtime.stops, 0);
    expect(runtime.pending!.isCompleted, isFalse);
  });

  test('daemon tool preserves the 24-hour default timeout', () async {
    runtime.pending = Completer<CommandResult>();
    final session = await service.openSession();
    final result = await TerminalCommandTool(service: service).execute({
      'action': 'daemon_start',
      'sessionId': session.id,
      'command': 'pwd',
    });
    expect(result.ok, isTrue);
    expect(runtime.lastTimeout, const Duration(hours: 24));
  });
}

class _Runtime implements LinuxRuntimeAdapter {
  Completer<CommandResult>? pending;
  String output = 'done';
  int stops = 0;
  Duration? lastTimeout;
  void complete() {
    final value = pending;
    if (value != null && !value.isCompleted) {
      value.complete(CommandResult(output: output, exitCode: 0));
    }
  }

  @override
  LinuxRuntimeKind get kind => LinuxRuntimeKind.hostProcess;
  @override
  bool get supportsShellSyntax => true;
  @override
  bool get supportsInterpreterEvaluation => true;
  @override
  bool get isRunning => pending != null && !pending!.isCompleted;
  @override
  Future<LinuxRuntimeInfo> inspect() async => const LinuxRuntimeInfo(
      kind: LinuxRuntimeKind.hostProcess,
      label: 'fixture',
      available: true,
      detail: 'mock only');
  @override
  Future<CommandResult> run(LinuxCommandRequest request,
      {required String workingDirectory, required Duration timeout}) async {
    lastTimeout = timeout;
    return pending?.future ?? CommandResult(output: output, exitCode: 0);
  }

  @override
  void stop() {
    stops++;
    complete();
  }
}
