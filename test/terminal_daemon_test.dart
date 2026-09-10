import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/infrastructure/terminal/adaptive_linux_runtime_adapter.dart';
import 'package:mobile_agent/infrastructure/terminal/linux_runtime.dart';
import 'package:mobile_agent/infrastructure/tools/command_tool.dart';

void main() {
  test('daemon start enforces the eight-process limit', () async {
    final directory =
        await Directory.systemTemp.createTemp('nexus-daemon-limit-');
    addTearDown(() => _deleteEventually(directory));
    final runtime = _DetachedRuntime();
    final service = TerminalCommandService(
      workspacePath: directory.path,
      runtime: runtime,
      daemonPersistence: TerminalDaemonPersistence(
        filePath: '${directory.path}${Platform.pathSeparator}daemons.json',
      ),
    );
    final session = await service.openSession();

    for (var i = 0; i < 8; i++) {
      final result = await service.startDaemon(
        sessionId: session.id,
        command: 'pwd',
      );
      expect(result.ok, isTrue);
    }
    final rejected = await service.startDaemon(
      sessionId: session.id,
      command: 'pwd',
    );
    expect(rejected.ok, isFalse);
    expect(rejected.code, ToolCodes.tooLarge);
    expect(runtime.detachedStarts, 8);
  });

  test('session keeps cwd across commands after cd &&', () async {
    final directory =
        await Directory.systemTemp.createTemp('nexus-daemon-cwd-');
    addTearDown(() => _deleteEventually(directory));
    final runtime = _DetachedRuntime(
      runOutput: (cwd) => 'cwd=$cwd',
    );
    final service = TerminalCommandService(
      workspacePath: directory.path,
      runtime: runtime,
      daemonPersistence: TerminalDaemonPersistence(
        filePath: '${directory.path}${Platform.pathSeparator}daemons.json',
      ),
    );
    final session = await service.openSession();
    final subdir = '${directory.path}${Platform.pathSeparator}project';
    await Directory(subdir).create();

    final first = await service.executeSession(
      sessionId: session.id,
      command: 'cd project && pwd',
    );
    expect(first.ok, isTrue, reason: '${first.code}: ${first.message}');
    expect(first.data?['cwd'], subdir);
    expect(runtime.lastWorkingDirectory, directory.path);

    final second = await service.executeSession(
      sessionId: session.id,
      command: 'pwd',
    );
    expect(second.ok, isTrue);
    expect(second.data?['cwd'], subdir);
    expect(runtime.lastWorkingDirectory, subdir);
  });

  test('async job logs can be paged after completion', () async {
    final directory =
        await Directory.systemTemp.createTemp('nexus-daemon-async-');
    addTearDown(() => _deleteEventually(directory));
    final runtime = _DetachedRuntime(
      completionResult: const CommandResult(output: 'abcdef', exitCode: 0),
    );
    final service = TerminalCommandService(
      workspacePath: directory.path,
      runtime: runtime,
      daemonPersistence: TerminalDaemonPersistence(
        filePath: '${directory.path}${Platform.pathSeparator}daemons.json',
      ),
    );
    final session = await service.openSession();
    final started = await service.executeSession(
      sessionId: session.id,
      command: 'pwd',
      asynchronous: true,
    );
    final jobId = started.data!['jobId'] as String;
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final first = await service.readAsyncResult(jobId: jobId, maxChars: 3);
    expect(first.ok, isTrue);
    expect(first.data?['output'], 'abc');
    expect(first.data?['nextOffsetChars'], 3);
    expect(first.data?['outputTruncated'], isTrue);

    final second = await service.readAsyncResult(
      jobId: jobId,
      offsetChars: 3,
      maxChars: 3,
    );
    expect(second.data?['output'], 'def');
    expect(second.data?['nextOffsetChars'], isNull);
    expect(second.data?['outputTruncated'], isFalse);
  });

  test('daemon logs expose bounded pages after completion', () async {
    final directory =
        await Directory.systemTemp.createTemp('nexus-daemon-pages-');
    addTearDown(() => _deleteEventually(directory));
    final runtime = _DetachedRuntime(
      completionResult: const CommandResult(output: 'abcdef', exitCode: 7),
    );
    final service = TerminalCommandService(
      workspacePath: directory.path,
      runtime: runtime,
      daemonPersistence: TerminalDaemonPersistence(
        filePath: '${directory.path}${Platform.pathSeparator}daemons.json',
      ),
    );
    final session = await service.openSession();
    final started = await service.startDaemon(
      sessionId: session.id,
      command: 'pwd',
    );
    final daemonId = started.data!['daemonId'] as String;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final page = await service.daemonLogs(daemonId, maxChars: 3);
    expect(page.ok, isFalse,
        reason: '${page.code}: ${page.message} ${page.data ?? {}}');
    expect(page.effect.name, 'applied');
    expect(page.data?['output'], 'abc');
    expect(page.data?['nextOffsetChars'], 3);
    expect(page.data?['outputTruncated'], isTrue);
  });

  test('restored daemon consumes an exit file after app restart', () async {
    final directory =
        await Directory.systemTemp.createTemp('nexus-daemon-restore-');
    addTearDown(() => _deleteEventually(directory));
    final log = File('${directory.path}${Platform.pathSeparator}daemon.log');
    final exit = File('${log.path}.exit.json');
    await log.writeAsString('restored output');
    await exit.writeAsString('{"exitCode":0,"timedOut":false}');
    final persistence = TerminalDaemonPersistence(
      filePath: '${directory.path}${Platform.pathSeparator}daemons.json',
    );
    await persistence.save([
      TerminalDaemonRecord(
        daemonId: 'daemon-restored',
        sessionId: 'session-restored',
        command: 'pwd',
        cwd: directory.path,
        ownerToken: 'owner-restored',
        startedAt: DateTime.now(),
        runtimeKind: LinuxRuntimeKind.hostProcess.name,
        pid: 54321,
        logPath: log.path,
      ),
    ]);
    final service = TerminalCommandService(
      workspacePath: directory.path,
      runtime: _DetachedRuntime(verifyResult: false),
      daemonPersistence: persistence,
    );

    final rows = await service.listDaemonsAsync();
    expect(rows.single['daemonId'], 'daemon-restored');
    expect(rows.single['running'], isFalse);
    final result = await service.daemonLogs('daemon-restored');
    expect(result.ok, isTrue);
    expect(result.data?['output'], 'restored output');
  });

  test('owner mismatch never reaches process stop', () async {
    final runtime = _DetachedRuntime(expectedOwner: 'owner-a');
    expect(await runtime.verifyDetached(100, 'owner-b'), isFalse);
    expect(await runtime.stopDetached(100, 'owner-b'), isFalse);
    expect(runtime.stopCalls, 0);
  });

  test('adaptive runtime falls back when detached start is unavailable',
      () async {
    final first = _DetachedRuntime(
      runtimeKind: LinuxRuntimeKind.builtinProot,
      failDetached: true,
    );
    final second = _DetachedRuntime(
      runtimeKind: LinuxRuntimeKind.termux,
      startResult: DetachedCommandHandle(
        pid: 99,
        completion: Future<CommandResult>.value(
          const CommandResult(output: 'ok', exitCode: 0),
        ),
      ),
    );
    final adaptive = AdaptiveLinuxRuntimeAdapter([first, second]);
    final handle = await adaptive.startDetached(
      const LinuxCommandRequest(
        commandLine: 'pwd',
        executable: 'pwd',
        normalizedCommand: 'pwd',
        arguments: [],
      ),
      workingDirectory: '.',
      timeout: const Duration(seconds: 1),
      ownerToken: 'owner',
      logPath: 'daemon.log',
    );
    expect(handle?.pid, 99);
    expect(first.detachedStarts, 1);
    expect(second.detachedStarts, 1);
  });
}

class _DetachedRuntime
    implements LinuxRuntimeAdapter, DetachedLinuxRuntimeAdapter {
  _DetachedRuntime({
    this.runtimeKind = LinuxRuntimeKind.hostProcess,
    this.completionResult = const CommandResult(output: '', exitCode: 0),
    this.startResult,
    this.failDetached = false,
    this.verifyResult = true,
    this.expectedOwner,
    this.runOutput,
  });

  final LinuxRuntimeKind runtimeKind;
  final CommandResult completionResult;
  final DetachedCommandHandle? startResult;
  final bool failDetached;
  final bool verifyResult;
  final String? expectedOwner;
  final String Function(String workingDirectory)? runOutput;
  int detachedStarts = 0;
  int stopCalls = 0;
  String? lastWorkingDirectory;

  @override
  LinuxRuntimeKind get kind => runtimeKind;

  @override
  bool get supportsShellSyntax => true;

  @override
  bool get supportsInterpreterEvaluation => true;

  @override
  bool get isRunning => false;

  @override
  Future<LinuxRuntimeInfo> inspect() async => LinuxRuntimeInfo(
        kind: runtimeKind,
        label: 'test',
        available: true,
        detail: 'test',
        supportsShellSyntax: true,
      );

  @override
  Future<CommandResult> run(
    LinuxCommandRequest request, {
    required String workingDirectory,
    required Duration timeout,
  }) async {
    lastWorkingDirectory = workingDirectory;
    final output = runOutput?.call(workingDirectory);
    return CommandResult(
      output: output ?? completionResult.output,
      exitCode: completionResult.exitCode,
      timedOut: completionResult.timedOut,
      notExecuted: completionResult.notExecuted,
    );
  }

  @override
  void stop() {}

  @override
  Future<DetachedCommandHandle?> startDetached(
    LinuxCommandRequest request, {
    required String workingDirectory,
    required Duration timeout,
    required String ownerToken,
    required String logPath,
  }) async {
    detachedStarts++;
    if (failDetached) return null;
    final explicit = startResult;
    if (explicit != null) return explicit;
    return DetachedCommandHandle(
      pid: 100 + detachedStarts,
      logPath: logPath,
      completion: Future<CommandResult>.value(completionResult),
    );
  }

  @override
  Future<bool> verifyDetached(int pid, String ownerToken) async =>
      (expectedOwner == null || expectedOwner == ownerToken) && verifyResult;

  @override
  Future<bool> stopDetached(int pid, String ownerToken) async {
    final verified = await verifyDetached(pid, ownerToken);
    if (verified) stopCalls++;
    return verified;
  }
}

Future<void> _deleteEventually(Directory directory) async {
  for (var attempt = 0; attempt < 10; attempt++) {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }
}
