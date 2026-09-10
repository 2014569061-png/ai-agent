import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/orchestration_module.dart';
import '../../application/providers.dart';
import '../../domain/collaboration_models.dart';
import '../../infrastructure/database/app_database.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../theme/app_theme.dart';
import '../widgets/nexus_metric_tile.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/nexus_section.dart';
import '../widgets/nexus_status_pill.dart';
import '../widgets/section_card.dart';

/// 协作分析时间线与决策看板 (CollaborationTimelinePage)
/// 严格依据 NEXUS UI 设计优化规范重构：
/// 1. 顶部总览卡：展示协作状态、当前轮次、Agent 数、Token 预算与消耗比。
/// 2. 待审批时顶部常驻高亮审批提示条，无需滚动页面底部。
/// 3. Agent 角色时间线：按顺序展示规划、分析、验证、审查角色的状态与摘要。
/// 4. 讨论流卡片：区分不同 Agent 角色色彩与头像标识。
/// 5. 主 Agent 决策汇总：清晰呈现共识、关键发现与分歧取舍。
class CollaborationTimelinePage extends ConsumerStatefulWidget {
  const CollaborationTimelinePage({
    super.key,
    required this.runId,
    this.initialRun,
  });

  final String runId;
  final CollaborationRunSnapshot? initialRun;

  @override
  ConsumerState<CollaborationTimelinePage> createState() =>
      _CollaborationTimelinePageState();
}

class _CollaborationTimelinePageState
    extends ConsumerState<CollaborationTimelinePage> {
  CollaborationRunSnapshot? _run;
  List<CollaborationAgentRun> _agents = const [];
  List<CollaborationArtifact> _artifacts = const [];
  List<CollaborationMessage> _messages = const [];
  StreamSubscription<CollaborationEvent>? _events;
  StreamSubscription<CollaborationRun?>? _runSubscription;
  StreamSubscription<List<CollaborationAgentRun>>? _agentSubscription;
  StreamSubscription<List<CollaborationArtifact>>? _artifactSubscription;
  Object? _error;
  bool _approving = false;

  @override
  void initState() {
    super.initState();
    _run = widget.initialRun;
    _load();
  }

  @override
  void dispose() {
    _events?.cancel();
    _runSubscription?.cancel();
    _agentSubscription?.cancel();
    _artifactSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final db = await ref.read(databaseProvider.future);
      final run = await db.findCollaborationRun(widget.runId);
      if (!mounted) return;
      setState(() {
        _run = run == null ? _run : _toSnapshot(run);
        _agents = [];
      });
      _agents = await db.agentRunsForCollaboration(widget.runId);
      _artifacts = await db.artifactsForCollaboration(widget.runId);
      _messages = await db.messagesForCollaboration(widget.runId);
      if (mounted) setState(() {});
      await _runSubscription?.cancel();
      _runSubscription = db.watchCollaborationRun(widget.runId).listen((run) {
        if (!mounted || run == null) return;
        setState(() => _run = _toSnapshot(run));
      });
      await _agentSubscription?.cancel();
      _agentSubscription = db
          .watchAgentRunsForCollaboration(widget.runId)
          .listen((rows) => mounted ? setState(() => _agents = rows) : null);
      await _artifactSubscription?.cancel();
      _artifactSubscription = db
          .watchArtifactsForCollaboration(widget.runId)
          .listen((rows) => mounted ? setState(() => _artifacts = rows) : null);
      await _events?.cancel();
      _events = ref
          .read(orchestrationModuleProvider)
          .watch(widget.runId)
          .listen((event) {
        if (!mounted) return;
        if (event is CollaborationRunEvent) setState(() => _run = event.run);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _cancel() async {
    await ref.read(orchestrationModuleProvider).cancel(widget.runId);
  }

  Future<void> _approveExecution() async {
    if (_approving) return;
    setState(() => _approving = true);
    try {
      await ref
          .read(orchestrationModuleProvider)
          .approveExecution(widget.runId);
      await _load();
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final run = _run;
    final isAwaitingApproval =
        run?.status == CollaborationStatus.awaitingExecutionApproval;
    final isRunning = run != null &&
        run.status != CollaborationStatus.completed &&
        run.status != CollaborationStatus.cancelled &&
        run.status != CollaborationStatus.failed;

    return Scaffold(
      backgroundColor: isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas,
      appBar: NexusPageHeader(
        title: '协作分析看板',
        statusPill: run != null
            ? NexusStatusPill.fromString(run.status.wireName, isCompact: true)
            : null,
        actions: [
          if (isRunning)
            IconButton(
              tooltip: '终止协作',
              icon: const Icon(Icons.stop_circle_outlined,
                  color: AppPalette.danger),
              onPressed: _cancel,
            ),
        ],
      ),
      body: _error != null
          ? Center(child: Text('加载失败：$_error'))
          : Column(
              children: [
                // 1. 等待执行审批时置顶固定提示条
                if (isAwaitingApproval)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppPalette.warning.withValues(alpha: 0.14),
                      border: const Border(
                        bottom: BorderSide(color: AppPalette.warning, width: 0.8),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_user_rounded,
                            size: 18, color: AppPalette.warning),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            '协作分析完成，已形成汇总决策，等待执行授权',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: AppPalette.warning,
                            ),
                          ),
                        ),
                        FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: _approving ? null : _approveExecution,
                          child: Text(_approving ? '确认中…' : '确认结果'),
                        ),
                      ],
                    ),
                  ),

                // 2. 主体滚动区
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                      children: [
                        // --- 一、总览看板卡 ---
                        if (run != null) _buildOverviewCard(run),

                        const SizedBox(height: 14),

                        // --- 二、各角色执行时间线 ---
                        NexusSection(
                          title: '参与角色与进度',
                          subtitle: '各子 Agent 独立分析范围与产出摘要',
                          child: _agents.isEmpty
                              ? const SectionCard(
                                  padding: EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      ),
                                      SizedBox(width: 12),
                                      Text('正在初始化子 Agent 角色…',
                                          style: TextStyle(fontSize: 13)),
                                    ],
                                  ),
                                )
                              : Column(
                                  children: _agents
                                      .map((a) => Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 8),
                                            child: _buildAgentCard(a),
                                          ))
                                      .toList(),
                                ),
                        ),

                        // --- 三、结构化产物卡 ---
                        if (_artifacts.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          NexusSection(
                            title: '分析产物清单',
                            subtitle: '已生成的代码定位、验证逻辑与风险清单',
                            child: Column(
                              children: _artifacts
                                  .map((a) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8),
                                        child: _buildArtifactCard(a),
                                      ))
                                  .toList(),
                            ),
                          ),
                        ],

                        // --- 四、讨论记录 ---
                        if (_messages.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          NexusSection(
                            title: '智能体协作讨论',
                            child: Column(
                              children: _messages
                                  .map((m) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8),
                                        child: _buildMessageCard(m),
                                      ))
                                  .toList(),
                            ),
                          ),
                        ],

                        // --- 五、主 Agent 汇总决策 ---
                        if (run?.result != null &&
                            run!.result!.summary.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          NexusSection(
                            title: '主 Agent 汇总决策',
                            child: _buildResultCard(run.result!),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildOverviewCard(CollaborationRunSnapshot run) {
    final ratio = run.budgetTokens == 0
        ? 0.0
        : (run.consumedTokens / run.budgetTokens).clamp(0.0, 1.0);
    final percent = (ratio * 100).toStringAsFixed(0);

    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${run.mode.label} · 第 ${run.currentRound}/${run.maxRounds} 轮',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '$percent% 预算占用',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: ratio > 0.8
                      ? AppPalette.danger
                      : (ratio > 0.6 ? AppPalette.warning : AppPalette.success),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
            child: LinearProgressIndicator(
              value: ratio == 0 ? 0.01 : ratio,
              minHeight: 6,
              valueColor: AlwaysStoppedAnimation<Color>(
                ratio > 0.8 ? AppPalette.danger : AppPalette.brand,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              NexusMetricTile(
                label: '已消耗 Token',
                value: NexusMetricTile.formatTokens(run.consumedTokens),
                unit: 'tok',
              ),
              NexusMetricTile(
                label: '预算上限',
                value: NexusMetricTile.formatTokens(run.budgetTokens),
                unit: 'tok',
              ),
              NexusMetricTile(
                label: '参与 Agent',
                value: '${run.maxAgents}',
                unit: '位',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAgentCard(CollaborationAgentRun agent) {
    final role = CollaborationAgentRoleX.parse(agent.role);
    final isDone = agent.status == 'completed';
    final isFailed = agent.status == 'failed';

    return SectionCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isDone
                      ? AppPalette.success.withValues(alpha: 0.12)
                      : (isFailed
                          ? AppPalette.danger.withValues(alpha: 0.12)
                          : AppPalette.brand.withValues(alpha: 0.12)),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isDone
                      ? Icons.check_circle_rounded
                      : (isFailed
                          ? Icons.error_outline_rounded
                          : Icons.smart_toy_outlined),
                  size: 16,
                  color: isDone
                      ? AppPalette.success
                      : (isFailed ? AppPalette.danger : AppPalette.brand),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  role.label,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w500),
                ),
              ),
              NexusStatusPill.fromString(agent.status, isCompact: true),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            agent.outputSummary ?? agent.failureReason ?? '正在阅读工作区执行分析…',
            style: const TextStyle(fontSize: 12.5, height: 1.35),
          ),
          const SizedBox(height: 6),
          Text(
            '输入 ${agent.inputTokens} Token · 输出 ${agent.outputTokens} Token',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArtifactCard(CollaborationArtifact artifact) {
    final payload = _decode(artifact.payloadJson);
    final confidence = ((artifact.confidence ?? 0) * 100).toStringAsFixed(0);

    return SectionCard(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: const Icon(Icons.inventory_2_outlined, size: 20),
        title: Text(artifact.type,
            style:
                const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
        subtitle: Text('置信度：$confidence%',
            style:
                const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(payload),
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageCard(CollaborationMessage message) {
    final isSynthesizer =
        message.senderAgentRunId == '${widget.runId}:synthesizer';
    return SectionCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isSynthesizer
                    ? Icons.auto_awesome_rounded
                    : Icons.forum_outlined,
                size: 15,
                color: isSynthesizer
                    ? AppPalette.brand
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                isSynthesizer
                    ? '主 Agent 汇总发言'
                    : (message.senderAgentRunId ?? '智能体消息'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            message.content,
            style: const TextStyle(fontSize: 13, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(CollaborationResult result) {
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            result.summary,
            style: const TextStyle(fontSize: 13.5, height: 1.4),
          ),
          if (result.findings.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('关键发现',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            ...result.findings.map((f) => Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ',
                          style: TextStyle(fontWeight: FontWeight.w500)),
                      Expanded(
                          child: SelectableText(
                              f.detail.isEmpty
                                  ? f.title
                                  : '${f.title}：${f.detail}',
                              style: const TextStyle(fontSize: 12.5))),
                    ],
                  ),
                )),
          ],
          if (result.disagreements.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('分歧与权衡取舍',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppPalette.warning)),
            const SizedBox(height: 4),
            ...result.disagreements.map((d) => Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ',
                          style: TextStyle(fontWeight: FontWeight.w500)),
                      Expanded(
                          child: SelectableText(d,
                              style: const TextStyle(fontSize: 12.5))),
                    ],
                  ),
                )),
          ],
          if (result.risks.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('风险与证据缺口',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppPalette.warning)),
            const SizedBox(height: 4),
            ...result.risks.map((risk) => Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ',
                          style: TextStyle(fontWeight: FontWeight.w500)),
                      Expanded(
                          child: SelectableText(risk,
                              style: const TextStyle(fontSize: 12.5))),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Map<String, dynamic> _decode(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    } catch (_) {
      return const {};
    }
  }

  CollaborationRunSnapshot _toSnapshot(CollaborationRun run) =>
      CollaborationRunSnapshot(
        id: run.id,
        taskId: run.taskId,
        mode: CollaborationModeX.parse(run.mode),
        status: CollaborationStatusX.parse(run.status),
        budgetTokens: run.budgetTokens,
        consumedTokens: run.consumedTokens,
        maxAgents: run.maxAgents,
        maxRounds: run.maxRounds,
        currentRound: run.currentRound,
        createdAt: run.createdAt,
        updatedAt: run.updatedAt,
        plan: CollaborationPlan.decode(run.planJson),
        result: CollaborationResult.decode(run.resultJson),
        error: run.error,
      );
}
