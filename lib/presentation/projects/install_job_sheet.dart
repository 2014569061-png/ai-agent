import 'package:flutter/material.dart';

import '../../application/install_job_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/nexus_list_tile.dart';
import '../widgets/section_card.dart';

class InstallJobSheet extends StatelessWidget {
  const InstallJobSheet({
    super.key,
    required this.job,
    this.busy = false,
    this.onStart,
    this.onClose,
  });

  final InstallJob job;
  final bool busy;
  final VoidCallback? onStart;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final sizeMb = (job.estimatedBytes / (1024 * 1024)).toStringAsFixed(0);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('安装作业', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '估计约 ${sizeMb}MB · runtime ${job.runtimeId}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppTokens.sp3),
            SectionCard(
              child: Column(
                children: [
                  if (job.steps.isEmpty)
                    const NexusListTile(
                      icon: Icons.check_circle_outline,
                      title: '没有缺失项',
                      subtitle: '当前环境已满足该项目要求',
                    )
                  else
                    for (final step in job.steps)
                      NexusListTile(
                        icon: step.failed
                            ? Icons.error_outline
                            : step.completed
                                ? Icons.check_circle_outline
                                : Icons.timelapse,
                        title: step.label,
                        subtitle: [
                          step.command,
                          if (step.log.isNotEmpty) step.log,
                        ].join('\n'),
                      ),
                ],
              ),
            ),
            const SizedBox(height: AppTokens.sp4),
            Row(
              children: [
                if (onClose != null)
                  TextButton(
                    onPressed: busy ? null : onClose,
                    child: const Text('关闭'),
                  ),
                const Spacer(),
                if (job.status != 'completed' && job.steps.isNotEmpty)
                  FilledButton(
                    onPressed: busy ? null : onStart,
                    child: Text(busy ? '安装中…' : '开始安装'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
