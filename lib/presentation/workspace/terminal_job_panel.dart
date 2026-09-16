import 'package:flutter/material.dart';

import '../../infrastructure/tools/command_tool.dart';
import '../theme/app_tokens.dart';
import '../widgets/nexus_list_tile.dart';
import '../widgets/section_card.dart';

class TerminalJobPanel extends StatelessWidget {
  const TerminalJobPanel({
    super.key,
    required this.jobs,
    required this.activeJobId,
    required this.onSelect,
    required this.onCancel,
  });

  final List<TerminalJobSnapshot> jobs;
  final String? activeJobId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onCancel;

  @override
  Widget build(BuildContext context) {
    if (jobs.isEmpty) {
      return const SizedBox.shrink();
    }
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('作业', style: Theme.of(context).textTheme.titleSmall),
          ),
          for (final job in jobs)
            NexusListTile(
              icon: job.completed
                  ? Icons.check_circle_outline
                  : Icons.timelapse,
              title: job.command,
              subtitle: job.completed
                  ? '已结束 · 退出码 ${job.exitCode ?? '-'}'
                  : (job.jobId == activeJobId ? '运行中（当前）' : '运行中'),
              onTap: () => onSelect(job.jobId),
              trailing: job.completed
                  ? null
                  : IconButton(
                      tooltip: '停止该作业',
                      icon: const Icon(Icons.stop_rounded),
                      onPressed: () => onCancel(job.jobId),
                    ),
            ),
          const SizedBox(height: AppTokens.sp2),
        ],
      ),
    );
  }
}
