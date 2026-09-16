import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/terminal/adaptive_linux_runtime_adapter.dart';
import 'package:mobile_agent/infrastructure/terminal/builtin_proot_runtime_adapter.dart';
import 'package:mobile_agent/infrastructure/terminal/termux_runtime_adapter.dart';
import 'package:mobile_agent/infrastructure/tools/command_tool.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('terminal service delegates full shell commands to the selected runtime',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('nexus-linux-runtime-');
    addTearDown(() => directory.delete(recursive: true));
    final runtime = _RecordingRuntime();
    final service = TerminalCommandService(
      workspacePath: directory.path,
      runtime: runtime,
    );

    final result = await service.run(
      'echo hello | tr a-z A-Z',
      workingDirectory: '.',
    );

    expect(result.exitCode, 0);
    expect(result.output, 'runtime-ok');
    expect(runtime.lastRequest?.commandLine, 'echo hello | tr a-z A-Z');
    expect(runtime.lastWorkingDirectory, directory.path);
  });

  test('terminal service keeps restricted command policy for host runtimes',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('nexus-linux-runtime-policy-');
    addTearDown(() => directory.delete(recursive: true));
    final runtime = _RecordingRuntime(
      shellSyntax: false,
      interpreterEvaluation: false,
    );
    final service = TerminalCommandService(
      workspacePath: directory.path,
      runtime: runtime,
    );

    final rejected = await service.run('echo hello');

    expect(rejected.exitCode, 126);
    expect(rejected.output, contains('允许列表'));
    expect(runtime.lastRequest, isNull);
  });

  test('terminal service blocks inline interpreters on permissive runtimes',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('nexus-linux-runtime-eval-');
    addTearDown(() => directory.delete(recursive: true));
    final runtime = _RecordingRuntime(
      shellSyntax: true,
      interpreterEvaluation: true,
    );
    final service = TerminalCommandService(
      workspacePath: directory.path,
      runtime: runtime,
    );

    final result = await service.run('python -c "print(1)"');

    expect(result.exitCode, 126);
    expect(result.output, contains('内联求值'));
    expect(runtime.lastRequest, isNull);
  });

  test('adaptive runtime falls back when built-in PRoot cannot launch',
      () async {
    final builtin = _RecordingRuntime(
      runtimeKind: LinuxRuntimeKind.builtinProot,
      response: const CommandResult(
        output: '[builtin-proot] 无法启动 PRoot',
        exitCode: 127,
      ),
    );
    final fallback = _RecordingRuntime(
      runtimeKind: LinuxRuntimeKind.androidShell,
      response: const CommandResult(output: 'fallback-ok', exitCode: 0),
    );
    final runtime = AdaptiveLinuxRuntimeAdapter([builtin, fallback]);

    final info = await runtime.inspect();
    final result = await runtime.run(
      const LinuxCommandRequest(
        commandLine: 'pwd',
        executable: 'pwd',
        normalizedCommand: 'pwd',
        arguments: [],
      ),
      workingDirectory: '.',
      timeout: const Duration(seconds: 1),
    );

    expect(info.kind, LinuxRuntimeKind.builtinProot);
    expect(result.output, 'fallback-ok');
    expect(builtin.runCount, 1);
    expect(fallback.runCount, 1);
  });

  test('adaptive runtime skips a hanging candidate before selecting fallback',
      () async {
    final hanging = _HangingRuntime(LinuxRuntimeKind.builtinProot);
    final fallback = _RecordingRuntime(
      runtimeKind: LinuxRuntimeKind.androidShell,
    );
    final runtime = AdaptiveLinuxRuntimeAdapter(
      [hanging, fallback],
      inspectionTimeout: const Duration(milliseconds: 20),
    );

    final info = await runtime.inspect();

    expect(info.kind, LinuxRuntimeKind.androidShell);
    expect(info.available, isTrue);
  });

  test('terminal service honors configured shell type and default workdir',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('nexus-linux-runtime-cfg-');
    final sub = Directory('${directory.path}${Platform.pathSeparator}sub')
      ..createSync();
    addTearDown(() => directory.delete(recursive: true));
    final runtime = _RecordingRuntime();
    final service = TerminalCommandService(
      workspacePath: directory.path,
      runtime: runtime,
      shellType: 'zsh',
      defaultWorkingDirectory: 'sub',
    );

    final result = await service.run('pwd');

    expect(result.exitCode, 0);
    expect(runtime.lastRequest?.shell, 'zsh');
    expect(runtime.lastWorkingDirectory, sub.path);
  });

  test(
      'terminal service falls back to workspace root for out-of-sandbox '
      'default workdir', () async {
    final directory =
        await Directory.systemTemp.createTemp('nexus-linux-runtime-fail-');
    addTearDown(() => directory.delete(recursive: true));
    final runtime = _RecordingRuntime();
    // Termux 风格的绝对路径不在工作区内，应回退到工作区根目录而非报错。
    final service = TerminalCommandService(
      workspacePath: directory.path,
      runtime: runtime,
      defaultWorkingDirectory: '/data/data/com.termux/files/../../etc',
    );

    final result = await service.run('pwd');

    expect(result.exitCode, 0);
    expect(runtime.lastWorkingDirectory, directory.path);
  });

  test('builtin PRoot inspect times out when its native bridge never replies',
      () async {
    const channel = MethodChannel('test/builtin-proot-timeout');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        channel, (_) => Completer<dynamic>().future);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final adapter = BuiltinProotRuntimeAdapter(
      bridge: channel,
      isAndroid: true,
      inspectTimeout: const Duration(milliseconds: 20),
    );

    final info = await adapter.inspect();

    expect(info.available, isFalse);
    expect(info.detail, contains('超时'));
  });

  test('Termux inspect times out when its bridge never replies', () async {
    const channel = MethodChannel('test/termux-inspect-timeout');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        channel, (_) => Completer<dynamic>().future);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final adapter = TermuxRuntimeAdapter(
      bridge: channel,
      isAndroid: true,
      inspectTimeout: const Duration(milliseconds: 20),
    );

    final info = await adapter.inspect();

    expect(info.available, isFalse);
    expect(info.detail, contains('打开 Termux'));
  });

  test(
      'Termux command returns a bridge diagnosis when RUN_COMMAND never replies',
      () async {
    const channel = MethodChannel('test/termux-run-timeout');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        channel, (_) => Completer<dynamic>().future);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final adapter = TermuxRuntimeAdapter(
      bridge: channel,
      isAndroid: true,
      bridgeCallTimeout: const Duration(milliseconds: 20),
    );

    final result = await adapter.run(
      const LinuxCommandRequest(
        commandLine: 'echo bridge-ok',
        executable: 'echo',
        normalizedCommand: 'echo',
        arguments: ['bridge-ok'],
      ),
      workingDirectory: '.',
      timeout: const Duration(seconds: 1),
    );

    expect(result.exitCode, 127);
    expect(result.output, contains('打开 Termux'));
  });
}

class _RecordingRuntime implements LinuxRuntimeAdapter {
  _RecordingRuntime({
    this.shellSyntax = true,
    this.interpreterEvaluation = true,
    this.runtimeKind = LinuxRuntimeKind.builtinProot,
    this.response = const CommandResult(output: 'runtime-ok', exitCode: 0),
  });

  final bool shellSyntax;
  final bool interpreterEvaluation;
  final LinuxRuntimeKind runtimeKind;
  final CommandResult response;
  LinuxCommandRequest? lastRequest;
  String? lastWorkingDirectory;
  int runCount = 0;

  @override
  LinuxRuntimeKind get kind => runtimeKind;

  @override
  bool get supportsShellSyntax => shellSyntax;

  @override
  bool get supportsInterpreterEvaluation => interpreterEvaluation;

  @override
  bool get isRunning => false;

  @override
  Future<LinuxRuntimeInfo> inspect() async => LinuxRuntimeInfo(
        kind: runtimeKind,
        label: '测试 Runtime',
        available: true,
        detail: '测试实现',
      );

  @override
  Future<CommandResult> run(
    LinuxCommandRequest request, {
    required String workingDirectory,
    required Duration timeout,
  }) async {
    runCount++;
    lastRequest = request;
    lastWorkingDirectory = workingDirectory;
    return response;
  }

  @override
  void stop() {}
}

class _HangingRuntime implements LinuxRuntimeAdapter {
  _HangingRuntime(this.runtimeKind);

  final LinuxRuntimeKind runtimeKind;

  @override
  LinuxRuntimeKind get kind => runtimeKind;

  @override
  bool get supportsShellSyntax => true;

  @override
  bool get supportsInterpreterEvaluation => true;

  @override
  bool get isRunning => false;

  @override
  Future<LinuxRuntimeInfo> inspect() => Completer<LinuxRuntimeInfo>().future;

  @override
  Future<CommandResult> run(
    LinuxCommandRequest request, {
    required String workingDirectory,
    required Duration timeout,
  }) async =>
      const CommandResult(output: '', exitCode: 0);

  @override
  void stop() {}
}
