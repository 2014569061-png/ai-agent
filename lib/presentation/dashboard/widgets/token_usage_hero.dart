import 'package:flutter/material.dart';

import '../../../application/dashboard_service.dart';
import '../../l10n/app_strings.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/section_card.dart';
import 'token_numbers.dart';

/// 今日 Token 用量总览 Hero。
///
/// 定位：Dashboard 顶部第一块，用「大数字 + 分段比例条 + 精确分项」把
/// 具体的 token 数字直接摆出来（输入 / 缓存 / 输出），底栏给调用次数与费用。
/// 视觉遵循极简规范：白卡 + hairline、单一强调色只用于「输出」段与数字。
class TokenUsageHero extends StatelessWidget {
  const TokenUsageHero({super.key, required this.days});

  final List<UsageDaily> days;

  /// 从 7 天桶里取「今天」的用量明细；无今日数据时视为空（页面不崩）。
  UsageDaily? get _today => days.where((d) => d.isToday).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final text = isDark ? AppPalette.darkText : AppPalette.lightText;
    final muted = isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final faint = isDark ? AppPalette.darkTextFaint : AppPalette.lightTextFaint;

    final today = _today;
    final hasData = today != null && today.promptTokens + today.completionTokens > 0;

    final prompt = hasData ? today.promptTokens : 0;
    final cached = hasData ? today.cachedTokens.clamp(0, prompt).toInt() : 0;
    final completion = hasData ? today.completionTokens : 0;
    final freshInput = (prompt - cached).clamp(0, prompt).toInt();
    final total = prompt + completion;
    final calls = hasData ? today.calls : 0;
    final costYuan = formatCostYuan(hasData ? today.costCents : 0);
    final cacheRate = hasData && total > 0 ? cached / total : null;

    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行：今日 Token + 缓存命中率徽标
          Row(
            children: [
              Icon(Icons.data_usage_rounded, size: 16, color: muted),
              const SizedBox(width: 6),
              Text(
                AppStrings.todayTokens,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: muted,
                ),
              ),
              const Spacer(),
              if (cacheRate != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark ? AppPalette.darkBrandSoft : AppPalette.lightBrandSoft,
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                  ),
                  child: Text(
                    '${AppStrings.cacheHit} ${formatPercent(cacheRate)}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? AppPalette.brand
                          : AppPalette.brandOnSoft,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // 大数字
          hasData
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      formatExact(total),
                      style: TextStyle(
                        fontSize: 32,
                        height: 1.1,
                        fontWeight: FontWeight.w500,
                        color: text,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'tok',
                      style: TextStyle(fontSize: 13, color: faint),
                    ),
                  ],
                )
              : Text(
                  '--',
                  style: TextStyle(
                    fontSize: 32,
                    height: 1.1,
                    fontWeight: FontWeight.w500,
                    color: faint,
                  ),
                ),
          const SizedBox(height: 14),

          // 分段比例条：输入(未缓存) / 缓存 / 输出
          _TokenSegmentBar(
            freshInput: freshInput,
            cached: cached,
            completion: completion,
          ),
          const SizedBox(height: 12),

          // 分项精确数字（图例）
          Row(
            children: [
              _SegmentLegend(
                color: isDark ? AppPalette.darkTextFaint : AppPalette.lightTextFaint,
                label: AppStrings.promptTokens,
                value: formatExact(freshInput),
              ),
              const SizedBox(width: 16),
              _SegmentLegend(
                color: isDark ? AppPalette.brand : AppPalette.brand,
                label: AppStrings.outputTokens,
                value: formatExact(completion),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _SegmentLegend(
                color: isDark ? AppPalette.darkBrandSoft : AppPalette.lightBrandSoft,
                label: AppStrings.cachedTokens,
                value: formatExact(cached),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 底部分隔 + 调用次数 / 费用
          Divider(height: 1, thickness: 1, color: isDark ? AppPalette.darkHairline : AppPalette.lightHairline),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.call_made_rounded, size: 14, color: muted),
              const SizedBox(width: 6),
              Text(
                '${AppStrings.callsLabel} $calls',
                style: TextStyle(fontSize: 13, color: muted),
              ),
              const Spacer(),
              if (costYuan != null)
                Text(
                  '${AppStrings.costLabel} ¥$costYuan',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 三段式比例条：输入(未缓存) / 缓存 / 输出。
/// 纯色块堆叠，无渐变无投影，符合禁用清单。
class _TokenSegmentBar extends StatelessWidget {
  const _TokenSegmentBar({
    required this.freshInput,
    required this.cached,
    required this.completion,
  });

  final int freshInput;
  final int cached;
  final int completion;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget segment(int value, Color color) {
      if (value <= 0) return const SizedBox.shrink();
      return Expanded(
        flex: value,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 8,
        child: Row(
          children: [
            segment(freshInput,
                isDark ? AppPalette.darkTextFaint : AppPalette.lightTextFaint),
            segment(cached,
                isDark ? AppPalette.darkBrandSoft : AppPalette.lightBrandSoft),
            segment(completion, AppPalette.brand),
          ],
        ),
      ),
    );
  }
}

/// 图例项：色点 + 标签 + 精确数字。
class _SegmentLegend extends StatelessWidget {
  const _SegmentLegend({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? AppPalette.darkText : AppPalette.lightText;
    final muted = isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    return Expanded(
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}