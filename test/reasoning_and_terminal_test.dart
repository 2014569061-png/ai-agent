import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/agent_executor.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/infrastructure/providers/llm_provider.dart';
import 'package:mobile_agent/infrastructure/tools/command_tool.dart';
import 'package:mobile_agent/infrastructure/tools/tool_registry.dart';

void main() {
  // Windows 下刚退出的子进程可能仍短暂持有工作目录句柄，直接删会抛
  // PathAccessException（并发跑测试时偶发）。带退避重试几次；最终仍失败
  // 则放弃删除 —— 目录位于系统临时区，留着无害，不该让它染红测试。
  Future<void> deleteTempDir(Directory directory) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        await directory.delete(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(Duration(milliseconds: 120 * (attempt + 1)));
      }
    }
  }

  test('agent executor preserves reasoning in the next request context',
      () async {
    final provider = _ReasoningProvider();
    final registry = ToolRegistry()..register(_NoopTool());
    final executor = AgentExecutor(provider: provider, tools: registry);
    await executor.run(
      history: [
        ChatMessage(
            role: MessageRole.user, parts: [const MessagePart.text('hi')])
      ],
      model: 'test',
    ).drain();

    expect(provider.requests, hasLength(2));
    expect(
      provider.requests[1].messages
          .any((message) => message.reasoning == '先分析\n'),
      isTrue,
    );
  });

  test('terminal service rejects shell syntax and runs inside workspace',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('nexus-terminal-test-');
    addTearDown(() => deleteTempDir(directory));
    final service = TerminalCommandService(workspacePath: directory.path);

    final rejected = await service.run('pwd && whoami');
    expect(rejected.exitCode, isNot(0));
    expect(rejected.output, contains('shell'));

    final executablePath =
        Platform.isWindows ? r'C:\Windows\System32\where.exe' : '/bin/pwd';
    final pathRejected = await service.run(executablePath);
    expect(pathRejected.exitCode, 126);

    await File('${directory.path}/gradlew').writeAsString('#!/bin/sh\n');
    final runtime = _CaptureRuntime();
    final wrapperService = TerminalCommandService(
      workspacePath: directory.path,
      runtime: runtime,
    );
    final wrapper = await wrapperService.run('./gradlew test');
    expect(wrapper.notExecuted, isFalse);
    expect(runtime.commands, contains('./gradlew test'));

    final command = Platform.isWindows ? 'dir' : 'pwd';
    // 这条断言验证的是「允许的命令能在工作区内跑通」，不是产品的默认超时常量。
    // 并发跑全套测试时 Windows 上出现过 cmd.exe 启动被拖慢、偶发触到默认 30s
    // 超时（适配器用 124 表示超时）的情况，因此这里显式放宽单条命令的预算。
    //
    // 2026-09-17 补充：`flutter test --coverage` 插桩会让整棵进程都变慢，1 分钟
    // 预算同样会被突破。窗口按 3 分钟给，与下方 test 级 timeout 对齐。
    final result =
        await service.run(command, timeout: const Duration(minutes: 3));
    expect(result.exitCode, 0);
    expect(result.output, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 6)));

  test('terminal tool requires confirmation', () {
    final tool = TerminalCommandTool(
      service: TerminalCommandService(workspacePath: Directory.current.path),
    );
    expect(tool.manifest.risk, ToolRisk.requiresConfirmation);
  });

  test('terminal service blocks interpreter inline-eval escapes', () async {
    final directory =
        await Directory.systemTemp.createTemp('nexus-terminal-eval-');
    addTearDown(() => deleteTempDir(directory));
    final service = TerminalCommandService(workspacePath: directory.path);

    final python = await service.run(r'python -c "import os; os.system(1)"');
    expect(python.exitCode, 126);
    expect(python.output, contains('内联求值'));

    final node = await service.run('node -e process.exit(0)');
    expect(node.exitCode, 126);
    expect(node.output, contains('内联求值'));

    final nodeEval = await service.run('node --eval process.exit(0)');
    expect(nodeEval.exitCode, 126);

    // 无内联求值参数的命令不应被该规则拦截（后续可能因解释器不存在而
    // 启动失败，但拒绝原因绝不能是内联求值）。
    final benign = await service.run('python script.py');
    expect(benign.output, isNot(contains('内联求值')));
  }, timeout: const Timeout(Duration(minutes: 2)));
}

class _NoopTool implements AgentTool {
  @override
  final manifest = const UnifiedTool(
    name: 'noop',
    description: 'test',
    parametersSchema: {'type': 'object'},
    risk: ToolRisk.safe,
  );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async =>
      ToolResult.text('ok');
}

class _ReasoningProvider implements LlmProvider {
  final requests = <UnifiedRequest>[];

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    requests.add(request);
    if (requests.length == 1) {
      yield const ReasoningDeltaEvent('先分析\n');
      yield const ToolCallEvent(ToolCall(id: '1', name: 'noop', arguments: {}));
    } else {
      yield const TextDeltaEvent('完成');
    }
    yield const CompletedEvent(stopReason: StopReason.toolUse);
  }
}

class _CaptureRuntime implements LinuxRuntimeAdapter {
  final commands = <String>[];

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
  }) async {
    commands.add(request.commandLine);
    return const CommandResult(output: 'ok', exitCode: 0);
  }

  @override
  void stop() {}
}
