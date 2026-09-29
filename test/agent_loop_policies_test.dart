// 阶段 2a：从 AgentExecutor.run 抽出的独立策略对象。
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/agent_loop/loop_messages.dart';
import 'package:mobile_agent/application/agent_loop/model_retry_policy.dart';
import 'package:mobile_agent/application/agent_loop/step_budget_policy.dart';
import 'package:mobile_agent/application/agent_loop/system_prompt_merge.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/domain/tool_result.dart';

const _call = ToolCall(id: '1', name: 'terminal', arguments: {'cmd': 'ls'});
final _ok = ToolResult.text('ok');
final _fail =
    ToolResult.failure(code: ToolCodes.invalidArguments, message: 'bad');

void main() {
  group('StepBudgetPolicy', () {
    test('proceeds within budget and pauses when exhausted without progress',
        () {
      final policy = StepBudgetPolicy(maxSteps: 2, autoContinueLimit: 2);
      expect(policy.beforeStep(0), isA<BudgetProceed>());
      expect(policy.beforeStep(1), isA<BudgetProceed>());
      final exhausted = policy.beforeStep(2);
      expect(exhausted, isA<BudgetExhausted>());
      expect((exhausted as BudgetExhausted).budget, 2);
    });

    test('extends the budget while tools keep succeeding, up to the limit', () {
      final policy = StepBudgetPolicy(maxSteps: 1, autoContinueLimit: 2);
      policy.recordToolOutcome(_call, _ok);
      final first = policy.beforeStep(1);
      expect(first, isA<BudgetExtended>());
      expect((first as BudgetExtended).round, 1);
      expect(first.addedSteps, 1);
      expect(policy.budget, 2);
      expect(policy.beforeStep(2), isA<BudgetExtended>());
      expect(policy.beforeStep(3), isA<BudgetExhausted>());
      expect(policy.budget, 3);
    });

    test('recent progress requires a success within the last four outcomes',
        () {
      final policy = StepBudgetPolicy(maxSteps: 1, failurePauseThreshold: 0);
      policy.recordToolOutcome(_call, _ok);
      for (var i = 0; i < 4; i++) {
        policy.recordToolOutcome(_call, _fail);
      }
      expect(policy.hasRecentProgress(), isFalse);
      policy.recordToolOutcome(_call, _ok);
      expect(policy.hasRecentProgress(), isTrue);
    });

    test('hints once per identical failing call and resets on success', () {
      final policy = StepBudgetPolicy(maxSteps: 8);
      policy.recordToolOutcome(_call, _fail);
      expect(policy.drainFailureHints(), isEmpty);
      policy.recordToolOutcome(_call, _fail);
      final hints = policy.drainFailureHints();
      expect(hints, hasLength(1));
      expect(hints.single, contains('terminal'));
      expect(hints.single, contains('2 次'));
      policy.recordToolOutcome(_call, _fail);
      expect(policy.drainFailureHints(), isEmpty, reason: '同一调用只提示一次');
    });

    test('the failure breaker trips at the threshold and resets on success',
        () {
      final policy = StepBudgetPolicy(maxSteps: 8, failurePauseThreshold: 3);
      policy.recordToolOutcome(_call, _fail);
      policy.recordToolOutcome(_call, _fail);
      expect(policy.shouldPauseForFailures, isFalse);
      policy.recordToolOutcome(_call, _ok);
      expect(policy.consecutiveFailures, 0);
      for (var i = 0; i < 3; i++) {
        policy.recordToolOutcome(_call, _fail);
      }
      expect(policy.shouldPauseForFailures, isTrue);
      expect(StepBudgetPolicy(maxSteps: 1, failurePauseThreshold: 0)
          .shouldPauseForFailures, isFalse);
    });
  });

  group('ModelRetryPolicy', () {
    const policy = ModelRetryPolicy(
        maxRetries: 2, backoff: Duration(milliseconds: 100));

    test('non-retryable failures are fatal', () {
      final d = policy.decide(
          const ProviderErrorEvent('invalid api key', statusCode: 401),
          hasContent: false,
          attempts: 0);
      expect(d, isA<RetryFatal>());
      expect(d.failure.kind, 'authentication');
    });

    test('transient failures back off exponentially until exhausted', () {
      const error = ProviderErrorEvent('upstream 503', statusCode: 503);
      final first = policy.decide(error, hasContent: false, attempts: 0);
      final second = policy.decide(error, hasContent: false, attempts: 1);
      expect(first, isA<RetryAfter>());
      expect((first as RetryAfter).attempt, 1);
      expect(first.delay, const Duration(milliseconds: 100));
      expect((second as RetryAfter).delay, const Duration(milliseconds: 200));
      expect(policy.decide(error, hasContent: false, attempts: 2),
          isA<RetryGiveUp>());
    });

    test('never retries once content has been produced', () {
      expect(
          policy.decide(const ProviderErrorEvent('timeout'),
              hasContent: true, attempts: 0),
          isA<RetryGiveUp>());
    });
  });

  group('mergeSystemPrompt', () {
    ChatMessage user(String t) =>
        ChatMessage(role: MessageRole.user, parts: [MessagePart.text(t)]);

    test('inserts a trimmed prompt with built-in rules in order', () {
      final messages = [user('hi')];
      mergeSystemPrompt(messages,
          requested: '  persona ', builtInRules: const ['r1', 'r2']);
      expect(messages.first.role, MessageRole.system);
      expect(messages.first.text, 'persona\n\nr1\n\nr2');
    });

    test('is idempotent on an existing system message', () {
      final messages = [
        ChatMessage(
            role: MessageRole.system, parts: const [MessagePart.text('base')]),
        user('hi'),
      ];
      mergeSystemPrompt(messages, requested: 'p', builtInRules: const ['r']);
      mergeSystemPrompt(messages, requested: 'p', builtInRules: const ['r']);
      expect(messages.first.text, 'base\n\np\n\nr');
      expect(messages, hasLength(2));
    });

    test('adds nothing when there is nothing to add', () {
      final messages = [user('hi')];
      mergeSystemPrompt(messages, requested: '   ');
      expect(messages, hasLength(1));
    });

    test('built-in rules apply only to Android with a terminal', () {
      expect(builtInEnvironmentRules(isAndroid: false, hasTerminal: true),
          isEmpty);
      expect(builtInEnvironmentRules(isAndroid: true, hasTerminal: false),
          isEmpty);
      expect(builtInEnvironmentRules(isAndroid: true, hasTerminal: true),
          hasLength(2));
    });
  });

  test('loop messages keep their model-visible wording', () {
    expect(LoopMessages.steering('x').text,
        '用户补充指令：x\n请继续执行，不要从头重复已完成的步骤。');
    expect(LoopMessages.planConfirmed().text, startsWith('[计划已确认]'));
    expect(LoopMessages.pauseInterrupted().text, startsWith('[系统提示] 上一段回复'));
    expect(LoopMessages.failureHints(['a', 'b']).text, 'a\nb');
  });
}
