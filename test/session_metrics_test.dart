import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/session_metrics.dart';

ChatMessage _user() => ChatMessage(
      role: MessageRole.user,
      parts: const [MessagePart.text('hi')],
    );

ChatMessage _assistant({
  Usage? usage,
  Duration? elapsed,
  Duration? ttft,
}) =>
    ChatMessage(
      role: MessageRole.assistant,
      parts: const [MessagePart.text('ok')],
      usage: usage,
      elapsed: elapsed,
      ttft: ttft,
    );

void main() {
  group('SessionMetrics.from', () {
    test('空消息列表 → isEmpty，且全部为 0 / null', () {
      final m = SessionMetrics.from(messages: const []);

      expect(m.isEmpty, isTrue);
      expect(m.rounds, 0);
      expect(m.steps, 0);
      expect(m.llmTime, Duration.zero);
      expect(m.toolTime, Duration.zero);
      expect(m.avgTtft, isNull);
      expect(m.tokensPerSecond, 0);
      expect(m.cacheHitRate, isNull);
      expect(m.promptTokens, 0);
      expect(m.completionTokens, 0);
    });

    test('轮数只统计用户消息，步数由控制器注入', () {
      final m = SessionMetrics.from(
        messages: [_user(), _assistant(), _user(), _assistant()],
        steps: 7,
      );

      expect(m.rounds, 2);
      expect(m.steps, 7);
      expect(m.isEmpty, isFalse);
    });

    test('token 累计与缓存命中率', () {
      final m = SessionMetrics.from(messages: [
        _assistant(
          usage: const Usage(
              promptTokens: 1000, completionTokens: 200, cachedTokens: 760),
        ),
        _assistant(
          usage: const Usage(
              promptTokens: 500, completionTokens: 50, cachedTokens: 100),
        ),
      ]);

      expect(m.promptTokens, 1500);
      expect(m.completionTokens, 250);
      expect(m.totalTokens, 1750);
      expect(m.cacheHitRate, closeTo(860 / 1500, 1e-9));
    });

    test('promptTokens 为 0 时缓存命中率为 null（不做除零）', () {
      final m = SessionMetrics.from(messages: [
        _assistant(usage: const Usage(completionTokens: 10)),
      ]);

      expect(m.cacheHitRate, isNull);
      expect(m.tokensPerSecond, 0);
    });

    test('生成速率是加权平均，不是「各条速率的平均」', () {
      // 慢样本会主导结果：加权 = 110 tok / 11 s = 10 tok/s；
      // 若误用简单平均会得到 (100 + 1) / 2 = 50.5 tok/s。
      final m = SessionMetrics.from(messages: [
        _assistant(
          usage: const Usage(completionTokens: 100),
          elapsed: const Duration(milliseconds: 1000),
          ttft: Duration.zero,
        ),
        _assistant(
          usage: const Usage(completionTokens: 10),
          elapsed: const Duration(milliseconds: 10000),
          ttft: Duration.zero,
        ),
      ]);

      expect(m.tokensPerSecond, closeTo(10.0, 1e-6));
    });

    test('生成窗口扣除 TTFT——首 token 到达前不产出 token', () {
      // 总耗时 2s，其中 TTFT 1.5s → 生成窗口只有 0.5s。
      // 100 tok / 0.5 s = 200 tok/s；若按 elapsed 计算只有 50 tok/s。
      final m = SessionMetrics.from(messages: [
        _assistant(
          usage: const Usage(completionTokens: 100),
          elapsed: const Duration(milliseconds: 2000),
          ttft: const Duration(milliseconds: 1500),
        ),
      ]);

      expect(m.tokensPerSecond, closeTo(200.0, 1e-6));
    });

    test('TTFT 窗口溢出时回退到 elapsed，不产生负数或除零', () {
      final m = SessionMetrics.from(messages: [
        _assistant(
          usage: const Usage(completionTokens: 100),
          elapsed: const Duration(milliseconds: 500),
          ttft: const Duration(milliseconds: 900),
        ),
      ]);

      expect(m.tokensPerSecond, closeTo(200.0, 1e-6));
    });

    test('首 token 平均跳过没有 ttft 的消息', () {
      final m = SessionMetrics.from(messages: [
        _assistant(ttft: const Duration(milliseconds: 100)),
        _assistant(ttft: const Duration(milliseconds: 300)),
        _assistant(), // 无 ttft → 不计入平均
      ]);

      expect(m.avgTtft, const Duration(milliseconds: 200));
    });

    test('LLM 耗时累加 assistant 的 elapsed，工具耗时直接透传（已剔除审批等待）', () {
      final m = SessionMetrics.from(
        messages: [
          _user(),
          _assistant(elapsed: const Duration(seconds: 2)),
          _assistant(elapsed: const Duration(seconds: 3)),
        ],
        toolExecutionMs: 40000,
      );

      expect(m.llmTime, const Duration(seconds: 5));
      expect(m.toolTime, const Duration(seconds: 40));
    });
  });
}
