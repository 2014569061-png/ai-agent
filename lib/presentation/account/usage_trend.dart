import 'package:flutter/material.dart';

import '../../application/billing_api.dart';

class TokenTrend extends StatelessWidget {
  const TokenTrend({super.key, required this.days});
  final List<UsageDaily> days;

  @override
  Widget build(BuildContext context) {
    final maxTotal = days.fold<int>(
        0, (max, day) => day.totalTokens > max ? day.totalTokens : max);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('最近 7 天 Token 趋势',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        ...days.map((day) {
          final ratio = maxTotal == 0 ? 0.0 : day.totalTokens / maxTotal;
          final cacheRatio = day.promptTokens == 0
              ? 0.0
              : (day.cachedTokens / day.promptTokens).clamp(0.0, 1.0);
          return Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(children: [
              SizedBox(
                  width: 76,
                  child: Text(day.day, overflow: TextOverflow.ellipsis)),
              Expanded(
                child: Stack(alignment: Alignment.centerLeft, children: [
                  LinearProgressIndicator(value: ratio, minHeight: 8),
                  FractionallySizedBox(
                    widthFactor: ratio * cacheRatio,
                    child: Container(
                        height: 8,
                        color: Theme.of(context).colorScheme.secondary),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 92,
                child: Text('${day.totalTokens} · 缓存 ${day.cachedTokens}'),
              ),
            ]),
          );
        }),
      ]),
    );
  }
}
