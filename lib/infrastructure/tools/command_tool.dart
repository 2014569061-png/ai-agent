import 'dart:io';

import '../../domain/models.dart';
import '../terminal/linux_runtime.dart';
import '../terminal/linux_runtime_factory.dart';
import 'tool_registry.dart';
import 'workspace_tools.dart';

export '../terminal/linux_runtime.dart'
    show
        CommandResult,
        LinuxCommandRequest,
        LinuxRuntimeAdapter,
        LinuxRuntimeInfo,
        LinuxRuntimeKind;

class TerminalCommandService {
  TerminalCommandService({
    required this.workspacePath,
    LinuxRuntimeAdapter? runtime,
  }) : _runtime = runtime ?? createDefaultLinuxRuntime();

  static const defaultTimeout = Duration(seconds: 30);
  final String workspacePath;
  final LinuxRuntimeAdapter _runtime;

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

    final cwd = _resolveWorkingDirectory(workingDirectory);
    if (cwd == null) {
      return const CommandResult(output: '工作目录必须位于当前工作区内', exitCode: 126);
    }

    final request = LinuxCommandRequest(
      commandLine: commandLine,
      executable: parsed.first,
      normalizedCommand: command,
      arguments: List<String>.unmodifiable(parsed.skip(1)),
    );

    final evalFlag = _inlineEvalFlag(command, parsed.skip(1));
    // Interpreter snippets can escape the workspace even when the runtime
    // itself supports them. Require a script file inside the workspace.
    if (evalFlag != null) {
      return CommandResult(
          output: '不允许使用内联求值参数（$evalFlag）：解释器子进程不受工作区沙箱约束，'
              '请改为执行工作区内的脚本文件',
          exitCode: 126);
    }

    // Android 的内置 Alpine/Termux Adapter 提供完整 shell；桌面/受限进程
    // Adapter 继续使用命令白名单、内联求值拦截和 shell 语法拦截。
    if (!_runtime.supportsShellSyntax) {
      if (!_allowedCommands.contains(command)) {
        return CommandResult(output: '命令不在允许列表中：$command', exitCode: 126);
      }
      if (_hasShellSyntax(commandLine)) {
        return const CommandResult(
            output: '为安全起见，不支持 shell 管道、重定向、命令连接或变量展开', exitCode: 126);
      }
    }

    final runtimeTimeout =
        _runtime.supportsShellSyntax && timeout == defaultTimeout
            ? const Duration(minutes: 5)
            : timeout;
    return _runtime.run(request,
        workingDirectory: cwd, timeout: runtimeTimeout);
  }

  void stop() => _runtime.stop();

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
