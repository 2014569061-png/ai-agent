import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/orchestration_module.dart';
import '../../domain/collaboration_models.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/section_card.dart';
import 'collaboration_timeline.dart';

/// 协作方案确认底栏 (CollaborationPlanSheet)
/// 严格依据 NEXUS UI 设计优化规范重构：
/// 1. 顶部优先呈现任务目标与只读安全保障说明。
/// 2. 参与角色卡展示职责、允许只读工具。
/// 3. 协作模式提供清晰的适用场景解释。
/// 4. 步进控制 Agent 数量、轮次与预算。
/// 5. 明确“确认方案并开始分析”主操作。
class CollaborationPlanSheet extends ConsumerStatefulWidget {
  const CollaborationPlanSheet({super.key, required this.task});

  final DevelopmentTaskInput task;

  @override
  ConsumerState<CollaborationPlanSheet> createState() =>
      _CollaborationPlanSheetState();
}

class _CollaborationPlanSheetState
    extends ConsumerState<CollaborationPlanSheet> {
  CollaborationPlan? _plan;
  CollaborationMode _mode = CollaborationMode.parallel;
  int _maxAgents = 3;
  int _maxRounds = 1;
  int _budgetTokens = 4000;
  Object? _error;
  bool _loading = true;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _loadPlan();
  }

  Future<void> _loadPlan() async {
    try {
      final plan =
          await ref.read(orchestrationModuleProvider).propose(widget.task);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _maxAgents = plan.maxAgents;
        _maxRounds = plan.maxRounds;
        _budgetTokens = plan.budgetTokens;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _start() async {
    final plan = _plan;
    if (plan == null || _starting) return;
    setState(() => _starting = true);
    try {
      final run = await ref.read(orchestrationModuleProvider).start(
            widget.task.taskId,
            CollaborationApproval(
              budgetTokens: _budgetTokens,
              maxAgents: _maxAgents,
              maxRounds: _maxRounds,
              mode: _mode,
            ),
          );
      if (!mounted) return;
      Navigator.pop(context);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CollaborationTimelinePage(
            runId: run.id,
            initialRun: run,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = error;
      });
    }
  }

  String _modeDescription(CollaborationMode mode) => switch (mode) {
        CollaborationMode.parallel => '多角色独立并行阅读代码与定位模块，速度最快',
        CollaborationMode.debate => '多角色互相校验与质疑方案，充分暴露隐患与冲突',
        CollaborationMode.sequential => '规划、分析、验证、审查按顺序递进深入',
      };

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: _loading
            ? const SizedBox(
                height: 260,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : _error != null
                ? _errorView()
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('协作分析方案确认',
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w500)),
                        const SizedBox(height: 6),

                        // 1. 目标任务与安全说明卡
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppPalette.brand.withValues(alpha: 0.08),
                            borderRadius:
                                BorderRadius.circular(AppTokens.radiusCard),
                            border: Border.all(
                              color: AppPalette.brand.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.shield_outlined,
                                      size: 16, color: AppPalette.brand),
                                  SizedBox(width: 6),
                                  Text(
                                    '只读安全协同',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: AppPalette.brand,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '任务目标：${widget.task.prompt.isEmpty ? "分析当前工程上下文并制定方案" : widget.task.prompt}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '协作分析仅使用只读工具（读文件/搜符号），不会修改任何工作区代码。',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        if (plan != null) ...[
                          // 2. 参与角色卡
                          _sectionTitle('参与协作角色'),
                          ...plan.agents.map(
                            (agent) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: SectionCard(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(Icons.smart_toy_outlined,
                                          size: 16,
                                          color: theme.colorScheme.primary),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            agent.role.label,
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            agent.role.responsibility,
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: theme.colorScheme
                                                    .onSurfaceVariant),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '允许工具：${agent.allowedTools.join("、")}',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: theme.colorScheme
                                                    .onSurfaceVariant
                                                    .withValues(alpha: 0.8)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // 3. 协作模式
                          _sectionTitle('协同模式'),
                          SegmentedButton<CollaborationMode>(
                            segments: CollaborationMode.values
                                .map((mode) => ButtonSegment(
                                      value: mode,
                                      label: Text(mode.label),
                                    ))
                                .toList(),
                            selected: {_mode},
                            onSelectionChanged: (value) =>
                                setState(() => _mode = value.first),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 6, bottom: 12),
                            child: Text(
                              _modeDescription(_mode),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),

                          // 4. 参数配置步进器
                          _sectionTitle('预算与规模控制'),
                          SectionCard(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                _stepperRow(
                                  '子 Agent 数量',
                                  '$_maxAgents 个',
                                  canDecrease: _maxAgents > 2,
                                  canIncrease: _maxAgents < plan.maxAgents,
                                  onDecrease: () =>
                                      setState(() => _maxAgents--),
                                  onIncrease: () =>
                                      setState(() => _maxAgents++),
                                ),
                                const Divider(height: 16),
                                _stepperRow(
                                  '最大讨论轮次',
                                  '$_maxRounds 轮',
                                  canDecrease: _maxRounds > 1,
                                  canIncrease: _maxRounds < 3,
                                  onDecrease: () =>
                                      setState(() => _maxRounds--),
                                  onIncrease: () =>
                                      setState(() => _maxRounds++),
                                ),
                                const Divider(height: 16),
                                _stepperRow(
                                  'Token 预算上限',
                                  '$_budgetTokens Token',
                                  canDecrease: _budgetTokens > 2000,
                                  canIncrease: _budgetTokens < 12000,
                                  onDecrease: () =>
                                      setState(() => _budgetTokens -= 1000),
                                  onIncrease: () =>
                                      setState(() => _budgetTokens += 1000),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 18),

                          // 5. 底部操作按钮
                          Row(
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('取消'),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(0, 46),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          AppTokens.radiusControl),
                                    ),
                                  ),
                                  onPressed: _starting ? null : _start,
                                  icon: _starting
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : const Icon(Icons.play_arrow_rounded),
                                  label:
                                      Text(_starting ? '正在启动协同…' : '确认方案并开始分析'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _stepperRow(
    String title,
    String valueText, {
    required bool canDecrease,
    required bool canIncrease,
    required VoidCallback onDecrease,
    required VoidCallback onIncrease,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.outlined(
              icon: const Icon(Icons.remove, size: 14),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: canDecrease ? onDecrease : null,
            ),
            SizedBox(
              width: 84,
              child: Text(
                valueText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            IconButton.outlined(
              icon: const Icon(Icons.add, size: 14),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: canIncrease ? onIncrease : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _errorView() => SizedBox(
        height: 260,
        child: Center(
          child: EmptyStateView.compact(
            icon: Icons.error_outline_rounded,
            title: '协作方案生成失败',
            message: '$_error',
          ),
        ),
      );

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Text(title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      );
}
