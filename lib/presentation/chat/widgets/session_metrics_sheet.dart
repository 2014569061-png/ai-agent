import 'package:flutter/material.dart';

import '../../../domain/session_metrics.dart';
import '../../dashboard/widgets/token_numbers.dart';
import '../../theme/app_palette.dart';
import '../../widgets/immersive_sheet.dart';
import '../../widgets/nexus_metric_tile.dart';

/// 打开会话指标详情弹层。
Future<void> showSessionMetricsSheet(
  BuildContext context, {
  required SessionMetrics metrics,
  int liveContextTokens = 0,
  int contextLimit = 0,
}) {
  return showImmersiveSheet<void>(
    context: context,
    builder: (_) => SessionMetricsSheet(
      metrics: metrics,
      liveContextTokens: liveContextTokens,
      contextLimit: contextLimit,
    ),
  );
}

/// 会话指标详情：把指标条的摘要展开成可读的网格 + 上下文水位。
///
/// 口径与 [SessionMetrics] 完全一致，不在这里做二次计算。
class SessionMetricsSheet extends StatelessWidget {
  const SessionMetricsSheet({
    super.key,
    required this.metrics,
    this.liveContextTokens = 0,
    this.contextLimit = 0,
  });

  final SessionMetrics metrics;
  final int liveContextTokens;
  final int contextLimit;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final hairline = isDark ? AppPalette.darkHairline : AppPalette.lightHairline;

    final tiles = <Widget>[
      NexusMetricTile(
        label: '轮次',
        value: '${metrics.rounds}',
        unit: '轮',
        icon: Icons.repeat_rounded,
        explanation: '一个用户请求计一轮',
      ),
      NexusMetricTile(
        label: '步数',
        value: '${metrics.steps}',
        unit: '步',
        icon: Icons.timeline_rounded,
        explanation: 'agent 循环迭代次数，等于模型调用次数',
      ),
      NexusMetricTile(
        label: 'LLM 耗时',
        value: formatDurationLabel(metrics.llmTime),
        icon: Icons.memory_rounded,
        explanation: '各轮模型调用 elapsed 之和',
      ),
      NexusMetricTile(
        label: '工具耗时',
        value: formatDurationLabel(metrics.toolTime),
        icon: Icons.build_outlined,
        explanation: '只累计工具真实执行区间，不含等待人工审批的时间',
      ),
      NexusMetricTile(
        label: '首 token 平均',
        value: formatDurationLabel(metrics.avgTtft),
        icon: Icons.flash_on_rounded,
        explanation: '仅统计有 TTFT 样本的轮次',
      ),
      NexusMetricTile(
        label: '生成速率',
        value: metrics.tokensPerSecond > 0
            ? '${metrics.tokensPerSecond.round()}'
            : '--',
        unit: 'tok/s',
        icon: Icons.speed_rounded,
        color: metrics.tokensPerSecond > 0 ? AppPalette.success : null,
        explanation: '加权平均：Σ输出 token ÷ Σ(elapsed − TTFT)，已扣掉首 token 等待',
      ),
      NexusMetricTile(
        label: '缓存命中',
        value: formatPercent(metrics.cacheHitRate),
        icon: Icons.bolt_rounded,
        explanation: 'Σ缓存 token ÷ Σ输入 token',
      ),
      NexusMetricTile(
        label: '输入',
        value: formatCompact(metrics.promptTokens),
        unit: 'tok',
        icon: Icons.upload_rounded,
      ),
      NexusMetricTile(
        label: '输出',
        value: formatCompact(metrics.completionTokens),
        unit: 'tok',
        icon: Icons.download_rounded,
      ),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.analytics_outlined, size: 20, color: textColor),
                const SizedBox(width: 8),
                Text(
                  '会话指标',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                    color: textColor,
                  ),
                ),
                const Spacer(),
                Text(
                  '合计 ${formatCompact(metrics.totalTokens)} tok',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: textMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (contextLimit > 0) ...[
              _ContextGauge(
                live: liveContextTokens,
                limit: contextLimit,
                hairline: hairline,
                textMuted: textMuted,
                textColor: textColor,
              ),
              const SizedBox(height: 16),
            ],

            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 420 ? 3 : 2;
                const gap = 8.0;
                final itemWidth =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final tile in tiles)
                      SizedBox(width: itemWidth, child: tile),
                  ],
                );
              },
            ),

            const SizedBox(height: 16),
            Text(
              '「工具耗时」只统计工具真实执行区间，审批等待时间不计入；'
              '指标随会话实时累计，暂不跨会话持久化。',
              style: TextStyle(
                fontSize: 11,
                height: 1.55,
                color: textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContextGauge extends StatelessWidget {
  const _ContextGauge({
    required this.live,
    required this.limit,
    required this.hairline,
    required this.textMuted,
    required this.textColor,
  });

  final int live;
  final int limit;
  final Color hairline;
  final Color textMuted;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final ratio = limit > 0 ? (live / limit).clamp(0.0, 1.0) : 0.0;
    final barColor = ratio >= 0.95
        ? AppPalette.danger
        : ratio >= 0.8
            ? AppPalette.warning
            : AppPalette.brand;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '上下文水位',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: textMuted,
              ),
            ),
            const Spacer(),
            Text(
              '${formatCompact(live)} / ${formatCompact(limit)}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: textColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: hairline,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
      ],
    );
  }
}
