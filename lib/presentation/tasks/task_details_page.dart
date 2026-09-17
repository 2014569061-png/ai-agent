import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/change_review.dart';
import '../../application/development_verification.dart';
import '../../application/providers.dart';
import '../../application/run_audit_report.dart';
import '../../application/task_feedback_service.dart';
import '../../application/task_service.dart';
import '../../application/workspace_service.dart';
import '../../domain/collaboration_models.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/files/conversation_exporter.dart';
import '../theme/app_appearance_controller.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../theme/app_theme.dart';
import '../l10n/app_strings.dart';
import '../diagnostics/run_analysis_page.dart';
import '../motion/nexus_page_route_factory.dart';
import '../widgets/confirm_action.dart';
import '../widgets/floating_toast.dart';
import '../widgets/glass_surface.dart';
import '../widgets/nexus_disclosure.dart';
import '../widgets/nexus_execution_status.dart';
import '../widgets/nexus_loading_skeleton.dart';
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
  bool? _helpful;
  bool _feedbackLoading = false;
  bool? _workspaceAccessible;

  @override
  void initState() {
    super.initState();
    _task = widget.task;
    _loadAudit();
    _loadFeedback();
    _checkWorkspace();
  }

  Future<void> _checkWorkspace() async {
    final path = _task.workspacePath;
    final accessible = await WorkspaceService().isAccessible(path);
    if (mounted) setState(() => _workspaceAccessible = accessible);
  }

  Future<void> _loadFeedback() async {
    if (!_feedbackEligible) return;
    final db = await ref.read(databaseProvider.future);
    final feedback =
        await const TaskFeedbackService().feedbackForTask(db, _task.id);
    if (mounted) setState(() => _helpful = feedback?.helpful);
  }

  bool get _feedbackEligible {
    final status = _task.status.toLowerCase();
    return (_task.type.toLowerCase().startsWith('development') ||
            const {
              'project_analysis',
              'bug_fix',
              'code_review',
              'release_check',
              'implement_and_verify',
            }.contains(_task.type.toLowerCase())) &&
        (status == 'completed' || status == 'failed' || status == 'cancelled');
  }

  Future<void> _saveFeedback(bool helpful) async {
    setState(() {
      _helpful = helpful;
      _feedbackLoading = true;
    });
    try {
      final db = await ref.read(databaseProvider.future);
      await const TaskFeedbackService()
          .save(db: db, taskId: _task.id, runId: _task.runId, helpful: helpful);
    } finally {
      if (mounted) setState(() => _feedbackLoading = false);
    }
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
    final run = _run;
    if (report == null || runId == null || runId.isEmpty) return;
    final payload = {
      'taskId': _task.id,
      'runId': runId,
      'task': _task.title,
      'run': run == null
          ? null
          : {
              'status': run.status,
              'model': run.model,
              'startedAt': run.startedAt.toIso8601String(),
              'endedAt': run.endedAt?.toIso8601String(),
              'retryCount': run.retryCount,
              'inputTokens': run.inputTokens,
              'outputTokens': run.outputTokens,
              'cachedTokens': run.cachedTokens,
              'estimatedCostCents': run.estimatedCostCents,
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
      NexusPageRoute.detail(builder: (_) => RunDetailPage(run: run)),
    );
  }

  Future<void> _rollbackAuditEntry(RunAuditEntry entry) async {
    final workspacePath = _task.workspacePath;
    if (workspacePath == null || workspacePath.isEmpty) {
      FloatingToast.show(context, '当前任务没有可用工作区', tone: ToastTone.warning);
      return;
    }
    final confirmed = await showConfirmAction(
      context,
      title: '回滚文件修改？',
      message: '将尝试恢复 ${entry.path ?? '目标文件'} 在该步骤之前的内容。',
      confirmLabel: '确认回滚',
      cancelLabel: '取消',
      isDanger: true,
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
    final summary = _task.summary;
    final structured = _task.structuredResult;
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

    if (summary != null && summary.isNotEmpty) {
      buffer
        ..writeln('## 结果摘要')
        ..writeln(summary)
        ..writeln();
    }

    if (structured != null) {
      if (structured.findings.isNotEmpty) {
        buffer.writeln('## 关键发现');
        for (final f in structured.findings) {
          final title = f['title']?.toString() ?? '';
          final detail = f['detail']?.toString() ?? '';
          buffer.writeln('- ${detail.isEmpty ? title : '$title: $detail'}');
        }
        buffer.writeln();
      }
      if (structured.actions.isNotEmpty) {
        buffer.writeln('## 建议动作');
        for (final a in structured.actions) {
          buffer.writeln('- $a');
        }
        buffer.writeln();
      }
      if (structured.nextSteps.isNotEmpty) {
        buffer.writeln('## 下一步计划');
        for (final s in structured.nextSteps) {
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
    final isFlat =
        AppAppearanceController.resolvedGlassIntensity == GlassIntensity.flat;
    final taskModel = _task.model;
    final workspacePath = _task.workspacePath;
    final summary = _task.summary;
    final structured = _task.structuredResult;
    final runId = _task.runId;

    return Scaffold(
      backgroundColor: isFlat
          ? (isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas)
          : Colors.transparent,
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
                  if (_needsImmediateAction) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: NexusExecutionStatus(
                        state: (_task.status == 'running')
                            ? NexusExecutionState.running
                            : NexusExecutionState.waitingForUser,
                        label: (_task.status == 'running')
                            ? '任务正在执行中…'
                            : '任务等待用户授权确认',
                        detail: '可点击下方按钮进入会话流处理',
                        onViewDetails: _task.conversationId.isNotEmpty
                            ? _openConversation
                            : null,
                      ),
                    ),
                  ],
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
                                  borderRadius: BorderRadius.circular(
                                      AppTokens.radiusControl),
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
                                  borderRadius: BorderRadius.circular(
                                      AppTokens.radiusControl),
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
                                value: taskModel != null && taskModel.isNotEmpty
                                    ? taskModel
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
                          if (workspacePath != null &&
                              workspacePath.isNotEmpty) ...[
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
                                    workspacePath,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary),
                                  ),
                                ),
                              ],
                            ),
                            if (_workspaceAccessible == false)
                              const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: Text(
                                  '项目目录已不可访问，请重新绑定工作区后再恢复任务。',
                                  style: TextStyle(
                                      fontSize: 12, color: AppPalette.warning),
                                ),
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
                  // 2.1 执行流水线与代码 Diff (Pipeline & Diff)
                  // ==========================================
                  NexusSection(
                    title: '执行流水线与变更',
                    child: _PipelineTimelineCard(
                      task: _task,
                      auditReport: _auditReport,
                      onRollback: _rollbackAuditEntry,
                    ),
                  ),
                  if (_task.changeReview != null ||
                      _task.verificationPlan != null)
                    NexusSection(
                      title: '改动审查与验证',
                      child: _ChangeReviewCard(
                        review: _task.changeReview,
                        plan: _task.verificationPlan,
                      ),
                    ),

                  // ==========================================
                  // 3. 执行结果与结构化产物卡 (Results Card)
                  // ==========================================
                  if (summary != null && summary.isNotEmpty) ...[
                    NexusSection(
                      title: '结果摘要',
                      child: SectionCard(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(
                          summary,
                          style: const TextStyle(fontSize: 14, height: 1.45),
                        ),
                      ),
                    ),
                  ],

                  if (structured != null) ...[
                    NexusSection(
                      title: '结构化产物',
                      child: SectionCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (structured.findings.isNotEmpty) ...[
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
                              ...structured.findings.map((f) {
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
                            if (structured.actions.isNotEmpty) ...[
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
                              ...structured.actions.map((a) => Padding(
                                    padding: const EdgeInsets.only(
                                        left: 8, bottom: 4),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text('• ',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w500)),
                                        Expanded(
                                            child: SelectableText(a,
                                                style: const TextStyle(
                                                    fontSize: 13))),
                                      ],
                                    ),
                                  )),
                              const SizedBox(height: 12),
                            ],
                            if (structured.nextSteps.isNotEmpty) ...[
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
                              ...structured.nextSteps.map((s) => Padding(
                                    padding: const EdgeInsets.only(
                                        left: 8, bottom: 4),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text('• ',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w500)),
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

                  if (_feedbackEligible) ...[
                    NexusSection(
                      title: AppStrings.taskFeedbackTitle,
                      child: SectionCard(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Expanded(
                                child: Text(AppStrings.taskFeedbackPrompt)),
                            IconButton(
                              tooltip: AppStrings.taskHelpful,
                              onPressed: _feedbackLoading
                                  ? null
                                  : () => _saveFeedback(true),
                              icon: Icon(
                                _helpful == true
                                    ? Icons.thumb_up_alt
                                    : Icons.thumb_up_alt_outlined,
                              ),
                            ),
                            IconButton(
                              tooltip: AppStrings.taskNotHelpful,
                              onPressed: _feedbackLoading
                                  ? null
                                  : () => _saveFeedback(false),
                              icon: Icon(
                                _helpful == false
                                    ? Icons.thumb_down_alt
                                    : Icons.thumb_down_alt_outlined,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  if (runId != null && runId.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _buildAuditSection(),
                  ],
                ],
              ),
            ),

            // ==========================================
            // 底部固定操作栏 (Scheme A Liquid Crystal)
            // ==========================================
            isFlat
                ? Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
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
                    child: Column(
                      children: [
                        if (_needsImmediateAction) ...[
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      AppTokens.radiusControl),
                                ),
                              ),
                              onPressed: _openConversation,
                              icon: const Icon(Icons.play_arrow_rounded,
                                  size: 18),
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
                                    borderRadius: BorderRadius.circular(
                                        AppTokens.radiusControl),
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
                                    borderRadius: BorderRadius.circular(
                                        AppTokens.radiusControl),
                                  ),
                                ),
                                onPressed: _task.conversationId.isEmpty
                                    ? null
                                    : _openConversation,
                                icon:
                                    const Icon(Icons.forum_outlined, size: 18),
                                label: const Text('打开关联会话'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : GlassSurface(
                    role: GlassRole.overlay,
                    variant: GlassVariant.regular,
                    intensity: AppAppearanceController.resolvedGlassIntensity,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AppTokens.radiusModal)),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: Column(
                      children: [
                        if (_needsImmediateAction) ...[
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      AppTokens.radiusControl),
                                ),
                              ),
                              onPressed: _openConversation,
                              icon: const Icon(Icons.play_arrow_rounded,
                                  size: 18),
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
                                    borderRadius: BorderRadius.circular(
                                        AppTokens.radiusControl),
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
                                    borderRadius: BorderRadius.circular(
                                        AppTokens.radiusControl),
                                  ),
                                ),
                                onPressed: _task.conversationId.isEmpty
                                    ? null
                                    : _openConversation,
                                icon:
                                    const Icon(Icons.forum_outlined, size: 18),
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
        child: Padding(
          padding: EdgeInsets.all(16),
          child: NexusCardSkeleton(),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: NexusDisclosure(
        leading: const Icon(Icons.fact_check_outlined, size: 18),
        title: Text(
          '副作用审计 (${report.entries.length} 项)',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  '输入 ${metrics.promptTokens} tok',
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
                Text(
                  '输出 ${metrics.completionTokens} tok',
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
                Text(
                  '缓存 ${metrics.cachedTokens} tok',
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
                Text(
                  '重试 ${metrics.retryCount} 次',
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
                if (metrics.estimatedCostCents != null)
                  Text(
                    '预计 ${metrics.estimatedCostCents} 分',
                    style:
                        const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(0, 36),
                  ),
                  onPressed: _exportAuditJson,
                  icon: const Icon(Icons.data_object, size: 16),
                  label: const Text('导出审计 JSON'),
                ),
                if (_run != null) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(0, 36),
                    ),
                    onPressed: _openRunReport,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('完整运行报告'),
                  ),
                ],
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
      ),
    );
  }

  Widget _auditEntry(RunAuditEntry entry) {
    final path = entry.path;
    final evidence = entry.evidence;
    final color = switch (entry.effect) {
      'applied' => AppPalette.success,
      'unknown' => AppPalette.warning,
      _ => AppTheme.textSecondary,
    };
    final details = <String>[
      if (path != null && path.isNotEmpty) path,
      if (entry.code.isNotEmpty) entry.code,
      if (evidence != null && evidence.isNotEmpty) evidence,
    ].join(' · ');
    final diff = entry.metadata['diff']?.toString();
    final hasDiff = diff != null && diff.trim().isNotEmpty;
    final canRollback = entry.tool == 'edit_file' &&
        entry.operation == 'edit' &&
        entry.effect == 'applied' &&
        entry.path != null &&
        hasDiff;

    if (hasDiff) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: _CodeDiffCard(
          filePath: entry.path ?? entry.tool,
          diffText: diff,
          onRollback: canRollback ? () => _rollbackAuditEntry(entry) : null,
        ),
      );
    }

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
                Text(
                  '${entry.tool} · effect=${entry.effect}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                  ),
                ),
                if (details.isNotEmpty)
                  Text(
                    details,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
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

/// 垂直流水线步骤节点卡片（对标效果图 3）
class _PipelineTimelineCard extends StatelessWidget {
  const _PipelineTimelineCard({
    required this.task,
    required this.auditReport,
    required this.onRollback,
  });

  final DevelopmentTaskInfo task;
  final RunAuditReport? auditReport;
  final ValueChanged<RunAuditEntry> onRollback;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCompleted = task.status.toLowerCase() == 'completed';
    final isRunning = task.status.toLowerCase() == 'running';
    final isWaiting = task.status.toLowerCase().contains('approval');
    final workspacePath = task.workspacePath;
    final summary = task.summary;

    final diffEntries = auditReport?.entries.where((e) {
          final diff = e.metadata['diff']?.toString();
          return diff != null && diff.trim().isNotEmpty;
        }).toList() ??
        const [];

    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step 1: 意图与工作区解析
          _timelineStep(
            context: context,
            stepNum: 1,
            title: '解析任务意图与工作区环境',
            status: _StepStatus.done,
            isLast: false,
            content: workspacePath != null && workspacePath.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: Text(
                      '工作区：$workspacePath',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppPalette.darkTextMuted
                            : AppPalette.lightTextMuted,
                        fontFamily: 'monospace',
                      ),
                    ),
                  )
                : null,
          ),

          // Step 2: 代码变更与工具执行
          _timelineStep(
            context: context,
            stepNum: 2,
            title: '执行代码变更与工具流水线',
            status: isCompleted
                ? _StepStatus.done
                : (isRunning || isWaiting
                    ? _StepStatus.active
                    : _StepStatus.pending),
            isLast: false,
            content: diffEntries.isNotEmpty
                ? Column(
                    children: diffEntries.take(3).map((entry) {
                      return _CodeDiffCard(
                        filePath: entry.path ?? entry.tool,
                        diffText: entry.metadata['diff'].toString(),
                        onRollback: () => onRollback(entry),
                      );
                    }).toList(),
                  )
                : (summary != null && summary.isNotEmpty
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 4),
                        child: Text(
                          isRunning ? '正在运行工具执行变更…' : '阶段执行就绪',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppPalette.darkTextMuted
                                : AppPalette.lightTextMuted,
                          ),
                        ),
                      )),
          ),

          // Step 3: 副作用审计与质量评估
          _timelineStep(
            context: context,
            stepNum: 3,
            title: '副作用审计与完成评估',
            status: isCompleted
                ? _StepStatus.done
                : (task.status.toLowerCase() == 'failed'
                    ? _StepStatus.failed
                    : _StepStatus.pending),
            isLast: true,
            content: null,
          ),
        ],
      ),
    );
  }

  Widget _timelineStep({
    required BuildContext context,
    required int stepNum,
    required String title,
    required _StepStatus status,
    required bool isLast,
    Widget? content,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? AppPalette.darkText : AppPalette.lightText;
    final muted = isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    Widget nodeIcon;
    Color lineColor;
    switch (status) {
      case _StepStatus.done:
        nodeIcon = Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: Color(0xFF00E676),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, size: 14, color: Colors.black),
        );
        lineColor = const Color(0xFF00E676);
      case _StepStatus.active:
        nodeIcon = Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
            border: Border.all(color: const Color(0xFF00E5FF), width: 2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
                blurRadius: 8,
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF00E5FF),
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
        lineColor = isDark ? AppPalette.darkHairline : AppPalette.lightHairline;
      case _StepStatus.failed:
        nodeIcon = Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: Color(0xFFFF5252),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close, size: 14, color: Colors.white),
        );
        lineColor = isDark ? AppPalette.darkHairline : AppPalette.lightHairline;
      case _StepStatus.pending:
        nodeIcon = Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color:
                  isDark ? AppPalette.darkHairline : AppPalette.lightHairline,
              width: 2,
            ),
          ),
        );
        lineColor = isDark ? AppPalette.darkHairline : AppPalette.lightHairline;
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              nodeIcon,
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: lineColor,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Step $stepNum',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: status == _StepStatus.active
                          ? const Color(0xFF00E5FF)
                          : muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: text,
                    ),
                  ),
                  if (content != null) ...[
                    const SizedBox(height: 6),
                    content,
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _StepStatus { done, active, failed, pending }

/// 代码 Diff 预览卡片（对标效果图 3）
class _CodeDiffCard extends StatelessWidget {
  const _CodeDiffCard({
    required this.filePath,
    required this.diffText,
    this.onRollback,
  });

  final String filePath;
  final String diffText;
  final VoidCallback? onRollback;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    final lines = diffText.split('\n');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14171F) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        border: Border.all(
          color: isDark ? const Color(0xFF282D3D) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：文件路径与回滚操作
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2330) : const Color(0xFFEDF2F7),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Icon(Icons.insert_drive_file_outlined,
                    size: 15, color: textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    filePath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onRollback != null)
                  GestureDetector(
                    onTap: onRollback,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          Icon(Icons.undo_rounded,
                              size: 14, color: AppPalette.brand),
                          SizedBox(width: 2),
                          Text(
                            '回滚',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppPalette.brand,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Diff 语法着色行
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines.map((line) {
                final isAdded = line.startsWith('+');
                final isDeleted = line.startsWith('-');
                final bgColor = isAdded
                    ? const Color(0xFF2E7D32).withValues(alpha: 0.2)
                    : isDeleted
                        ? const Color(0xFFC62828).withValues(alpha: 0.2)
                        : Colors.transparent;
                final textColor = isAdded
                    ? const Color(0xFF69F0AE)
                    : isDeleted
                        ? const Color(0xFFFF5252)
                        : (isDark ? AppPalette.darkText : AppPalette.lightText);

                return Container(
                  width: double.infinity,
                  color: bgColor,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  child: Text(
                    line,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      color: textColor,
                      height: 1.4,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangeReviewCard extends StatelessWidget {
  const _ChangeReviewCard({this.review, this.plan});

  final ChangeReview? review;
  final DevelopmentVerificationPlan? plan;

  @override
  Widget build(BuildContext context) {
    final review = this.review;
    final plan = this.plan;
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (review != null) ...[
            Text(
              '本次修改 ${review.files.length} 个文件（+${review.linesAdded} / -${review.linesRemoved}）· ${review.mark.label}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final file in review.files) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      file.path,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                  Text(
                    '${file.operation} +${file.linesAdded}/-${file.linesRemoved}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
              if (file.diff.isNotEmpty)
                _CodeDiffCard(filePath: file.path, diffText: file.diff),
              const SizedBox(height: 8),
            ],
          ],
          if (plan != null) ...[
            const Text('验证步骤', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            for (final step in plan.steps)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${step.title} · ${step.status.label}'
                  '${step.command.isEmpty ? '' : ' · ${step.command}'}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
