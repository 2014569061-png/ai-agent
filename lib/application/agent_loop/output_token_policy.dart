/// 单次模型输出上限（请求里的 max_tokens / max_completion_tokens）的解析策略。
///
/// 背景：推理模型（阶跃 Step、DeepSeek-R1、o 系列等）的输出上限通常同时约束
/// “思考 + 正文”。旧的全局默认 2048 在对话变长、思考变多后会被思考耗尽，
/// 表现为回复半截中断或干脆为空。
///
/// 规则：
/// - 用户显式配置的非默认值原样尊重；
/// - 等于旧默认 [legacyDefault]（Agent 表默认值/未选 Agent）视为“未设置”，
///   推理模型给 [reasoningDefault]，其他模型给 [standardDefault]（4096 对
///   几乎所有常见模型都在其输出上限之内，避免 400）；
/// - 自动值不超过上下文窗口的一半，保证输入侧仍有足够空间；不低于旧默认。
abstract final class OutputTokenPolicy {
  static const legacyDefault = 2048;
  static const standardDefault = 4096;
  static const reasoningDefault = 16384;

  static int resolve({
    required String model,
    required int configured,
    required int contextWindow,
  }) {
    if (configured != legacyDefault) return configured;
    var value = isReasoningModel(model) ? reasoningDefault : standardDefault;
    if (contextWindow > 0) {
      final cap = contextWindow ~/ 2;
      if (cap < value) value = cap;
    }
    return value < legacyDefault ? legacyDefault : value;
  }

  /// 按模型名识别“会先长篇思考”的推理模型族。宁缺毋滥：误判为推理模型只会
  /// 让自动上限更大，而部分老模型会以 400 拒绝过大的 max_tokens。
  static bool isReasoningModel(String model) {
    final lower = model.toLowerCase();
    final name = lower.contains('/') ? lower.split('/').last : lower;
    return name.startsWith('step-') ||
        name.startsWith('o1') ||
        name.startsWith('o3') ||
        name.startsWith('o4') ||
        name.startsWith('gpt-5') ||
        name.startsWith('qwq') ||
        name.startsWith('qwen3') ||
        name.startsWith('glm-z1') ||
        name.contains('deepseek-r1') ||
        name.contains('deepseek-reasoner') ||
        name.contains('reasoner') ||
        name.contains('reasoning') ||
        name.contains('thinking');
  }
}
