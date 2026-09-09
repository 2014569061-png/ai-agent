import 'package:flutter/material.dart';

import '../../application/billing_api.dart';
import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';

class TokenTrend extends StatelessWidget {
  const TokenTrend({
    super.key,
    required this.days,
    this.title,
    this.showTitle = true,
    this.padding = const EdgeInsets.all(16),
  });

  final List<UsageDaily> days;
  final String? title;
  final bool showTitle;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppTheme.semanticOf(context);

    if (days.isEmpty) {
      return Padding(
        padding: padding,
        child: Center(
          child: Text(
            AppStrings.noTokenData,
            style: TextStyle(fontSize: 13, color: semantic.mutedOnGlass),
          ),
        ),
      );
    }

    final maxTotal = days.fold<int>(
        0, (max, day) => day.totalTokens > max ? day.totalTokens : max);

    return Padding(
      padding: padding,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (showTitle) ...[
          Text(
            title ?? AppStrings.tokenTrend7Days,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 12),
        ],
        ...days.map((day) {
          final isNoData = day.totalTokens == 0;
          final ratio = maxTotal == 0 ? 0.0 : day.totalTokens / maxTotal;
          final cacheRatio = day.promptTokens == 0
              ? 0.0
              : (day.cachedTokens / day.promptTokens).clamp(0.0, 1.0);
          final dayLabel = day.isToday ? '${day.day} 今天' : day.day;
          return Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(children: [
              SizedBox(
                width: 86,
                child: Text(
                  dayLabel,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        day.isToday ? FontWeight.w600 : FontWeight.normal,
                    color: day.isToday ? theme.colorScheme.primary : null,
                  ),
                ),
              ),
              Expanded(
                child: Stack(alignment: Alignment.centerLeft, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 8,
                      backgroundColor: semantic.surfaceTint,
                    ),
                  ),
                  if (cacheRatio > 0)
                    FractionallySizedBox(
                      widthFactor: (ratio * cacheRatio).clamp(0.0, 1.0),
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.secondary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                ]),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: Text(
                  isNoData
                      ? '无数据'
                      : '${day.totalTokens} · ${AppStrings.cached} ${day.cachedTokens}',
                  style: TextStyle(
                    fontSize: 11,
                    color: semantic.mutedOnGlass,
                  ),
                ),
              ),
            ]),
          );
        }),
      ]),
    );
  }
}
