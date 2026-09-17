import 'package:flutter/material.dart';

import '../../../domain/session_metrics.dart';
import '../../dashboard/widgets/token_numbers.dart';
import '../../theme/app_palette.dart';
import '../../widgets/nexus_sheet.dart';
import '../../widgets/nexus_metric_tile.dart';

/// 打开会话指标详情弹层。
Future<void> showSessionMetricsSheet(
  BuildContext context, {
  required SessionMetrics metrics,
  int liveContextTokens = 0,
  int contextLimit = 0,
}) {
  return showNexusSheet<void>(
    context: context,
    builder: (_) => SessionMetricsSheet(
      metrics: metrics,
      liveContextTokens: liveContextTokens,
      contextLimit: contextLimit,
    ),
  );
}

/// 会话指标详情：紧凑型微仪表盘 HUD，优先展示高频核心 KPI，支持点击展开全量指标。
class SessionMetricsSheet extends StatefulWidget {
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
  State<SessionMetricsSheet> createState() => _SessionMetricsSheetState();
}

class _SessionMetricsSheetState extends State<SessionMetricsSheet> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final hairline =
        isDark ? AppPalette.darkHairline : AppPalette.lightHairline;
    final metrics = widget.metrics;

    final primaryCards = [
      _CompactKpiCard(
        icon: Icons.repeat_rounded,
        label: '轮次 · 步数',
        value: '${metrics.rounds}轮 · ${metrics.steps}步',
        isDark: isDark,
      ),
      _CompactKpiCard(
        icon: Icons.timer_outlined,
        label: 'LLM 耗时',
        value: formatDurationLabel(metrics.llmTime),
        isDark: isDark,
      ),
      _CompactKpiCard(
        icon: Icons.swap_vert_rounded,
        label: '输入 / 输出',
        value:
            '${formatCompact(metrics.promptTokens)} / ${formatCompact(metrics.completionTokens)}',
        isDark: isDark,
      ),
      _CompactKpiCard(
        icon: Icons.bolt_rounded,
        label: '生成速率',
        value: metrics.tokensPerSecond > 0
            ? '${metrics.tokensPerSecond.round()} tok/s'
            : '--',
        highlight: metrics.tokensPerSecond > 0,
        isDark: isDark,
      ),
    ];

    final detailedTiles = <Widget>[
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
        explanation: '加权平均：Σ输出 token ÷ Σ(elapsed − TTFT)',
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
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶栏：标题 + Token 徽标 + 关闭按钮
            Row(
              children: [
                const Icon(Icons.analytics_outlined, size: 20, color: AppPalette.brand),
                const SizedBox(width: 8),
                Text(
                  '会话指标',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: isDark ? 0.08 : 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: (isDark ? Colors.white : Colors.black)
                          .withValues(alpha: isDark ? 0.14 : 0.08),
                    ),
                  ),
                  child: Text(
                    '合计 ${formatCompact(metrics.totalTokens)} tok',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: textMuted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: Icon(Icons.close_rounded, size: 18, color: textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 上下文水位线性条
            if (widget.contextLimit > 0) ...[
              _ContextGauge(
                live: widget.liveContextTokens,
                limit: widget.contextLimit,
                hairline: hairline,
                textMuted: textMuted,
                textColor: textColor,
              ),
              const SizedBox(height: 12),
            ],

            // 核心高频 KPI 4格紧凑卡片 (2x2)
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.7,
              children: primaryCards,
            ),
            const SizedBox(height: 8),

            // 展开详细数据切换器
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _showDetails = !_showDetails),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _showDetails ? '收起详细指标' : '查看完整指标与说明',
                      style: TextStyle(fontSize: 11, color: textMuted),
                    ),
                    Icon(
                      _showDetails
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: textMuted,
                    ),
                  ],
                ),
              ),
            ),

            // 展开后的完整 9 个指标及说明
            if (_showDetails) ...[
              const SizedBox(height: 8),
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
                      for (final tile in detailedTiles)
                        SizedBox(width: itemWidth, child: tile),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              Text(
                '「工具耗时」只统计工具真实执行区间，审批等待时间不计入；'
                '指标随会话实时累计，暂不跨会话持久化。',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.45,
                  color: textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CompactKpiCard extends StatelessWidget {
  const _CompactKpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isDark;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;

    final cardBg = highlight
        ? AppPalette.brand.withValues(alpha: isDark ? 0.16 : 0.08)
        : (isDark ? Colors.white : Colors.black)
            .withValues(alpha: isDark ? 0.07 : 0.035);
    final cardBorder = highlight
        ? AppPalette.brand.withValues(alpha: isDark ? 0.50 : 0.40)
        : (isDark
            ? Colors.white.withValues(alpha: 0.14)
            : Colors.black.withValues(alpha: 0.07));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder, width: 0.8),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: (highlight ? AppPalette.brand : textMuted)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: highlight ? AppPalette.brand : textMuted,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color: textMuted,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: highlight ? AppPalette.brand : textColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
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
    final percent = (ratio * 100).toStringAsFixed(0);
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
            const SizedBox(width: 6),
            Text(
              '$percent%',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: barColor,
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
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2.5),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 5,
            backgroundColor: (textColor == AppPalette.darkText ? Colors.white : Colors.black)
                .withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
      ],
    );
  }
}
