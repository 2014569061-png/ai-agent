import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/agent_executor.dart';
import 'package:mobile_agent/application/agent_loop/agent_loop_hooks.dart';
import 'package:mobile_agent/application/agent_loop/builtin_hooks.dart';
import 'package:mobile_agent/application/agent_loop/loop_messages.dart';
import 'package:mobile_agent/application/agent_loop/output_token_policy.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/providers/llm_provider.dart';
import 'package:mobile_agent/infrastructure/tools/tool_registry.dart';

void main() {
  group('OutputTokenPolicy', () {
    test('legacy 2048 becomes a larger auto budget for reasoning models', () {
      expect(
        OutputTokenPolicy.resolve(
            model: 'step-5-preview', configured: 2048, contextWindow: 256000),
        OutputTokenPolicy.reasoningDefault,
      );
      expect(
        OutputTokenPolicy.resolve(
            model: 'stepfun/step-3.7-flash',
            configured: 2048,
            contextWindow: 0),
        OutputTokenPolicy.reasoningDefault,
      );
    });

    test('auto budget is capped at half of the context window', () {
      expect(
        OutputTokenPolicy.resolve(
            model: 'step-5-preview', configured: 2048, contextWindow: 32000),
        16000,
      );
      expect(
        OutputTokenPolicy.resolve(
            model: 'step-5-preview', configured: 2048, contextWindow: 3000),
        OutputTokenPolicy.legacyDefault,
      );
    });

    test('non-reasoning models get the conservative standard default', () {
      expect(
        OutputTokenPolicy.resolve(
            model: 'gpt-4o-mini', configured: 2048, contextWindow: 128000),
        OutputTokenPolicy.standardDefault,
      );
      expect(OutputTokenPolicy.isReasoningModel('deepseek-chat'), isFalse);
      expect(OutputTokenPolicy.isReasoningModel('deepseek-reasoner'), isTrue);
    });

    test('explicit non-default values are respected', () {
      expect(
        OutputTokenPolicy.resolve(
            model: 'step-5-preview', configured: 1000, contextWindow: 256000),
        1000,
      );
      expect(
        OutputTokenPolicy.resolve(
            model: 'gpt-4o', configured: 12000, contextWindow: 128000),
        12000,
      );
    });
  });

  group('OutputLimitTurnStopping', () {
    TurnStoppingContext ctx(StopReason reason, String text) =>
        TurnStoppingContext(step: 1, finalText: text, stopReason: reason);

    test('ignores normal stops', () {
      final handler = OutputLimitTurnStopping();
      expect(handler.onTurnStopping(ctx(StopReason.endOfTurn, 'x')), isNull);
      expect(handler.used, 0);
    });

    test('continues a limited number of times', () {
      final handler = OutputLimitTurnStopping(maxContinuations: 2);
      final first = handler.onTurnStopping(ctx(StopReason.outputLimit, 'half'));
      expect(first, isNotNull);
      expect(first!.keepAssistantText, isTrue);
      expect(handler.onTurnStopping(ctx(StopReason.outputLimit, 'more')),
          isNotNull);
      expect(
          handler.onTurnStopping(ctx(StopReason.outputLimit, 'more')), isNull);
    });

    test('empty truncated reply asks for a direct answer', () {
      final handler = OutputLimitTurnStopping();
      final continuation =
          handler.onTurnStopping(ctx(StopReason.outputLimit, '  '))!;
      expect(continuation.keepAssistantText, isFalse);
      final text =
          continuation.messages.single.parts.map((p) => p.value).join();
      expect(text, contains('精简思考'));
    });
  });

  group('AgentExecutor output-limit handling', () {
    test('auto-continues a truncated reply and keeps the partial text',
        () async {
      final provider = _ScriptedProvider([
        ('第一段', StopReason.outputLimit),
        ('第二段', StopReason.endOfTurn),
      ]);
      final output = StringBuffer();
      await for (final event in AgentExecutor(
        provider: provider,
        tools: ToolRegistry(),
      ).run(history: _history(), model: 'step-5-preview')) {
        if (event is TextEvent) output.write(event.text);
      }
      expect(output.toString(), '第一段第二段');
      expect(provider.requests, hasLength(2));
      final follow = provider.requests.last.messages;
      String textOf(ChatMessage m) => m.parts.map((p) => p.value).join();
      final nudge = follow.indexWhere(
          (m) => m.role == MessageRole.user && textOf(m).contains('接着输出'));
      expect(nudge, greaterThan(0));
      expect(follow[nudge - 1].role, MessageRole.assistant);
      expect(textOf(follow[nudge - 1]), '第一段');
    });

    test('shows a visible notice when continuations are exhausted', () async {
      final provider = _ScriptedProvider([
        ('', StopReason.outputLimit),
        ('', StopReason.outputLimit),
        ('', StopReason.outputLimit),
      ]);
      final output = StringBuffer();
      var completed = false;
      await for (final event in AgentExecutor(
        provider: provider,
        tools: ToolRegistry(),
      ).run(history: _history(), model: 'step-5-preview')) {
        if (event is TextEvent) output.write(event.text);
        if (event is AgentStatusEvent && event.status == RunStatus.completed) {
          completed = true;
        }
      }
      expect(provider.requests, hasLength(3));
      expect(output.toString(), LoopMessages.outputLimitNotice);
      expect(completed, isTrue);
    });

    test('explicit task budget of 2048 is not expanded for reasoning models',
        () async {
      final provider = _ScriptedProvider([('ok', StopReason.endOfTurn)]);
      await AgentExecutor(provider: provider, tools: ToolRegistry())
          .run(
              history: _history(),
              model: 'step-5-preview',
              maxTokens: 2048,
              autoOutputTokens: false,
              contextBudgetTokens: 256000)
          .drain<void>();
      expect(provider.requests.single.maxTokens, 2048);
    });

    test('legacy default output budget is raised for reasoning models',
        () async {
      final provider = _ScriptedProvider([('ok', StopReason.endOfTurn)]);
      await AgentExecutor(provider: provider, tools: ToolRegistry())
          .run(
            history: _history(),
            model: 'step-5-preview',
            contextBudgetTokens: 256000,
          )
          .drain<void>();
      expect(provider.requests.single.maxTokens,
          OutputTokenPolicy.reasoningDefault);
    });
  });
}

List<ChatMessage> _history() => [
      ChatMessage(role: MessageRole.user, parts: [const MessagePart.text('写')])
    ];

class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.script);

  final List<(String, StopReason)> script;
  final requests = <UnifiedRequest>[];

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    final (text, reason) = script[requests.length];
    requests.add(request);
    if (text.isNotEmpty) yield TextDeltaEvent(text);
    yield CompletedEvent(stopReason: reason);
  }
}
