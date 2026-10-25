import '../../theme/mobile_theme.dart';
import 'package:flutter/material.dart';

import '../../../domain/context_insights.dart';
import '../../theme/app_palette.dart';

class ContextBudgetHint extends StatelessWidget {
  const ContextBudgetHint(
      {super.key,
      required this.liveContextTokens,
      required this.contextTokens,
      required this.reservedOutputTokens,
      required this.running,
      required this.onTap,
      this.omittedContext = const []});
  final int liveContextTokens;
  final int contextTokens;
  final int reservedOutputTokens;
  final bool running;
  final List<String> omittedContext;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (omittedContext.isEmpty &&
        (running || contextTokens <= 0 || liveContextTokens <= 0)) {
      return const SizedBox.shrink();
    }
    final level = ContextBudget.levelFor(
        usedTokens: liveContextTokens,
        contextWindow: contextTokens,
        reservedOutputTokens: reservedOutputTokens);
    if (omittedContext.isEmpty && level == ContextBudgetLevel.normal) {
      return const SizedBox.shrink();
    }
    final percent = (ContextBudget.ratioFor(
                    usedTokens: liveContextTokens,
                    contextWindow: contextTokens,
                    reservedOutputTokens: reservedOutputTokens)
                .clamp(0.0, 1.0) *
            100)
        .round();
    final urgent = level == ContextBudgetLevel.critical;
    final warning = level == ContextBudgetLevel.warning;
    final color = urgent
        ? AppPalette.danger
        : warning
            ? AppPalette.warning
            : MobileTheme.brand(context);
    final hint = omittedContext.isNotEmpty
        ? '因预算省略：${omittedContext.join('、')}'
        : switch (level) {
            ContextBudgetLevel.attention => '上下文已使用 $percent%，建议打开指标查看增长来源',
            ContextBudgetLevel.warning => '上下文已使用 $percent%，建议优先处理工具结果',
            ContextBudgetLevel.critical => '上下文已使用 $percent%，下一轮需要裁剪或压缩',
            ContextBudgetLevel.normal => '',
          };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: (urgent
                ? AppPalette.danger
                : warning
                    ? AppPalette.warning
                    : MobileTheme.brand(context))
            .withValues(alpha: urgent || warning ? .14 : .10),
        borderRadius: BorderRadius.circular(MobileTheme.controlRadius(context)),
        child: InkWell(
          borderRadius:
              BorderRadius.circular(MobileTheme.controlRadius(context)),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              Icon(
                  urgent || warning
                      ? Icons.warning_amber_rounded
                      : Icons.compress_rounded,
                  size: 16,
                  color: color),
              const SizedBox(width: 7),
              Expanded(
                  child: Text(hint,
                      style: const TextStyle(fontSize: 12, height: 1.4))),
              const Icon(Icons.chevron_right_rounded, size: 18),
            ]),
          ),
        ),
      ),
    );
  }
}
