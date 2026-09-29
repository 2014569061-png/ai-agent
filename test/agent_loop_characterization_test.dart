// 阶段 0 特征测试：锁定 AgentExecutor.run() 当前的可观察行为。
//
// 这些测试描述“现在是什么”，不是“应该是什么”。后续把 run() 拆成
// preStep / request / stream / tools / stepEnd / turnStopping 阶段钩子时，
// 本文件必须一行不改地通过；若确需改变行为，先在此处显式修改期望并说明原因。
import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/agent_executor.dart';
import 'package:mobile_agent/application/run_controller.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/infrastructure/providers/llm_provider.dart';
import 'package:mobile_agent/infrastructure/tools/tool_registry.dart';

ChatMessage _user(String text) =>
    ChatMessage(role: MessageRole.user, parts: [MessagePart.text(text)]);

/// 把事件流压成稳定的字符串轨迹，便于整体比较顺序。
String _trace(AgentEvent e) => switch (e) {
      AgentStatusEvent(:final status) => 'status:${status.name}',
      ContextSnapshotEvent(:final step) => 'snapshot:$step',
      ContextBudgetWarningEvent() => 'budgetWarning',
      AgentContextChangeEvent(:final kind, :final category) =>
        'change:$kind:$category',
      AgentContextCompressionEvent() => 'compression',
      AgentStepUsageEvent(:final step) => 'stepUsage:$step',
      TextEvent(:final text) => 'text:$text',
      ReasoningEvent(:final text) => 'reasoning:$text',
      ToolRequestedEvent(:final call) => 'toolRequested:${call.name}',
      ApprovalRequiredEvent(:final call) => 'approval:${call.name}',
      ToolResultEvent(:final call, :final result) =>
        'toolResult:${call.name}:${result.ok ? 'ok' : 'fail'}',
      AgentErrorEvent(:final retryable) => 'error:retryable=$retryable',
      AgentBudgetExhaustedEvent(:final reason) => 'budgetExhausted:${reason.name}',
      AgentBudgetExtendedEvent(:final round) => 'budgetExtended:$round',
      AgentRetryEvent(:final attempt) => 'retry:$attempt',
      AgentUsageEvent() => 'usage',
    };

/// 按脚本逐步应答的 Provider；在请求发出的那一刻为消息列表拍快照。
///
/// 注意：[UnifiedRequest.messages] 与执行器内部的工作列表是同一个对象，
/// 执行器随后追加的消息会反映到已记录的请求上（见 “request aliasing” 用例）。
/// 这里记录快照，才能反映模型当时真正看到的内容。
class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.steps);

  final List<List<UnifiedEvent>> steps;
  final requests = <UnifiedRequest>[];
  final raw = <UnifiedRequest>[];

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    raw.add(request);
    requests.add(UnifiedRequest(
      model: request.model,
      messages: List<ChatMessage>.of(request.messages),
      tools: request.tools,
      temperature: request.temperature,
      maxTokens: request.maxTokens,
      topP: request.topP,
      reasoningEffort: request.reasoningEffort,
    ));
    final index = requests.length - 1;
    final script = index < steps.length
        ? steps[index]
        : const <UnifiedEvent>[
            TextDeltaEvent('fallback'),
            CompletedEvent(stopReason: StopReason.endOfTurn),
          ];
    for (final event in script) {
      yield event;
    }
  }
}

const _calcCall =
    ToolCall(id: 'c1', name: 'calculator', arguments: {'a': 1, 'b': 2});

List<UnifiedEvent> _toolStep([ToolCall call = _calcCall]) => [
      const TextDeltaEvent('let me compute'),
      ToolCallEvent(call),
      const CompletedEvent(stopReason: StopReason.toolUse),
    ];

const List<UnifiedEvent> _textStep = [
  TextDeltaEvent('done'),
  CompletedEvent(stopReason: StopReason.endOfTurn),
];

ToolRegistry _registry() => ToolRegistry()..register(CalculatorTool());

Future<List<AgentEvent>> _collect(Stream<AgentEvent> stream) => stream.toList();

void main() {
  group('event order', () {
    test('a plain text turn emits a fixed event sequence', () async {
      final provider = _ScriptedProvider([_textStep]);
      final events = await _collect(AgentExecutor(
        provider: provider,
        tools: _registry(),
      ).run(history: [_user('hi')], model: 'm'));

      expect(events.map(_trace).toList(), [
        'status:waitingModel',
        'snapshot:1',
        'text:done',
        'stepUsage:1',
        'usage',
        'status:completed',
      ]);
    });

    test('a tool step followed by a text step keeps step boundaries ordered',
        () async {
      final provider = _ScriptedProvider([_toolStep(), _textStep]);
      final events = await _collect(AgentExecutor(
        provider: provider,
        tools: _registry(),
      ).run(history: [_user('1+2')], model: 'm'));

      final trace = events
          .map(_trace)
          .where((t) => !t.startsWith('change:'))
          .toList();
      final step1 = trace.indexOf('snapshot:1');
      final requested = trace.indexOf('toolRequested:calculator');
      final usage1 = trace.indexOf('stepUsage:1');
      final result = trace.indexOf('toolResult:calculator:ok');
      final step2 = trace.indexOf('snapshot:2');
      expect(trace.first, 'status:waitingModel');
      expect(step1, greaterThan(0));
      // 工具调用事件在流式阶段就发出，早于本步用量；结果在用量之后。
      expect(requested, greaterThan(step1));
      expect(usage1, greaterThan(requested));
      expect(result, greaterThan(usage1));
      expect(step2, greaterThan(result));
      expect(trace.sublist(trace.length - 3),
          ['stepUsage:2', 'usage', 'status:completed']);
      expect(trace.where((t) => t == 'usage'), hasLength(1),
          reason: '累计用量只在最终完成时发出一次');
    });
  });

  group('request history', () {
    test('the second request carries assistant tool calls then the tool result',
        () async {
      final provider = _ScriptedProvider([_toolStep(), _textStep]);
      await _collect(AgentExecutor(provider: provider, tools: _registry())
          .run(history: [_user('1+2')], model: 'm'));

      expect(provider.requests, hasLength(2));
      final first = provider.requests[0].messages;
      expect(first.map((m) => m.role).toList(), [MessageRole.user]);

      final second = provider.requests[1].messages;
      expect(second.map((m) => m.role).toList(),
          [MessageRole.user, MessageRole.assistant, MessageRole.tool]);
      final assistant = second[1];
      expect(assistant.text, 'let me compute');
      expect(assistant.toolCalls.map((c) => c.id).toList(), ['c1']);
      final tool = second[2];
      expect(tool.toolCallId, 'c1');
      expect(tool.text, contains('3'));
    });

    test('request aliasing: the recorded request list grows after sending',
        () async {
      // 现状特征（阶段 1 需要处理）：请求对象持有执行器工作列表的引用，
      // 本步结束后追加的 assistant/tool 消息会出现在“已发送”的请求里。
      // 会话日志必须在发送时刻记录快照，不能事后读取 request.messages。
      final provider = _ScriptedProvider([_toolStep(), _textStep]);
      await _collect(AgentExecutor(provider: provider, tools: _registry())
          .run(history: [_user('1+2')], model: 'm'));
      expect(provider.requests[1].messages, hasLength(3));
      expect(provider.raw[1].messages.length, greaterThan(3));
      expect(identical(provider.raw[1].messages, provider.raw[0].messages),
          isFalse,
          reason: '每步裁剪都会产生新列表；别名只存在于同一步内');
    });

    test('every request in a run sends the same tool list', () async {
      final provider = _ScriptedProvider([_toolStep(), _textStep]);
      await _collect(AgentExecutor(provider: provider, tools: _registry())
          .run(history: [_user('1+2')], model: 'm'));
      final names = provider.requests
          .map((r) => r.tools.map((t) => t.name).join(','))
          .toSet();
      expect(names, {'calculator'});
    });
  });

  group('system prompt assembly', () {
    test('inserts the requested prompt as a leading system message', () async {
      final provider = _ScriptedProvider([_textStep]);
      await _collect(AgentExecutor(provider: provider, tools: _registry()).run(
        history: [_user('hi')],
        model: 'm',
        systemPrompt: '  be brief  ',
      ));
      final messages = provider.requests.single.messages;
      expect(messages.first.role, MessageRole.system);
      expect(messages.first.text, 'be brief');
      expect(messages.where((m) => m.role == MessageRole.system), hasLength(1));
    });

    test('merges into an existing system message without duplicating it',
        () async {
      final provider = _ScriptedProvider([_textStep, _textStep]);
      final executor = AgentExecutor(provider: provider, tools: _registry());
      final history = [
        ChatMessage(
            role: MessageRole.system,
            parts: [const MessagePart.text('base rules')]),
        _user('hi'),
      ];
      await _collect(
          executor.run(history: history, model: 'm', systemPrompt: 'extra'));
      expect(provider.requests[0].messages.first.text, 'base rules\n\nextra');

      // 已包含相同 prompt 时保持原样。
      final already = [
        ChatMessage(
            role: MessageRole.system,
            parts: [const MessagePart.text('base rules\n\nextra')]),
        _user('hi'),
      ];
      await _collect(
          executor.run(history: already, model: 'm', systemPrompt: 'extra'));
      expect(provider.requests[1].messages.first.text, 'base rules\n\nextra');
    });

    test('does not mutate the caller history list', () async {
      final provider = _ScriptedProvider([_toolStep(), _textStep]);
      final history = [_user('1+2')];
      await _collect(AgentExecutor(provider: provider, tools: _registry())
          .run(history: history, model: 'm', systemPrompt: 'p'));
      expect(history, hasLength(1));
      expect(history.single.role, MessageRole.user);
    });
  });

  group('steering', () {
    test('steering queued at the completion boundary starts another step',
        () async {
      final controller = AgentRunController();
      final provider = _ScriptedProvider([_textStep, _textStep]);
      controller.steer('also add tests');
      final events = await _collect(
          AgentExecutor(provider: provider, tools: _registry()).run(
        history: [_user('hi')],
        model: 'm',
        runController: controller,
      ));

      expect(provider.requests, hasLength(2));
      final second = provider.requests[1].messages;
      expect(second.last.role, MessageRole.user);
      expect(second.last.text, contains('用户补充指令：also add tests'));
      // 现状：被插话打断的那一步，其 assistant 文本不进入下一次请求。
      expect(second.where((m) => m.role == MessageRole.assistant), isEmpty);
      expect(events.map(_trace).last, 'status:completed');
      expect(controller.isSealed, isTrue,
          reason: '无新指令的完成边界会封存控制器');
    });

    test('steering queued during a tool step follows the tool results',
        () async {
      final controller = AgentRunController();
      final provider = _ScriptedProvider([_toolStep(), _textStep]);
      final stream = AgentExecutor(provider: provider, tools: _registry()).run(
        history: [_user('1+2')],
        model: 'm',
        runController: controller,
      );
      await for (final event in stream) {
        if (event is ToolRequestedEvent) controller.steer('use integers');
      }
      final second = provider.requests[1].messages;
      expect(second.map((m) => m.role).toList(), [
        MessageRole.user,
        MessageRole.assistant,
        MessageRole.tool,
        MessageRole.user,
      ]);
      expect(second.last.text, contains('用户补充指令：use integers'));
    });

    test('steering after completion is rejected', () async {
      final controller = AgentRunController();
      await _collect(
          AgentExecutor(provider: _ScriptedProvider([_textStep]), tools: _registry())
              .run(history: [_user('hi')], model: 'm', runController: controller));
      expect(controller.steer('late'), isFalse);
    });
  });

  group('cancellation and plan gate', () {
    test('a run cancelled before start emits only cancelled', () async {
      final provider = _ScriptedProvider([_textStep]);
      final token = AgentCancellationToken()..cancel();
      final events = await _collect(
          AgentExecutor(provider: provider, tools: _registry()).run(
        history: [_user('hi')],
        model: 'm',
        cancellationToken: token,
      ));
      expect(events.map(_trace).toList(), ['status:cancelled']);
      expect(provider.requests, isEmpty);
    });

    test('rejecting the plan cancels before any tool executes', () async {
      final provider = _ScriptedProvider([_toolStep(), _textStep]);
      String? seenPlan;
      final events = await _collect(
          AgentExecutor(provider: provider, tools: _registry()).run(
        history: [_user('1+2')],
        model: 'm',
        confirmPlan: (calls, planText) async {
          seenPlan = planText;
          return false;
        },
      ));
      final trace = events.map(_trace).toList();
      expect(seenPlan, 'let me compute');
      expect(trace.last, 'status:cancelled');
      expect(trace.any((t) => t.startsWith('toolResult:')), isFalse);
      expect(provider.requests, hasLength(1));
    });

    test('the plan gate only applies to the first step', () async {
      final provider =
          _ScriptedProvider([_textStepWithTool(), _toolStep(), _textStep]);
      var asked = 0;
      await _collect(AgentExecutor(provider: provider, tools: _registry()).run(
        history: [_user('go')],
        model: 'm',
        confirmPlan: (calls, planText) async {
          asked++;
          return true;
        },
      ));
      // 第 1 步停因不是 toolUse，夹带调用被拒绝且不触发计划门禁；第 2 步的
      // 真实工具调用也不再询问（step != 0）。
      expect(asked, 0);
      expect(provider.requests, hasLength(3));
    });
  });

  group('stop reasons', () {
    test('tool calls under a non-tool stop reason settle as UNEXPECTED',
        () async {
      final provider = _ScriptedProvider([_textStepWithTool(), _textStep]);
      final events = await _collect(
          AgentExecutor(provider: provider, tools: _registry())
              .run(history: [_user('go')], model: 'm'));
      final result = events.whereType<ToolResultEvent>().single;
      expect(result.result.ok, isFalse);
      expect(result.result.encode(), contains(ToolCodes.unexpectedToolCall));
      // 被拒绝的调用仍以 assistant(tool_calls) + tool 形式进入下一次请求。
      final second = provider.requests[1].messages;
      expect(second.map((m) => m.role).toList(),
          [MessageRole.user, MessageRole.assistant, MessageRole.tool]);
      expect(events.map(_trace).last, 'status:completed');
    });
  });

  group('model failures', () {
    test('a non-retryable failure stops immediately and cancels the caller token',
        () async {
      final provider = _ScriptedProvider([
        [const ProviderErrorEvent('invalid api key', statusCode: 401)],
      ]);
      final cancelToken = CancelToken();
      final events = await _collect(
          AgentExecutor(provider: provider, tools: _registry()).run(
        history: [_user('hi')],
        model: 'm',
        cancelToken: cancelToken,
        retryBackoff: const Duration(milliseconds: 1),
      ));
      final error = events.whereType<AgentErrorEvent>().single;
      expect(error.retryable, isFalse);
      expect(error.failureKind, 'authentication');
      expect(error.statusCode, 401);
      expect(provider.requests, hasLength(1));
      expect(cancelToken.isCancelled, isTrue);
      expect(events.map(_trace).any((t) => t.startsWith('retry:')), isFalse);
    });

    test('an idle timeout is retried as a transient failure', () async {
      final provider = _HangOnceProvider();
      final events = await _collect(
          AgentExecutor(provider: provider, tools: _registry()).run(
        history: [_user('hi')],
        model: 'm',
        requestTimeout: const Duration(milliseconds: 50),
        retryBackoff: const Duration(milliseconds: 1),
      ));
      final trace = events.map(_trace).toList();
      expect(trace, contains('retry:1'));
      expect(trace, contains('text:recovered'));
      expect(trace.last, 'status:completed');
      expect(provider.calls, 2);
    });
  });

  group('budget pause', () {
    test('the paused context ends with the last tool result', () async {
      final provider = _ScriptedProvider([_toolStep(), _toolStep()]);
      final events = await _collect(
          AgentExecutor(provider: provider, tools: _registry()).run(
        history: [_user('loop')],
        model: 'm',
        maxSteps: 1,
      ));
      final trace = events.map(_trace).toList();
      expect(trace.sublist(trace.length - 2),
          ['status:paused', 'budgetExhausted:budget']);
      final paused = events.whereType<AgentBudgetExhaustedEvent>().single;
      expect(paused.maxSteps, 1);
      expect(paused.context.map((m) => m.role).toList(),
          [MessageRole.user, MessageRole.assistant, MessageRole.tool]);
      expect(provider.requests, hasLength(1));
    });
  });
}

List<UnifiedEvent> _textStepWithTool() => const [
      TextDeltaEvent('thinking'),
      ToolCallEvent(_calcCall),
      CompletedEvent(stopReason: StopReason.endOfTurn),
    ];

/// 第一次请求一直不产出数据（触发空闲超时），第二次正常完成。
class _HangOnceProvider implements LlmProvider {
  var calls = 0;

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) {
    calls++;
    if (calls == 1) {
      // 永不产出、可立即取消的流：模拟连接挂起。
      return StreamController<UnifiedEvent>().stream;
    }
    return Stream<UnifiedEvent>.fromIterable(const [
      TextDeltaEvent('recovered'),
      CompletedEvent(stopReason: StopReason.endOfTurn),
    ]);
  }
}
