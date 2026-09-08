import 'package:flutter/material.dart';

import '../../../application/dashboard_service.dart';
import '../../account/usage_report_page.dart';
import '../../history/history_page.dart';
import '../../l10n/app_strings.dart';
import '../../tasks/development_tasks_page.dart';
import '../../theme/app_theme.dart';
import '../../widgets/nexus_metric_tile.dart';

/// M1: 2×2 核心 KPI 卡片网格
/// 复用 NexusMetricTile 统一排版与可读性解释。
///
/// 空值约定：无数据展示 `--`（绝不显示 0 误导）；仅"今日会话/进行中任务"
/// 的 0 是合法业务值，保留显示。
class KpiCardGrid extends StatelessWidget {
  const KpiCardGrid({super.key, required this.kpis});

  final DashboardKpis kpis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasTokenData = kpis.todayTokens > 0;
    final cachePct =
        hasTokenData ? (kpis.cacheHitRate * 100).toStringAsFixed(0) : null;
    final successRate = kpis.taskSuccessRate;
    final successColor = successRate == null
        ? null
        : (successRate >= 90
            ? AppTheme.success
            : (successRate >= 75 ? AppTheme.warning : AppTheme.danger));

    return LayoutBuilder(builder: (context, constraints) {
      final itemWidth = (constraints.maxWidth - 10) / 2;

      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          // 1. 今日会话
          SizedBox(
            width: itemWidth,
            child: NexusMetricTile(
              label: AppStrings.todayConversations,
              value: '${kpis.todayConversations}',
              unit: '条',
              icon: Icons.chat_bubble_outline_rounded,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HistoryPage()),
                );
              },
            ),
          ),

          // 2. 今日 Token
          SizedBox(
            width: itemWidth,
            child: NexusMetricTile(
              label: AppStrings.todayTokens,
              value: hasTokenData
                  ? NexusMetricTile.formatTokens(kpis.todayTokens)
                  : '--',
              unit: hasTokenData ? 'T' : null,
              explanation:
                  hasTokenData ? '${AppStrings.cacheHit} $cachePct%' : null,
              icon: Icons.data_usage_rounded,
              color: theme.colorScheme.primary,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const UsageReportPage()),
                );
              },
            ),
          ),

          // 3. 进行中任务
          SizedBox(
            width: itemWidth,
            child: NexusMetricTile(
              label: AppStrings.runningTasks,
              value: '${kpis.runningTasks}',
              unit: '项',
              icon: Icons.pending_actions_rounded,
              color: kpis.runningTasks > 0 ? AppTheme.warning : null,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const DevelopmentTasksPage()),
                );
              },
            ),
          ),

          // 4. 任务成功率（无已完成/失败任务时展示 --）
          SizedBox(
            width: itemWidth,
            child: NexusMetricTile(
              label: AppStrings.taskSuccessRate,
              value: successRate == null
                  ? '--'
                  : '${successRate.toStringAsFixed(0)}%',
              icon: Icons.task_alt_rounded,
              color: successColor,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const DevelopmentTasksPage()),
                );
              },
            ),
          ),
        ],
      );
    });
  }
}
