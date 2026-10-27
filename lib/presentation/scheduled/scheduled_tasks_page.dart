import '../theme/mobile_theme.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../widgets/nexus_page_layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../application/reminder_service.dart';
import '../../application/scheduled_task_service.dart';
import '../../domain/reminder.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/notifications/notification_service.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../widgets/async_state_view.dart';
import '../widgets/confirm_action.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/nexus_dropdown.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/section_card.dart';
import '../l10n/app_strings.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_sheet.dart';
import '../widgets/nexus_switch.dart';
import '../../application/local_error_copy.dart';

/// 定时任务管理页（C5）：新建「每天/每周某时刻」执行指定提示词的 Agent 任务。
class ScheduledTasksPage extends ConsumerStatefulWidget {
  const ScheduledTasksPage({super.key, this.initialReminderId});
  final String? initialReminderId;

  @override
  ConsumerState<ScheduledTasksPage> createState() => _ScheduledTasksPageState();
}

class _ScheduledTasksPageState extends ConsumerState<ScheduledTasksPage>
    with WidgetsBindingObserver {
  bool _loading = true;
  Object? _error;
  List<ScheduledTask> _tasks = [];
  List<ReminderItem> _reminders = [];
  ExactAlarmCapability? _currentReminderCapability;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_loading) _load();
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
      final reminders = await ReminderService(db).list();
      final capability =
          await NotificationService.instance.reminderCapability();
      reminders.sort((a, b) => a.id == widget.initialReminderId
          ? -1
          : b.id == widget.initialReminderId
              ? 1
              : a.effectiveTriggerUtc.compareTo(b.effectiveTriggerUtc));
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _reminders = reminders;
        _currentReminderCapability = capability;
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
      if (mounted) FloatingToast.show(context, LocalErrorCopy.of(error, action: '删除').headline());
    }
  }

  Future<void> _showHistory(ScheduledTask task) async {
    try {
      final db = await ref.read(databaseProvider.future);
      final logs = await db.scheduledTaskRunHistory(task.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${task.name} · 执行记录'),
          content: SizedBox(
            width: double.maxFinite,
            child: logs.isEmpty
                ? const Text('暂无执行记录')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: logs.length,
                    separatorBuilder: (_, __) => const Divider(height: 16),
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      Map<String, dynamic> detail;
                      try {
                        detail = Map<String, dynamic>.from(
                            jsonDecode(log.detail) as Map);
                      } catch (_) {
                        detail = const {};
                      }
                      final result = detail['result']?.toString() ?? '';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${detail['status'] ?? log.decision ?? '未知'} · '
                            '${log.createdAt.toLocal().toString().substring(0, 19)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (detail['durationMs'] is num)
                            Text('耗时 ${detail['durationMs']} ms'),
                          if (result.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            SelectableText(result),
                          ],
                        ],
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) FloatingToast.show(context, LocalErrorCopy.of(error, action: '读取执行记录').headline());
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

    final saved = await showNexusSheet<bool>(
      context: context,
      isScrollControlled: true,
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
                                    fontWeight: FontWeight.w500,
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
                                child: NexusDropdown<int>(
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
                                child: NexusDropdown<int>(
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
                              backgroundColor: MobileTheme.brand(context),
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
      removeInnerViewInsets: true,
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

  Future<void> _createQuickReminder() async {
    final title = TextEditingController();
    final notes = TextEditingController();
    var due = DateTime.now().add(const Duration(hours: 1));
    bool? accepted;
    try {
      accepted = await showNexusDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
              builder: (context, update) => AlertDialog(
                    title: const Text('新建提醒'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: title,
                          autofocus: true,
                          decoration: const InputDecoration(labelText: '提醒事项')),
                      TextField(
                          controller: notes,
                          decoration:
                              const InputDecoration(labelText: '备注（可选）')),
                      const SizedBox(height: 12),
                      Text(
                          '设备时区：${due.timeZoneName} · ${due.toString().substring(0, 16)}'),
                      TextButton(
                          onPressed: () async {
                            final day = await showDatePicker(
                                context: dialogContext,
                                initialDate: due,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 3650)));
                            if (day == null || !dialogContext.mounted) return;
                            final time = await showTimePicker(
                                context: dialogContext,
                                initialTime: TimeOfDay.fromDateTime(due));
                            if (time != null && dialogContext.mounted) {
                              update(() => due = DateTime(day.year, day.month,
                                  day.day, time.hour, time.minute));
                            }
                          },
                          child: const Text('选择日期与时间')),
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('取消')),
                      FilledButton(
                          onPressed: () {
                            if (title.text.trim().isEmpty ||
                                !due.isAfter(DateTime.now())) {
                              FloatingToast.show(context, '请输入提醒事项并选择未来时间');
                              return;
                            }
                            Navigator.pop(dialogContext, true);
                          },
                          child: const Text('创建')),
                    ],
                  )));
      if (accepted != true || !mounted) return;
      await NotificationService.instance.ensurePermissionOnce();
      if (!mounted) return;
      final db = await ref.read(databaseProvider.future);
      final item = await ReminderService(db).create(
        title: title.text,
        notes: notes.text,
        scheduledAtUtc: due.toUtc(),
        timezoneId: due.timeZoneName,
        utcOffsetMinutes: due.timeZoneOffset.inMinutes,
      );
      await _load();
      if (mounted) {
        FloatingToast.show(
            context,
            item.exactAlarmCapability == ExactAlarmCapability.denied
                ? '提醒已保存；通知不可用，请检查系统权限'
                : '提醒已创建 · ${item.exactAlarmCapability.label}');
      }
    } catch (error) {
      if (mounted) FloatingToast.show(context, LocalErrorCopy.of(error, action: '创建提醒').headline());
    } finally {
      title.dispose();
      notes.dispose();
    }
  }

  Future<void> _cancelReminder(ReminderItem item) async {
    try {
      final db = await ref.read(databaseProvider.future);
      await ReminderService(db).cancel(item.id);
      await _load();
    } catch (error) {
      if (mounted) FloatingToast.show(context, LocalErrorCopy.of(error, action: '取消提醒').headline());
    }
  }

  Future<void> _snoozeReminder(ReminderItem item) async {
    try {
      final db = await ref.read(databaseProvider.future);
      await ReminderService(db).snooze(item.id);
      await _load();
      if (mounted) FloatingToast.show(context, '已延后 10 分钟提醒');
    } catch (error) {
      if (mounted) FloatingToast.show(context, LocalErrorCopy.of(error, action: '延后').headline());
    }
  }

  Future<void> _completeReminder(ReminderItem item) async {
    try {
      final db = await ref.read(databaseProvider.future);
      await ReminderService(db).complete(item.id);
      await _load();
      if (mounted) FloatingToast.show(context, '提醒已标记完成');
    } catch (error) {
      if (mounted) FloatingToast.show(context, LocalErrorCopy.of(error, action: '操作').headline());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: MobileTheme.pageBackground(context),
      appBar: const NexusPageHeader(
        title: '定时任务',
        subtitle: '自动化循环计划与后台执行',
      ),
      body: NexusPageLayout(
          child: AsyncStateView(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: Column(
          children: [
            Flexible(
                child: SingleChildScrollView(
                    child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: SectionCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.notifications_active_outlined,
                            size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '主动提醒 (${_reminders.length})',
                            style: const TextStyle(
                              fontSize: AppTokens.fontSizeBody,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          key: const ValueKey('create-quick-reminder'),
                          onPressed: _createQuickReminder,
                          icon: const Icon(Icons.add_alarm_rounded, size: 16),
                          label: const Text('新建提醒'),
                        ),
                      ],
                    ),
                    Text(
                        '当前系统能力：${_currentReminderCapability?.label ?? "尚未确认"}',
                        style: const TextStyle(
                            fontSize: AppTokens.fontSizeCaption)),
                    if (_reminders.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          '按选择的日期与时间通知；精确闹钟未授权时会显示降级状态。',
                          style: TextStyle(fontSize: AppTokens.fontSizeCaption),
                        ),
                      )
                    else
                      for (final rem in _reminders)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${rem.title} · ${rem.status.label}\n${rem.effectiveTriggerUtc.toLocal().toString().substring(0, 16)} · ${rem.exactAlarmCapability.label}',
                                style: const TextStyle(
                                    fontSize: AppTokens.fontSizeFootnote),
                              ),
                              if (rem.status == ReminderStatus.scheduled ||
                                  rem.status == ReminderStatus.snoozed ||
                                  rem.status == ReminderStatus.paused)
                                Wrap(children: [
                                  TextButton(
                                    onPressed: () => _snoozeReminder(rem),
                                    child: const Text('+10m'),
                                  ),
                                  TextButton(
                                    onPressed: () => _completeReminder(rem),
                                    child: const Text('完成'),
                                  ),
                                  TextButton(
                                      onPressed: () => _cancelReminder(rem),
                                      child: const Text('取消')),
                                ]),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ))),
            Expanded(
              child: _tasks.isEmpty
                  ? const EmptyStateView(
                      icon: Icons.schedule_outlined,
                      title: '无定时任务',
                      message: '还没有定时任务，点击右下角新建')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      itemCount: _tasks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final task = _tasks[index];
                        final spec = ScheduleSpec.fromCron(task.cron);
                        final daysLabel = spec.days.isEmpty
                            ? AppStrings.everyDay
                            : spec.days
                                .map((day) =>
                                    AppStrings.weekdays[day] ??
                                    AppStrings.weekday(day))
                                .join('/');
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
                                child: NexusSwitch(
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
                                      fontSize: AppTokens.fontSizeBody,
                                      fontWeight: FontWeight.w600,
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
                                        MobileTheme.controlRadius(context)),
                                  ),
                                  child: Text(
                                    task.enabled ? '已启用' : '已暂停',
                                    style: TextStyle(
                                      fontSize: AppTokens.fontSizeBadge,
                                      fontWeight: FontWeight.w600,
                                      color: task.enabled
                                          ? MobileTheme.brand(context)
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
                                      fontSize: AppTokens.fontSizeFootnote,
                                      fontWeight: FontWeight.w500,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                      color: task.enabled
                                          ? (isDark
                                              ? Colors.white70
                                              : Colors.black87)
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
                                      fontSize: AppTokens.fontSizeCaption,
                                      color: isDark
                                          ? AppPalette.darkTextMuted
                                          : AppPalette.lightTextMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.history_outlined),
                                  tooltip: '查看执行记录',
                                  constraints: const BoxConstraints(
                                    minWidth: AppTokens.kMinTouchTarget,
                                    minHeight: AppTokens.kMinTouchTarget,
                                  ),
                                  onPressed: () => _showHistory(task),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: '删除任务',
                                  constraints: const BoxConstraints(
                                    minWidth: AppTokens.kMinTouchTarget,
                                    minHeight: AppTokens.kMinTouchTarget,
                                  ),
                                  onPressed: () => _delete(task),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      )),
      floatingActionButton: FloatingActionButton(
        onPressed: _create,
        tooltip: '新建定时任务',
        child: const Icon(Icons.add),
      ),
    );
  }
}
