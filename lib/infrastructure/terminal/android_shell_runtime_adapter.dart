import 'dart:async';
import 'dart:io';

import 'linux_runtime.dart';

typedef AndroidShellProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment,
  bool runInShell,
  ProcessStartMode mode,
});

typedef ProcessSignalSender = bool Function(int pid, ProcessSignal signal);
typedef ProcessGroupLeaderCheck = bool Function(int pid);
typedef ProcessAliveCheck = bool Function(int pid);
typedef ProcessChildrenReader = List<int> Function(int pid);

/// Last-resort Android system shell. It has no bundled Linux toolchain, but
/// keeps basic shell commands usable when neither PRoot nor Termux is ready.
class AndroidShellRuntimeAdapter
    implements LinuxRuntimeAdapter, DetachedLinuxRuntimeAdapter {
  AndroidShellRuntimeAdapter({
    this.maxOutputBytes = 128 * 1024,
    this.killGrace = const Duration(milliseconds: 200),
    bool? isAndroid,
    AndroidShellProcessStarter? processStarter,
    ProcessSignalSender? signalSender,
    ProcessGroupLeaderCheck? isGroupLeader,
    ProcessAliveCheck? isProcessAlive,
    ProcessAliveCheck? isGroupAlive,
    ProcessChildrenReader? readChildren,
    String? groupLauncher,
  })  : _isAndroid = isAndroid ?? Platform.isAndroid,
        _processStarter = processStarter ?? Process.start,
        _signalSender = signalSender ?? Process.killPid,
        _isGroupLeader = isGroupLeader ?? _safeGroupLeader,
        _isProcessAlive = isProcessAlive ?? _safeAlive,
        _isGroupAlive = isGroupAlive ?? _safeGroupAlive,
        _readChildren = readChildren ?? _safeChildren,
        _groupLauncher = groupLauncher ??
            (Platform.isAndroid && File('/system/bin/setsid').existsSync()
                ? '/system/bin/setsid'
                : null);

  final int maxOutputBytes;
  final Duration killGrace;
  final bool _isAndroid;
  final AndroidShellProcessStarter _processStarter;
  final ProcessSignalSender _signalSender;
  final ProcessGroupLeaderCheck _isGroupLeader;
  final ProcessAliveCheck _isProcessAlive;
  final ProcessAliveCheck _isGroupAlive;
  final ProcessChildrenReader _readChildren;
  final String? _groupLauncher;
  Process? _process;
  bool _starting = false;
  bool _stopRequested = false;
  Future<bool>? _foregroundTermination;
  Future<void> Function()? _cancelForegroundOutput;
  final Map<int, Future<bool>> _terminations = {};

  /// 命令进程不继承 App 环境。API Key 等机密在父进程里，不能透传给 shell。
  /// 只给 Android 系统命令一个固定 PATH，避免绝对路径启动后内部命令找不到。
  static const sanitizedEnvironment = {
    'PATH': '/system/bin:/system/xbin:/vendor/bin',
    'HOME': '/data/local/tmp',
    'TMPDIR': '/data/local/tmp',
    'LANG': 'C.UTF-8',
  };

  /// 后台命令必须带上和前台同一份消毒环境，再附加 owner token。
  /// 只留 token 时 sh 找不到 PATH 里的程序，前台能跑的命令后台会失败。
  static Map<String, String> detachedEnvironment(String ownerToken) => {
        ...sanitizedEnvironment,
        'NEXUS_DAEMON_OWNER': ownerToken,
      };

  @override
  LinuxRuntimeKind get kind => LinuxRuntimeKind.androidShell;

  @override
  bool get supportsShellSyntax => true;

  @override
  bool get supportsInterpreterEvaluation => true;

  @override
  bool get isRunning => _starting || _process != null;

  @override
  Future<LinuxRuntimeInfo> inspect() async => LinuxRuntimeInfo(
        kind: kind,
        label: 'Android Shell',
        available: _isAndroid,
        detail: _isAndroid
            ? '系统自带 shell 可用，但不包含 Alpine/Termux 的完整开发工具链。'
            : 'Android Shell 仅支持 Android。',
        supportsInteractive: false,
        supportsShellSyntax: true,
      );

  @override
  Future<CommandResult> run(
    LinuxCommandRequest request, {
    required String workingDirectory,
    required Duration timeout,
  }) async {
    if (!_isAndroid) {
      return const CommandResult(
        output: '[android-shell] 该运行时仅支持 Android。',
        exitCode: 127,
      );
    }

    if (isRunning) {
      return const CommandResult(
        output: '[android-shell] 已有命令正在运行。',
        exitCode: 125,
      );
    }
    _starting = true;
    _stopRequested = false;
    _foregroundTermination = null;
    final output = StringBuffer();
    var timedOut = false;
    try {
      final process = await _launch(
        request,
        workingDirectory: workingDirectory,
        environment: sanitizedEnvironment,
      );
      _process = process;
      _starting = false;
      final stdout = _collect(process.stdout, output);
      final stderr = _collect(process.stderr, output, prefix: 'stderr: ');
      _cancelForegroundOutput = () async {
        await Future.wait([stdout.cancel(), stderr.cancel()]);
      };
      if (_stopRequested) stop();
      // EOF is part of command completion: a child can retain a pipe after sh
      // has exited. Bound both exit and output, then cancel remaining readers.
      final exitCode = await _waitForOutput(process, stdout, stderr)
          .timeout(timeout, onTimeout: () async {
        timedOut = true;
        await (_foregroundTermination ??= _terminateForeground(process));
        return 124;
      });
      final suffix = timedOut ? '\n命令超时，已终止进程。' : '';
      return CommandResult(
        output: '${output.toString()}$suffix',
        exitCode: exitCode,
        timedOut: timedOut,
      );
    } catch (error) {
      final process = _process;
      if (process != null) {
        await (_foregroundTermination ??= _terminateForeground(process));
      }
      return CommandResult(
        output: '[android-shell] 启动命令失败：$error',
        exitCode: 127,
      );
    } finally {
      // stop() is synchronous, but run() must not finish before escalation.
      await _foregroundTermination;
      await _cancelForegroundOutput?.call();
      _cancelForegroundOutput = null;
      _process = null;
      _starting = false;
      _stopRequested = false;
      _foregroundTermination = null;
    }
  }

  @override
  void stop() {
    if (!isRunning) return;
    _stopRequested = true;
    final process = _process;
    if (process == null) return;
    _foregroundTermination ??= _terminateForeground(process);
  }

  Future<bool> _terminateForeground(Process process) async {
    final signaled = await _terminate(process.pid, process: process);
    await _cancelForegroundOutput?.call();
    return signaled;
  }

  static Future<int> _waitForOutput(
    Process process,
    _ShellOutputDrain stdout,
    _ShellOutputDrain stderr,
  ) async {
    final results = await Future.wait<int>([
      process.exitCode,
      stdout.done.then((_) => 0),
      stderr.done.then((_) => 0),
    ], eagerError: true);
    return results.first;
  }

  @override
  Future<DetachedCommandHandle?> startDetached(
    LinuxCommandRequest request, {
    required String workingDirectory,
    required Duration timeout,
    required String ownerToken,
    required String logPath,
  }) async {
    if (!_isAndroid) return null;
    final log = File(logPath);
    await log.parent.create(recursive: true);
    if (await log.exists()) await log.delete();
    try {
      final process = await _launch(
        request,
        workingDirectory: workingDirectory,
        environment: detachedEnvironment(ownerToken),
      );
      final sink = log.openWrite(mode: FileMode.writeOnlyAppend);
      final stdoutDone = _pipeToFile(process.stdout, sink);
      final stderrDone = _pipeToFile(process.stderr, sink, prefix: 'stderr: ');
      final completion = () async {
        var timedOut = false;
        var exitCode = 127;
        try {
          exitCode = await _waitForOutput(process, stdoutDone, stderrDone)
              .timeout(timeout, onTimeout: () async {
            timedOut = true;
            await _terminate(process.pid, process: process);
            await Future.wait([stdoutDone.cancel(), stderrDone.cancel()]);
            return 124;
          });
        } catch (_) {
          timedOut = true;
          await _terminate(process.pid, process: process);
        }
        await Future.wait([stdoutDone.cancel(), stderrDone.cancel()]);
        await sink.flush();
        await sink.close();
        return CommandResult(
          output: await _readLog(log),
          exitCode: exitCode,
          timedOut: timedOut,
        );
      }();
      return DetachedCommandHandle(pid: process.pid, completion: completion);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> verifyDetached(int pid, String ownerToken) async {
    if (!Platform.isAndroid || !_isAndroid || pid <= 0 || ownerToken.isEmpty) {
      return false;
    }
    final proc = Directory('/proc/$pid');
    if (!proc.existsSync()) return false;
    try {
      final environment =
          String.fromCharCodes(await File('/proc/$pid/environ').readAsBytes());
      return environment
          .split('\u0000')
          .contains('NEXUS_DAEMON_OWNER=$ownerToken');
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> stopDetached(int pid, String ownerToken) async {
    if (!await verifyDetached(pid, ownerToken)) return false;
    return _terminate(pid);
  }

  /// setsid 会让 shell 成为进程组组长，超时后 kill(-pid) 才能带走管道和孙进程。
  /// 没有 setsid 时退回按 /proc 子进程树发送信号。
  Future<Process> _launch(
    LinuxCommandRequest request, {
    required String workingDirectory,
    required Map<String, String> environment,
  }) {
    final shell = _shellBinary(request.shell);
    final launcher = _groupLauncher;
    if (launcher != null) {
      return _processStarter(
        launcher,
        [shell, '-c', request.commandLine],
        workingDirectory: workingDirectory,
        environment: environment,
        includeParentEnvironment: false,
        runInShell: false,
      );
    }
    return _processStarter(
      shell,
      ['-c', request.commandLine],
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: false,
      runInShell: false,
    );
  }

  Future<bool> _terminate(int pid, {Process? process}) {
    if (pid <= 0) return Future.value(false);
    return _terminations.putIfAbsent(
      pid,
      () => _terminateTree(pid, process: process).whenComplete(() {
        _terminations.remove(pid);
      }),
    );
  }

  Future<bool> _terminateTree(int pid, {Process? process}) async {
    final leader = _isGroupLeader(pid) ||
        // With our normal-mode setsid launch, the group ID remains the original
        // PID even after its shell exits while descendants retain output pipes.
        (_groupLauncher != null && !_isProcessAlive(pid) && _isGroupAlive(pid));
    // Snapshot BEFORE SIGTERM: children may be reparented as soon as sh exits.
    final children = _descendants(pid);
    final identities = {
      for (final target in [pid, ...children]) target: _safeStartTime(target),
    };
    bool sameProcess(int target) {
      final before = identities[target];
      return before == null || _safeStartTime(target) == before;
    }

    var signaled = false;
    if (leader) {
      signaled = _send(-pid, ProcessSignal.sigterm);
    }
    // Also handle descendants which have moved into their own process group.
    for (final child in children) {
      signaled = _send(child, ProcessSignal.sigterm) || signaled;
    }
    signaled = _signalRoot(pid, process, ProcessSignal.sigterm) || signaled;
    if (killGrace > Duration.zero) await Future<void>.delayed(killGrace);

    // A process group can outlive its leader. Never gate this on root liveness.
    // If the PID was reused for a different root, do not signal its new group.
    if (leader &&
        (!_isProcessAlive(pid) || sameProcess(pid)) &&
        _isGroupAlive(pid)) {
      _send(-pid, ProcessSignal.sigkill);
    }
    for (final child in children) {
      if (_isProcessAlive(child) && sameProcess(child)) {
        _send(child, ProcessSignal.sigkill);
      }
    }
    // A lone shell that ignores TERM must also receive KILL.
    if (_isProcessAlive(pid) && sameProcess(pid)) {
      for (final child in _descendants(pid)) {
        if (!identities.containsKey(child)) {
          _send(child, ProcessSignal.sigkill);
        }
      }
      _signalRoot(pid, process, ProcessSignal.sigkill);
    }
    return signaled;
  }

  bool _signalRoot(int pid, Process? process, ProcessSignal signal) {
    if (process != null) {
      try {
        return process.kill(signal);
      } catch (_) {
        // A process may exit between the liveness check and signal delivery.
        // Return false so callers do not treat the failed signal as success.
      }
      return false;
    }
    if (pid > 0) return _send(pid, signal);
    return false;
  }

  bool _send(int pid, ProcessSignal signal) {
    try {
      return _signalSender(pid, signal);
    } catch (_) {
      // Unsupported signals or permission failures are reported as a failed
      // delivery; cleanup continues for other owned descendants.
    }
    return false;
  }

  List<int> _descendants(int pid) {
    final out = <int>[];
    final visited = <int>{pid};
    void walk(int current) {
      for (final child in _readChildren(current)) {
        if (child <= 0 || !visited.add(child)) continue;
        walk(child);
        out.add(child);
      }
    }

    walk(pid);
    return out;
  }

  static bool _safeGroupLeader(int pid) {
    if (!Platform.isAndroid) return false;
    return _pidIsGroupLeader(pid);
  }

  static bool _safeGroupAlive(int groupId) {
    if (!Platform.isAndroid || groupId <= 0) return false;
    try {
      for (final entry in Directory('/proc').listSync()) {
        final name = entry.path.split('/').last;
        if (int.tryParse(name) == null) continue;
        try {
          final fields =
              _statFields(File('${entry.path}/stat').readAsStringSync());
          if (fields.length > 2 && int.tryParse(fields[2]) == groupId) {
            return true;
          }
        } catch (_) {
          // Processes can disappear while /proc is being enumerated.
        }
      }
    } catch (_) {
      // Android may deny /proc enumeration. Fail closed: never guess a group
      // is alive or broaden the signal target when ownership cannot be checked.
    }
    return false;
  }

  static List<String> _statFields(String stat) {
    final end = stat.lastIndexOf(')');
    if (end < 0) return const [];
    return stat.substring(end + 1).trim().split(RegExp(r'\s+'));
  }

  static String? _safeStartTime(int pid) {
    if (!Platform.isAndroid || pid <= 0) return null;
    try {
      final fields = _statFields(File('/proc/$pid/stat').readAsStringSync());
      // Field 22; the suffix starts with field 3 (state).
      return fields.length > 19 ? fields[19] : null;
    } catch (_) {
      return null;
    }
  }

  static bool _safeAlive(int pid) {
    if (!Platform.isAndroid) return false;
    return _pidIsAlive(pid);
  }

  static List<int> _safeChildren(int pid) {
    if (!Platform.isAndroid) return const [];
    return _pidChildren(pid);
  }

  /// /proc/pid/stat 的 comm 可以含括号。进程组号是最后一个 ) 之后的第 3 个字段。
  static bool pidIsGroupLeaderStat(String stat, int pid) {
    final end = stat.lastIndexOf(')');
    if (end < 0 || end + 2 >= stat.length) return false;
    final fields = stat.substring(end + 2).split(' ');
    if (fields.length < 3) return false;
    return int.tryParse(fields[2]) == pid;
  }

  static bool _pidIsGroupLeader(int pid) {
    try {
      return pidIsGroupLeaderStat(
          File('/proc/$pid/stat').readAsStringSync(), pid);
    } catch (_) {
      return false;
    }
  }

  static bool _pidIsAlive(int pid) {
    try {
      return Directory('/proc/$pid').existsSync();
    } catch (_) {
      return false;
    }
  }

  static List<int> _pidChildren(int pid) {
    try {
      final raw = File('/proc/$pid/task/$pid/children').readAsStringSync();
      final parts = raw.replaceAll('\n', ' ').replaceAll('\t', ' ').split(' ');
      return [
        for (final part in parts)
          if (int.tryParse(part) != null) int.parse(part),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// 把用户在环境页选择的 Shell 映射到 Android 可用的解释器路径；
  /// 未知或不存在的 Shell 一律回退到系统自带的 /system/bin/sh。
  String _shellBinary(String shell) {
    final bin = switch (shell.trim()) {
      'zsh' => '/system/bin/zsh',
      'bash' => '/system/bin/bash',
      _ => null,
    };
    if (bin != null && File(bin).existsSync()) return bin;
    return '/system/bin/sh';
  }

  _ShellOutputDrain _collect(
    Stream<List<int>> stream,
    StringBuffer output, {
    String prefix = '',
  }) =>
      _ShellOutputDrain(stream, (chunk) {
        if (output.length >= maxOutputBytes) return;
        final text = String.fromCharCodes(chunk);
        if (text.isEmpty) return;
        final remaining = maxOutputBytes - output.length;
        final body =
            text.length > remaining ? text.substring(0, remaining) : text;
        output.write('$prefix$body');
      }, onDone: () {
        if (output.length >= maxOutputBytes) output.write('\n[输出已截断]');
      });

  _ShellOutputDrain _pipeToFile(Stream<List<int>> stream, IOSink sink,
          {String prefix = ''}) =>
      _ShellOutputDrain(stream, (chunk) {
        sink.write(prefix);
        sink.add(chunk);
      });

  Future<String> _readLog(File log) async {
    try {
      return await log.readAsString();
    } catch (_) {
      return '';
    }
  }
}

/// Cancelling a pipe reader must also resolve its completion future. Using an
/// async-for collector alone leaves the caller waiting for inherited pipe EOF.
class _ShellOutputDrain {
  _ShellOutputDrain(Stream<List<int>> stream, void Function(List<int>) onData,
      {void Function()? onDone})
      : _onDone = onDone {
    _subscription =
        stream.listen(onData, onError: (Object error, StackTrace stack) {
      if (!_done.isCompleted) _done.completeError(error, stack);
    }, onDone: _finish, cancelOnError: true);
  }

  final _done = Completer<void>();
  final void Function()? _onDone;
  late final StreamSubscription<List<int>> _subscription;
  Future<void>? _cancellation;

  Future<void> get done => _done.future;

  void _finish() {
    if (_done.isCompleted) return;
    _onDone?.call();
    _done.complete();
  }

  Future<void> cancel() => _cancellation ??= () async {
        await _subscription.cancel();
        _finish();
      }();
}
