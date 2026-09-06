import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

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

  /// G1 Android 上需要完整 Linux 工具链的命令，经 MethodChannel 转交
  /// Termux 沙箱执行（工具链在手机本机，离线可用，不依赖任何电脑）。
  static const _termuxBridge = MethodChannel('nexus/termux_bridge');

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
    // G1 Android 桥分支：Termux 沙箱是本机唯一完整 Linux 环境（有 git/go/node
    // 等，系统 toybox 没有），所有命令统一经桥执行；桥是完整 bash（支持管道、
    // 重定向、GOOS=xxx 前缀、printf/echo 等），安全边界 = 用户逐次确认 + 沙箱。
    if (Platform.isAndroid) {
      final bridgeCwd = _resolveWorkingDirectory(workingDirectory);
      if (bridgeCwd == null) {
        return const CommandResult(output: '工作目录必须位于当前工作区内', exitCode: 126);
      }
      final bridgeTimeout =
          identical(timeout, defaultTimeout) ? const Duration(minutes: 5) : timeout;
      return _runViaTermux(commandLine, bridgeCwd, bridgeTimeout);
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

  /// G1 经 Termux 桥执行（文件交换协议）：命令输出重定向到 /sdcard/pocketforge-bridge，
  /// 本方法轮询退出码文件。不依赖 PendingIntent 广播（ColorOS 上不可靠）。
  /// 首次 go build 较慢，默认超时放宽到 5 分钟（由调用方传入）。
  Future<CommandResult> _runViaTermux(
      String commandLine, String cwd, Duration timeout) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final bridgeDir = '/sdcard/pocketforge-bridge';
    final outFile = '$bridgeDir/out-$id.txt';
    final codeFile = '$bridgeDir/code-$id.txt';
    try {
      Directory(bridgeDir).createSync(recursive: true);
      final oldOut = File(outFile);
      if (oldOut.existsSync()) oldOut.deleteSync();
      final oldCode = File(codeFile);
      if (oldCode.existsSync()) oldCode.deleteSync();
    } catch (_) {}

    final escapedCwd = cwd.replaceAll("'", "'\\''");
    final script = "cd '$escapedCwd' 2>/dev/null || exit 125\n"
        '{\n$commandLine\n} > \'$outFile\' 2>&1\n'
        "echo \$? > '$codeFile'";
    try {
      await _termuxBridge.invokeMethod('runInTermux', {
        'command': script,
        'timeoutMs': timeout.inMilliseconds,
      });
    } on PlatformException catch (e) {
      return CommandResult(
        output: 'Termux 桥不可用：${e.message}\n'
            '请确认：① 手机已安装 Termux；② Termux 内已配置 allow-external-apps=true'
            '（~/.termux/termux.properties）并重启 Termux；③ 若仍失败，请先打开一次'
            ' Termux 再试（部分 ROM 会冻结后台应用）。',
        exitCode: 127,
      );
    }

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 400));
      final codeFileHandle = File(codeFile);
      if (!codeFileHandle.existsSync()) continue;
      final code = int.tryParse(codeFileHandle.readAsStringSync().trim()) ?? -1;
      var output = '';
      final outFileHandle = File(outFile);
      if (outFileHandle.existsSync()) {
        output = outFileHandle.readAsStringSync();
        if (output.length > maxOutputBytes) {
          output = output.substring(output.length - maxOutputBytes);
        }
      }
      // 清理交换文件，避免堆积
      try {
        outFileHandle.deleteSync();
        codeFileHandle.deleteSync();
      } catch (_) {}
      return CommandResult(output: output, exitCode: code);
    }
    return CommandResult(
      output: '[bridge] Termux 执行超时（${timeout.inSeconds}s）。'
          '请确认 Termux 未被系统冻结：最近是否打开过 Termux？',
      exitCode: 124,
      timedOut: true,
    );
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
        '注意：python/node 等解释器实际执行的脚本代码本身不受工作区沙箱限制。'
        'Android 上 go/gofmt/bash/curl/jq/make/zig 会转交 Termux 沙箱执行'
        '（完整 bash 语法，支持管道与重定向；需已安装 Termux），用于交叉编译 Windows exe 等场景。',
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
