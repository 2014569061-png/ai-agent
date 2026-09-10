import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

import '../../domain/models.dart';
import '../../domain/tool_codes.dart';
import '../../domain/tool_result.dart';
import '../terminal/linux_runtime.dart';
import '../terminal/linux_runtime_factory.dart';
import '../terminal/daemon_persistence.dart';
import 'tool_registry.dart';
import 'workspace_tools.dart';

export '../terminal/linux_runtime.dart'
    show
        CommandResult,
        LinuxCommandRequest,
        LinuxRuntimeAdapter,
        LinuxRuntimeInfo,
        LinuxRuntimeKind;
export '../terminal/daemon_persistence.dart'
    show TerminalDaemonPersistence, TerminalDaemonRecord;

class TerminalCommandService {
  TerminalCommandService({
    required this.workspacePath,
    LinuxRuntimeAdapter? runtime,
    String? shellType,
    String? defaultWorkingDirectory,
    TerminalDaemonPersistence? daemonPersistence,
  })  : _runtime = runtime ?? createDefaultLinuxRuntime(),
        _shellTypeOverride = shellType,
        _defaultWorkDirOverride = defaultWorkingDirectory,
        _daemonPersistence = daemonPersistence ?? TerminalDaemonPersistence() {
    unawaited(_loadEnvironmentSettings());
    _daemonReady = _restoreDaemons();
  }

  static const defaultTimeout = Duration(seconds: 30);

  /// 与 Linux 环境页共用同一组 SharedPreferences Key，确保用户在此页面做的
  /// 选择能真实作用到终端执行。
  static const _shellTypeKey = 'settings.linux.shell_type';
  static const _workDirKey = 'settings.linux.default_work_dir';

  final String workspacePath;
  final LinuxRuntimeAdapter _runtime;
  final String? _shellTypeOverride;
  final String? _defaultWorkDirOverride;
  final TerminalDaemonPersistence _daemonPersistence;

  final Map<String, _TerminalSession> _sessions = {};
  final Map<String, _TerminalJob> _jobs = {};
  final Map<String, _TerminalDaemon> _daemons = {};
  Future<void> _serialTail = Future<void>.value();
  late final Future<void> _daemonReady;

  String _shellType = 'bash';
  String? _defaultWorkDir;

  static const _allowedCommands = {
    'cat',
    'dart',
    'dir',
    'findstr',
    'flutter',
    'git',
    'gradle',
    'gradlew',
    'ls',
    'node',
    'npm',
    'pip',
    'python',
    'python3',
    'pwd',
    'rg',
    'type',
  };

  /// 解释器类命令的内联求值参数可以执行任意代码（如
  /// `python -c "import os; ..."`），实质绕过工作区沙箱，予以拦截。
  static const _inlineEvalFlags = {
    'python': {'-c'},
    'python3': {'-c'},
    'node': {'-e', '--eval', '-p', '--print'},
  };

  bool get isRunning => _runtime.isRunning;

  LinuxRuntimeAdapter get runtime => _runtime;

  Future<LinuxRuntimeInfo> inspectRuntime() => _runtime.inspect();

  /// 创建可复用的轻量终端会话。会话只持有工作目录与任务索引，真正的
  /// 进程仍由 Runtime 串行执行，避免 Android 前台状态下并发碰撞。
  Future<TerminalSessionSnapshot> openSession(
      {String? workingDirectory}) async {
    final cwd = _resolveWorkingDirectory(workingDirectory) ??
        _resolveWorkingDirectory(_defaultWorkDir) ??
        _resolveWorkingDirectory('.') ??
        workspacePath;
    final id =
        'session-${DateTime.now().microsecondsSinceEpoch}-${_sessions.length}';
    final session = _TerminalSession(id: id, cwd: cwd);
    _sessions[id] = session;
    return session.snapshot;
  }

  TerminalSessionSnapshot? session(String id) => _sessions[id]?.snapshot;

  Future<TerminalSessionExecution> executeSession({
    required String sessionId,
    required String command,
    Duration timeout = defaultTimeout,
    bool asynchronous = false,
  }) async {
    final session = _sessions[sessionId];
    if (session == null) {
      return const TerminalSessionExecution(
          ok: false, code: ToolCodes.notFound, message: '终端会话不存在');
    }
    final parsedCd = _parseLeadingCd(command, session.cwd);
    final future =
        run(command, workingDirectory: session.cwd, timeout: timeout);
    if (asynchronous) {
      final jobId =
          'job-${DateTime.now().microsecondsSinceEpoch}-${_jobs.length}';
      final job = _TerminalJob(
          jobId: jobId, sessionId: sessionId, command: command, future: future);
      _jobs[jobId] = job;
      unawaited(future.then((result) {
        job.result = result;
        job.completed = true;
        if (parsedCd != null &&
            result.exitCode == 0 &&
            !result.timedOut &&
            !result.notExecuted) {
          session.cwd = parsedCd;
        }
      }, onError: (Object error, StackTrace stack) {
        job.error = error.toString();
        job.completed = true;
      }));
      return TerminalSessionExecution(
        ok: true,
        code: ToolCodes.ok,
        message: '异步命令已启动',
        effect: ToolEffect.applied,
        data: {'sessionId': sessionId, 'jobId': jobId, 'cwd': session.cwd},
      );
    }
    final result = await future;
    if (parsedCd != null &&
        result.exitCode == 0 &&
        !result.timedOut &&
        !result.notExecuted) {
      session.cwd = parsedCd;
    }
    return _executionFromResult(sessionId, command, result);
  }

  Future<TerminalSessionExecution> readAsyncResult({
    required String jobId,
    int offsetChars = 0,
    int maxChars = 64000,
  }) async {
    final job = _jobs[jobId];
    if (job == null) {
      return const TerminalSessionExecution(
          ok: false, code: ToolCodes.notFound, message: '异步任务不存在');
    }
    if (!job.completed) {
      return TerminalSessionExecution(
        ok: true,
        code: ToolCodes.ok,
        message: '异步任务仍在运行',
        data: {'jobId': jobId, 'running': true, 'nextOffsetChars': offsetChars},
      );
    }
    final result = job.result;
    if (result == null) {
      return TerminalSessionExecution(
        ok: false,
        code: ToolCodes.outcomeUnknown,
        message: '异步任务结果无法确认，请先检查目标状态',
        data: {'jobId': jobId, 'error': job.error},
        effect: ToolEffect.unknown,
      );
    }
    return _pagedResult(jobId, result, offsetChars, maxChars,
        runningMessage: '异步命令已完成');
  }

  Future<TerminalSessionExecution> closeSession(String sessionId) async {
    if (_sessions.remove(sessionId) == null) {
      return const TerminalSessionExecution(
          ok: false, code: ToolCodes.notFound, message: '终端会话不存在');
    }
    _jobs.removeWhere((_, job) => job.sessionId == sessionId && !job.completed);
    return const TerminalSessionExecution(
        ok: true, code: ToolCodes.ok, message: '终端会话已关闭');
  }

  Future<TerminalSessionExecution> startDaemon({
    required String sessionId,
    required String command,
    Duration timeout = const Duration(hours: 24),
  }) async {
    await _daemonReady;
    if (_daemons.length >= 8) {
      return const TerminalSessionExecution(
          ok: false, code: ToolCodes.tooLarge, message: '后台进程数量已达上限 8');
    }
    final session = _sessions[sessionId];
    if (session == null) {
      return const TerminalSessionExecution(
          ok: false, code: ToolCodes.notFound, message: '终端会话不存在');
    }
    final daemonId =
        'daemon-${DateTime.now().microsecondsSinceEpoch}-${_daemons.length}';
    final ownerToken = _newOwnerToken();
    final logPath = await _daemonPersistence.logPath(daemonId);
    DetachedCommandHandle? detached;
    final runtime = _runtime;
    final prepared = _prepareDetachedCommand(
        command, session.cwd, timeout, runtime.supportsShellSyntax);
    if (prepared != null && runtime is DetachedLinuxRuntimeAdapter) {
      detached = await (runtime as DetachedLinuxRuntimeAdapter).startDetached(
        prepared.$1,
        workingDirectory: prepared.$2,
        timeout: prepared.$3,
        ownerToken: ownerToken,
        logPath: logPath,
      );
    }
    final future = detached?.completion ??
        run(command, workingDirectory: session.cwd, timeout: timeout);
    final daemon = _TerminalDaemon(
      daemonId: daemonId,
      sessionId: sessionId,
      command: command,
      ownerToken: ownerToken,
      future: future,
      pid: detached?.pid,
      logPath: detached?.logPath ?? logPath,
      runtimeKind: runtime.kind.name,
    );
    _daemons[daemonId] = daemon;
    await _saveDaemons();
    unawaited(future.then((result) {
      daemon.result = result;
      daemon.completed = true;
      unawaited(_saveDaemonOutput(daemon, result));
      unawaited(_saveDaemons());
    }, onError: (Object error, StackTrace stack) {
      daemon.error = error.toString();
      daemon.completed = true;
      unawaited(_saveDaemons());
    }));
    return TerminalSessionExecution(
      ok: true,
      code: ToolCodes.ok,
      message: '后台进程已启动',
      effect: ToolEffect.applied,
      data: {
        'daemonId': daemonId,
        'ownerToken': ownerToken,
        'sessionId': sessionId
      },
    );
  }

  List<Map<String, dynamic>> listDaemons() => _daemons.values
      .map((daemon) => {
            'daemonId': daemon.daemonId,
            'sessionId': daemon.sessionId,
            'command': daemon.command,
            'ownerToken': daemon.ownerToken,
            if (daemon.pid != null) 'pid': daemon.pid,
            if (daemon.logPath != null) 'logPath': daemon.logPath,
            'running': !daemon.completed,
          })
      .toList(growable: false);

  Future<List<Map<String, dynamic>>> listDaemonsAsync() async {
    await _daemonReady;
    await _refreshRestoredDaemons();
    return listDaemons();
  }

  Future<TerminalSessionExecution> daemonLogs(String daemonId,
      {int offsetChars = 0, int maxChars = 64000}) async {
    await _daemonReady;
    final daemon = _daemons[daemonId];
    if (daemon == null) {
      return const TerminalSessionExecution(
          ok: false, code: ToolCodes.notFound, message: '后台进程不存在');
    }
    if (!daemon.completed && daemon.future == null) {
      await _refreshDaemon(daemon);
    }
    if (!daemon.completed) {
      final partial = await _readDaemonLog(daemon);
      final page = _pageText(partial, offsetChars, maxChars);
      return TerminalSessionExecution(
        ok: true,
        code: ToolCodes.ok,
        message: '后台进程仍在运行',
        data: {
          'daemonId': daemonId,
          'running': true,
          'output': page.$1,
          'nextOffsetChars': page.$2,
          'outputTruncated': page.$3,
        },
      );
    }
    final result = daemon.result;
    if (result == null) {
      return const TerminalSessionExecution(
          ok: false,
          code: ToolCodes.outcomeUnknown,
          message: '后台进程结果无法确认',
          effect: ToolEffect.unknown);
    }
    return _pagedResult(daemonId, result, offsetChars, maxChars,
        runningMessage: '后台进程日志已读取');
  }

  Future<TerminalSessionExecution> stopDaemon(String daemonId) async {
    await _daemonReady;
    final daemon = _daemons[daemonId];
    if (daemon == null) {
      return const TerminalSessionExecution(
          ok: false, code: ToolCodes.notFound, message: '后台进程不存在');
    }
    if (!daemon.completed) {
      final pid = daemon.pid;
      final runtime = _runtime;
      if (pid != null && runtime is DetachedLinuxRuntimeAdapter) {
        final stopped = await (runtime as DetachedLinuxRuntimeAdapter)
            .stopDetached(pid, daemon.ownerToken);
        if (!stopped) {
          return const TerminalSessionExecution(
            ok: false,
            code: ToolCodes.outcomeUnknown,
            message: '鏃犳硶璇佹槑 daemon 灞炰簬褰撳墠 App锛屽凡鎷掔粷鍋滄浠ュ厤璇潃 PID',
            effect: ToolEffect.unknown,
          );
        }
      } else {
        stop();
      }
      daemon.stopped = true;
      await _saveDaemons();
      return const TerminalSessionExecution(
          ok: false,
          code: ToolCodes.outcomeUnknown,
          message: '已提交停止请求，最终状态请通过 daemon_logs 确认',
          effect: ToolEffect.unknown);
    }
    return const TerminalSessionExecution(
        ok: true, code: ToolCodes.ok, message: '后台进程已结束');
  }

  Future<void> _restoreDaemons() async {
    final records = await _daemonPersistence.load();
    for (final record in records) {
      if (_daemons.containsKey(record.daemonId)) continue;
      final daemon = _TerminalDaemon(
        daemonId: record.daemonId,
        sessionId: record.sessionId,
        command: record.command,
        ownerToken: record.ownerToken,
        future: null,
        pid: record.pid,
        logPath: record.logPath,
        runtimeKind: record.runtimeKind,
        startedAt: record.startedAt,
        completed: record.completed,
      );
      if (record.completed) {
        daemon.result = CommandResult(
          output: await _readDaemonLog(daemon),
          exitCode: record.exitCode ?? 0,
          timedOut: record.timedOut,
        );
        daemon.error = record.error;
      }
      _daemons[daemon.daemonId] = daemon;
    }
  }

  Future<void> _refreshRestoredDaemons() async {
    for (final daemon in _daemons.values.toList(growable: false)) {
      if (!daemon.completed && daemon.future == null) {
        await _refreshDaemon(daemon);
      }
    }
  }

  Future<void> _refreshDaemon(_TerminalDaemon daemon) async {
    if (daemon.completed) return;
    final pid = daemon.pid;
    final runtime = _runtime;
    if (pid == null || runtime is! DetachedLinuxRuntimeAdapter) {
      daemon.completed = true;
      daemon.result = CommandResult(
        output: await _readDaemonLog(daemon),
        exitCode: 124,
        timedOut: true,
      );
      await _saveDaemons();
      return;
    }
    final alive = await (runtime as DetachedLinuxRuntimeAdapter)
        .verifyDetached(pid, daemon.ownerToken);
    if (alive) return;
    final completedResult = await _readDaemonCompletion(daemon);
    if (completedResult != null) {
      daemon.completed = true;
      daemon.result = completedResult;
      await _saveDaemons();
      return;
    }
    daemon.completed = true;
    daemon.result = CommandResult(
      output: await _readDaemonLog(daemon),
      exitCode: 124,
      timedOut: true,
    );
    await _saveDaemons();
  }

  Future<void> _saveDaemons() async {
    try {
      await _daemonPersistence.save(_daemons.values.map(_toDaemonRecord));
    } catch (_) {
      // 元数据写入失败不能改变前台工具结果；下次启动仍会重新尝试读取。
    }
  }

  TerminalDaemonRecord _toDaemonRecord(_TerminalDaemon daemon) {
    final result = daemon.result;
    return TerminalDaemonRecord(
      daemonId: daemon.daemonId,
      sessionId: daemon.sessionId,
      command: daemon.command,
      cwd: _sessions[daemon.sessionId]?.cwd ?? workspacePath,
      ownerToken: daemon.ownerToken,
      startedAt: daemon.startedAt,
      runtimeKind: daemon.runtimeKind,
      pid: daemon.pid,
      logPath: daemon.logPath,
      completed: daemon.completed,
      exitCode: result?.exitCode,
      timedOut: result?.timedOut ?? false,
      error: daemon.error,
    );
  }

  Future<void> _saveDaemonOutput(
      _TerminalDaemon daemon, CommandResult result) async {
    final path = daemon.logPath;
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(result.output, flush: true);
    } catch (_) {}
  }

  Future<String> _readDaemonLog(_TerminalDaemon daemon) async {
    final path = daemon.logPath;
    if (path == null || path.isEmpty) return daemon.result?.output ?? '';
    try {
      final file = File(path);
      if (!await file.exists()) return daemon.result?.output ?? '';
      return await file.readAsString();
    } catch (_) {
      return daemon.result?.output ?? '';
    }
  }

  Future<CommandResult?> _readDaemonCompletion(_TerminalDaemon daemon) async {
    final path = daemon.logPath;
    if (path == null || path.isEmpty) return null;
    try {
      final file = File('$path.exit.json');
      if (!await file.exists()) return null;
      final value = jsonDecode(await file.readAsString());
      if (value is! Map) return null;
      return CommandResult(
        output: await _readDaemonLog(daemon),
        exitCode: (value['exitCode'] as num?)?.toInt() ?? 127,
        timedOut: value['timedOut'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  (String, int?, bool) _pageText(String text, int offset, int maxChars) {
    final start = offset.clamp(0, text.length).toInt();
    final end =
        (start + maxChars.clamp(1, 64000)).clamp(start, text.length).toInt();
    return (
      text.substring(start, end),
      end < text.length ? end : null,
      end < text.length,
    );
  }

  String _newOwnerToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return 'nexus-${bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join()}';
  }

  (LinuxCommandRequest, String, Duration)? _prepareDetachedCommand(
      String commandLine,
      String workingDirectory,
      Duration timeout,
      bool supportsShellSyntax) {
    final parsed = _parse(commandLine);
    if (parsed.isEmpty) return null;
    final command = _normalizeCommand(parsed.first);
    if (parsed.first.contains('/') || parsed.first.contains('\\')) return null;
    final cwd = _resolveWorkingDirectory(workingDirectory);
    if (cwd == null) return null;
    if (_inlineEvalFlag(command, parsed.skip(1)) != null) return null;
    if (!supportsShellSyntax) {
      if (!_allowedCommands.contains(command) || _hasShellSyntax(commandLine)) {
        return null;
      }
    }
    final request = LinuxCommandRequest(
      commandLine: commandLine,
      executable: parsed.first,
      normalizedCommand: command,
      arguments: List<String>.unmodifiable(parsed.skip(1)),
      shell: _shellType,
    );
    final runtimeTimeout = supportsShellSyntax && timeout == defaultTimeout
        ? const Duration(minutes: 5)
        : timeout;
    return (request, cwd, runtimeTimeout);
  }

  Future<CommandResult> run(String commandLine,
      {String? workingDirectory, Duration timeout = defaultTimeout}) async {
    final parsed = _parse(commandLine);
    if (parsed.isEmpty) {
      return const CommandResult(
          output: '请输入要执行的命令', exitCode: 2, notExecuted: true);
    }
    final command = _normalizeCommand(parsed.first);
    if (parsed.first.contains('/') || parsed.first.contains('\\')) {
      return const CommandResult(
          output: '不允许通过路径指定可执行文件', exitCode: 126, notExecuted: true);
    }

    // 未显式指定工作目录时，尝试使用用户在环境页配置的默认工作目录；若该目录
    // 不在工作区内（如桌面端的 Termux 路径）则回退到工作区根目录。
    final String? cwd;
    if (workingDirectory == null || workingDirectory.trim().isEmpty) {
      final configured = _resolveWorkingDirectory(_defaultWorkDir);
      cwd = configured ?? _resolveWorkingDirectory('.');
    } else {
      cwd = _resolveWorkingDirectory(workingDirectory);
    }
    if (cwd == null) {
      return const CommandResult(
          output: '工作目录必须位于当前工作区内', exitCode: 126, notExecuted: true);
    }

    final request = LinuxCommandRequest(
      commandLine: commandLine,
      executable: parsed.first,
      normalizedCommand: command,
      arguments: List<String>.unmodifiable(parsed.skip(1)),
      shell: _shellType,
    );

    final evalFlag = _inlineEvalFlag(command, parsed.skip(1));
    // Interpreter snippets can escape the workspace even when the runtime
    // itself supports them. Require a script file inside the workspace.
    if (evalFlag != null) {
      return CommandResult(
          output: '不允许使用内联求值参数（$evalFlag）：解释器子进程不受工作区沙箱约束，'
              '请改为执行工作区内的脚本文件',
          exitCode: 126,
          notExecuted: true);
    }

    // Android 的内置 Alpine/Termux Adapter 提供完整 shell；桌面/受限进程
    // Adapter 继续使用命令白名单、内联求值拦截和 shell 语法拦截。
    if (!_runtime.supportsShellSyntax) {
      if (!_allowedCommands.contains(command)) {
        return CommandResult(
            output: '命令不在允许列表中：$command', exitCode: 126, notExecuted: true);
      }
      if (_hasShellSyntax(commandLine)) {
        return const CommandResult(
            output: '为安全起见，不支持 shell 管道、重定向、命令连接或变量展开',
            exitCode: 126,
            notExecuted: true);
      }
    }

    final runtimeTimeout =
        _runtime.supportsShellSyntax && timeout == defaultTimeout
            ? const Duration(minutes: 5)
            : timeout;
    // Runtime 可能持有同一个 shell / PRoot 进程；即使上层未来出现多个
    // 调用者，也必须按提交顺序串行进入，避免 cwd 和输出互相污染。
    return _serialize(() =>
        _runtime.run(request, workingDirectory: cwd!, timeout: runtimeTimeout));
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _serialTail.then((_) => operation());
    _serialTail = result.then<void>((_) {}, onError: (_, __) {});
    return result;
  }

  void stop() => _runtime.stop();

  TerminalSessionExecution _executionFromResult(
      String sessionId, String command, CommandResult result) {
    final ok = result.exitCode == 0 && !result.timedOut && !result.notExecuted;
    return TerminalSessionExecution(
      ok: ok,
      code: result.notExecuted
          ? ToolCodes.permissionRequired
          : result.timedOut
              ? ToolCodes.outcomeUnknown
              : ok
                  ? ToolCodes.ok
                  : ToolCodes.toolError,
      message:
          result.timedOut ? '命令超时，副作用无法确认' : '命令已结束（退出码 ${result.exitCode}）',
      effect: result.notExecuted
          ? ToolEffect.none
          : result.timedOut
              ? ToolEffect.unknown
              : ToolEffect.applied,
      data: {
        'sessionId': sessionId,
        'command': command,
        'exitCode': result.exitCode,
        'output': result.output,
        'cwd': _sessions[sessionId]?.cwd,
      },
    );
  }

  TerminalSessionExecution _pagedResult(
      String id, CommandResult result, int offsetChars, int maxChars,
      {required String runningMessage}) {
    final output = result.output;
    final start = offsetChars.clamp(0, output.length).toInt();
    final end =
        (start + maxChars.clamp(1, 64000)).clamp(start, output.length).toInt();
    final timedOut = result.timedOut;
    final ok = result.exitCode == 0 && !timedOut && !result.notExecuted;
    return TerminalSessionExecution(
      ok: ok,
      code: result.notExecuted
          ? ToolCodes.permissionRequired
          : timedOut
              ? ToolCodes.outcomeUnknown
              : ok
                  ? ToolCodes.ok
                  : ToolCodes.toolError,
      message: timedOut
          ? '后台命令超时，副作用无法确认'
          : '$runningMessage（退出码 ${result.exitCode}）',
      data: {
        'id': id,
        'running': false,
        'exitCode': result.exitCode,
        'output': output.substring(start, end),
        'nextOffsetChars': end < output.length ? end : null,
        'outputTruncated': end < output.length,
      },
      effect: result.notExecuted
          ? ToolEffect.none
          : timedOut
              ? ToolEffect.unknown
              : ToolEffect.applied,
    );
  }

  String? _parseLeadingCd(String command, String currentCwd) {
    final match = RegExp(
      r'''^\s*cd\s+(?:"([^"]+)"|'([^']+)'|([^\s;&]+))\s*(?:&&|;)''',
    ).firstMatch(command);
    if (match == null) return null;
    final raw = match.group(1) ?? match.group(2) ?? match.group(3) ?? '';
    return _resolveWorkingDirectory(
        p.isAbsolute(raw) ? raw : p.join(currentCwd, raw));
  }

  /// 读取 Linux 环境页保存的 Shell 类型与默认工作目录。显式传入的覆盖优先；
  /// 其余情况回退到 SharedPreferences，最终回退到默认值。
  Future<void> _loadEnvironmentSettings() async {
    final shell = _shellTypeOverride;
    final workDir = _defaultWorkDirOverride;
    if (shell != null) _shellType = shell;
    if (workDir != null) _defaultWorkDir = workDir;
    if (shell != null && workDir != null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (_shellTypeOverride == null) {
        _shellType = prefs.getString(_shellTypeKey) ?? 'bash';
      }
      if (_defaultWorkDirOverride == null) {
        final dir = prefs.getString(_workDirKey);
        if (dir != null && dir.trim().isNotEmpty) {
          _defaultWorkDir = dir.trim();
        }
      }
    } catch (_) {
      // SharedPreferences 不可用（例如测试环境）时保留默认值，不影响执行。
    }
  }

  String? _resolveWorkingDirectory(String? requested) {
    final sandbox = WorkspaceSandbox(workspacePath);
    try {
      final path =
          requested == null || requested.trim().isEmpty ? '.' : requested;
      final resolved = sandbox.resolvePath(path);
      if (!Directory(resolved).existsSync()) return null;
      return resolved;
    } catch (_) {
      return null;
    }
  }

  String _normalizeCommand(String value) {
    final base = value.replaceAll('\\', '/').split('/').last.toLowerCase();
    return base.endsWith('.exe') ? base.substring(0, base.length - 4) : base;
  }

  bool _hasShellSyntax(String value) => RegExp(r'[|&;<>`$()]').hasMatch(value);

  /// 命中内联求值参数时返回该参数（用于拒绝提示），否则返回 null。
  String? _inlineEvalFlag(String command, Iterable<String> args) {
    final flags = _inlineEvalFlags[command];
    if (flags == null) return null;
    for (final argument in args) {
      if (flags.contains(argument)) return argument;
    }
    return null;
  }

  List<String> _parse(String value) {
    final result = <String>[];
    final buffer = StringBuffer();
    String? quote;
    for (var i = 0; i < value.length; i++) {
      final char = value[i];
      if ((char == '"' || char == "'") && (quote == null || quote == char)) {
        quote = quote == null ? char : null;
      } else if (char.trim().isEmpty && quote == null) {
        if (buffer.isNotEmpty) {
          result.add(buffer.toString());
          buffer.clear();
        }
      } else {
        buffer.write(char);
      }
    }
    if (quote != null) return const [];
    if (buffer.isNotEmpty) result.add(buffer.toString());
    return result;
  }
}

class TerminalSessionSnapshot {
  const TerminalSessionSnapshot({required this.id, required this.cwd});

  final String id;
  final String cwd;

  Map<String, dynamic> toJson() => {'sessionId': id, 'cwd': cwd};
}

class TerminalSessionExecution {
  const TerminalSessionExecution({
    required this.ok,
    required this.code,
    required this.message,
    this.effect = ToolEffect.none,
    this.data,
  });

  final bool ok;
  final String code;
  final String message;
  final ToolEffect effect;
  final Map<String, dynamic>? data;
}

class _TerminalSession {
  _TerminalSession({required this.id, required this.cwd});

  final String id;
  String cwd;

  TerminalSessionSnapshot get snapshot =>
      TerminalSessionSnapshot(id: id, cwd: cwd);
}

class _TerminalJob {
  _TerminalJob({
    required this.jobId,
    required this.sessionId,
    required this.command,
    required this.future,
  });

  final String jobId;
  final String sessionId;
  final String command;
  final Future<CommandResult> future;
  CommandResult? result;
  String? error;
  bool completed = false;
}

class _TerminalDaemon {
  _TerminalDaemon({
    required this.daemonId,
    required this.sessionId,
    required this.command,
    required this.ownerToken,
    required this.future,
    DateTime? startedAt,
    this.pid,
    this.logPath,
    this.runtimeKind = 'unknown',
    this.completed = false,
  }) : startedAt = startedAt ?? DateTime.now();

  final String daemonId;
  final String sessionId;
  final String command;
  final String ownerToken;
  final Future<CommandResult>? future;
  final DateTime startedAt;
  final int? pid;
  final String? logPath;
  final String runtimeKind;
  CommandResult? result;
  String? error;
  bool completed;
  bool stopped = false;
}

class TerminalCommandTool implements AgentTool {
  TerminalCommandTool({required this.service});
  final TerminalCommandService service;

  @override
  final manifest = const UnifiedTool(
    name: 'terminal',
    description: '在当前工作区内运行受限的终端命令（git/python/node 等）。命令会经过用户确认；'
        '禁止 shell 管道、重定向与解释器内联求值参数（如 python -c）。'
        '注意：python/node 等解释器实际执行的脚本代码本身不受工作区沙箱限制。'
        'Android 上优先使用内置 Alpine Linux（PRoot + ARM64 rootfs），失败时自动回退到 Termux，'
        '最后使用 Android Shell。内置 rootfs 提供 Linux shell 与基础 BusyBox 工具；Go/Git/Node/Python 等'
        '开发工具需要在 Alpine 中通过 apk 安装，或在需要完整工具链时配置 Termux。',
    parametersSchema: {
      'type': 'object',
      'properties': {
        'action': {
          'type': 'string',
          'enum': [
            'open',
            'exec',
            'open_and_exec',
            'read_async_result',
            'close',
            'daemon_start',
            'daemon_list',
            'daemon_logs',
            'daemon_stop',
          ],
          'description': '会话动作；省略时按 exec 兼容旧调用',
        },
        'command': {
          'type': 'string',
          'description':
              '命令及参数，例如 git status 或 dart analyze；exec/daemon_start 必填',
        },
        'workingDirectory': {'type': 'string', 'description': '工作区内的相对目录，可选'},
        'working_directory': {'type': 'string'},
        'sessionId': {'type': 'string'},
        'session_id': {'type': 'string'},
        'jobId': {'type': 'string'},
        'job_id': {'type': 'string'},
        'daemonId': {'type': 'string'},
        'daemon_id': {'type': 'string'},
        'asynchronous': {'type': 'boolean'},
        'async': {'type': 'boolean'},
        'offsetChars': {'type': 'integer', 'minimum': 0},
        'offset_chars': {'type': 'integer', 'minimum': 0},
        'maxChars': {'type': 'integer', 'minimum': 1, 'maximum': 64000},
        'max_chars': {'type': 'integer', 'minimum': 1, 'maximum': 64000},
        'timeoutSeconds': {'type': 'integer', 'minimum': 1, 'maximum': 86400},
        'timeout_seconds': {'type': 'integer', 'minimum': 1, 'maximum': 86400},
      },
      'required': [],
    },
    risk: ToolRisk.requiresConfirmation,
    // 命令类工具会真实执行编译、拉包、跑测试等长任务（工具自身可用
    // timeoutSeconds 参数把单条命令放宽到最长 86400s）。若沿用默认 120s 的
    // 外层超时，会在命令仍在正常执行时被 AgentExecutor 提前判为 TIMEOUT。
    // 这里把外层上限放宽到 10 分钟：既覆盖绝大多数合理的长命令，又保留一个
    // 兜底，避免进程卡死时无限期挂住整个回合。
    timeout: Duration(minutes: 10),
  );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    try {
      final actionValue = arguments['action']?.toString().trim().toLowerCase();
      final action =
          actionValue == null || actionValue.isEmpty ? 'exec' : actionValue;
      final command = (arguments['command']?.toString() ?? '').trim();
      final cwd =
          (arguments['workingDirectory'] ?? arguments['working_directory'])
              ?.toString();
      final sessionId =
          (arguments['sessionId'] ?? arguments['session_id'])?.toString();
      final timeoutSeconds =
          (arguments['timeoutSeconds'] ?? arguments['timeout_seconds']) as num?;
      final timeout = Duration(
        seconds: ((timeoutSeconds?.toInt() ?? 30).clamp(1, 86400)).toInt(),
      );
      final offset =
          (((arguments['offsetChars'] ?? arguments['offset_chars']) as num?)
                      ?.toInt() ??
                  0)
              .clamp(0, 1 << 30)
              .toInt();
      final maxChars =
          (((arguments['maxChars'] ?? arguments['max_chars']) as num?)
                      ?.toInt() ??
                  64000)
              .clamp(1, 64000)
              .toInt();

      switch (action) {
        case 'open':
          final snapshot = await service.openSession(workingDirectory: cwd);
          return ToolResult.success(
            message: '终端会话已打开：${snapshot.id}',
            data: snapshot.toJson(),
          );
        case 'open_and_exec':
          if (command.isEmpty) {
            return ToolResult.failure(
                code: ToolCodes.invalidArguments,
                message: 'open_and_exec 需要 command');
          }
          final snapshot = await service.openSession(workingDirectory: cwd);
          final execution = await service.executeSession(
            sessionId: snapshot.id,
            command: command,
            timeout: timeout,
            asynchronous:
                arguments['asynchronous'] == true || arguments['async'] == true,
          );
          return _fromSessionExecution(execution, extra: {
            'sessionId': snapshot.id,
          });
        case 'exec':
          if (sessionId != null && sessionId.isNotEmpty) {
            if (command.isEmpty) {
              return ToolResult.failure(
                  code: ToolCodes.invalidArguments, message: 'exec 需要 command');
            }
            return _fromSessionExecution(await service.executeSession(
              sessionId: sessionId,
              command: command,
              timeout: timeout,
              asynchronous: arguments['asynchronous'] == true ||
                  arguments['async'] == true,
            ));
          }
          if (command.isEmpty) {
            return ToolResult.failure(
                code: ToolCodes.invalidArguments, message: 'exec 需要 command');
          }
          return _fromCommand(
              await service.run(command,
                  workingDirectory: cwd, timeout: timeout),
              command);
        case 'read_async_result':
          final jobId =
              (arguments['jobId'] ?? arguments['job_id'])?.toString() ?? '';
          if (jobId.isEmpty) {
            return ToolResult.failure(
                code: ToolCodes.invalidArguments,
                message: 'read_async_result 需要 jobId');
          }
          return _fromSessionExecution(await service.readAsyncResult(
              jobId: jobId, offsetChars: offset, maxChars: maxChars));
        case 'close':
          if (sessionId == null || sessionId.isEmpty) {
            return ToolResult.failure(
                code: ToolCodes.invalidArguments,
                message: 'close 需要 sessionId');
          }
          return _fromSessionExecution(await service.closeSession(sessionId));
        case 'daemon_start':
          if (command.isEmpty || sessionId == null || sessionId.isEmpty) {
            return ToolResult.failure(
                code: ToolCodes.invalidArguments,
                message: 'daemon_start 需要 sessionId 和 command');
          }
          return _fromSessionExecution(await service.startDaemon(
              sessionId: sessionId, command: command, timeout: timeout));
        case 'daemon_list':
          final daemons = await service.listDaemonsAsync();
          return ToolResult.success(
              message: '已读取后台进程列表', data: {'daemons': daemons});
        case 'daemon_logs':
          final daemonId =
              (arguments['daemonId'] ?? arguments['daemon_id'])?.toString() ??
                  '';
          if (daemonId.isEmpty) {
            return ToolResult.failure(
                code: ToolCodes.invalidArguments,
                message: 'daemon_logs 需要 daemonId');
          }
          return _fromSessionExecution(await service.daemonLogs(daemonId,
              offsetChars: offset, maxChars: maxChars));
        case 'daemon_stop':
          final daemonId =
              (arguments['daemonId'] ?? arguments['daemon_id'])?.toString() ??
                  '';
          if (daemonId.isEmpty) {
            return ToolResult.failure(
                code: ToolCodes.invalidArguments,
                message: 'daemon_stop 需要 daemonId');
          }
          return _fromSessionExecution(await service.stopDaemon(daemonId));
        default:
          return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: '不支持的 terminal action：$action');
      }
    } catch (e) {
      // 连运行时都没能给出结果：进程可能已启动也可能没有，无法判定。
      return ToolResult.failure(
        code: ToolCodes.toolError,
        message: '命令执行异常：$e；进程可能已启动，'
            '请先检查工作区状态再决定是否重跑',
        effect: ToolEffect.unknown,
      );
    }
  }

  ToolResult _fromCommand(CommandResult result, String command) {
    final text = '退出码：${result.exitCode}\n${result.output}'.trim();
    if (result.notExecuted) {
      return ToolResult.failure(
        code: ToolCodes.permissionRequired,
        message: result.output,
        data: {'command': command, 'exitCode': result.exitCode},
      );
    }
    if (result.timedOut) {
      return ToolResult.failure(
        code: ToolCodes.outcomeUnknown,
        message:
            '命令超时已终止（退出码 ${result.exitCode}）；副作用无法确认，请先检查目标文件或进程状态再决定是否重跑。',
        data: {'command': command, 'output': result.output},
        effect: ToolEffect.unknown,
      );
    }
    return result.succeeded
        ? ToolResult.text(text,
            effect: ToolEffect.applied,
            extra: {'command': command, 'exitCode': result.exitCode})
        : ToolResult.failure(
            code: ToolCodes.toolError,
            message: '命令以退出码 ${result.exitCode} 结束',
            data: {'command': command, 'output': result.output},
            effect: ToolEffect.applied,
          );
  }

  ToolResult _fromSessionExecution(TerminalSessionExecution execution,
      {Map<String, dynamic>? extra}) {
    final data = <String, dynamic>{
      ...?execution.data,
      ...?extra,
    };
    if (execution.ok) {
      return ToolResult.success(
        message: execution.message,
        data: data.isEmpty ? null : data,
        effect: execution.effect,
      );
    }
    return ToolResult.failure(
      code: execution.code,
      message: execution.message,
      data: data.isEmpty ? null : data,
      effect: execution.effect,
    );
  }
}
