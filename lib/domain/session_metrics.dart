import 'models.dart';

/// 会话级指标聚合（纯派生值，不落库）。
///
/// 设计要点：
/// * **轮** = 用户消息条数（一个用户请求算一轮）。
/// * **步** = agent 循环迭代次数，由 [totalSteps] 注入 —— 一轮对话只落一条
///   最终 assistant 消息，所以步数无法从消息条数推导，必须由控制器在
///   `RunStatus.waitingModel` 时累计。
/// * **工具耗时** = 只累计工具真实执行区间（[toolExecutionMs] 由 ToolActivity
///   在「执行中」区间内累计），**不含等待人工审批的时间**。
/// * **生成速率** 用 `completionTokens / (elapsed - ttft)` 求和后再相除（加权），
///   而不是「各条速率的平均值」——后者会让短回复被过度放大；同时扣掉 TTFT，
///   因为首 token 到达前并没有产出 token。
class SessionMetrics {
  const SessionMetrics({
    required this.rounds,
    required this.steps,
    required this.llmTime,
    required this.toolTime,
    required this.avgTtft,
    required this.tokensPerSecond,
    required this.cacheHitRate,
    required this.promptTokens,
    required this.completionTokens,
  });

  /// 轮：用户消息条数。
  final int rounds;

  /// 步：agent 循环迭代次数（= 模型调用次数）。
  final int steps;

  /// LLM 累计耗时（各轮 assistant 消息的 elapsed 之和）。
  final Duration llmTime;

  /// 工具累计真实执行耗时，不含审批等待。
  final Duration toolTime;

  /// 首 token 平均耗时；无样本时为 null。
  final Duration? avgTtft;

  /// 加权生成速率（tok/s）；无可测算样本时为 0。
  final double tokensPerSecond;

  /// 缓存命中率 0..1；promptTokens 为 0 时为 null。
  final double? cacheHitRate;

  final int promptTokens;
  final int completionTokens;

  int get totalTokens => promptTokens + completionTokens;

  /// 空会话：既不显示指标条，也不展示详情。
  bool get isEmpty => rounds == 0 && steps == 0;

  static const empty = SessionMetrics(
    rounds: 0,
    steps: 0,
    llmTime: Duration.zero,
    toolTime: Duration.zero,
    avgTtft: null,
    tokensPerSecond: 0,
    cacheHitRate: null,
    promptTokens: 0,
    completionTokens: 0,
  );

  /// 从消息列表与控制器累计值聚合出全部指标。
  ///
  /// [toolExecutionMs] 与 [steps] 由调用方从 `ChatState` 取。
  factory SessionMetrics.from({
    required List<ChatMessage> messages,
    int steps = 0,
    int toolExecutionMs = 0,
  }) {
    var rounds = 0;
    var prompt = 0;
    var completion = 0;
    var cached = 0;
    var llmMs = 0;
    var generationMs = 0;
    var ttftSumMs = 0;
    var ttftCount = 0;

    for (final message in messages) {
      if (message.role == MessageRole.user) rounds++;

      final usage = message.usage;
      if (usage != null) {
        prompt += usage.promptTokens;
        completion += usage.completionTokens;
        cached += usage.cachedTokens;
      }

      if (message.role != MessageRole.assistant) continue;

      final elapsed = message.elapsed;
      if (elapsed != null) llmMs += elapsed.inMilliseconds;

      final ttft = message.ttft;
      if (ttft != null) {
        ttftSumMs += ttft.inMilliseconds;
        ttftCount++;
      }

      // 只把「真的产出了 token」的轮次计入速率分母。
      if (elapsed != null && (usage?.completionTokens ?? 0) > 0) {
        final window = elapsed.inMilliseconds - (ttft?.inMilliseconds ?? 0);
        generationMs += window > 0 ? window : elapsed.inMilliseconds;
      }
    }

    return SessionMetrics(
      rounds: rounds,
      steps: steps,
      llmTime: Duration(milliseconds: llmMs),
      toolTime: Duration(milliseconds: toolExecutionMs),
      avgTtft: ttftCount > 0
          ? Duration(milliseconds: (ttftSumMs / ttftCount).round())
          : null,
      tokensPerSecond:
          generationMs > 0 ? completion * 1000 / generationMs : 0,
      cacheHitRate: prompt > 0 ? cached / prompt : null,
      promptTokens: prompt,
      completionTokens: completion,
    );
  }
}
