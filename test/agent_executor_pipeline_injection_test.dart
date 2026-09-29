// S4：AgentExecutor 支持注入自定义工具管线。
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/agent_executor.dart';
import 'package:mobile_agent/application/tool_pipeline/execution_interceptors.dart';
import 'package:mobile_agent/application/tool_pipeline/tool_invocation.dart';
import 'package:mobile_agent/application/tool_pipeline/tool_pipeline.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/infrastructure/providers/llm_provider.dart';
import 'package:mobile_agent/infrastructure/tools/tool_registry.dart';

void main() {
  Future<List<AgentEvent>> run(AgentExecutor executor) async {
    final events = <AgentEvent>[];
    await for (final event in executor.run(
      history: [
        ChatMessage(
          role: MessageRole.user,
          parts: [const MessagePart.text('run')],
        ),
      ],
      model: 'test',
      maxSteps: 2,
    )) {
      events.add(event);
    }
    return events;
  }

  test('uses the shared default pipeline when none is injected', () {
    final executor =
        AgentExecutor(provider: _OneCallProvider(), tools: ToolRegistry());
    expect(executor.toolPipeline, same(AgentExecutor.defaultToolPipeline));
  });

  test('an appended interceptor observes executed calls and their results',
      () async {
    final recorder = _Recorder();
    final events = await run(AgentExecutor(
      provider: _OneCallProvider(),
      tools: ToolRegistry()..register(CalculatorTool()),
      toolPipeline: ToolPipeline([...defaultToolInterceptors(), recorder]),
    ));
    expect(recorder.seen, ['calculator:3.0']);
    final result = events.whereType<ToolResultEvent>().single.result;
    expect(result.ok, isTrue);
  });

  test('an injected interceptor can block execution and still settles once',
      () async {
    final tool = _CountingCalculator();
    final events = await run(AgentExecutor(
      provider: _OneCallProvider(),
      tools: ToolRegistry()..register(tool),
      toolPipeline: ToolPipeline([const _DenyAll(), ...defaultToolInterceptors()]),
    ));
    expect(tool.executions, 0);
    final results = events.whereType<ToolResultEvent>().toList();
    expect(results, hasLength(1));
    expect(results.single.result.code, 'POLICY_DENIED');
  });
}

class _OneCallProvider implements LlmProvider {
  var _requests = 0;

  @override
  Stream<UnifiedEvent> stream(
    UnifiedRequest request, {
    CancelToken? cancelToken,
  }) async* {
    if (_requests++ == 0) {
      yield const ToolCallEvent(
        ToolCall(id: 'c1', name: 'calculator', arguments: {'a': 1, 'b': 2}),
      );
      yield const CompletedEvent(stopReason: StopReason.toolUse);
      return;
    }
    yield const TextDeltaEvent('done');
    yield const CompletedEvent(stopReason: StopReason.endOfTurn);
  }
}

class _Recorder implements ToolInterceptor {
  final seen = <String>[];

  @override
  String get id => 'recorder';

  @override
  Future<ToolResult> intercept(ToolInvocation invocation, ToolNext next) async {
    final result = await next(invocation);
    seen.add('${invocation.call.name}:${result.data?['text']}');
    return result;
  }
}

class _DenyAll implements ToolInterceptor {
  const _DenyAll();

  @override
  String get id => 'deny-all';

  @override
  Future<ToolResult> intercept(ToolInvocation invocation, ToolNext next) async =>
      ToolResult.failure(code: 'POLICY_DENIED', message: 'blocked by policy');
}

class _CountingCalculator extends CalculatorTool {
  var executions = 0;

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) {
    executions++;
    return super.execute(arguments);
  }
}
