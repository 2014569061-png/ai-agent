import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'linux_runtime.dart';

/// Android 上的外部 Termux Adapter。
///
/// 这是 Android 的外部备用 Linux 用户空间实现。Termux 提供完整 bash 和开发
/// 工具链；默认优先使用内置 PRoot，只有内置运行时不可用时才选择本 Adapter。
class TermuxRuntimeAdapter
    implements LinuxRuntimeAdapter, DetachedLinuxRuntimeAdapter {
  TermuxRuntimeAdapter({this.maxOutputBytes = 128 * 1024});

  static const bridgeDir = '/sdcard/pocketforge-bridge';
  static const _bridge = MethodChannel('nexus/termux_bridge');

  final int maxOutputBytes;
  bool _running = false;
  final Map<String, DateTime> _procVerificationCache = {};

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

  /// Termux 的 RUN_COMMAND 不把外部进程句柄回传给 Flutter，因此 daemon
  /// 使用共享目录里的 owner/pid/exit 三个小文件建立可恢复协议。PID 的
  /// 停止请求仍由 Termux 自己执行，避免 Android App 直接跨 UID 杀进程。
  @override
  Future<DetachedCommandHandle?> startDetached(
    LinuxCommandRequest request, {
    required String workingDirectory,
    required Duration timeout,
    required String ownerToken,
    required String logPath,
  }) async {
    if (!Platform.isAndroid || ownerToken.trim().isEmpty) return null;
    final paths = _detachedPaths(ownerToken);
    await _deleteFiles(paths.values);
    final inner = _detachedScript(
      request.commandLine,
      workingDirectory,
      ownerToken,
      paths,
    );
    // 鍦ㄥ惎鍔ㄦ椂灏嗘墍鏈夋潈 token 娉ㄥ叆杩涚▼鍒濆鐜锛屽惁鍒欐敼鍙樼幆澧冨悗
    // /proc/<pid>/environ 可能不可读，状态校验失败时宁可拒绝认领，避免误杀正常进程。
    final launch = 'env NEXUS_DAEMON_OWNER=${_shellQuote(ownerToken)} '
        'nohup setsid bash -lc ${_shellQuote(inner)} '
        '> /dev/null 2>&1 < /dev/null &';
    try {
      await _bridge.invokeMethod('runInTermux', {
        'command': launch,
        'timeoutMs': const Duration(seconds: 30).inMilliseconds,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }

    final pid = await _waitForPid(paths['pid']!, const Duration(seconds: 5));
    if (pid == null || pid <= 0) return null;
    return DetachedCommandHandle(
      pid: pid,
      logPath: paths['log'],
      completion: _waitDetached(
        pid: pid,
        ownerToken: ownerToken,
        paths: paths,
        timeout: timeout,
      ),
    );
  }

  @override
  Future<bool> verifyDetached(int pid, String ownerToken) async {
    if (!Platform.isAndroid || pid <= 0 || ownerToken.trim().isEmpty) {
      return false;
    }
    final paths = _detachedPaths(ownerToken);
    if (await File(paths['exit']!).exists()) return false;
    try {
      final owner = (await File(paths['owner']!).readAsString()).trim();
      final storedPid = (await File(paths['pid']!).readAsString()).trim();
      if (owner != ownerToken || storedPid != '$pid') return false;
      final cacheKey = '$pid:$ownerToken';
      final now = DateTime.now();
      final cachedUntil = _procVerificationCache[cacheKey];
      if (cachedUntil != null && now.isBefore(cachedUntil)) return true;
      final verified = await _verifyProcOwner(
        pid: pid,
        ownerToken: ownerToken,
        markerPath: paths['procCheck']!,
      );
      if (verified) {
        _procVerificationCache[cacheKey] = now.add(const Duration(seconds: 2));
      } else {
        _procVerificationCache.remove(cacheKey);
      }
      return verified;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> stopDetached(int pid, String ownerToken) async {
    if (!await verifyDetached(pid, ownerToken)) return false;
    final paths = _detachedPaths(ownerToken);
    final ack = paths['stop']!;
    final ownerPath = _shellQuote(paths['owner']!);
    final pidPath = _shellQuote(paths['pid']!);
    final procPath = _shellQuote('/proc/$pid/environ');
    final token = _shellQuote(ownerToken);
    final pidLiteral = _shellQuote('$pid');
    final ownerLine = _shellQuote('NEXUS_DAEMON_OWNER=$ownerToken');
    final ackPart = _shellQuote('$ack.part');
    final ackPath = _shellQuote(ack);
    final commandBuilder = StringBuffer()
      ..write(r'owner=$(cat ')
      ..write(ownerPath)
      ..write(r'); currentPid=$(cat ')
      ..write(pidPath)
      ..write(r'); if [ "$owner" = ')
      ..write(token)
      ..write(r' ] && [ "$currentPid" = ')
      ..write(pidLiteral)
      ..write(r' ] && [ -r ')
      ..write(procPath)
      ..write(" ] && tr '\\0' '\\n' < ")
      ..write(procPath)
      ..write(r' | grep -Fqx ')
      ..write(ownerLine)
      ..write(r'; then kill "$currentPid" 2>/dev/null || true; ')
      ..write('printf true > ')
      ..write(ackPart)
      ..write('; mv ')
      ..write(ackPart)
      ..write(' ')
      ..write(ackPath)
      ..write('; fi');
    final command = commandBuilder.toString();
    try {
      await _bridge.invokeMethod('runInTermux', {
        'command': command,
        'timeoutMs': const Duration(seconds: 30).inMilliseconds,
      });
    } catch (_) {
      return false;
    }
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      try {
        if ((await File(ack).readAsString()).trim() == 'true') {
          await File(ack).delete();
          return true;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  Map<String, String> _detachedPaths(String ownerToken) {
    final safe = ownerToken.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final base = '$bridgeDir/nexus-daemon-$safe';
    return {
      'log': '$base.log',
      'pid': '$base.pid',
      'owner': '$base.owner',
      'exit': '$base.exit.json',
      'stop': '$base.stop',
      'procCheck': '$base.proc-check',
    };
  }

  Future<bool> _verifyProcOwner({
    required int pid,
    required String ownerToken,
    required String markerPath,
  }) async {
    final partPath = '$markerPath.part';
    await _deleteFiles([markerPath, partPath]);
    final procPath = _shellQuote('/proc/$pid/environ');
    final ownerLine = _shellQuote('NEXUS_DAEMON_OWNER=$ownerToken');
    final marker = _shellQuote(markerPath);
    final part = _shellQuote(partPath);
    final command =
        'if [ -r $procPath ] && tr \'\\0\' \'\\n\' < $procPath | grep -Fqx $ownerLine; '
        'then printf true > $part; mv $part $marker; else rm -f $part $marker; fi';
    try {
      await _bridge.invokeMethod('runInTermux', {
        'command': command,
        'timeoutMs': const Duration(seconds: 10).inMilliseconds,
      });
    } catch (_) {
      return false;
    }
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (DateTime.now().isBefore(deadline)) {
      try {
        if ((await File(markerPath).readAsString()).trim() == 'true') {
          await _deleteFiles([markerPath, partPath]);
          return true;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await _deleteFiles([markerPath, partPath]);
    return false;
  }

  Future<void> _deleteFiles(Iterable<String> paths) async {
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  String _detachedScript(
    String commandLine,
    String cwd,
    String ownerToken,
    Map<String, String> paths,
  ) {
    final log = _shellQuote(paths['log']!);
    final pid = _shellQuote(paths['pid']!);
    final owner = _shellQuote(paths['owner']!);
    final exit = _shellQuote(paths['exit']!);
    final cwdArg = _shellQuote(cwd);
    final token = _shellQuote(ownerToken);
    final completionPart = _shellQuote('${paths['exit']!}.part');
    return '''
umask 077
mkdir -p ${_shellQuote(bridgeDir)}
printf '%s' $token > $owner
echo \$\$ > $pid
finish() {
  code=\$?
  printf '{"exitCode":%s,"timedOut":false}' "\$code" > $completionPart
  mv $completionPart $exit
  rm -f $pid
}
trap finish EXIT TERM INT
cd $cwdArg 2>/dev/null || exit 125
export NEXUS_DAEMON_OWNER=$token
{
$commandLine
} > $log 2>&1
''';
  }

  Future<int?> _waitForPid(String path, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final pid = int.tryParse((await File(path).readAsString()).trim());
        if (pid != null && pid > 0) return pid;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return null;
  }

  Future<CommandResult> _waitDetached({
    required int pid,
    required String ownerToken,
    required Map<String, String> paths,
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout + const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      final completion = File(paths['exit']!);
      if (await completion.exists()) {
        try {
          final value = jsonDecode(await completion.readAsString());
          return CommandResult(
            output: await _readFileBounded(paths['log']!),
            exitCode: value is Map
                ? (value['exitCode'] as num?)?.toInt() ?? 127
                : 127,
            timedOut: value is Map && value['timedOut'] == true,
          );
        } catch (_) {}
      }
      if (!await verifyDetached(pid, ownerToken)) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (await completion.exists()) continue;
        return CommandResult(
          output: await _readFileBounded(paths['log']!),
          exitCode: 124,
          timedOut: true,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    return CommandResult(
      output: await _readFileBounded(paths['log']!),
      exitCode: 124,
      timedOut: true,
    );
  }

  String _shellQuote(String value) =>
      "'${value.replaceAll("'", "'\\\"'\\\"'")}'";

  Future<String> _readFileBounded(String path) async {
    try {
      var value = await File(path).readAsString();
      if (value.length > maxOutputBytes) {
        value = '[输出已截断]\n${value.substring(value.length - maxOutputBytes)}';
      }
      return value;
    } catch (_) {
      return '';
    }
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
