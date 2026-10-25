// 阶段 2b：执行循环阶段钩子。
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/agent_executor.dart';
import 'package:mobile_agent/application/agent_loop/agent_loop_hooks.dart';
import 'package:mobile_agent/application/run_controller.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/infrastructure/providers/llm_provider.dart';
import 'package:mobile_agent/infrastructure/tools/tool_registry.dart';

ChatMessage _user(String text) =>
    ChatMessage(role: MessageRole.user, parts: [MessagePart.text(text)]);

class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.steps);
  final List<List<UnifiedEvent>> steps;
  final sent = <List<ChatMessage>>[];

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    sent.add(List<ChatMessage>.of(request.messages));
    final i = sent.length - 1;
    for (final e in i < steps.length ? steps[i] : _text('fallback')) {
      yield e;
    }
  }
}

List<UnifiedEvent> _text(String t) =>
    [TextDeltaEvent(t), const CompletedEvent(stopReason: StopReason.endOfTurn)];

List<UnifiedEvent> _calls(List<ToolCall> calls) => [
      for (final c in calls) ToolCallEvent(c),
      const CompletedEvent(stopReason: StopReason.toolUse),
    ];

const _calc =
    ToolCall(id: 'c1', name: 'calculator', arguments: {'a': 1, 'b': 2});

class _InjectTransform implements RequestTransform {
  final seenSteps = <int>[];

  @override
  String get id => 'test.inject';

  @override
  RequestTransformResult apply(
      RequestContext context, List<ChatMessage> messages) {
    seenSteps.add(context.step);
    return RequestTransformResult(
      [...messages, _user('[注入] step ${context.step}')],
      [
        AgentContextChangeEvent(
          step: context.step,
          kind: 'context_inject',
          category: 'test',
          deltaTokens: 1,
        ),
      ],
    );
  }
}

class _RecordingOutcomes implements ToolOutcomeObserver {
  final calls = <String>[];

  @override
  void onToolOutcome(ToolCall call, ToolResult result) =>
      calls.add('${call.name}:${result.ok}');
}

class _ContinueOnce implements TurnStoppingHandler {
  _ContinueOnce({this.keep = true});
  final bool keep;
  var asked = 0;
  String? seenText;

  @override
  String get id => 'test.continue-once';

  @override
  TurnContinuation? onTurnStopping(TurnStoppingContext context) {
    asked++;
    seenText ??= context.finalText;
    if (asked > 1) return null;
    return TurnContinuation([_user('[提醒] 请先运行验证')], keepAssistantText: keep);
  }
}

void main() {
  test('request transforms run before trimming and their events are emitted',
      () async {
    final transform = _InjectTransform();
    final provider = _ScriptedProvider([
      _calls([_calc]),
      _text('done')
    ]);
    final logged = <List<ChatMessage>>[];
    final events = await AgentExecutor(
      provider: provider,
      tools: ToolRegistry()..register(CalculatorTool()),
      hooks: AgentLoopHooks(requestTransforms: [transform]),
    ).run(
      history: [_user('1+2')],
      model: 'm',
      onRequest: (_, request) => logged.add(request.messages),
    ).toList();

    expect(transform.seenSteps, [1, 2]);
    expect(provider.sent.first.last.text, '[注入] step 1');
    // 注入发生在请求之前，所以会进入请求观察者（会话日志）的快照。
    expect(logged.first.last.text, '[注入] step 1');
    // 第 2 步：上一步注入的内容保留在工作列表中，本步再注入一次。
    expect(
        provider.sent[1].where((m) => m.text.startsWith('[注入]')), hasLength(2));
    final trace = events.map((e) => e.runtimeType.toString()).toList();
    final inject = trace.indexOf('AgentContextChangeEvent');
    expect(inject, lessThan(trace.indexOf('ContextSnapshotEvent')));
  });

  test('executor-level observers run before the per-run onRequest', () async {
    final order = <String>[];
    await AgentExecutor(
      provider: _ScriptedProvider([_text('ok')]),
      tools: ToolRegistry(),
      hooks: AgentLoopHooks(requestObservers: [
        (step, request) => order.add('hook:$step'),
      ]),
    ).run(
      history: [_user('hi')],
      model: 'm',
      onRequest: (step, request) => order.add('run:$step'),
    ).drain<void>();
    expect(order, ['hook:1', 'run:1']);
  });

  test('tool outcome observers only see calls that actually executed',
      () async {
    final outcomes = _RecordingOutcomes();
    await AgentExecutor(
      provider: _ScriptedProvider([
        _calls([
          _calc,
          const ToolCall(id: 'x', name: 'no_such_tool', arguments: {}),
        ]),
        _text('done'),
      ]),
      tools: ToolRegistry()..register(CalculatorTool()),
      hooks: AgentLoopHooks(toolOutcomeObservers: [outcomes]),
    ).run(history: [_user('go')], model: 'm').drain<void>();
    expect(outcomes.calls, ['calculator:true']);
  });

  test('a turn-stopping handler can keep the run going with the reply kept',
      () async {
    final handler = _ContinueOnce();
    final controller = AgentRunController();
    final provider = _ScriptedProvider([_text('看起来完成了'), _text('验证通过')]);
    final events = await AgentExecutor(
      provider: provider,
      tools: ToolRegistry(),
      hooks: AgentLoopHooks(turnStopping: [handler]),
    ).run(
        history: [_user('改一下')],
        model: 'm',
        runController: controller).toList();

    expect(handler.asked, 2);
    expect(handler.seenText, '看起来完成了');
    final second = provider.sent[1];
    expect(second.map((m) => m.role).toList(),
        [MessageRole.user, MessageRole.assistant, MessageRole.user]);
    expect(second[1].text, '看起来完成了');
    expect(second[2].text, '[提醒] 请先运行验证');
    expect(
        events.whereType<AgentStatusEvent>().last.status, RunStatus.completed);
    expect(controller.isSealed, isTrue, reason: '最终完成时由内置 steering 封存');
  });

  test('an external continuation is asked before steering seals the run',
      () async {
    final handler = _ContinueOnce(keep: false);
    final controller = AgentRunController()..steer('顺便加注释');
    final provider =
        _ScriptedProvider([_text('第一版'), _text('第二版'), _text('第三版')]);
    await AgentExecutor(
      provider: provider,
      tools: ToolRegistry(),
      hooks: AgentLoopHooks(turnStopping: [handler]),
    ).run(
        history: [_user('写')],
        model: 'm',
        runController: controller).drain<void>();
    // 已排队插话在第一次请求前交付；外部 continuation 仍优先于封存。
    expect(provider.sent, hasLength(2));
    expect(provider.sent.first.last.text, contains('用户补充指令：顺便加注释'));
    expect(provider.sent[1].last.text, '[提醒] 请先运行验证');
    expect(provider.sent[1].where((m) => m.role == MessageRole.assistant),
        isEmpty);
    expect(controller.isSealed, isTrue);
  });

  test('merge keeps order with the other set appended', () {
    void a(int s, UnifiedRequest r) {}
    void b(int s, UnifiedRequest r) {}
    final merged = AgentLoopHooks(requestObservers: [a])
        .merge(AgentLoopHooks(requestObservers: [b]));
    expect(merged.requestObservers, [a, b]);
    expect(
        AgentLoopHooks.empty.merge(AgentLoopHooks.empty).turnStopping, isEmpty);
  });
}
