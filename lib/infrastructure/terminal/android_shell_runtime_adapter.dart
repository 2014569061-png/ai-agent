import 'dart:async';
import 'dart:io';

import 'linux_runtime.dart';

/// Last-resort Android system shell. It has no bundled Linux toolchain, but
/// keeps basic shell commands usable when neither PRoot nor Termux is ready.
class AndroidShellRuntimeAdapter implements LinuxRuntimeAdapter {
  AndroidShellRuntimeAdapter({this.maxOutputBytes = 128 * 1024});

  final int maxOutputBytes;
  Process? _process;

  @override
  LinuxRuntimeKind get kind => LinuxRuntimeKind.androidShell;

  @override
  bool get supportsShellSyntax => true;

  @override
  bool get supportsInterpreterEvaluation => true;

  @override
  bool get isRunning => _process != null;

  @override
  Future<LinuxRuntimeInfo> inspect() async => LinuxRuntimeInfo(
        kind: kind,
        label: 'Android Shell',
        available: Platform.isAndroid,
        detail: Platform.isAndroid
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
    if (!Platform.isAndroid) {
      return const CommandResult(
        output: '[android-shell] 该运行时仅支持 Android。',
        exitCode: 127,
      );
    }

    final output = StringBuffer();
    var timedOut = false;
    try {
      final shellBinary = _shellBinary(request.shell);
      final process = await Process.start(
        shellBinary,
        ['-c', request.commandLine],
        workingDirectory: workingDirectory,
        runInShell: false,
      );
      _process = process;
      final stdout = _collect(process.stdout, output);
      final exitCode = await process.exitCode.timeout(timeout, onTimeout: () {
        timedOut = true;
        process.kill(ProcessSignal.sigterm);
        return 124;
      });
      await stdout;
      final suffix = timedOut ? '\n命令超时，已终止进程。' : '';
      return CommandResult(
        output: '${output.toString()}$suffix',
        exitCode: exitCode,
        timedOut: timedOut,
      );
    } catch (error) {
      return CommandResult(
        output: '[android-shell] 启动命令失败：$error',
        exitCode: 127,
      );
    } finally {
      _process = null;
    }
  }

  @override
  void stop() {
    _process?.kill(ProcessSignal.sigterm);
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

  Future<void> _collect(Stream<List<int>> stream, StringBuffer output) async {
    await for (final chunk in stream) {
      if (output.length >= maxOutputBytes) continue;
      final text = String.fromCharCodes(chunk);
      final remaining = maxOutputBytes - output.length;
      output.write(
        text.length > remaining ? text.substring(0, remaining) : text,
      );
    }
    if (output.length >= maxOutputBytes) output.write('\n[输出已截断]');
  }
}
