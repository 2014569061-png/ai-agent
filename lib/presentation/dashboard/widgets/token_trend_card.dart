import 'package:flutter/material.dart';

import '../../../application/billing_api.dart';
import '../../account/usage_report_page.dart';
import '../../account/usage_trend.dart';
import '../../l10n/app_strings.dart';
import '../../widgets/section_card.dart';

/// M2: Token 近 7 天用量趋势卡片
/// 包装泛化后的 TokenTrend 到 SectionCard，提供一键跳转至完整用量报告入口。
class TokenTrendCard extends StatelessWidget {
  const TokenTrendCard({super.key, required this.days});

  final List<UsageDaily> days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.trending_up_rounded,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    AppStrings.tokenTrend7Days,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const UsageReportPage()),
                  );
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppStrings.viewUsageReport,
                      style: TextStyle(fontSize: 12),
                    ),
                    SizedBox(width: 2),
                    Icon(Icons.chevron_right_rounded, size: 16),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TokenTrend(
            days: days,
            showTitle: false,
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}
