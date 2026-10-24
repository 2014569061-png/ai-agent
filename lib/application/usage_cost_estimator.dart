// 按模型价目表估算一次调用的成本与缓存节省（单位：分）。
//
// 从 ChatController 抽出，行为保持不变。价格优先取服务商自定义配置，
// 缺省时回退到本地价目表。

import '../domain/models.dart';
import '../infrastructure/providers/provider_config.dart';

/// 本地价目表：模型名 -> (输入每百万 token 分, 输出每百万 token 分)。
const _fallbackRates = <String, (int, int)>{
  'gpt-4o-mini': (2, 9),
  'gpt-4o': (35, 140),
  'claude-sonnet-4-5': (45, 190),
  'deepseek-chat': (3, 11),
  'deepseek-reasoner': (6, 22),
};

/// 估算成本：返回 (本次成本分, 缓存命中节省分)。无法估算时两者均为 null。
({int? costCents, int? savedCostCents}) estimateUsageCostCents(
    ProviderConfig config, Usage usage) {
  final fallback = _fallbackRates[config.model];
  final inputRate = config.inputPricePerMillionCents ?? fallback?.$1;
  final outputRate = config.outputPricePerMillionCents ?? fallback?.$2;
  final cachedRate = config.cachedPricePerMillionCents ??
      (inputRate == null ? null : (inputRate / 10).round());
  if (inputRate == null ||
      outputRate == null ||
      cachedRate == null ||
      usage.totalTokens == 0) {
    return (costCents: null, savedCostCents: null);
  }
  final freshInput =
      (usage.promptTokens - usage.cachedTokens).clamp(0, 1 << 30);
  final cost = ((freshInput * inputRate +
              usage.cachedTokens * cachedRate +
              usage.completionTokens * outputRate) /
          1000000)
      .ceil();
  final saved =
      ((usage.cachedTokens * (inputRate - cachedRate)) / 1000000).ceil();
  return (costCents: cost, savedCostCents: saved);
}
