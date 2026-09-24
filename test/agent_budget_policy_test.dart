import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/agent_executor.dart';
import 'package:mobile_agent/application/error_humanizer.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/infrastructure/providers/llm_provider.dart';
import 'package:mobile_agent/infrastructure/tools/tool_registry.dart';

/// 预算策略回归：有进展时自动续跑、没进展时照常暂停、连续失败提前熔断、
/// 同一调用反复失败时提示模型换方法。
Future<List<AgentEvent>> _run(
  LlmProvider provider,
  AgentTool tool, {
  required int maxSteps,
  int autoContinueLimit = 0,
}) async {
  final events = <AgentEvent>[];
  await for (final event in AgentExecutor(
    provider: provider,
    tools: ToolRegistry()..register(tool),
  ).run(
    history: [
      ChatMessage(
          role: MessageRole.user, parts: [const MessagePart.text('开始')]),
    ],
    model: 'test',
    maxSteps: maxSteps,
    autoContinueLimit: autoContinueLimit,
  )) {
    events.add(event);
  }
  return events;
}

void main() {
  test('auto-continues twice while tools keep succeeding, then pauses',
      () async {
    final provider = _EndlessToolProvider();
    final events = await _run(provider, _StubTool(ok: true),
        maxSteps: 2, autoContinueLimit: 2);

    final extensions = events.whereType<AgentBudgetExtendedEvent>().toList();
    expect(extensions.map((event) => event.round), [1, 2]);
    expect(
      extensions.every((event) => event.addedSteps == 2 && event.limit == 2),
      isTrue,
    );
    final budget = events.whereType<AgentBudgetExhaustedEvent>().single;
    expect(budget.reason, AgentPauseReason.budget);
    expect(budget.maxSteps, 6);
    expect(provider.requests, 6);
  });

  test('does not auto-continue without recent progress', () async {
    final provider = _EndlessToolProvider(varyArguments: true);
    final events = await _run(provider, _StubTool(ok: false),
        maxSteps: 2, autoContinueLimit: 2);

    expect(events.whereType<AgentBudgetExtendedEvent>(), isEmpty);
    final budget = events.whereType<AgentBudgetExhaustedEvent>().single;
    expect(budget.reason, AgentPauseReason.budget);
    expect(budget.maxSteps, 2);
  });

  test('pauses early after four consecutive tool failures', () async {
    final provider = _EndlessToolProvider(varyArguments: true);
    final events = await _run(provider, _StubTool(ok: false), maxSteps: 10);

    final pause = events.whereType<AgentBudgetExhaustedEvent>().single;
    expect(pause.reason, AgentPauseReason.repeatedFailures);
    expect(pause.maxSteps, 4);
    expect(provider.requests, 4);
    expect(events.whereType<AgentStatusEvent>().last.status, RunStatus.paused);
  });

  test('hints the model after the same call fails twice', () async {
    final provider = _EndlessToolProvider();
    await _run(provider, _StubTool(ok: false), maxSteps: 3);

    expect(
      provider.history[1].any((message) => message.text.contains('[系统提示]')),
      isFalse,
      reason: '只失败过一次时不应提示',
    );
    final hint = provider.history[2]
        .lastWhere((message) => message.role == MessageRole.user);
    expect(hint.text, contains('[系统提示]'));
    expect(hint.text, contains('失败 2 次'));
  });

  test('repeated-failure pauses render their own notice', () {
    final text = formatRunPauseForMessage(
      kind: RunPauseKind.repeatedFailures,
      maxSteps: 4,
    );
    final notice = splitRunPauseNotice(text).notice;
    expect(notice?.kind, RunPauseKind.repeatedFailures);
    expect(notice?.title, contains('连续多次'));
  });
}

/// 每轮都请求调用一次 stub 工具，永不给出最终答案。
class _EndlessToolProvider implements LlmProvider {
  _EndlessToolProvider({this.varyArguments = false});

  final bool varyArguments;
  final history = <List<ChatMessage>>[];

  int get requests => history.length;

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    history.add(List<ChatMessage>.of(request.messages));
    final n = history.length;
    yield ToolCallEvent(ToolCall(
      id: 'call-$n',
      name: 'stub',
      arguments: {'n': varyArguments ? n : 0},
    ));
    yield const CompletedEvent(stopReason: StopReason.toolUse);
  }
}

class _StubTool implements AgentTool {
  _StubTool({required this.ok});

  final bool ok;

  @override
  final manifest = const UnifiedTool(
    name: 'stub',
    description: 'stub tool',
    parametersSchema: {'type': 'object'},
    risk: ToolRisk.safe,
  );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async => ok
      ? ToolResult.text('ok')
      : ToolResult.failure(code: ToolCodes.toolError, message: 'boom');
}
