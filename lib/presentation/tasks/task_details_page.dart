import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../application/task_service.dart';
import '../../domain/collaboration_models.dart';
import '../../infrastructure/database/app_database.dart';
import '../theme/app_theme.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_metric_tile.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/nexus_section.dart';
import '../widgets/nexus_status_pill.dart';
import '../widgets/section_card.dart';
import 'collaboration_plan_sheet.dart';

/// 完整开发任务详情页 (TaskDetailsPage)
/// 严格依据 NEXUS UI 设计优化规范重构，替代旧版紧凑底部弹层：
/// 1. 顶部 Header：返回、标题、统一状态徽标、操作菜单。
/// 2. 第一张总览卡：任务类型、当前状态、模型、工作区、更新时间、恢复次数。
/// 3. 第二张输入与进度卡：任务原始输入、当前执行阶段、步骤进度。
/// 4. 第三张结果卡：总结摘要、结构化发现、建议动作、下一步计划。
/// 5. 底部固定操作栏：打开关联会话、发起协作分析、复制结果 Markdown。
class TaskDetailsPage extends ConsumerStatefulWidget {
  const TaskDetailsPage({
    super.key,
    required this.task,
    this.onConversationSelected,
  });

  final DevelopmentTaskInfo task;
  final ValueChanged<Conversation>? onConversationSelected;

  @override
  ConsumerState<TaskDetailsPage> createState() => _TaskDetailsPageState();
}

class _TaskDetailsPageState extends ConsumerState<TaskDetailsPage> {
  late DevelopmentTaskInfo _task;

  @override
  void initState() {
    super.initState();
    _task = widget.task;
  }

  String _formatDate(DateTime time) {
    final local = time.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _taskMarkdownReport() {
    final buffer = StringBuffer()
      ..writeln('# 任务详情：${_task.title}')
      ..writeln()
      ..writeln('- 状态：${_task.status}')
      ..writeln('- 类型：${_task.type}')
      ..writeln('- 模型：${_task.model ?? '默认模型'}')
      ..writeln('- 工作区：${_task.workspacePath ?? '无'}')
      ..writeln('- 更新时间：${_formatDate(_task.updatedAt)}')
      ..writeln()
      ..writeln('## 任务输入')
      ..writeln(_task.prompt.isEmpty ? '（无输入）' : _task.prompt)
      ..writeln();

    if (_task.summary != null && _task.summary!.isNotEmpty) {
      buffer
        ..writeln('## 结果摘要')
        ..writeln(_task.summary!)
        ..writeln();
    }

    if (_task.structuredResult != null) {
      final res = _task.structuredResult!;
      if (res.findings.isNotEmpty) {
        buffer.writeln('## 关键发现');
        for (final f in res.findings) {
          final title = f['title']?.toString() ?? '';
          final detail = f['detail']?.toString() ?? '';
          buffer.writeln('- ${detail.isEmpty ? title : '$title: $detail'}');
        }
        buffer.writeln();
      }
      if (res.actions.isNotEmpty) {
        buffer.writeln('## 建议动作');
        for (final a in res.actions) {
          buffer.writeln('- $a');
        }
        buffer.writeln();
      }
      if (res.nextSteps.isNotEmpty) {
        buffer.writeln('## 下一步计划');
        for (final s in res.nextSteps) {
          buffer.writeln('- $s');
        }
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  Future<void> _openConversation() async {
    if (_task.conversationId.isEmpty) {
      FloatingToast.show(context, '该任务未关联会话');
      return;
    }
    final db = await ref.read(databaseProvider.future);
    final conv = await db.findConversation(_task.conversationId);
    if (!mounted) return;
    if (conv != null) {
      Navigator.pop(context);
      widget.onConversationSelected?.call(conv);
    } else {
      FloatingToast.show(context, '未找到关联的历史会话');
    }
  }

  Future<void> _startCollaboration() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CollaborationPlanSheet(
        task: DevelopmentTaskInput(
          taskId: _task.id,
          prompt: _task.prompt,
          taskType: _task.type,
          workspacePath: _task.workspacePath,
          model: _task.model,
        ),
      ),
    );
  }

  bool get _needsImmediateAction =>
      _task.status == 'waiting_approval' ||
      _task.status == 'awaiting_approval' ||
      _task.status == 'running';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: NexusPageHeader(
        title: _task.title,
        statusPill: NexusStatusPill.fromString(_task.status, isCompact: true),
        actions: [
          IconButton(
            tooltip: '复制任务摘要 Markdown',
            icon: const Icon(Icons.copy_all_rounded, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _taskMarkdownReport()));
              FloatingToast.show(context, '已复制任务 Markdown 报告',
                  tone: ToastTone.success);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                children: [
                  // ==========================================
                  // 1. 任务总览卡 (Overview Card)
                  // ==========================================
                  NexusSection(
                    title: '任务总览',
                    child: SectionCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '类型：${_task.type}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: theme
                                      .colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '来源：${_task.sourceType}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 12,
                            runSpacing: 10,
                            children: [
                              NexusMetricTile(
                                label: '执行状态',
                                value: _task.status,
                                icon: Icons.sync_rounded,
                              ),
                              NexusMetricTile(
                                label: '指定模型',
                                value: _task.model?.isNotEmpty == true
                                    ? _task.model!
                                    : '默认配置',
                                icon: Icons.psychology_outlined,
                              ),
                              if (_task.resumeCount > 0)
                                NexusMetricTile(
                                  label: '恢复执行',
                                  value: '${_task.resumeCount}',
                                  unit: '次',
                                  icon: Icons.replay_rounded,
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 10),
                          if (_task.workspacePath != null &&
                              _task.workspacePath!.isNotEmpty) ...[
                            Row(
                              children: [
                                const Icon(Icons.folder_outlined,
                                    size: 15, color: AppTheme.textSecondary),
                                const SizedBox(width: 6),
                                const Text('工作区：',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                                Expanded(
                                  child: SelectableText(
                                    _task.workspacePath!,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                          ],
                          Row(
                            children: [
                              const Icon(Icons.schedule_rounded,
                                  size: 15, color: AppTheme.textSecondary),
                              const SizedBox(width: 6),
                              Text(
                                '更新时间：${_formatDate(_task.updatedAt)}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ==========================================
                  // 2. 任务输入卡 (Prompt Card)
                  // ==========================================
                  NexusSection(
                    title: '任务输入指令',
                    child: SectionCard(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        _task.prompt.isEmpty ? '（无文本输入）' : _task.prompt,
                        style: const TextStyle(fontSize: 14, height: 1.45),
                      ),
                    ),
                  ),

                  // ==========================================
                  // 3. 执行结果与结构化产物卡 (Results Card)
                  // ==========================================
                  if (_task.summary != null && _task.summary!.isNotEmpty) ...[
                    NexusSection(
                      title: '结果摘要',
                      child: SectionCard(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(
                          _task.summary!,
                          style: const TextStyle(fontSize: 14, height: 1.45),
                        ),
                      ),
                    ),
                  ],

                  if (_task.structuredResult != null) ...[
                    NexusSection(
                      title: '结构化产物',
                      child: SectionCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_task
                                .structuredResult!.findings.isNotEmpty) ...[
                              const Row(
                                children: [
                                  Icon(Icons.lightbulb_outline_rounded,
                                      size: 16, color: AppTheme.warning),
                                  SizedBox(width: 6),
                                  Text('关键发现',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ..._task.structuredResult!.findings.map((f) {
                                final title = f['title']?.toString() ?? '';
                                final detail = f['detail']?.toString() ?? '';
                                final text =
                                    detail.isEmpty ? title : '$title：$detail';
                                return Padding(
                                  padding:
                                      const EdgeInsets.only(left: 8, bottom: 4),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('• ',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w700)),
                                      Expanded(
                                          child: SelectableText(text,
                                              style: const TextStyle(
                                                  fontSize: 13))),
                                    ],
                                  ),
                                );
                              }),
                              const SizedBox(height: 12),
                            ],
                            if (_task.structuredResult!.actions.isNotEmpty) ...[
                              const Row(
                                children: [
                                  Icon(Icons.check_circle_outline_rounded,
                                      size: 16, color: AppTheme.success),
                                  SizedBox(width: 6),
                                  Text('建议采取动作',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ..._task.structuredResult!.actions
                                  .map((a) => Padding(
                                        padding: const EdgeInsets.only(
                                            left: 8, bottom: 4),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text('• ',
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.w700)),
                                            Expanded(
                                                child: SelectableText(a,
                                                    style: const TextStyle(
                                                        fontSize: 13))),
                                          ],
                                        ),
                                      )),
                              const SizedBox(height: 12),
                            ],
                            if (_task
                                .structuredResult!.nextSteps.isNotEmpty) ...[
                              const Row(
                                children: [
                                  Icon(Icons.arrow_forward_rounded,
                                      size: 16, color: AppTheme.brandBright),
                                  SizedBox(width: 6),
                                  Text('下一步实施计划',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ..._task.structuredResult!.nextSteps
                                  .map((s) => Padding(
                                        padding: const EdgeInsets.only(
                                            left: 8, bottom: 4),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text('• ',
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.w700)),
                                            Expanded(
                                                child: SelectableText(s,
                                                    style: const TextStyle(
                                                        fontSize: 13))),
                                          ],
                                        ),
                                      )),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ==========================================
            // 底部固定操作栏
            // ==========================================
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                color: isDark
                    ? AppTheme.darkElevated.withValues(alpha: 0.95)
                    : AppTheme.lightElevated.withValues(alpha: 0.95),
                border: Border(
                  top: BorderSide(
                    color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                  ),
                ),
              ),
              child: Column(
                children: [
                  if (_needsImmediateAction) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _openConversation,
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('立即处理'),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _startCollaboration,
                          icon: const Icon(Icons.hub_outlined, size: 18),
                          label: const Text('发起协作分析'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _task.conversationId.isEmpty
                              ? null
                              : _openConversation,
                          icon: const Icon(Icons.forum_outlined, size: 18),
                          label: const Text('打开关联会话'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
