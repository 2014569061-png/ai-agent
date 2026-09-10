import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../application/scheduled_task_service.dart';
import '../../infrastructure/database/app_database.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../widgets/async_state_view.dart';
import '../widgets/confirm_action.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/immersive_dropdown.dart';
import '../widgets/immersive_sheet.dart';
import '../widgets/section_card.dart';
import '../widgets/floating_toast.dart';

/// 定时任务管理页（C5）：新建「每天/每周某时刻」执行指定提示词的 Agent 任务。
class ScheduledTasksPage extends ConsumerStatefulWidget {
  const ScheduledTasksPage({super.key});

  @override
  ConsumerState<ScheduledTasksPage> createState() => _ScheduledTasksPageState();
}

class _ScheduledTasksPageState extends ConsumerState<ScheduledTasksPage> {
  bool _loading = true;
  Object? _error;
  List<ScheduledTask> _tasks = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final db = await ref.read(databaseProvider.future);
      final tasks = await db.allScheduledTasks();
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _toggle(ScheduledTask task, bool enabled) async {
    final db = await ref.read(databaseProvider.future);
    await db.saveScheduledTask(
        task.copyWith(enabled: enabled, updatedAt: DateTime.now()));
    await _load();
  }

  Future<void> _delete(ScheduledTask task) async {
    final confirmed = await showConfirmAction(context,
        title: '删除定时任务？',
        message: '将删除“${task.name}”及其执行计划。',
        confirmLabel: '删除');
    if (!confirmed || !mounted) return;
    try {
      final db = await ref.read(databaseProvider.future);
      await db.deleteScheduledTask(task.id);
      await _load();
      if (mounted) FloatingToast.show(context, '定时任务已删除');
    } catch (error) {
      if (mounted) FloatingToast.show(context, '删除失败：$error');
    }
  }

  Future<void> _create() async {
    final name = TextEditingController(text: '新闻摘要');
    final prompt = TextEditingController(text: '总结今日要闻，用 3 条要点输出');
    var hour = 9;
    var minute = 0;
    var days = <int>[];

    final saved = await showImmersiveDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('新建定时任务'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '任务名称')),
              const SizedBox(height: 12),
              TextField(
                  controller: prompt,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '提示词')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: ImmersiveDropdown<int>(
                    labelText: '时',
                    initialValue: hour,
                    items: [
                      for (var i = 0; i < 24; i++)
                        DropdownMenuItem(value: i, child: Text('$i 时'))
                    ],
                    onChanged: (v) => setDialogState(() => hour = v ?? 9),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ImmersiveDropdown<int>(
                    labelText: '分',
                    initialValue: minute,
                    items: [
                      for (var i = 0; i < 60; i += 5)
                        DropdownMenuItem(value: i, child: Text('$i 分'))
                    ],
                    onChanged: (v) => setDialogState(() => minute = v ?? 0),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 6, children: [
                for (final d in const [
                  (1, '周一'),
                  (2, '周二'),
                  (3, '周三'),
                  (4, '周四'),
                  (5, '周五'),
                  (6, '周六'),
                  (7, '周日')
                ])
                  FilterChip(
                    label: Text(d.$2),
                    selected: days.contains(d.$1),
                    onSelected: (sel) => setDialogState(() {
                      if (sel) {
                        days.add(d.$1);
                      } else {
                        days.remove(d.$1);
                      }
                    }),
                  ),
              ]),
              const SizedBox(height: 4),
              Text('不选则每天执行',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppPalette.darkTextMuted
                          : AppPalette.lightTextMuted)),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
            FilledButton(
                style: FilledButton.styleFrom(
                  elevation: 0,
                  backgroundColor: AppPalette.brand,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppTokens.radiusControl),
                  ),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('创建')),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final db = await ref.read(databaseProvider.future);
    await ref.read(scheduledTaskServiceProvider).create(
          db: db,
          name: name.text.trim().isEmpty ? '定时任务' : name.text.trim(),
          prompt: prompt.text.trim(),
          schedule: ScheduleSpec(hour: hour, minute: minute, days: days),
        );
    await _load();
    if (mounted) FloatingToast.show(context, '已创建（约每 15 分钟检查一次，实际执行时间可能略有偏差）');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas,
      appBar: AppBar(title: const Text('定时任务')),
      body: AsyncStateView(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: _tasks.isEmpty
            ? const EmptyStateView(
                icon: Icons.schedule_outlined,
                title: '无定时任务',
                message: '还没有定时任务，点击右下角新建')
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _tasks.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final task = _tasks[index];
                  final spec = ScheduleSpec.fromCron(task.cron);
                  final daysLabel =
                      spec.days.isEmpty ? '每天' : '周${spec.days.join('/')}';
                  return SectionCard(
                    child: ListTile(
                      leading: Switch(
                          value: task.enabled,
                          onChanged: (v) => _toggle(task, v)),
                      title: Text(
                        task.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        '$daysLabel ${spec.hour}:${spec.minute.toString().padLeft(2, '0')} · ${task.prompt}',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? AppPalette.darkTextMuted
                              : AppPalette.lightTextMuted,
                        ),
                      ),
                      trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(task)),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _create,
        backgroundColor: AppPalette.brand,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}
