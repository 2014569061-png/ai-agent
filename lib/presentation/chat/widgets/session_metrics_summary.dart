import 'package:flutter/material.dart';
import '../../../domain/context_insights.dart';
import '../../../domain/models.dart';
import '../../../domain/session_metrics.dart';
import '../../dashboard/widgets/token_numbers.dart';
import '../../theme/app_tokens.dart';
import 'context_budget_bar.dart';

/// A compact overview; detailed telemetry remains available via explicit disclosure.
class SessionMetricsSummary extends StatelessWidget {
  const SessionMetricsSummary(
      {super.key,
      required this.metrics,
      required this.used,
      required this.limit,
      required this.reserved,
      required this.timing,
      this.usage,
      this.status});
  final SessionMetrics metrics;
  final int used, limit, reserved;
  final TimingSnapshot timing;
  final Usage? usage;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final ratio = ContextBudget.ratioFor(
        usedTokens: used, contextWindow: limit, reservedOutputTokens: reserved);
    final measured = usage?.usageReported ?? false;
    final recorded = measured || metrics.totalTokens > 0;
    final prompt = usage?.promptTokens ?? metrics.promptTokens;
    final output = usage?.completionTokens ?? metrics.completionTokens;
    final wall = timing.wallMs;
    final aggregate = metrics.llmTime + metrics.toolTime;
    final items = <(String, String, String)>[
      (
        '上下文占用',
        limit > 0 ? '≈${(ratio * 100).round()}%' : '未知',
        '估算 · 含输出预留 ${formatCompact(reserved)} tok'
      ),
      (
        '输入 / 输出',
        recorded
            ? '${formatCompact(prompt)} / ${formatCompact(output)}'
            : '未记录',
        measured
            ? 'tok · 服务商上报'
            : recorded
                ? 'tok · 会话累计记录'
                : '服务商未上报用量'
      ),
      (
        '耗时',
        wall > 0
            ? formatDurationLabel(Duration(milliseconds: wall))
            : aggregate > Duration.zero
                ? formatDurationLabel(aggregate)
                : '未记录',
        wall > 0
            ? '已测量 · 运行总耗时'
            : aggregate > Duration.zero
                ? '已记录 · 模型与工具累计'
                : '无耗时样本'
      ),
      ('状态', status?.isNotEmpty == true ? status! : '未记录', '详细执行结果见消息与事件'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (limit > 0)
        Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ContextBudgetBar(
                segments: [
                  ContextBudgetSegment(
                      tokens: used,
                      color: contextBudgetColor(ContextBudget.levelFor(
                          usedTokens: used,
                          contextWindow: limit,
                          reservedOutputTokens: reserved)))
                ],
                limit: limit,
                reservedOutputTokens: reserved,
                fallbackRatio: ratio,
                fallbackColor: contextBudgetColor(ContextBudget.levelFor(
                    usedTokens: used,
                    contextWindow: limit,
                    reservedOutputTokens: reserved)))),
      LayoutBuilder(builder: (context, constraints) {
        final wideText = MediaQuery.textScalerOf(context).scale(14) > 21;
        final width = wideText || constraints.maxWidth < 280
            ? constraints.maxWidth
            : (constraints.maxWidth - 12) / 2;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final item in items)
            SizedBox(
                width: width,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius:
                          BorderRadius.circular(AppTokens.radiusCard)),
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.$1,
                                style: Theme.of(context).textTheme.labelMedium),
                            const SizedBox(height: 6),
                            Text(item.$2,
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text(item.$3,
                                style: Theme.of(context).textTheme.bodySmall),
                          ])),
                )),
        ]);
      }),
    ]);
  }
}
