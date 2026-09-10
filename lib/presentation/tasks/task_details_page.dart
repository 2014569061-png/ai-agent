import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../application/run_audit_report.dart';
import '../../application/task_service.dart';
import '../../domain/collaboration_models.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/files/conversation_exporter.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../theme/app_theme.dart';
import '../diagnostics/run_analysis_page.dart';
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
  RunRecord? _run;
  RunAuditReport? _auditReport;
  bool _auditLoading = false;
  Object? _auditError;

  @override
  void initState() {
    super.initState();
    _task = widget.task;
    _loadAudit();
  }

  Future<void> _loadAudit() async {
    final runId = _task.runId;
    if (runId == null || runId.isEmpty) return;
    setState(() {
      _auditLoading = true;
      _auditError = null;
    });
    try {
      final db = await ref.read(databaseProvider.future);
      final run = await db.findRunRecord(runId);
      final events = await db.eventsForRun(runId, limit: 2000);
      if (!mounted) return;
      setState(() {
        _run = run;
        _auditReport = RunAuditReport.fromEvents(events);
        _auditLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _auditError = error;
        _auditLoading = false;
      });
    }
  }

  Future<void> _exportAuditJson() async {
    final report = _auditReport;
    final runId = _task.runId;
    if (report == null || runId == null || runId.isEmpty) return;
    final payload = {
      'taskId': _task.id,
      'runId': runId,
      'task': _task.title,
      'run': _run == null
          ? null
          : {
              'status': _run!.status,
              'model': _run!.model,
              'startedAt': _run!.startedAt.toIso8601String(),
              'endedAt': _run!.endedAt?.toIso8601String(),
              'retryCount': _run!.retryCount,
              'inputTokens': _run!.inputTokens,
              'outputTokens': _run!.outputTokens,
              'cachedTokens': _run!.cachedTokens,
              'estimatedCostCents': _run!.estimatedCostCents,
            },
      'audit': report.toJson(),
    };
    final path = await exportConversationJson('task-audit-$runId',
        const JsonEncoder.withIndent('  ').convert(payload));
    if (!mounted) return;
    FloatingToast.show(
      context,
      path.isEmpty ? '当前平台不支持文件导出' : '审计 JSON 已导出：$path',
      tone: path.isEmpty ? ToastTone.warning : ToastTone.success,
    );
  }

  Future<void> _openRunReport() async {
    final run = _run;
    if (run == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RunDetailPage(run: run)),
    );
  }

  Future<void> _rollbackAuditEntry(RunAuditEntry entry) async {
    final workspacePath = _task.workspacePath;
    if (workspacePath == null || workspacePath.isEmpty) {
      FloatingToast.show(context, '当前任务没有可用工作区', tone: ToastTone.warning);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('回滚文件修改？'),
        content: Text('将尝试恢复 ${entry.path ?? '目标文件'} 在该步骤之前的内容。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('回滚'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await AuditRollbackService().rollbackEditFile(
      workspacePath: workspacePath,
      entry: entry,
    );
    if (!mounted) return;
    FloatingToast.show(
      context,
      result.message,
      tone: result.ok ? ToastTone.success : ToastTone.warning,
    );
    if (result.ok) await _loadAudit();
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
      backgroundColor: isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas,
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
                                  borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                                ),
                                child: Text(
                                  '类型：${_task.type}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
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
                                  borderRadius: BorderRadius.circular(AppTokens.radiusControl),
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
                                        fontWeight: FontWeight.w500)),
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
                                      size: 16, color: AppPalette.warning),
                                  SizedBox(width: 6),
                                  Text('关键发现',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500)),
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
                                              fontWeight: FontWeight.w500)),
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
                                      size: 16, color: AppPalette.success),
                                  SizedBox(width: 6),
                                  Text('建议采取动作',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500)),
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
                                                        FontWeight.w500)),
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
                                      size: 16, color: AppPalette.brand),
                                  SizedBox(width: 6),
                                  Text('下一步实施计划',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500)),
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
                                                        FontWeight.w500)),
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

                  if (_task.runId != null && _task.runId!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _buildAuditSection(),
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
                color: isDark ? AppPalette.darkSurface : AppPalette.lightSurface,
                border: Border(
                  top: BorderSide(
                    color: isDark ? AppPalette.darkHairline : AppPalette.lightHairline,
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
                            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
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
                              borderRadius: BorderRadius.circular(AppTokens.radiusControl),
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
                              borderRadius: BorderRadius.circular(AppTokens.radiusControl),
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

  Widget _buildAuditSection() {
    if (_auditLoading) {
      return const SectionCard(
        child: ListTile(
          leading: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text('副作用审计'),
          subtitle: Text('正在读取本次运行的结构化轨迹…'),
        ),
      );
    }
    if (_auditError != null) {
      return SectionCard(
        child: ListTile(
          leading: const Icon(Icons.warning_amber_outlined),
          title: const Text('副作用审计暂不可用'),
          subtitle: Text('读取运行轨迹失败：$_auditError'),
          trailing: IconButton(
            tooltip: '重试',
            onPressed: _loadAudit,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
      );
    }
    final report = _auditReport;
    if (report == null) return const SizedBox.shrink();
    final metrics = report.metrics;
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('副作用审计',
                    style: TextStyle(fontWeight: FontWeight.w500)),
              ),
              IconButton(
                tooltip: '导出审计 JSON',
                onPressed: _exportAuditJson,
                icon: const Icon(Icons.data_object, size: 19),
              ),
              if (_run != null)
                IconButton(
                  tooltip: '打开完整运行报告',
                  onPressed: _openRunReport,
                  icon: const Icon(Icons.open_in_new, size: 18),
                ),
            ],
          ),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              Text('输入 ${metrics.promptTokens} tok'),
              Text('输出 ${metrics.completionTokens} tok'),
              Text('缓存 ${metrics.cachedTokens} tok'),
              Text('重试 ${metrics.retryCount} 次'),
              if (metrics.estimatedCostCents != null)
                Text('预计 ${metrics.estimatedCostCents} 分'),
            ],
          ),
          const SizedBox(height: 8),
          if (report.entries.isEmpty)
            const Text('本次运行没有记录到文件、终端或设备副作用。',
                style: TextStyle(fontSize: 12.5))
          else
            ...report.entries.map((entry) => _auditEntry(entry)),
        ],
      ),
    );
  }

  Widget _auditEntry(RunAuditEntry entry) {
    final color = switch (entry.effect) {
      'applied' => AppPalette.success,
      'unknown' => AppPalette.warning,
      _ => AppTheme.textSecondary,
    };
    final details = <String>[
      if (entry.path != null && entry.path!.isNotEmpty) entry.path!,
      if (entry.code.isNotEmpty) entry.code,
      if (entry.evidence != null && entry.evidence!.isNotEmpty) entry.evidence!,
    ].join(' · ');
    final canRollback = entry.tool == 'edit_file' &&
        entry.operation == 'edit' &&
        entry.effect == 'applied' &&
        entry.path != null &&
        (entry.metadata['diff']?.toString().isNotEmpty ?? false);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            entry.effect == 'applied'
                ? Icons.check_circle_outline
                : entry.effect == 'unknown'
                    ? Icons.help_outline
                    : Icons.remove_circle_outline,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${entry.tool} · effect=${entry.effect}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                if (details.isNotEmpty)
                  Text(details,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          if (canRollback)
            IconButton(
              tooltip: '回滚此编辑',
              onPressed: () => _rollbackAuditEntry(entry),
              icon: const Icon(Icons.undo_rounded, size: 18),
            ),
        ],
      ),
    );
  }
}
