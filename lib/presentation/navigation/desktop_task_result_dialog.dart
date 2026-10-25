import 'package:flutter/material.dart';
import '../../application/task_service.dart';
import '../../application/development_verification.dart';
import '../diagnostics/log_viewer_page.dart';
import '../tasks/task_details_page.dart';

class DesktopTaskResultDialog extends StatelessWidget {
  const DesktopTaskResultDialog(
      {super.key, required this.task, required this.onReview});
  final DevelopmentTaskInfo task;
  final VoidCallback onReview;
  @override
  Widget build(BuildContext context) {
    final steps = task.verificationPlan?.steps ?? const <VerificationStep>[];
    return AlertDialog(
        title: Text(task.title),
        content: SizedBox(
            width: 720,
            height: 520,
            child: ListView(children: [
              Text('任务状态：${task.status}'),
              const SizedBox(height: 8),
              SelectableText(task.summary ?? '暂无结果摘要'),
              const Divider(height: 24),
              Text('修改文件', style: Theme.of(context).textTheme.titleMedium),
              if (task.changeReview?.files.isEmpty ?? true)
                const Text('未记录文件修改'),
              for (final file in task.changeReview?.files ?? [])
                ListTile(
                    dense: true,
                    title: Text(file.path),
                    subtitle: Text(
                        '${file.operation}  +${file.linesAdded} −${file.linesRemoved}')),
              const Divider(height: 24),
              Text('验证与产物', style: Theme.of(context).textTheme.titleMedium),
              if (steps.isEmpty) const Text('未记录验证步骤，不能据此判定检查通过。'),
              for (final step in steps)
                ExpansionTile(
                    title: Text('${step.status.label} · ${step.title}'),
                    subtitle:
                        Text('${step.command}\n退出码：${step.exitCode ?? '未记录'}'),
                    children: [
                      Padding(
                          padding: const EdgeInsets.all(12),
                          child: SelectableText(
                              '${step.error ?? ''}\n${step.output}')),
                      if (step.expectedArtifactPath != null)
                        Padding(
                            padding: const EdgeInsets.all(12),
                            child: SelectableText(
                                '产物：${step.expectedArtifactPath}'))
                    ]),
              if (task.structuredResult != null) ...[
                const Divider(height: 24),
                Text('证据与剩余问题', style: Theme.of(context).textTheme.titleMedium),
                for (final item in [
                  ...task.structuredResult!.evidence,
                  ...task.structuredResult!.risks,
                  ...task.structuredResult!.nextSteps
                ])
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: SelectableText(item)),
              ],
            ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => LogViewerPage(runId: task.runId))),
              child: const Text('运行日志')),
          TextButton(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => TaskDetailsPage(task: task))),
              child: const Text('完整任务记录')),
          FilledButton(
              onPressed: () {
                Navigator.pop(context);
                onReview();
              },
              child: const Text('审查改动与恢复')),
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ]);
  }
}
