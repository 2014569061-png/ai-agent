import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/models.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/immersive_sheet.dart';
import '../../widgets/immersive_surface.dart';
import '../../widgets/nexus_status_pill.dart';

/// 执行计划浮层卡片 (PlanPanel)
/// 严格依据 NEXUS UI 设计优化规范重构：
/// 1. 顶部展示统一状态徽标 (NexusStatusPill)、完成进度、当前步骤与预计预估。
/// 2. 确认按钮文案明确为“确认并执行计划”，执行中变为“停止执行”。
/// 3. 当前步骤使用品牌色，已完成步骤绿色划线，失败步骤红色高亮并提供重试。
/// 4. 完成后收拢为极简紧凑完成条，点击可展开复盘，不再遮挡消息流。
class PlanPanel extends StatefulWidget {
  final PlanState plan;
  final String? goal;
  final VoidCallback onApprove;
  final VoidCallback onCancel;
  final VoidCallback? onRetry;
  final VoidCallback? onResume;

  const PlanPanel({
    super.key,
    required this.plan,
    this.goal,
    required this.onApprove,
    required this.onCancel,
    this.onRetry,
    this.onResume,
  });

  @override
  State<PlanPanel> createState() => _PlanPanelState();
}

class _PlanPanelState extends State<PlanPanel> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    // 未确认时展开方便审核；执行完成后默认紧凑收起，避免遮挡消息；
    // 暂停态默认展开以展示“继续执行”入口。
    _expanded = !widget.plan.isConfirmed &&
            widget.plan.status != 'completed' &&
            widget.plan.status != 'paused' ||
        widget.plan.status == 'paused';
  }

  @override
  void didUpdateWidget(covariant PlanPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.plan.isConfirmed && oldWidget.plan.isConfirmed) {
      _expanded = true;
    }
  }

  PlanStep? get _currentStep {
    final running = widget.plan.steps.where((s) => s.status == 'running');
    if (running.isNotEmpty) return running.first;
    final pending = widget.plan.steps.where((s) => s.status == 'pending');
    return pending.isNotEmpty ? pending.first : null;
  }

  int get _completedCount =>
      widget.plan.steps.where((s) => s.status == 'completed').length;

  bool get _isCompleted => widget.plan.status == 'completed';
  bool get _isExecuting => widget.plan.status == 'executing';
  bool get _isFailed => widget.plan.status == 'failed';
  bool get _isPaused => widget.plan.status == 'paused';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted =
        isDark ? AppTheme.darkSemantic.mutedOnGlass : AppTheme.textSecondary;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380, maxHeight: 420),
      child: ImmersiveSurface(
        level: ImmersiveMaterialLevel.ultraThick,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          child: _isCompleted && !_expanded
              ? _buildCompletedCompact(muted)
              : (_expanded
                  ? SizedBox(
                      height: math.min(
                          410.0, MediaQuery.sizeOf(context).height * 0.58),
                      child: Column(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              child:
                                  _buildExpanded(muted, includeActions: false),
                            ),
                          ),
                          _buildPlanActions(),
                        ],
                      ),
                    )
                  : _buildCollapsed(muted)),
        ),
      ),
    );
  }

  // --- 执行完成时的紧凑条 ---
  Widget _buildCompletedCompact(Color muted) {
    final total = widget.plan.steps.length;
    return InkWell(
      onTap: () => setState(() => _expanded = true),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                size: 18, color: AppTheme.success),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '执行计划已完成 · 全部 $total 个步骤均通过',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.success,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text('查看',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary)),
            const Icon(Icons.chevron_right_rounded, size: 16),
          ],
        ),
      ),
    );
  }

  // --- 折叠态：仅展示当前步骤与进度 ---
  Widget _buildCollapsed(Color muted) {
    final current = _currentStep;
    final label = current?.description ?? '查看执行计划详情';
    final total = widget.plan.steps.length;
    final done = _completedCount;

    return InkWell(
      onTap: () => setState(() => _expanded = true),
      borderRadius: BorderRadius.circular(AppTokens.radiusCard),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.checklist_rounded,
                size: 18, color: AppPalette.brand),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        '进度 $done/$total',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: muted,
                        ),
                      ),
                      const SizedBox(width: 6),
                      NexusStatusPill.fromString(
                        widget.plan.status,
                        isCompact: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '展开计划',
              icon: const Icon(Icons.expand_more_rounded, size: 20),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => setState(() => _expanded = true),
            ),
          ],
        ),
      ),
    );
  }

  // --- 展开态 ---
  Widget _buildExpanded(Color muted, {bool includeActions = true}) {
    final theme = Theme.of(context);
    final total = widget.plan.steps.length;
    final done = _completedCount;
    final progress = total == 0 ? 0.0 : done / total;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部：标题 + 状态徽标 + 收起图标
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
          child: Row(
            children: [
              const Icon(Icons.checklist_rounded,
                  size: 18, color: AppPalette.brand),
              const SizedBox(width: 8),
              Text(
                '执行计划',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 8),
              NexusStatusPill.fromString(
                widget.plan.status,
                isCompact: true,
              ),
              const Spacer(),
              _threeDotMenu(muted),
              IconButton(
                tooltip: '收起计划',
                icon: const Icon(Icons.expand_less_rounded, size: 20),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => setState(() => _expanded = false),
              ),
            ],
          ),
        ),

        // 目标区
        if (widget.goal != null && widget.goal!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.brandBright.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppTheme.brandBright.withValues(alpha: 0.15),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('执行目标',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppPalette.brand)),
                  const SizedBox(height: 3),
                  Text(
                    widget.goal!,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.3,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 进度指示条
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
          child: Row(
            children: [
              Text('完成度 $done/$total',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: theme.brightness == Brightness.dark
                        ? AppTheme.darkBorder
                        : AppTheme.lightBorder,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _isFailed ? AppTheme.danger : AppTheme.brandBright,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 步骤清单
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: widget.plan.steps
                .map((step) => _buildStepRow(step, muted))
                .toList(),
          ),
        ),

        // 操作控制区
        if (includeActions && !widget.plan.isConfirmed)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onCancel,
                    child: const Text('取消计划'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: widget.onApprove,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('确认并执行计划'),
                  ),
                ),
              ],
            ),
          )
        else if (includeActions && _isExecuting)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.danger,
                  side: const BorderSide(color: AppTheme.danger),
                ),
                onPressed: widget.onCancel,
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: const Text('停止执行计划'),
              ),
            ),
          )
        else if (includeActions && _isPaused)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onCancel,
                    child: const Text('终止计划'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: widget.onResume ?? widget.onApprove,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('继续执行'),
                  ),
                ),
              ],
            ),
          )
        else if (includeActions && _isFailed)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onCancel,
                    child: const Text('重新生成'),
                  ),
                ),
                if (widget.onRetry != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: widget.onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('重试失败步骤'),
                    ),
                  ),
                ],
              ],
            ),
          ),

        // 底部署名
        const Divider(height: 1, thickness: 0.8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 13, color: AppTheme.brandBright),
              SizedBox(width: 5),
              Text(
                'NEXUS 智能协同执行引擎',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.mutedOnGlassLight,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlanActions() {
    if (!widget.plan.isConfirmed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: widget.onCancel,
                child: const Text('取消计划'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: widget.onApprove,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('确认并执行计划'),
              ),
            ),
          ],
        ),
      );
    }
    if (_isExecuting) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.danger,
              side: const BorderSide(color: AppTheme.danger),
            ),
            onPressed: widget.onCancel,
            icon: const Icon(Icons.stop_circle_outlined, size: 18),
            label: const Text('停止执行计划'),
          ),
        ),
      );
    }
    if (_isPaused) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: widget.onCancel,
                child: const Text('终止计划'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: widget.onResume ?? widget.onApprove,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('继续执行'),
              ),
            ),
          ],
        ),
      );
    }
    if (_isFailed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: widget.onCancel,
                child: const Text('重新生成'),
              ),
            ),
            if (widget.onRetry != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: widget.onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('重试失败步骤'),
                ),
              ),
            ],
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildStepRow(PlanStep step, Color muted) {
    final isCurrent = step.status == 'running' ||
        (step.status == 'pending' && step == _currentStep);
    // 仅当计划处于活跃执行态（executing）时才显示步骤转圈；
    // 进入 completed / failed / cancelled / paused 后不再转圈。
    final showSpinner = isCurrent && _isExecuting;
    final isDone = step.status == 'completed';
    final isFailed = step.status == 'failed';

    IconData leadIcon;
    Color leadColor;
    if (isDone) {
      leadIcon = Icons.check_circle_rounded;
      leadColor = AppTheme.success;
    } else if (isFailed) {
      leadIcon = Icons.cancel_rounded;
      leadColor = AppTheme.danger;
    } else if (isCurrent) {
      leadIcon = Icons.arrow_right_alt_rounded;
      leadColor = AppTheme.brandBright;
    } else {
      leadIcon = Icons.radio_button_unchecked_rounded;
      leadColor = muted;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(leadIcon, size: 18, color: leadColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              step.description,
              style: TextStyle(
                fontSize: 13.5,
                color: isCurrent
                    ? AppTheme.brandBright
                    : (isDone
                        ? AppTheme.success
                        : (isFailed ? AppTheme.danger : muted)),
                fontWeight:
                    (isCurrent || isDone) ? FontWeight.w500 : FontWeight.normal,
                decoration: isDone ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (showSpinner)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  Future<void> _showActionsMenu() async {
    final action = await showImmersiveSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.plan.isConfirmed)
              ListTile(
                leading: const Icon(Icons.play_arrow_rounded),
                title: const Text('确认并执行计划'),
                onTap: () => Navigator.pop(sheetContext, 'approve'),
              ),
            ListTile(
              leading: const Icon(Icons.close_rounded),
              title: const Text('取消 / 终止计划'),
              onTap: () => Navigator.pop(sheetContext, 'cancel'),
            ),
            ListTile(
              leading: const Icon(Icons.expand_less_rounded),
              title: const Text('收起卡片'),
              onTap: () => Navigator.pop(sheetContext, 'collapse'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'approve') widget.onApprove();
    if (action == 'cancel') widget.onCancel();
    if (action == 'collapse') setState(() => _expanded = false);
  }

  Widget _threeDotMenu(Color muted) {
    return IconButton(
      icon: Icon(Icons.more_horiz_rounded, size: 20, color: muted),
      tooltip: '更多操作',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: _showActionsMenu,
    );
  }
}
