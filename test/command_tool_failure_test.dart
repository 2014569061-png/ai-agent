import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/infrastructure/tools/command_tool.dart';

class _FakeRuntime implements LinuxRuntimeAdapter {
  _FakeRuntime(this.result);

  final CommandResult result;

  @override
  bool get supportsShellSyntax => true;

  @override
  bool get supportsInterpreterEvaluation => false;

  @override
  bool get isRunning => false;

  @override
  LinuxRuntimeKind get kind => LinuxRuntimeKind.hostProcess;

  @override
  Future<LinuxRuntimeInfo> inspect() async => const LinuxRuntimeInfo(
        kind: LinuxRuntimeKind.hostProcess,
        label: 'fake',
        available: true,
        detail: '',
      );

  @override
  Future<CommandResult> run(
    LinuxCommandRequest request, {
    required String workingDirectory,
    required Duration timeout,
  }) async =>
      result;

  @override
  void stop() {}
}

void main() {
  test('失败摘要携带命令输出尾段，超长时截头保留错误行', () async {
    final errorLines = List.generate(200, (i) => 'noise line $i');
    final output = '${errorLines.join('\n')}\napk: unable to select packages';
    final runtime = _FakeRuntime(
      CommandResult(output: output, exitCode: 2),
    );
    final workspace =
        await Directory.systemTemp.createTemp('nexus-command-tool-');
    addTearDown(() {
      if (workspace.existsSync()) workspace.delete(recursive: true);
    });

    final tool = TerminalCommandTool(
      service: TerminalCommandService(
        workspacePath: workspace.path,
        runtime: runtime,
      ),
    );

    final result =
        await tool.execute({'command': 'apk add --no-cache openjdk17'});

    expect(result.ok, isFalse);
    expect(result.code, ToolCodes.toolError);
    expect(result.message, contains('命令以退出码 2 结束'));
    expect(result.message, contains('apk: unable to select packages'));
    expect(result.message.length, lessThan(1200));
  });

  test('无输出的失败明确说明无输出', () async {
    final runtime = _FakeRuntime(const CommandResult(output: '', exitCode: 1));
    final workspace =
        await Directory.systemTemp.createTemp('nexus-command-tool-');
    addTearDown(() {
      if (workspace.existsSync()) workspace.delete(recursive: true);
    });

    final tool = TerminalCommandTool(
      service: TerminalCommandService(
        workspacePath: workspace.path,
        runtime: runtime,
      ),
    );

    final result = await tool.execute({'command': 'false'});

    expect(result.ok, isFalse);
    expect(result.message, contains('（无输出）'));
  });
}
