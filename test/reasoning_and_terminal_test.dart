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
  test('agent executor preserves reasoning in the next request context',
      () async {
    final provider = _ReasoningProvider();
    final registry = ToolRegistry()..register(_NoopTool());
    final executor = AgentExecutor(provider: provider, tools: registry);
    await executor.run(
      history: [
        ChatMessage(role: MessageRole.user, parts: [const MessagePart.text('hi')])
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
    addTearDown(() => directory.delete(recursive: true));
    final service = TerminalCommandService(workspacePath: directory.path);

    final rejected = await service.run('pwd && whoami');
    expect(rejected.exitCode, isNot(0));
    expect(rejected.output, contains('shell'));

    final executablePath =
        Platform.isWindows ? r'C:\Windows\System32\where.exe' : '/bin/pwd';
    final pathRejected = await service.run(executablePath);
    expect(pathRejected.exitCode, 126);

    final command = Platform.isWindows ? 'dir' : 'pwd';
    final result = await service.run(command);
    expect(result.exitCode, 0);
    expect(result.output, isNotEmpty);
  });

  test('terminal tool requires confirmation', () {
    final tool = TerminalCommandTool(
      service: TerminalCommandService(workspacePath: Directory.current.path),
    );
    expect(tool.manifest.risk, ToolRisk.requiresConfirmation);
  });

  test('terminal service blocks interpreter inline-eval escapes', () async {
    final directory =
        await Directory.systemTemp.createTemp('nexus-terminal-eval-');
    addTearDown(() => directory.delete(recursive: true));
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
  });
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
