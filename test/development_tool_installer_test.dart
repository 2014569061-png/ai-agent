import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/development_tool_installer.dart';
import 'package:mobile_agent/infrastructure/terminal/linux_runtime.dart';

void main() {
  test('one-click setup installs the common toolchain into built-in Alpine',
      () async {
    final runtime = _RecordingRuntime(LinuxRuntimeKind.builtinProot);
    final directory = await Directory.systemTemp.createTemp('tool-installer-');
    addTearDown(() => directory.delete(recursive: true));
    final installer = DevelopmentToolInstaller(
      candidates: [runtime],
      supportDirectory: () async => directory,
    );

    final result = await installer.installCommonTools();

    expect(result.succeeded, isTrue);
    expect(result.runtime, LinuxRuntimeKind.builtinProot);
    expect(runtime.command, DevelopmentToolInstaller.alpineCommand);
    expect(runtime.command, contains('nodejs npm'));
    expect(runtime.command, contains('python3 py3-pip'));
    expect(runtime.command, contains('go git curl jq'));
  });

  test('one-click setup reports when no installable runtime is available',
      () async {
    final installer = DevelopmentToolInstaller(
      candidates: [_RecordingRuntime(LinuxRuntimeKind.androidShell)],
    );

    final result = await installer.installCommonTools();

    expect(result.succeeded, isFalse);
    expect(result.message, contains('没有可安装工具'));
  });
}

class _RecordingRuntime implements LinuxRuntimeAdapter {
  _RecordingRuntime(this.kind);

  @override
  final LinuxRuntimeKind kind;
  String? command;

  @override
  bool get isRunning => false;

  @override
  bool get supportsInterpreterEvaluation => true;

  @override
  bool get supportsShellSyntax => true;

  @override
  Future<LinuxRuntimeInfo> inspect() async => LinuxRuntimeInfo(
        kind: kind,
        label: kind.name,
        available: true,
        detail: 'available',
      );

  @override
  Future<CommandResult> run(
    LinuxCommandRequest request, {
    required String workingDirectory,
    required Duration timeout,
  }) async {
    command = request.commandLine;
    return const CommandResult(output: 'ok', exitCode: 0);
  }

  @override
  void stop() {}
}
