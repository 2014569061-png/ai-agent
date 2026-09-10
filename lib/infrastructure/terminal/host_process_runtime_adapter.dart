import 'dart:async';
import 'dart:io';

import 'linux_runtime.dart';

/// 桌面端的本机进程 Adapter。
///
/// Android 不使用该实现；Android 上由自适应 Adapter 选择内置 PRoot、Termux
/// 或系统 Shell。保留本 Adapter 可以让桌面端测试继续走真实进程，同时让 TerminalCommandService
/// 不再感知平台分支。
class HostProcessRuntimeAdapter
    implements LinuxRuntimeAdapter, DetachedLinuxRuntimeAdapter {
  HostProcessRuntimeAdapter({this.maxOutputBytes = 128 * 1024});

  final int maxOutputBytes;
  Process? _process;

  @override
  LinuxRuntimeKind get kind => LinuxRuntimeKind.hostProcess;

  @override
  bool get supportsShellSyntax => false;

  @override
  bool get supportsInterpreterEvaluation => false;

  @override
  bool get isRunning => _process != null;

  @override
  Future<LinuxRuntimeInfo> inspect() async => LinuxRuntimeInfo(
        kind: kind,
        label: '本机进程',
        available: true,
        detail: '使用当前桌面系统的受限进程执行器（${Platform.operatingSystem}）。',
      );

  @override
  Future<CommandResult> run(
    LinuxCommandRequest request, {
    required String workingDirectory,
    required Duration timeout,
  }) async {
    final executableAndArgs = _executable(request);
    final output = StringBuffer();
    var timedOut = false;
    try {
      final process = await Process.start(
        executableAndArgs.$1,
        [...executableAndArgs.$2, ...request.arguments],
        workingDirectory: workingDirectory,
        runInShell: false,
      );
      _process = process;
      final stdout = _collect(process.stdout, output);
      final stderr = _collect(process.stderr, output, prefix: 'stderr: ');
      final exitCode = await process.exitCode.timeout(timeout, onTimeout: () {
        timedOut = true;
        process.kill(ProcessSignal.sigterm);
        return 124;
      });
      await Future.wait([stdout, stderr]);
      final suffix = timedOut ? '\n命令超时，已终止进程。' : '';
      return CommandResult(
        output: '${output.toString()}$suffix',
        exitCode: exitCode,
        timedOut: timedOut,
      );
    } catch (error) {
      return CommandResult(output: '启动命令失败：$error', exitCode: 127);
    } finally {
      _process = null;
    }
  }

  @override
  void stop() {
    _process?.kill(ProcessSignal.sigterm);
  }

  @override
  Future<DetachedCommandHandle?> startDetached(
    LinuxCommandRequest request, {
    required String workingDirectory,
    required Duration timeout,
    required String ownerToken,
    required String logPath,
  }) async {
    final executableAndArgs = _executable(request);
    final log = File(logPath);
    await log.parent.create(recursive: true);
    if (await log.exists()) await log.delete();

    Process process;
    try {
      process = await Process.start(
        executableAndArgs.$1,
        [...executableAndArgs.$2, ...request.arguments],
        workingDirectory: workingDirectory,
        runInShell: false,
        environment: {'NEXUS_DAEMON_OWNER': ownerToken},
        includeParentEnvironment: true,
      );
    } catch (_) {
      return null;
    }

    final sink = log.openWrite(mode: FileMode.writeOnlyAppend);
    final stdoutDone = _pipeToFile(process.stdout, sink);
    final stderrDone = _pipeToFile(process.stderr, sink, prefix: 'stderr: ');
    final completion = () async {
      var timedOut = false;
      var exitCode = 127;
      try {
        exitCode = await process.exitCode.timeout(timeout, onTimeout: () {
          timedOut = true;
          process.kill(ProcessSignal.sigterm);
          return 124;
        });
      } catch (_) {
        timedOut = true;
        process.kill(ProcessSignal.sigterm);
      }
      await Future.wait([stdoutDone, stderrDone]);
      await sink.flush();
      await sink.close();
      String output = '';
      try {
        output = await log.readAsString();
      } catch (_) {}
      return CommandResult(
        output: output,
        exitCode: exitCode,
        timedOut: timedOut,
      );
    }();
    return DetachedCommandHandle(pid: process.pid, completion: completion);
  }

  @override
  Future<bool> verifyDetached(int pid, String ownerToken) async {
    if (pid <= 0 || ownerToken.isEmpty) return false;
    if (Platform.isLinux || Platform.isAndroid) {
      final proc = Directory('/proc/$pid');
      if (!proc.existsSync()) return false;
      try {
        final bytes = await File('/proc/$pid/environ').readAsBytes();
        final environment = String.fromCharCodes(bytes);
        return environment
            .split('\u0000')
            .contains('NEXUS_DAEMON_OWNER=$ownerToken');
      } catch (_) {
        return false;
      }
    }
    if (Platform.isWindows) {
      try {
        final result = await Process.run(
            'tasklist', ['/FI', 'PID eq $pid', '/FO', 'CSV', '/NH']);
        return result.exitCode == 0 &&
            result.stdout.toString().contains(pid.toString());
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  @override
  Future<bool> stopDetached(int pid, String ownerToken) async {
    if (!await verifyDetached(pid, ownerToken)) return false;
    return Process.killPid(pid, ProcessSignal.sigterm);
  }

  Future<void> _pipeToFile(Stream<List<int>> stream, IOSink sink,
      {String prefix = ''}) async {
    await for (final chunk in stream) {
      sink.write(prefix);
      sink.add(chunk);
    }
  }

  Future<void> _collect(
    Stream<List<int>> stream,
    StringBuffer output, {
    String prefix = '',
  }) async {
    await for (final chunk in stream) {
      if (output.length >= maxOutputBytes) continue;
      final text = String.fromCharCodes(chunk);
      final remaining = maxOutputBytes - output.length;
      output.write(
        '$prefix${text.length > remaining ? text.substring(0, remaining) : text}',
      );
    }
    if (output.length >= maxOutputBytes) output.write('\n[输出已截断]');
  }

  (String, List<String>) _executable(LinuxCommandRequest request) {
    if (Platform.isWindows &&
        (request.normalizedCommand == 'dir' ||
            request.normalizedCommand == 'type')) {
      return ('cmd.exe', ['/d', '/c', request.normalizedCommand]);
    }
    return (request.executable, const []);
  }
}
