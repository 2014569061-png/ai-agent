import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/dashboard_service.dart';
import '../../../application/providers.dart';
import '../../../application/task_service.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../l10n/app_strings.dart';
import '../../tasks/development_tasks_page.dart';
import '../../tasks/task_details_page.dart';
import '../../theme/app_theme.dart';
import '../../widgets/nexus_metric_tile.dart';
import '../../widgets/nexus_section.dart';
import '../../widgets/nexus_status_pill.dart';
import '../../widgets/section_card.dart';

/// M3: 运行状态与最近任务列表
/// 展示最近 6 条 Agent / 开发任务，状态横标 + 耗时，直跳任务详情。
class RunStatusList extends ConsumerWidget {
  const RunStatusList({
    super.key,
    required this.runs,
    this.onConversationSelected,
  });

  final List<DashboardRunItem> runs;
  final ValueChanged<Conversation>? onConversationSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final semantic = AppTheme.semanticOf(context);

    return NexusSection(
      title: AppStrings.runStatus,
      icon: Icons.alt_route_rounded,
      trailing: TextButton(
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DevelopmentTasksPage()),
          );
        },
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppStrings.viewAll, style: TextStyle(fontSize: 12)),
            SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: 16),
          ],
        ),
      ),
      child: SectionCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: runs.isEmpty
            ? Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                child: Center(
                  child: Text(
                    AppStrings.noRunningRecords,
                    style: TextStyle(
                      fontSize: 13,
                      color: semantic.mutedOnGlass,
                    ),
                  ),
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: runs.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  thickness: 0.6,
                  color: semantic.border.withValues(alpha: 0.35),
                  indent: 16,
                  endIndent: 16,
                ),
                itemBuilder: (ctx, index) {
                  final item = runs[index];
                  final durationStr = item.durationMs != null
                      ? NexusMetricTile.formatDuration(item.durationMs)
                      : '';

                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    title: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          NexusStatusPill.fromString(
                            item.status,
                            isCompact: true,
                          ),
                          if (durationStr.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              AppStrings.durationLabel(durationStr),
                              style: TextStyle(
                                fontSize: 11,
                                color: semantic.mutedOnGlass,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: Colors.grey,
                    ),
                    onTap: () async {
                      final db = await ref.read(databaseProvider.future);
                      final task = await db.findTask(item.id);
                      if (task != null && context.mounted) {
                        final info = DevelopmentTaskInfo.fromTask(task);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TaskDetailsPage(
                              task: info,
                              onConversationSelected: onConversationSelected,
                            ),
                          ),
                        );
                      } else if (context.mounted) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const DevelopmentTasksPage()),
                        );
                      }
                    },
                  );
                },
              ),
      ),
    );
  }
}
