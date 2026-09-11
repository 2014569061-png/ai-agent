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
import '../widgets/nexus_page_header.dart';
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

  String _formatNextRun(ScheduleSpec spec, bool enabled) {
    if (!enabled) return '已暂停';
    final now = DateTime.now();
    for (int dayOffset = 0; dayOffset < 8; dayOffset++) {
      final targetDay = now.add(Duration(days: dayOffset));
      if (spec.days.isNotEmpty && !spec.days.contains(targetDay.weekday)) {
        continue;
      }
      final scheduledTime = DateTime(
        targetDay.year,
        targetDay.month,
        targetDay.day,
        spec.hour,
        spec.minute,
      );
      if (dayOffset == 0 && !now.isBefore(scheduledTime)) {
        continue;
      }
      final timeStr =
          '${spec.hour.toString().padLeft(2, '0')}:${spec.minute.toString().padLeft(2, '0')}';
      if (dayOffset == 0) return '今天 $timeStr';
      if (dayOffset == 1) return '明天 $timeStr';
      const weekdayMap = {
        1: '周一',
        2: '周二',
        3: '周三',
        4: '周四',
        5: '周五',
        6: '周六',
        7: '周日',
      };
      return '${weekdayMap[targetDay.weekday]} $timeStr';
    }
    return '待定';
  }

  Future<void> _create() async {
    final name = TextEditingController(text: '新闻摘要');
    final prompt = TextEditingController(text: '总结今日要闻，用 3 条要点输出');
    var hour = 9;
    var minute = 0;
    var days = <int>[];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          isDark ? AppPalette.darkSurface : AppPalette.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTokens.radiusModal)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => FractionallySizedBox(
          heightFactor: 0.85,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Row(
                      children: [
                        Text(
                          '新建定时任务',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          tooltip: '关闭',
                          onPressed: () => Navigator.pop(context, false),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: isDark
                        ? AppPalette.darkHairline
                        : AppPalette.lightHairline,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: name,
                            decoration: const InputDecoration(
                              labelText: '任务名称 *',
                              hintText: '如：早间简报、自动整理',
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: prompt,
                            maxLines: 4,
                            minLines: 2,
                            decoration: const InputDecoration(
                              labelText: '执行提示词 *',
                              hintText: '输入 Agent 定时执行的任务说明…',
                              alignLabelWithHint: true,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '执行时刻',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? AppPalette.darkTextMuted
                                  : AppPalette.lightTextMuted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: ImmersiveDropdown<int>(
                                  labelText: '时',
                                  initialValue: hour,
                                  items: [
                                    for (var i = 0; i < 24; i++)
                                      DropdownMenuItem(
                                          value: i,
                                          child: Text(
                                              '${i.toString().padLeft(2, '0')} 时'))
                                  ],
                                  onChanged: (v) =>
                                      setSheetState(() => hour = v ?? 9),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ImmersiveDropdown<int>(
                                  labelText: '分',
                                  initialValue: minute,
                                  items: [
                                    for (var i = 0; i < 60; i += 5)
                                      DropdownMenuItem(
                                          value: i,
                                          child: Text(
                                              '${i.toString().padLeft(2, '0')} 分'))
                                  ],
                                  onChanged: (v) =>
                                      setSheetState(() => minute = v ?? 0),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '周期重复（不选则每天执行）',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? AppPalette.darkTextMuted
                                  : AppPalette.lightTextMuted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final d in const [
                                (1, '周一'),
                                (2, '周二'),
                                (3, '周三'),
                                (4, '周四'),
                                (5, '周五'),
                                (6, '周六'),
                                (7, '周日'),
                              ])
                                FilterChip(
                                  label: Text(d.$2),
                                  selected: days.contains(d.$1),
                                  onSelected: (sel) => setSheetState(() {
                                    if (sel) {
                                      days.add(d.$1);
                                    } else {
                                      days.remove(d.$1);
                                    }
                                  }),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppPalette.darkSurface
                          : AppPalette.lightSurface,
                      border: Border(
                        top: BorderSide(
                          color: isDark
                              ? AppPalette.darkHairline
                              : AppPalette.lightHairline,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(
                                  AppTokens.kMinTouchTarget),
                            ),
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(
                                  AppTokens.kMinTouchTarget),
                              backgroundColor: AppPalette.brandAction,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () {
                              if (name.text.trim().isEmpty ||
                                  prompt.text.trim().isEmpty) {
                                return;
                              }
                              Navigator.pop(context, true);
                            },
                            child: const Text('创建'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
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
      appBar: const NexusPageHeader(
        title: '定时任务',
        subtitle: '自动化循环计划与后台执行',
      ),
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
                  final timeLabel =
                      '${spec.hour.toString().padLeft(2, '0')}:${spec.minute.toString().padLeft(2, '0')}';
                  final nextRun = _formatNextRun(spec, task.enabled);
                  final tz = DateTime.now().timeZoneName;

                  return SectionCard(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      leading: SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: Switch(
                            value: task.enabled,
                            onChanged: (v) => _toggle(task, v),
                          ),
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              task.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: task.enabled
                                  ? (isDark
                                      ? AppPalette.brandSoftDark
                                      : AppPalette.brandSoftLight)
                                  : (isDark
                                      ? AppPalette.darkCanvas
                                      : AppPalette.lightCanvas),
                              borderRadius: BorderRadius.circular(
                                  AppTokens.radiusControl),
                            ),
                            child: Text(
                              task.enabled ? '已启用' : '已暂停',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: task.enabled
                                    ? AppPalette.brandAction
                                    : (isDark
                                        ? AppPalette.darkTextMuted
                                        : AppPalette.lightTextMuted),
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$daysLabel $timeLabel · 下次：$nextRun · 时区：$tz',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: task.enabled
                                    ? (isDark ? Colors.white70 : Colors.black87)
                                    : (isDark
                                        ? AppPalette.darkTextMuted
                                        : AppPalette.lightTextMuted),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              task.prompt,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? AppPalette.darkTextMuted
                                    : AppPalette.lightTextMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '删除任务',
                        constraints: const BoxConstraints(
                          minWidth: AppTokens.kMinTouchTarget,
                          minHeight: AppTokens.kMinTouchTarget,
                        ),
                        onPressed: () => _delete(task),
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _create,
        tooltip: '新建定时任务',
        backgroundColor: AppPalette.brandAction,
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
