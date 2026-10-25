import '../../theme/mobile_theme.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../motion/nexus_motion.dart';

import '../../../application/chat_controller.dart';
import '../../../application/context_compression_planner.dart';
import '../../../domain/context_insights.dart';
import '../../../domain/models.dart';
import '../../../domain/session_metrics.dart';
import '../../dashboard/widgets/token_numbers.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/nexus_sheet.dart';
import 'context_budget_bar.dart';
import 'session_metrics_summary.dart';

/// Opens the current conversation telemetry sheet.
Future<void> showSessionMetricsSheet(
  BuildContext context, {
  required SessionMetrics metrics,
  List<ChatMessage> messages = const [],
  ValueChanged<ContextCompressionPlan>? onCompress,
  required int liveContextTokens,
  required int contextLimit,
  int reservedOutputTokens = 2048,
  ContextSnapshot? contextSnapshot,
  List<ContextStepRecord> contextSteps = const [],
  List<ContextRunHistory> contextRuns = const [],
  TimingSnapshot timing = TimingSnapshot.empty,
  List<ToolActivity> toolActivities = const [],
  String? runLabel,
  ValueChanged<String?>? onJumpToMessage,
}) {
  return showNexusSheet<void>(
    context: context,
    maxHeightRatio: 0.78,
    builder: (_) => SessionMetricsSheet(
      metrics: metrics,
      messages: messages,
      onCompress: onCompress,
      liveContextTokens: liveContextTokens,
      contextLimit: contextLimit,
      reservedOutputTokens: reservedOutputTokens,
      contextSnapshot: contextSnapshot,
      contextSteps: contextSteps,
      contextRuns: contextRuns,
      timing: timing,
      toolActivities: toolActivities,
      runLabel: runLabel,
      onJumpToMessage: onJumpToMessage,
    ),
  );
}

/// The single entry point for current-conversation context and run telemetry.
class SessionMetricsSheet extends StatefulWidget {
  const SessionMetricsSheet({
    super.key,
    required this.metrics,
    this.messages = const [],
    this.onCompress,
    required this.liveContextTokens,
    required this.contextLimit,
    this.reservedOutputTokens = 2048,
    this.contextSnapshot,
    this.contextSteps = const [],
    this.contextRuns = const [],
    this.timing = TimingSnapshot.empty,
    this.toolActivities = const [],
    this.runLabel,
    this.onJumpToMessage,
  });

  final SessionMetrics metrics;
  final List<ChatMessage> messages;
  final ValueChanged<ContextCompressionPlan>? onCompress;
  final int liveContextTokens;
  final int contextLimit;
  final int reservedOutputTokens;
  final ContextSnapshot? contextSnapshot;
  final List<ContextStepRecord> contextSteps;
  final List<ContextRunHistory> contextRuns;
  final TimingSnapshot timing;
  final List<ToolActivity> toolActivities;
  final String? runLabel;
  final ValueChanged<String?>? onJumpToMessage;

  @override
  State<SessionMetricsSheet> createState() => _SessionMetricsSheetState();
}

class _SessionMetricsSheetState extends State<SessionMetricsSheet> {
  var _selectedTab = 0;
  bool _showDetails = false;
  int? _selectedHistoryIndex;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedHistory = _selectedHistoryIndex != null &&
            _selectedHistoryIndex! < widget.contextRuns.length
        ? widget.contextRuns[_selectedHistoryIndex!]
        : null;
    final snapshot = selectedHistory?.latestSnapshot ?? widget.contextSnapshot;
    final steps = selectedHistory?.steps ?? widget.contextSteps;
    final historyEvents = selectedHistory?.events ?? const <ContextRunEvent>[];
    final liveTokens = snapshot?.usedTokens ?? widget.liveContextTokens;
    final limit = snapshot?.contextWindow ?? widget.contextLimit;
    final reservedOutput =
        snapshot?.reservedOutputTokens ?? widget.reservedOutputTokens;
    final compressionPlan = selectedHistory == null
        ? const ContextCompressionPlanner().planForConversation(
            messages: widget.messages,
            liveToolResults: [
              for (final activity in widget.toolActivities)
                if (activity.result != null)
                  ToolResultRef(
                    toolCallId: activity.call.id,
                    result: activity.result!,
                  ),
            ],
            contextWindow: limit,
            fixedTokens: snapshot?.tokensFor(ContextPartType.tools) ?? 0,
            reservedOutputTokens:
                snapshot?.reservedOutputTokens ?? widget.reservedOutputTokens,
          )
        : null;
    final usage = snapshot?.providerUsage;
    final totalTokens = usage?.totalTokens ?? widget.metrics.totalTokens;
    final hasUsage = usage?.usageReported ?? totalTokens > 0;
    final hasTiming = widget.timing != TimingSnapshot.empty;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              totalTokens: totalTokens,
              hasUsage: hasUsage,
              runLabel: widget.runLabel,
              onClose: () => Navigator.pop(context),
            ),
            if (!_showDetails) ...[
              const SizedBox(height: 12),
              SessionMetricsSummary(
                  metrics: widget.metrics,
                  used: liveTokens,
                  limit: limit,
                  reserved: reservedOutput,
                  timing: widget.timing,
                  usage: usage,
                  status: widget.runLabel),
              if (snapshot != null &&
                  snapshot.budgetLevel != ContextBudgetLevel.normal)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _ContextInsight(
                        snapshot: snapshot, budget: snapshot.budgetLevel)),
              if (compressionPlan?.shouldSuggest == true)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _CompressionSuggestion(
                        plan: compressionPlan!, onCompress: widget.onCompress)),
            ],
            Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('metrics-details-toggle'),
                  onPressed: () => setState(() {
                    _showDetails = !_showDetails;
                    if (!_showDetails) _selectedHistoryIndex = null;
                  }),
                  icon: Icon(
                      _showDetails ? Icons.expand_less : Icons.tune_rounded),
                  label: Text(_showDetails ? '返回简要总览' : '详细诊断'),
                )),
            if (_showDetails) ...[
              if (widget.contextRuns.isNotEmpty) ...[
                const SizedBox(height: 8),
                _RunSelector(
                  runs: widget.contextRuns,
                  selectedIndex: _selectedHistoryIndex,
                  onChanged: (index) {
                    setState(() => _selectedHistoryIndex = index);
                    if (index != null && widget.onJumpToMessage != null) {
                      final anchor = widget
                          .contextRuns[index].steps.lastOrNull?.anchorMessageId;
                      widget.onJumpToMessage!(anchor);
                    }
                  },
                ),
              ],
              const SizedBox(height: 12),
              _MetricsTabs(
                selected: _selectedTab,
                onSelected: (index) => setState(() => _selectedTab = index),
              ),
              const SizedBox(height: 14),
              _SectionDivider(color: scheme.outlineVariant),
              const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: NexusMotion.durationFast(context),
                child: _buildTab(
                  snapshot: snapshot,
                  liveTokens: liveTokens,
                  limit: limit,
                  reservedOutputTokens: reservedOutput,
                  usage: usage,
                  steps: steps,
                  historyEvents: historyEvents,
                  hasUsage: hasUsage,
                  hasTiming: hasTiming,
                  compressionPlan: compressionPlan,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTab({
    required ContextSnapshot? snapshot,
    required int liveTokens,
    required int limit,
    required Usage? usage,
    required List<ContextStepRecord> steps,
    required List<ContextRunEvent> historyEvents,
    required bool hasUsage,
    required bool hasTiming,
    required int reservedOutputTokens,
    required ContextCompressionPlan? compressionPlan,
  }) {
    return switch (_selectedTab) {
      0 => _OverviewTab(
          key: const ValueKey('overview'),
          snapshot: snapshot,
          liveTokens: liveTokens,
          limit: limit,
          metrics: widget.metrics,
          usage: usage,
          timing: widget.timing,
          hasUsage: hasUsage,
          hasTiming: hasTiming,
          reservedOutputTokens: reservedOutputTokens,
          compressionPlan: compressionPlan,
          onCompress: widget.onCompress,
        ),
      1 => _StepsTab(
          key: const ValueKey('steps'),
          snapshot: snapshot,
          metrics: widget.metrics,
          timing: widget.timing,
          contextSteps: steps,
          toolActivities: widget.toolActivities,
          onJumpToMessage: widget.onJumpToMessage,
        ),
      2 => _ContextBrowserTab(
          key: const ValueKey('browser'),
          snapshot: snapshot,
          liveTokens: liveTokens,
          limit: limit,
          reservedOutputTokens: reservedOutputTokens,
        ),
      3 => _EventsTab(
          key: const ValueKey('events'),
          toolActivities: widget.toolActivities,
          historyEvents: historyEvents,
          runLabel: widget.runLabel,
        ),
      4 => _FileActivityTab(
          key: const ValueKey('files'),
          toolActivities: widget.toolActivities,
          historyEvents: historyEvents,
        ),
      _ => _AgentNetworkTab(
          key: const ValueKey('network'),
          liveTokens: liveTokens,
          limit: limit,
          timing: widget.timing,
          runLabel: widget.runLabel,
        ),
    };
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.totalTokens,
    required this.hasUsage,
    required this.runLabel,
    required this.onClose,
  });

  final int totalTokens;
  final bool hasUsage;
  final String? runLabel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final status = runLabel?.trim();
    return Row(
      children: [
        Icon(Icons.analytics_outlined,
            size: 21, color: AppPalette.brandText(context)),
        const SizedBox(width: 8),
        const Text('会话指标',
            style: TextStyle(
                fontSize: AppTokens.fontSizeHeading,
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            status?.isNotEmpty == true
                ? status!
                : (hasUsage
                    ? '本次运行 ${formatCompact(totalTokens)} tok'
                    : 'Token 统计待模型返回'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                TextStyle(fontSize: AppTokens.fontSizeFootnote, color: muted),
          ),
        ),
        Semantics(
          label: '关闭会话指标',
          button: true,
          child: IconButton(
            tooltip: '关闭会话指标',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, color: muted),
            onPressed: onClose,
          ),
        ),
      ],
    );
  }
}

class _MetricsTabs extends StatelessWidget {
  const _MetricsTabs({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;
  static const _labels = ['概览', '步骤', '浏览', '事件', '文件', '网络'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brandColor = AppPalette.brandText(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < _labels.length; index++)
            Padding(
              padding:
                  EdgeInsets.only(right: index == _labels.length - 1 ? 0 : 8),
              child: ChoiceChip(
                label: Text(_labels[index]),
                selected: selected == index,
                onSelected: (_) => onSelected(index),
                selectedColor: isDark
                    ? AppPalette.darkBrandSoft
                    : MobileTheme.brand(context).withValues(alpha: 0.14),
                side: BorderSide(
                  color: selected == index ? brandColor : scheme.outlineVariant,
                ),
                labelStyle: TextStyle(
                  fontSize: AppTokens.fontSizeCaption,
                  fontWeight:
                      selected == index ? FontWeight.w600 : FontWeight.w400,
                  color:
                      selected == index ? brandColor : scheme.onSurfaceVariant,
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    super.key,
    required this.snapshot,
    required this.liveTokens,
    required this.limit,
    required this.reservedOutputTokens,
    required this.metrics,
    required this.usage,
    required this.timing,
    required this.hasUsage,
    required this.hasTiming,
    required this.compressionPlan,
    required this.onCompress,
  });

  final ContextSnapshot? snapshot;
  final int liveTokens;
  final int limit;
  final int reservedOutputTokens;
  final SessionMetrics metrics;
  final Usage? usage;
  final TimingSnapshot timing;
  final bool hasUsage;
  final bool hasTiming;
  final ContextCompressionPlan? compressionPlan;
  final ValueChanged<ContextCompressionPlan>? onCompress;

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).colorScheme.outlineVariant;
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ContextCapacity(
          snapshot: snapshot,
          liveTokens: liveTokens,
          limit: limit,
          reservedOutputTokens: reservedOutputTokens,
          compressionPlan: compressionPlan,
          onCompress: onCompress,
        ),
        const SizedBox(height: 18),
        _SectionDivider(color: divider),
        const SizedBox(height: 14),
        _TokenComposition(metrics: metrics, usage: usage, hasUsage: hasUsage),
        const SizedBox(height: 18),
        _SectionDivider(color: divider),
        const SizedBox(height: 14),
        _TimingBreakdown(
          timing: timing,
          fallbackLlm: metrics.llmTime,
          fallbackTool: metrics.toolTime,
          showDetailedTiming: hasTiming,
        ),
      ],
    );
  }
}

class _StepsTab extends StatelessWidget {
  const _StepsTab({
    super.key,
    required this.snapshot,
    required this.metrics,
    required this.timing,
    required this.contextSteps,
    required this.toolActivities,
    this.onJumpToMessage,
  });

  final ContextSnapshot? snapshot;
  final SessionMetrics metrics;
  final TimingSnapshot timing;
  final List<ContextStepRecord> contextSteps;
  final List<ToolActivity> toolActivities;
  final ValueChanged<String?>? onJumpToMessage;

  @override
  Widget build(BuildContext context) {
    final estimated = snapshot?.usedTokens;
    final actual = snapshot?.providerUsage?.promptTokens;
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
            icon: Icons.stacked_bar_chart_rounded, label: '上下文趋势'),
        const SizedBox(height: 10),
        if (contextSteps.isEmpty)
          Text(
            '等待第一次模型请求后生成逐步快照。',
            style: TextStyle(
                fontSize: AppTokens.fontSizeFootnote,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          )
        else ...[
          _ContextTrend(steps: contextSteps),
          const SizedBox(height: 12),
          for (final step in contextSteps.reversed)
            _StepRow(
              record: step,
              onTap: onJumpToMessage == null
                  ? null
                  : () => onJumpToMessage!(step.anchorMessageId),
            ),
        ],
        const SizedBox(height: 14),
        const _SectionTitle(icon: Icons.analytics_outlined, label: '当前步骤'),
        const SizedBox(height: 10),
        _MetricRows(rows: [
          _MetricRowData(
              '对话轮次', '${metrics.rounds}', '轮', MobileTheme.brand(context)),
          _MetricRowData(
              '模型步骤', '${metrics.steps}', '步', MobileTheme.brand(context)),
          _MetricRowData(
              '估算上下文',
              estimated == null ? '--' : '≈${formatCompact(estimated)}',
              'tok',
              AppPalette.success),
          _MetricRowData('实际输入', actual == null ? '--' : formatCompact(actual),
              actual == null ? '待模型返回' : 'tok', AppPalette.warning),
          _MetricRowData(
              '工具调用', '${toolActivities.length}', '次', AppPalette.danger),
          _MetricRowData(
              '模型请求',
              '${timing.modelCalls > 0 ? timing.modelCalls : metrics.steps}',
              '次',
              MobileTheme.brand(context)),
        ]),
        if (snapshot != null) ...[
          const SizedBox(height: 16),
          ContextBudgetBar.fromParts(
              parts: snapshot!.parts,
              limit: snapshot!.contextWindow,
              reservedOutputTokens: snapshot!.reservedOutputTokens,
              fallbackRatio: snapshot!.ratio,
              fallbackColor: MobileTheme.brand(context)),
        ],
      ],
    );
  }
}

class _ContextTrend extends StatelessWidget {
  const _ContextTrend({required this.steps});

  final List<ContextStepRecord> steps;

  @override
  Widget build(BuildContext context) {
    final maxTokens = steps.fold<int>(
        1, (maxValue, step) => math.max(maxValue, step.snapshot.usedTokens));
    return SizedBox(
      height: 92,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final step in steps)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Tooltip(
                  message:
                      '第 ${step.step} 步：≈${formatCompact(step.snapshot.usedTokens)} tok',
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor: step.snapshot.usedTokens / maxTokens,
                            widthFactor: 1,
                            child: ContextBudgetBar.fromParts(
                              parts: step.snapshot.parts,
                              limit: step.snapshot.usedTokens,
                              fallbackRatio: 1,
                              fallbackColor: MobileTheme.brand(context),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text('${step.step}',
                          style: TextStyle(
                              fontSize: AppTokens.fontSizeBadge,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.record, this.onTap});

  final ContextStepRecord record;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final usage = record.usage;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: MobileTheme.brand(context).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(5)),
              child: Text('${record.step}',
                  style: TextStyle(
                      fontSize: AppTokens.fontSizeFootnote,
                      fontWeight: FontWeight.w600,
                      color: MobileTheme.brand(context))),
            ),
            const SizedBox(width: 9),
            Expanded(
                child: Text('估算 ≈${formatCompact(record.snapshot.usedTokens)}',
                    style: const TextStyle(
                        fontSize: AppTokens.fontSizeCaption,
                        fontWeight: FontWeight.w500))),
            Text(
              usage == null
                  ? '等待统计'
                  : '实际 ${formatCompact(usage.promptTokens)}',
              style:
                  TextStyle(fontSize: AppTokens.fontSizeFootnote, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContextBrowserTab extends StatelessWidget {
  const _ContextBrowserTab({
    super.key,
    required this.snapshot,
    required this.liveTokens,
    required this.limit,
    required this.reservedOutputTokens,
  });

  final ContextSnapshot? snapshot;
  final int liveTokens;
  final int limit;
  final int reservedOutputTokens;

  @override
  Widget build(BuildContext context) {
    final parts = snapshot?.parts ?? const <ContextPart>[];
    final total = snapshot?.usedTokens ?? liveTokens;
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
            icon: Icons.account_tree_outlined,
            label: '上下文浏览器',
            trailing: '下一次请求'),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('估算合计 ≈${formatCompact(total)}',
                style: const TextStyle(
                    fontSize: AppTokens.fontSizeSubhead,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('/ ${formatCompact(limit)} tok',
                style: TextStyle(
                    fontSize: AppTokens.fontSizeFootnote,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 10),
        ContextBudgetBar.fromParts(
            parts: parts,
            limit: limit,
            reservedOutputTokens: reservedOutputTokens,
            fallbackRatio: limit <= 0 ? 0 : total / limit,
            fallbackColor: MobileTheme.brand(context)),
        const SizedBox(height: 12),
        if (parts.isEmpty)
          const _EmptyTabState(
              icon: Icons.hourglass_empty_rounded, text: '等待第一次模型请求后生成上下文快照')
        else
          for (final part in parts) _ContextPartRow(part: part, total: total),
      ],
    );
  }
}

class _EventsTab extends StatelessWidget {
  const _EventsTab({
    super.key,
    required this.toolActivities,
    required this.historyEvents,
    required this.runLabel,
  });

  final List<ToolActivity> toolActivities;
  final List<ContextRunEvent> historyEvents;
  final String? runLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(icon: Icons.bolt_outlined, label: '上下文事件'),
        const SizedBox(height: 8),
        Text(historyEvents.isEmpty ? '仅显示当前运行中已记录的工具和状态事件。' : '显示所选历史运行的已记录事件。',
            style: TextStyle(
                fontSize: AppTokens.fontSizeFootnote,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 14),
        if (historyEvents.isNotEmpty)
          for (final event in historyEvents)
            _EventRow(
              icon: _eventIcon(event.type),
              color: _eventColor(context, event.type, event.status),
              title: event.name,
              detail: _eventDetail(event),
            )
        else ...[
          if (runLabel?.isNotEmpty == true)
            _EventRow(
                icon: Icons.radio_button_checked_rounded,
                color: MobileTheme.brand(context),
                title: runLabel!,
                detail: '当前状态'),
          for (final activity in toolActivities)
            _EventRow(
              icon: activity.status == '已完成'
                  ? Icons.check_circle_outline_rounded
                  : Icons.build_outlined,
              color: activity.status == '已完成'
                  ? AppPalette.success
                  : AppPalette.warning,
              title: activity.call.name,
              detail:
                  '${activity.status} · ${formatDurationLabel(activity.duration)}',
            ),
          if (toolActivities.isEmpty && runLabel?.isNotEmpty != true)
            const _EmptyTabState(
                icon: Icons.event_note_outlined, text: '当前运行暂无可展示事件'),
        ],
      ],
    );
  }
}

class _FileActivityTab extends StatelessWidget {
  const _FileActivityTab({
    super.key,
    required this.toolActivities,
    required this.historyEvents,
  });
  final List<ToolActivity> toolActivities;
  final List<ContextRunEvent> historyEvents;

  @override
  Widget build(BuildContext context) {
    final fileEvents = historyEvents
        .where((event) =>
            event.type == 'file_operation' || _isFileTool(event.name))
        .toList(growable: false);
    final fileTools = toolActivities
        .where((activity) => _isFileTool(activity.call.name))
        .toList(growable: false);
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(icon: Icons.folder_outlined, label: '文件活动'),
        const SizedBox(height: 8),
        Text('本次运行的文件工具调用。路径与内容仅在工具返回时记录。',
            style: TextStyle(
                fontSize: AppTokens.fontSizeFootnote,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 14),
        if (fileEvents.isNotEmpty)
          for (final event in fileEvents)
            _EventRow(
              icon: Icons.description_outlined,
              color: _eventColor(context, event.type, event.status),
              title: event.metadata['path']?.toString() ?? event.name,
              detail: _eventDetail(event),
            )
        else if (fileTools.isEmpty)
          const _EmptyTabState(
              icon: Icons.insert_drive_file_outlined, text: '本次运行尚未调用文件工具')
        else
          for (final activity in fileTools)
            _EventRow(
              icon: Icons.description_outlined,
              color: activity.status == '已完成'
                  ? AppPalette.success
                  : AppPalette.warning,
              title: activity.call.name,
              detail:
                  '${activity.status} · ${formatDurationLabel(activity.duration)}',
            ),
      ],
    );
  }
}

class _AgentNetworkTab extends StatelessWidget {
  const _AgentNetworkTab({
    super.key,
    required this.liveTokens,
    required this.limit,
    required this.timing,
    required this.runLabel,
  });

  final int liveTokens;
  final int limit;
  final TimingSnapshot timing;
  final String? runLabel;

  @override
  Widget build(BuildContext context) {
    final ratio = limit <= 0 ? 0.0 : (liveTokens / limit).clamp(0.0, 1.0);
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(icon: Icons.hub_outlined, label: 'Agent 网络'),
        const SizedBox(height: 8),
        Text('当前项目尚未记录子 Agent 拓扑，显示主 Agent 实时上下文。',
            style: TextStyle(
                fontSize: AppTokens.fontSizeFootnote,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 18),
        Center(
            child: _NetworkNode(
                ratio: ratio,
                tokens: liveTokens,
                label: runLabel ?? '主 Agent')),
        const SizedBox(height: 16),
        _MetricRows(rows: [
          _MetricRowData('运行 Agent', '1', '个', MobileTheme.brand(context)),
          _MetricRowData(
              '模型请求', '${timing.modelCalls}', '次', MobileTheme.brand(context)),
          _MetricRowData(
              '上下文合计', formatCompact(liveTokens), 'tok', AppPalette.success),
        ]),
      ],
    );
  }
}

class _RunSelector extends StatelessWidget {
  const _RunSelector({
    required this.runs,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<ContextRunHistory> runs;
  final int? selectedIndex;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = selectedIndex;
    return DropdownButtonFormField<int?>(
      key: ValueKey(current),
      initialValue: current,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: '运行记录',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(7)),
      ),
      items: [
        const DropdownMenuItem<int?>(value: null, child: Text('当前运行')),
        for (var index = 0; index < runs.length; index++)
          DropdownMenuItem<int?>(
            value: index,
            child: Text(_runLabel(runs[index], index)),
          ),
      ],
      onChanged: onChanged,
    );
  }

  String _runLabel(ContextRunHistory run, int index) {
    final time =
        '${run.startedAt.hour.toString().padLeft(2, '0')}:${run.startedAt.minute.toString().padLeft(2, '0')}';
    return '历史运行 ${index + 1} · ${run.steps.length} 步 · $time · ${run.status}';
  }
}

IconData _eventIcon(String type) => switch (type) {
      'file_operation' => Icons.description_outlined,
      'tool_call' => Icons.build_outlined,
      'model_request' => Icons.memory_rounded,
      'context_snapshot' => Icons.data_usage_outlined,
      'context_usage' => Icons.analytics_outlined,
      'context_inject' => Icons.add_circle_outline_rounded,
      'context_prune' => Icons.remove_circle_outline_rounded,
      'context_compress' => Icons.compress_rounded,
      'context_budget' => Icons.speed_rounded,
      _ => Icons.event_note_outlined,
    };

Color _eventColor(BuildContext context, String type, String status) {
  if (status == 'failed') return AppPalette.danger;
  if (type == 'file_operation') return AppPalette.success;
  if (type == 'model_request') return MobileTheme.brand(context);
  if (type == 'context_snapshot' || type == 'context_usage') {
    return MobileTheme.brand(context);
  }
  if (type == 'context_inject') return AppPalette.success;
  if (type == 'context_prune') return AppPalette.warning;
  if (type == 'context_compress') return MobileTheme.brand(context);
  if (type == 'context_budget') {
    return status == 'critical' ? AppPalette.danger : AppPalette.warning;
  }
  return status == 'success' ? AppPalette.success : AppPalette.warning;
}

String _eventDetail(ContextRunEvent event) {
  final step = event.metadata['step'];
  final delta = event.metadata['deltaTokens'];
  final level = event.metadata['level'];
  final usedTokens = event.metadata['usedTokens'];
  final remainingTokens = event.metadata['remainingTokens'];
  final time =
      '${event.createdAt.hour.toString().padLeft(2, '0')}:${event.createdAt.minute.toString().padLeft(2, '0')}';
  final stepLabel = step == null ? '' : '步骤 $step · ';
  if (delta is num) {
    final prefix = delta >= 0 ? '+' : '-';
    return '$stepLabel$prefix≈${formatCompact(delta.abs().round())} tok · $time';
  }
  if (level is String) {
    final used = usedTokens is num ? formatCompact(usedTokens.round()) : '--';
    final remaining =
        remainingTokens is num ? formatCompact(remainingTokens.round()) : '--';
    return '$stepLabel预算$level · $used / 剩余 $remaining · $time';
  }
  return '$stepLabel$time';
}

class _ContextCapacity extends StatelessWidget {
  const _ContextCapacity({
    required this.snapshot,
    required this.liveTokens,
    required this.reservedOutputTokens,
    required this.limit,
    required this.compressionPlan,
    required this.onCompress,
  });

  final ContextSnapshot? snapshot;
  final int liveTokens;
  final int reservedOutputTokens;
  final int limit;
  final ContextCompressionPlan? compressionPlan;
  final ValueChanged<ContextCompressionPlan>? onCompress;

  @override
  Widget build(BuildContext context) {
    final parts = snapshot?.parts ?? const <ContextPart>[];
    final hasParts = parts.any((part) => part.tokens > 0);
    final effectiveReservedOutput =
        snapshot?.reservedOutputTokens ?? reservedOutputTokens;
    final inputLimit = ContextBudget.inputBudgetFor(
      contextWindow: limit,
      reservedOutputTokens: effectiveReservedOutput,
    );
    final ratio = ContextBudget.ratioFor(
      usedTokens: liveTokens,
      contextWindow: limit,
      reservedOutputTokens: effectiveReservedOutput,
    ).clamp(0.0, 1.0);
    final percent = (ratio * 100).round();
    final budget = snapshot?.budgetLevel ??
        ContextBudget.levelFor(
          usedTokens: liveTokens,
          contextWindow: limit,
          reservedOutputTokens: effectiveReservedOutput,
        );
    final color = contextBudgetColor(budget);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(icon: Icons.data_usage_outlined, label: '当前上下文'),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              formatCompact(liveTokens),
              style: const TextStyle(
                  fontSize: AppTokens.fontSizeDisplay2,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()]),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                limit > 0 ? '/ 输入上限 ${formatCompact(inputLimit)} tok' : 'tok',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: AppTokens.fontSizeSubhead,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            Text('$percent%',
                style: TextStyle(
                    fontSize: AppTokens.fontSizeMetric,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ],
        ),
        if (effectiveReservedOutput > 0) ...[
          const SizedBox(height: 2),
          Text(
            '含输出预留 ≈${formatCompact(effectiveReservedOutput)} tok',
            style: TextStyle(
              fontSize: AppTokens.fontSizeFootnote,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 10),
        ContextBudgetBar.fromParts(
            parts: parts,
            limit: limit,
            reservedOutputTokens: effectiveReservedOutput,
            fallbackRatio: ratio,
            fallbackColor: color),
        if (snapshot != null) ...[
          const SizedBox(height: 10),
          _ContextInsight(snapshot: snapshot!, budget: budget),
        ],
        if (compressionPlan?.shouldSuggest == true) ...[
          const SizedBox(height: 10),
          _CompressionSuggestion(
            plan: compressionPlan!,
            onCompress: onCompress,
          ),
        ],
        if (hasParts) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 7,
            children: [
              for (final part in parts.where((part) => part.tokens > 0))
                _Legend(
                  color: contextPartColor(part.type),
                  label: part.type.label,
                  value: '≈${formatCompact(part.tokens)}',
                ),
              if (effectiveReservedOutput > 0)
                _Legend(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  label: '输出预留',
                  value: '≈${formatCompact(effectiveReservedOutput)}',
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ContextInsight extends StatelessWidget {
  const _ContextInsight({required this.snapshot, required this.budget});

  final ContextSnapshot snapshot;
  final ContextBudgetLevel budget;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final dominant = snapshot.dominantPart;
    final title = dominant == null
        ? '上下文组成待生成'
        : '主要占用：${dominant.type.label} ${formatCompact(dominant.tokens)} tok';
    final estimate = snapshot.hasEstimatedComposition ? '组成估算' : '组成统计';
    final changes = <String>[
      if (snapshot.omittedParts.isNotEmpty)
        '已压缩${snapshot.omittedParts.join('、')}',
      if (snapshot.truncatedParts.isNotEmpty)
        '已截断${snapshot.truncatedParts.join('、')}',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: contextBudgetColor(budget).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            budget == ContextBudgetLevel.critical
                ? Icons.warning_amber_rounded
                : Icons.insights_outlined,
            size: 18,
            color: contextBudgetColor(budget),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: AppTokens.fontSizeCaption,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${budget.description} · 剩余 ${formatCompact(snapshot.remainingTokens)} tok · 预留输出 ${formatCompact(snapshot.reservedOutputTokens)} tok · $estimate',
                  style: TextStyle(
                    fontSize: AppTokens.fontSizeBadge,
                    color: muted,
                  ),
                ),
                if (changes.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    changes.join(' · '),
                    style: TextStyle(
                      fontSize: AppTokens.fontSizeBadge,
                      color: muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompressionSuggestion extends StatelessWidget {
  const _CompressionSuggestion({required this.plan, this.onCompress});

  final ContextCompressionPlan plan;
  final ValueChanged<ContextCompressionPlan>? onCompress;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppPalette.warning.withValues(alpha: 0.10),
        border: Border.all(color: AppPalette.warning.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.compress_rounded,
            size: 18,
            color: AppPalette.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '建议压缩工具结果',
                  style: TextStyle(
                    fontSize: AppTokens.fontSizeCaption,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '优先处理 ${plan.candidates.length} 项，预计释放 ${formatCompact(plan.estimatedSavings)} tok，预计剩余 ${formatCompact(plan.projectedTokens)} tok',
                  style: TextStyle(
                    fontSize: AppTokens.fontSizeBadge,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '仅提供建议，不会自动修改会话内容',
                  style: TextStyle(
                    fontSize: AppTokens.fontSizeBadge,
                    color: muted,
                  ),
                ),
                if (onCompress != null) ...[
                  const SizedBox(height: 5),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => onCompress!(plan),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text('应用建议'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TokenComposition extends StatelessWidget {
  const _TokenComposition({
    required this.metrics,
    required this.usage,
    required this.hasUsage,
  });

  final SessionMetrics metrics;
  final Usage? usage;
  final bool hasUsage;

  @override
  Widget build(BuildContext context) {
    final prompt = usage?.promptTokens ?? metrics.promptTokens;
    final output = usage?.completionTokens ?? metrics.completionTokens;
    final cached = usage?.cachedTokens ?? 0;
    final fresh = math.max(0, prompt - cached);
    final cacheKnown = usage?.cacheStatsReported ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
            icon: Icons.pie_chart_outline_rounded, label: 'Token 构成'),
        const SizedBox(height: 10),
        _TokenBar(fresh: fresh, cached: cached, output: output),
        const SizedBox(height: 12),
        _MetricRows(
          rows: [
            _MetricRowData('输入', hasUsage ? formatCompact(prompt) : '--', 'tok',
                MobileTheme.brand(context)),
            _MetricRowData('输出', hasUsage ? formatCompact(output) : '--', 'tok',
                AppPalette.danger),
            _MetricRowData('缓存命中', cacheKnown ? formatCompact(cached) : '--',
                cacheKnown ? 'tok' : '未上报', AppPalette.success),
            if ((usage?.reasoningTokens ?? 0) > 0)
              _MetricRowData('推理', formatCompact(usage!.reasoningTokens), 'tok',
                  MobileTheme.brand(context)),
            if ((usage?.cacheWriteTokens ?? 0) > 0)
              _MetricRowData(
                  'Cache write',
                  formatCompact(usage!.cacheWriteTokens),
                  'tok',
                  AppPalette.warning),
          ],
        ),
      ],
    );
  }
}

class _TimingBreakdown extends StatelessWidget {
  const _TimingBreakdown({
    required this.timing,
    required this.fallbackLlm,
    required this.fallbackTool,
    required this.showDetailedTiming,
  });

  final TimingSnapshot timing;
  final Duration fallbackLlm;
  final Duration fallbackTool;
  final bool showDetailedTiming;

  @override
  Widget build(BuildContext context) {
    final total = showDetailedTiming
        ? Duration(milliseconds: timing.wallMs)
        : fallbackLlm + fallbackTool;
    final rows = showDetailedTiming
        ? [
            _MetricRowData(
                '模型等待',
                formatDurationLabel(Duration(milliseconds: timing.modelWaitMs)),
                '${timing.modelCalls} 次',
                MobileTheme.brand(context)),
            _MetricRowData(
                '模型推理',
                formatDurationLabel(Duration(milliseconds: timing.reasoningMs)),
                '',
                MobileTheme.brand(context)),
            _MetricRowData(
                '模型输出',
                formatDurationLabel(Duration(milliseconds: timing.outputMs)),
                '',
                AppPalette.danger),
            _MetricRowData(
                '工具执行',
                formatDurationLabel(
                    Duration(milliseconds: timing.toolExecutionMs)),
                '${timing.toolCalls} 次',
                AppPalette.success),
          ]
        : [
            _MetricRowData('模型耗时', formatDurationLabel(fallbackLlm), '',
                MobileTheme.brand(context)),
            _MetricRowData('工具执行', formatDurationLabel(fallbackTool), '',
                AppPalette.success),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          icon: Icons.timer_outlined,
          label: '运行耗时',
          trailing: '运行 ${formatDurationLabel(total)}',
        ),
        const SizedBox(height: 10),
        _MetricRows(rows: rows),
      ],
    );
  }
}

class _ContextPartRow extends StatelessWidget {
  const _ContextPartRow({required this.part, required this.total});

  final ContextPart part;
  final int total;

  @override
  Widget build(BuildContext context) {
    final percent = total <= 0 ? 0 : (part.tokens / total * 100).round();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          Icon(Icons.chevron_right_rounded, size: 18, color: muted),
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: contextPartColor(part.type),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Expanded(
              child: Text(part.type.label,
                  style: const TextStyle(
                      fontSize: AppTokens.fontSizeSubhead,
                      fontWeight: FontWeight.w500))),
          Text('≈${formatCompact(part.tokens)}',
              style: const TextStyle(
                  fontSize: AppTokens.fontSizeCaption,
                  fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(width: 10),
          SizedBox(
              width: 34,
              child: Text('$percent%',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                      fontSize: AppTokens.fontSizeFootnote, color: muted))),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow(
      {required this.icon,
      required this.color,
      required this.title,
      required this.detail});

  final IconData icon;
  final Color color;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 9),
            Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: AppTokens.fontSizeSubhead,
                        fontWeight: FontWeight.w500))),
            Text(detail,
                style: TextStyle(
                    fontSize: AppTokens.fontSizeFootnote,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
}

class _EmptyTabState extends StatelessWidget {
  const _EmptyTabState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(icon,
                size: 28,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 9),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: AppTokens.fontSizeCaption,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
}

class _NetworkNode extends StatelessWidget {
  const _NetworkNode(
      {required this.ratio, required this.tokens, required this.label});

  final double ratio;
  final int tokens;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 104,
          height: 104,
          child: CustomPaint(
            painter: _NetworkRingPainter(
                brand: MobileTheme.brand(context),
                progress: ratio,
                track: Theme.of(context).colorScheme.surfaceContainerHighest),
            child: Center(
              child: Text('${(ratio * 100).round()}%',
                  style: const TextStyle(
                      fontSize: AppTokens.fontSizeSection,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ),
        const SizedBox(height: 9),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: AppTokens.fontSizeSubhead,
                fontWeight: FontWeight.w600)),
        Text('${formatCompact(tokens)} tok',
            style: TextStyle(
                fontSize: AppTokens.fontSizeFootnote,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _NetworkRingPainter extends CustomPainter {
  const _NetworkRingPainter(
      {required this.progress, required this.track, required this.brand});
  final double progress;
  final Color track;
  final Color brand;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - 14) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, paint..color = track);
    if (progress > 0) {
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false,
          paint..color = brand);
    }
  }

  @override
  bool shouldRepaint(covariant _NetworkRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.track != track ||
      oldDelegate.brand != brand;
}

bool _isFileTool(String name) => const {
      'read_file',
      'write_file',
      'edit_file',
      'list_files',
      'search_files',
      'grep',
      'glob',
    }.contains(name);

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.label, this.trailing});

  final IconData icon;
  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 17, color: muted),
        const SizedBox(width: 7),
        Text(label,
            style: const TextStyle(
                fontSize: AppTokens.fontSizeBody, fontWeight: FontWeight.w600)),
        const Spacer(),
        if (trailing != null)
          Text(trailing!,
              style: TextStyle(
                  fontSize: AppTokens.fontSizeFootnote, color: muted)),
      ],
    );
  }
}

class _TokenBar extends StatelessWidget {
  const _TokenBar(
      {required this.fresh, required this.cached, required this.output});

  final int fresh;
  final int cached;
  final int output;

  @override
  Widget build(BuildContext context) {
    final total = fresh + cached + output;
    if (total <= 0) {
      return SizedBox(
          height: 8,
          child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: Row(
          children: [
            if (fresh > 0)
              Expanded(
                  flex: fresh,
                  child: ColoredBox(color: MobileTheme.brand(context))),
            if (cached > 0)
              Expanded(
                  flex: cached,
                  child: const ColoredBox(color: Color(0xFF0F9F92))),
            if (output > 0)
              Expanded(
                  flex: output,
                  child: const ColoredBox(color: Color(0xFFDB2777))),
          ],
        ),
      ),
    );
  }
}

class _MetricRows extends StatelessWidget {
  const _MetricRows({required this.rows});

  final List<_MetricRowData> rows;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final row in rows) _MetricRow(row: row),
        ],
      );
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.row});

  final _MetricRowData row;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: row.color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Expanded(
              child: Text(row.label,
                  style: const TextStyle(fontSize: AppTokens.fontSizeCaption))),
          Text(row.value,
              style: const TextStyle(
                  fontSize: AppTokens.fontSizeCaption,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()])),
          if (row.unit.isNotEmpty) ...[
            const SizedBox(width: 5),
            Text(row.unit,
                style: TextStyle(
                    fontSize: AppTokens.fontSizeFootnote, color: muted)),
          ],
        ],
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(height: 1, color: color);
}

class _Legend extends StatelessWidget {
  const _Legend(
      {required this.color, required this.label, required this.value});
  final Color color;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: AppTokens.fontSizeBadge,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(width: 3),
          Text(value,
              style: const TextStyle(
                  fontSize: AppTokens.fontSizeBadge,
                  fontWeight: FontWeight.w500)),
        ],
      );
}

class _MetricRowData {
  const _MetricRowData(this.label, this.value, this.unit, this.color);
  final String label;
  final String value;
  final String unit;
  final Color color;
}
