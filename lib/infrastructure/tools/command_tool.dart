import 'dart:async';
import 'dart:io';

import '../../domain/models.dart';
import 'tool_registry.dart';
import 'workspace_tools.dart';

class CommandResult {
  const CommandResult(
      {required this.output, required this.exitCode, this.timedOut = false});

  final String output;
  final int exitCode;
  final bool timedOut;

  bool get succeeded => exitCode == 0 && !timedOut;
}

class TerminalCommandService {
  TerminalCommandService({required this.workspacePath});

  static const maxOutputBytes = 128 * 1024;
  static const defaultTimeout = Duration(seconds: 30);
  final String workspacePath;
  Process? _process;

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

  bool get isRunning => _process != null;

  Future<CommandResult> run(String commandLine,
      {String? workingDirectory, Duration timeout = defaultTimeout}) async {
    final parsed = _parse(commandLine);
    if (parsed.isEmpty) {
      return const CommandResult(output: '请输入要执行的命令', exitCode: 2);
    }
    final command = _normalizeCommand(parsed.first);
    if (parsed.first.contains('/') || parsed.first.contains('\\')) {
      return const CommandResult(output: '不允许通过路径指定可执行文件', exitCode: 126);
    }
    if (!_allowedCommands.contains(command)) {
      return CommandResult(output: '命令不在允许列表中：$command', exitCode: 126);
    }
    final evalFlag = _inlineEvalFlag(command, parsed.skip(1));
    if (evalFlag != null) {
      return CommandResult(
          output:
              '不允许使用内联求值参数（$evalFlag）：解释器子进程不受工作区沙箱约束，'
              '请改为执行工作区内的脚本文件',
          exitCode: 126);
    }
    if (_hasShellSyntax(commandLine)) {
      return const CommandResult(
          output: '为安全起见，不支持 shell 管道、重定向、命令连接或变量展开', exitCode: 126);
    }

    final cwd = _resolveWorkingDirectory(workingDirectory);
    if (cwd == null) {
      return const CommandResult(output: '工作目录必须位于当前工作区内', exitCode: 126);
    }

    final executableAndArgs = _executable(parsed);
    final output = StringBuffer();
    var timedOut = false;
    try {
      final process = await Process.start(
        executableAndArgs.$1,
        [...executableAndArgs.$2, ...parsed.skip(1)],
        workingDirectory: cwd,
        runInShell: false,
      );
      _process = process;
      final stdout = _collect(process.stdout, output);
      final stderr = _collect(process.stderr, output, prefix: 'stderr: ');
      final exitFuture = process.exitCode;
      final exitCode = await exitFuture.timeout(timeout, onTimeout: () {
        timedOut = true;
        process.kill(ProcessSignal.sigterm);
        return 124;
      });
      await Future.wait([stdout, stderr]);
      final suffix = timedOut ? '\n命令超时，已终止进程。' : '';
      return CommandResult(
          output: '${output.toString()}$suffix',
          exitCode: exitCode,
          timedOut: timedOut);
    } catch (error) {
      return CommandResult(output: '启动命令失败：$error', exitCode: 127);
    } finally {
      _process = null;
    }
  }

  void stop() {
    _process?.kill(ProcessSignal.sigterm);
  }

  Future<void> _collect(Stream<List<int>> stream, StringBuffer output,
      {String prefix = ''}) async {
    await for (final chunk in stream) {
      if (output.length >= maxOutputBytes) continue;
      final text = String.fromCharCodes(chunk);
      final remaining = maxOutputBytes - output.length;
      output.write(
          '$prefix${text.length > remaining ? text.substring(0, remaining) : text}');
    }
    if (output.length >= maxOutputBytes) output.write('\n[输出已截断]');
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

  (String, List<String>) _executable(List<String> parsed) {
    final command = _normalizeCommand(parsed.first);
    if (Platform.isWindows && (command == 'dir' || command == 'type')) {
      return ('cmd.exe', ['/d', '/c', command]);
    }
    return (parsed.first, const []);
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

class TerminalCommandTool implements AgentTool {
  TerminalCommandTool({required this.service});
  final TerminalCommandService service;

  @override
  final manifest = const UnifiedTool(
    name: 'terminal',
    description:
        '在当前工作区内运行受限的终端命令（git/python/node 等）。命令会经过用户确认；'
        '禁止 shell 管道、重定向与解释器内联求值参数（如 python -c）。'
        '注意：python/node 等解释器实际执行的脚本代码本身不受工作区沙箱限制。',
    parametersSchema: {
      'type': 'object',
      'properties': {
        'command': {
          'type': 'string',
          'description': '命令及参数，例如 git status 或 dart analyze'
        },
        'workingDirectory': {'type': 'string', 'description': '工作区内的相对目录，可选'},
      },
      'required': ['command'],
    },
    risk: ToolRisk.requiresConfirmation,
  );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final command = arguments['command'] as String? ?? '';
    final cwd = arguments['workingDirectory'] as String?;
    final result = await service.run(command, workingDirectory: cwd);
    return '退出码：${result.exitCode}\n${result.output}'.trim();
  }
}
