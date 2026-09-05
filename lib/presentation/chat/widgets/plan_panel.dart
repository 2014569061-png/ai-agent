import 'package:flutter/material.dart';

import '../../../domain/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/immersive_sheet.dart';

/// Zcode 风格的执行计划浮层卡片。
///
/// - 折叠态：右侧胶囊卡片，仅展示当前项（带 → 箭头前缀）。
/// - 展开态：标题「计划」、目标区、进度（已完成/总数）、步骤清单
///   （已完成绿勾划线、当前项箭头、未完成空心圆）、顶部三点菜单与
///   展开/收起图标、底部「智能体」署名。
class PlanPanel extends StatefulWidget {
  final PlanState plan;
  final String? goal;
  final VoidCallback onApprove;
  final VoidCallback onCancel;

  const PlanPanel({
    super.key,
    required this.plan,
    this.goal,
    required this.onApprove,
    required this.onCancel,
  });

  @override
  State<PlanPanel> createState() => _PlanPanelState();
}

class _PlanPanelState extends State<PlanPanel> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    // 未确认（等待用户审批）时默认展开，便于用户查看完整计划。
    _expanded = !widget.plan.isConfirmed;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? AppTheme.darkElevated : AppTheme.lightElevated;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final muted = isDark ? const Color(0xFF8A94A6) : const Color(0xFF64748B);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      // 右侧浮层卡片观感：受限宽度 + 阴影。
      constraints: const BoxConstraints(maxWidth: 420),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: border),
        boxShadow: AppTheme.floatingShadow(isDark),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: _expanded ? _buildExpanded(muted) : _buildCollapsed(muted),
      ),
    );
  }

  // --- 折叠态：仅显示当前项 ---
  Widget _buildCollapsed(Color muted) {
    final current = _currentStep;
    final label = current?.description ?? '查看执行计划';
    return InkWell(
      onTap: () => setState(() => _expanded = true),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.checklist_rounded,
                size: 18, color: Color(0xFF1677FF)),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  const Icon(Icons.arrow_right_alt_rounded,
                      size: 16, color: Color(0xFF1677FF)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1677FF),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _threeDotMenu(muted),
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
  Widget _buildExpanded(Color muted) {
    final theme = Theme.of(context);
    final total = widget.plan.steps.length;
    final done = _completedCount;
    final progress = total == 0 ? 0.0 : done / total;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部：标题 + 三点菜单 + 收起图标
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
          child: Row(
            children: [
              const Icon(Icons.checklist_rounded,
                  size: 18, color: Color(0xFF1677FF)),
              const SizedBox(width: 8),
              Text(
                '计划',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              _threeDotMenu(muted),
              IconButton(
                tooltip: '收起计划',
                icon: const Icon(Icons.expand_more_rounded, size: 20),
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
                color: const Color(0xFF1677FF).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('目标',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1677FF))),
                  const SizedBox(height: 2),
                  Text(
                    widget.goal!,
                    style: TextStyle(
                        fontSize: 13,
                        color: theme.brightness == Brightness.dark
                            ? const Color(0xFFEDF1F8)
                            : const Color(0xFF243B53)),
                  ),
                ],
              ),
            ),
          ),
        // 进度
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          child: Row(
            children: [
              Text('进度 $done/$total',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: theme.brightness == Brightness.dark
                        ? const Color(0xFF303746)
                        : const Color(0xFFE2E8F0),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Color(0xFF1677FF)),
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
        // 未确认时的审批按钮
        if (!widget.plan.isConfirmed)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onCancel,
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: widget.onApprove,
                    child: const Text('执行'),
                  ),
                ),
              ],
            ),
          ),
        // 底部署名
        const Divider(height: 1, thickness: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  size: 14, color: Color(0xFF1677FF)),
              const SizedBox(width: 6),
              const Text('智能体',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF627D98))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepRow(PlanStep step, Color muted) {
    final isCurrent = step.status == 'running' ||
        (step.status == 'pending' && step == _currentStep);
    final isDone = step.status == 'completed';
    final isFailed = step.status == 'failed';

    IconData leadIcon;
    Color leadColor;
    if (isDone) {
      leadIcon = Icons.check_circle_rounded;
      leadColor = const Color(0xFF16A34A);
    } else if (isFailed) {
      leadIcon = Icons.cancel_rounded;
      leadColor = const Color(0xFFDC2626);
    } else if (isCurrent) {
      leadIcon = Icons.arrow_right_alt_rounded;
      leadColor = const Color(0xFF1677FF);
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
                fontSize: 14,
                color: isCurrent
                    ? const Color(0xFF1677FF)
                    : (isDone
                        ? const Color(0xFF16A34A)
                        : (isFailed ? const Color(0xFFDC2626) : muted)),
                fontWeight:
                    (isCurrent || isDone) ? FontWeight.w600 : FontWeight.normal,
                decoration: isDone ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (isCurrent)
            const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
    );
  }

  /// 计划操作菜单：与全应用一致的沉浸式毛玻璃面板（替代不透明 PopupMenu）。
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
                title: const Text('执行计划'),
                onTap: () => Navigator.pop(sheetContext, 'approve'),
              ),
            if (!widget.plan.isConfirmed)
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text('取消计划'),
                onTap: () => Navigator.pop(sheetContext, 'cancel'),
              ),
            ListTile(
              leading: const Icon(Icons.expand_less_rounded),
              title: const Text('收起'),
              onTap: () => Navigator.pop(sheetContext, 'collapse'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
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
