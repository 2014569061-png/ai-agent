import 'package:flutter/material.dart';

import '../../../application/dashboard_service.dart';
import '../../history/history_page.dart';
import '../../l10n/app_strings.dart';
import '../../tasks/development_tasks_page.dart';
import '../../theme/app_palette.dart';
import '../../widgets/nexus_metric_tile.dart';

/// M1: 2×2 核心 KPI 卡片网格
class KpiCardGrid extends StatelessWidget {
  const KpiCardGrid({super.key, required this.kpis});

  final DashboardKpis kpis;

  @override
  Widget build(BuildContext context) {
    final hasTokenData = kpis.todayTokens > 0;
    final cachePct =
        hasTokenData ? (kpis.cacheHitRate * 100).toStringAsFixed(0) : null;
    final successRate = kpis.taskSuccessRate;
    final successColor = successRate == null
        ? null
        : (successRate >= 90
            ? AppPalette.success
            : (successRate >= 75 ? AppPalette.warning : AppPalette.danger));

    return LayoutBuilder(builder: (context, constraints) {
      final itemWidth = (constraints.maxWidth - 12) / 2;

      return Wrap(
        spacing: 12,
        runSpacing: 12,
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

          // 2. 缓存命中率（今日 Token 详情已由 TokenUsageHero 承接）
          SizedBox(
            width: itemWidth,
            child: NexusMetricTile(
              label: AppStrings.cacheHitRate,
              value: cachePct == null ? '--' : '$cachePct%',
              explanation: AppStrings.cacheHitRateHint,
              icon: Icons.bolt_rounded,
              color: cachePct == null
                  ? null
                  : (int.parse(cachePct) >= 30 ? AppPalette.success : null),
              onTap: () {},
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
              color: kpis.runningTasks > 0 ? AppPalette.warning : null,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const DevelopmentTasksPage()),
                );
              },
            ),
          ),

          // 4. 用户好评率（样本数）
          SizedBox(
            width: itemWidth,
            child: NexusMetricTile(
              label: AppStrings.taskFeedbackRate,
              value: kpis.taskFeedbackRate == null
                  ? '--'
                  : '${kpis.taskFeedbackRate!.toStringAsFixed(0)}%',
              unit: AppStrings.taskFeedbackSamples(kpis.taskFeedbackSamples),
              icon: Icons.thumb_up_alt_outlined,
            ),
          ),

          // 5. 北极星指标：近 7 天被标记“有帮助”的开发任务数
          SizedBox(
            width: itemWidth,
            child: NexusMetricTile(
              label: AppStrings.weeklyHelpfulTasks,
              value: '${kpis.weeklyHelpfulTasks}',
              unit: '项',
              icon: Icons.thumb_up_alt_outlined,
              color: kpis.weeklyHelpfulTasks > 0 ? AppPalette.success : null,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const DevelopmentTasksPage()),
                );
              },
            ),
          ),

          // 6. 任务成功率（无已完成/失败任务时展示 --）
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
