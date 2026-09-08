import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'linux_runtime.dart';

/// Android 上的外部 Termux Adapter。
///
/// 这是 Android 的外部备用 Linux 用户空间实现。Termux 提供完整 bash 和开发
/// 工具链；默认优先使用内置 PRoot，只有内置运行时不可用时才选择本 Adapter。
class TermuxRuntimeAdapter implements LinuxRuntimeAdapter {
  TermuxRuntimeAdapter({this.maxOutputBytes = 128 * 1024});

  static const bridgeDir = '/sdcard/pocketforge-bridge';
  static const _bridge = MethodChannel('nexus/termux_bridge');

  final int maxOutputBytes;
  bool _running = false;

  @override
  LinuxRuntimeKind get kind => LinuxRuntimeKind.termux;

  @override
  bool get supportsShellSyntax => true;

  @override
  bool get supportsInterpreterEvaluation => true;

  @override
  bool get isRunning => _running;

  @override
  Future<LinuxRuntimeInfo> inspect() async {
    if (!Platform.isAndroid) {
      return const LinuxRuntimeInfo(
        kind: LinuxRuntimeKind.termux,
        label: 'Termux',
        available: false,
        detail: 'Termux 运行时仅支持 Android。',
        requiresExternalApp: true,
      );
    }
    try {
      final installed = await _bridge.invokeMethod('isTermuxInstalled') == true;
      return LinuxRuntimeInfo(
        kind: kind,
        label: 'Termux Linux',
        available: installed,
        detail: installed
            ? '使用外部 Termux 提供 bash、Git、Python、Node、Go 等 Linux 工具。'
            : '未检测到 Termux；后续可切换到内置 PRoot Runtime。',
        supportsInteractive: false,
        supportsShellSyntax: true,
        requiresExternalApp: true,
      );
    } on MissingPluginException {
      return const LinuxRuntimeInfo(
        kind: LinuxRuntimeKind.termux,
        label: 'Termux Linux',
        available: false,
        detail: '当前平台没有注册 Termux 桥。',
        requiresExternalApp: true,
      );
    } catch (error) {
      return LinuxRuntimeInfo(
        kind: kind,
        label: 'Termux Linux',
        available: false,
        detail: 'Termux 检测失败：$error',
        requiresExternalApp: true,
      );
    }
  }

  @override
  Future<CommandResult> run(
    LinuxCommandRequest request, {
    required String workingDirectory,
    required Duration timeout,
  }) async {
    _running = true;
    try {
      final bridgeTimeout = timeout == const Duration(seconds: 30)
          ? const Duration(minutes: 5)
          : timeout;
      return await _runViaTermux(
        request.commandLine,
        workingDirectory,
        bridgeTimeout,
      );
    } finally {
      _running = false;
    }
  }

  @override
  void stop() {
    // 当前 Termux RUN_COMMAND 桥以后台 Intent 启动任务，没有可靠的进程句柄。
    // 保留该方法，待任务 ID/停止协议接入后由此处实现真正取消。
  }

  Future<CommandResult> _runViaTermux(
    String commandLine,
    String cwd,
    Duration timeout,
  ) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
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
      await _bridge.invokeMethod('runInTermux', {
        'command': script,
        'timeoutMs': timeout.inMilliseconds,
      });
    } on PlatformException catch (error) {
      return CommandResult(
        output: 'Termux 桥不可用：${error.message}\n'
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
}
