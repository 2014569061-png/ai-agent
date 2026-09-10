import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/chat_controller.dart';
import '../../application/run_audit_report.dart';
import '../../application/providers.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/files/conversation_exporter.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../markdown/markdown_render_metrics.dart';
import '../widgets/async_state_view.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/nexus_metric_tile.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/nexus_section.dart';
import '../widgets/nexus_status_pill.dart';
import '../widgets/section_card.dart';
import 'log_viewer_page.dart';

/// 运行分析与 Token 可观测性页面 (RunAnalysisPage)
/// 严格依据 NEXUS UI 设计优化规范重构：
/// 1. 拆分“当前运行”与“历史记录”双 Tab 视图。
/// 2. 第一屏聚焦 4 大核心指标：输入 Token、输出 Token、缓存 Token、缓存命中率，并提供通俗解释。
/// 3. 第二层展示首字节时间 (TTFT)、总耗时、工具调用、重试与费用。
/// 4. 历史运行支持按成功/失败状态与模型筛选。
class RunAnalysisPage extends ConsumerStatefulWidget {
  const RunAnalysisPage({super.key});

  @override
  ConsumerState<RunAnalysisPage> createState() => _RunAnalysisPageState();
}

class _RunAnalysisPageState extends ConsumerState<RunAnalysisPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<RunRecord> _runs = const [];
  String _historyFilter = 'all';
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = await ref.read(databaseProvider.future);
      final runs = await db.recentRuns();
      if (!mounted) return;
      setState(() {
        _runs = runs;
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

  List<RunRecord> get _filteredRuns {
    if (_historyFilter == 'all') return _runs;
    if (_historyFilter == 'success') {
      return _runs.where((r) => r.status == 'success').toList();
    }
    if (_historyFilter == 'failed') {
      return _runs.where((r) => r.status == 'failed').toList();
    }
    return _runs;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatState = ref.watch(chatControllerProvider);

    return Scaffold(
      backgroundColor: isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas,
      appBar: NexusPageHeader(
        title: '运行分析与观测',
        bottom: TabBar(
          controller: _tabController,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: const [
            Tab(text: '当前运行监控'),
            Tab(text: '历史执行报告'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '全部诊断日志',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LogViewerPage()),
            ),
          ),
          IconButton(
            tooltip: '刷新数据',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: AsyncStateView(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: TabBarView(
          controller: _tabController,
          children: [
            // Tab 1: 当前运行与实时观测
            _buildCurrentRunView(chatState),

            // Tab 2: 历史报告列表与筛选
            _buildHistoryRunsView(),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // Tab 1: 当前会话/运行实时观测
  // ==========================================================
  Widget _buildCurrentRunView(ChatState chatState) {
    final theme = Theme.of(context);

    // 计算当前会话的累积指标
    final inputTokens = chatState.messages.fold<int>(
      0,
      (acc, m) => acc + (m.usage?.promptTokens ?? 0),
    );
    final outputTokens = chatState.messages.fold<int>(
      0,
      (acc, m) => acc + (m.usage?.completionTokens ?? 0),
    );
    final cachedTokens = chatState.messages.fold<int>(
      0,
      (acc, m) => acc + (m.usage?.cachedTokens ?? 0),
    );
    final totalTokens = inputTokens + outputTokens;
    final cacheHitRate =
        inputTokens == 0 ? 0.0 : (cachedTokens / inputTokens).clamp(0.0, 1.0);
    final cacheHitPercent = (cacheHitRate * 100).toStringAsFixed(1);

    final latestUsage = chatState.messages.reversed
        .where((m) => m.usage != null)
        .map((m) => m.usage!)
        .firstOrNull;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // 运行状态卡
        SectionCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              NexusStatusPill(
                status: chatState.running
                    ? NexusStatusType.running
                    : NexusStatusType.completed,
                customLabel: chatState.running ? 'Agent 正在执行' : '就绪等待指令',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  chatState.activeModel.isNotEmpty
                      ? '当前模型：${chatState.activeModel}'
                      : '服务商：${chatState.activeProviderName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // --- 第一屏：4 大核心指标 ---
        NexusSection(
          title: '会话 Token 核心指标',
          subtitle: '点击问号可查看各指标含义与优化建议',
          child: GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.1,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              NexusMetricTile(
                label: '输入 Token',
                value: NexusMetricTile.formatTokens(inputTokens),
                unit: 'tok',
                icon: Icons.input_rounded,
                color: theme.colorScheme.primary,
                explanation: '模型接收上下文、历史消息与系统提示词消耗的 Token 总量。',
              ),
              NexusMetricTile(
                label: '输出 Token',
                value: NexusMetricTile.formatTokens(outputTokens),
                unit: 'tok',
                icon: Icons.output_rounded,
                color: AppPalette.brand,
                explanation: '模型思考过程与最终输出文本所生成的 Token 总量。',
              ),
              NexusMetricTile(
                label: '缓存 Token',
                value: NexusMetricTile.formatTokens(cachedTokens),
                unit: 'tok',
                icon: Icons.cached_rounded,
                color: AppPalette.success,
                explanation: '服务商 Prompt Cache 命中的 Token，享受折扣且大幅降低延迟。',
              ),
              NexusMetricTile(
                label: '缓存命中率',
                value: '$cacheHitPercent%',
                icon: Icons.pie_chart_outline_rounded,
                color: cacheHitRate > 0.3 ? AppPalette.success : null,
                explanation: '缓存 Token 占总输入 Token 的比例，越高代表上下文复用越好。',
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // --- 第二层：辅助指标与上下文水位 ---
        NexusSection(
          title: '上下文水位与单轮开销',
          child: SectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('上下文占用率',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: theme.colorScheme.onSurfaceVariant)),
                    Text(
                      '${NexusMetricTile.formatTokens(chatState.liveContextTokens > 0 ? chatState.liveContextTokens : totalTokens)} / ${NexusMetricTile.formatTokens(chatState.contextTokens)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                  child: LinearProgressIndicator(
                    value: chatState.contextTokens <= 0
                        ? 0.01
                        : ((chatState.liveContextTokens > 0
                                    ? chatState.liveContextTokens
                                    : totalTokens) /
                                chatState.contextTokens)
                            .clamp(0.01, 1.0),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    NexusMetricTile(
                      label: '最近轮次输入',
                      value: latestUsage != null
                          ? '${latestUsage.promptTokens}'
                          : '暂无',
                      unit: latestUsage != null ? 'tok' : null,
                    ),
                    NexusMetricTile(
                      label: '最近轮次输出',
                      value: latestUsage != null
                          ? '${latestUsage.completionTokens}'
                          : '暂无',
                      unit: latestUsage != null ? 'tok' : null,
                    ),
                    NexusMetricTile(
                      label: '工具活动记录',
                      value: '${chatState.toolActivities.length}',
                      unit: '次',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // 最新完成的一次运行详情快捷入口
        if (_runs.isNotEmpty) ...[
          const SizedBox(height: 14),
          NexusSection(
            title: '最近一次完成的 Agent 执行',
            trailing: TextButton(
              onPressed: () => _tabController.animateTo(1),
              child: const Text('查看全部 >', style: TextStyle(fontSize: 12)),
            ),
            child: _buildRunTile(_runs.first),
          ),
        ],
      ],
    );
  }

  // ==========================================================
  // Tab 2: 历史报告列表
  // ==========================================================
  Widget _buildHistoryRunsView() {
    final runs = _filteredRuns;

    return Column(
      children: [
        // 筛选 ChoiceChip
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            children: [
              _filterChip('all', '全部 (${_runs.length})'),
              const SizedBox(width: 8),
              _filterChip('success',
                  '成功 (${_runs.where((r) => r.status == 'success').length})'),
              const SizedBox(width: 8),
              _filterChip('failed',
                  '失败 (${_runs.where((r) => r.status == 'failed').length})'),
            ],
          ),
        ),

        Expanded(
          child: runs.isEmpty
              ? const EmptyStateView(
                  icon: Icons.timeline_outlined,
                  title: '暂无运行报告',
                  message: '完成任务后，这里会沉淀执行耗时、首字节响应与每一步的执行日志。',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: runs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _buildRunTile(runs[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _filterChip(String key, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _historyFilter == key,
      onSelected: (_) => setState(() => _historyFilter = key),
    );
  }

  Widget _buildRunTile(RunRecord run) {
    final total = run.inputTokens + run.outputTokens;
    final isFailed = run.status == 'failed';
    final hitRate = run.inputTokens == 0
        ? '0%'
        : '${(run.cachedTokens / run.inputTokens * 100).toStringAsFixed(0)}%';

    return SectionCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Icon(
          isFailed
              ? Icons.error_outline_rounded
              : Icons.check_circle_outline_rounded,
          color: isFailed ? AppPalette.danger : AppPalette.success,
        ),
        title: Text(
          run.model,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
        subtitle: Text(
          '${run.startedAt.toLocal().toString().substring(0, 16)} · '
          '${NexusMetricTile.formatTokens(total)} Token · 命中 $hitRate'
          '${run.totalDurationMs != null ? ' · ${NexusMetricTile.formatDuration(run.totalDurationMs)}' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, size: 18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RunDetailPage(run: run)),
        ),
      ),
    );
  }
}

/// 运行详情独立页面 (RunDetailPage)
class RunDetailPage extends ConsumerStatefulWidget {
  const RunDetailPage({super.key, required this.run});

  final RunRecord run;

  @override
  ConsumerState<RunDetailPage> createState() => _RunDetailPageState();
}

class _RunDetailPageState extends ConsumerState<RunDetailPage> {
  static const _pageSize = 50;
  final ScrollController _scrollController = ScrollController();
  late RunRecord _run;
  List<RunEvent> _events = const [];
  StreamSubscription<List<RunEvent>>? _eventSubscription;
  StreamSubscription<RunRecord?>? _runSubscription;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _run = widget.run;
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _runSubscription?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 320) unawaited(_loadMore());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = await ref.read(databaseProvider.future);
      final events = await db.eventsForRun(widget.run.runId, limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _events = events;
        _hasMore = events.length == _pageSize;
        _loading = false;
      });
      await _eventSubscription?.cancel();
      _eventSubscription = db
          .watchEventsForRun(widget.run.runId, limit: _pageSize)
          .listen(_mergeLiveEvents);
      await _runSubscription?.cancel();
      _runSubscription = db.watchRunRecord(widget.run.runId).listen((run) {
        if (!mounted || run == null) return;
        setState(() => _run = run);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _mergeLiveEvents(List<RunEvent> incoming) {
    if (!mounted || incoming.isEmpty) return;
    final byId = <String, RunEvent>{
      for (final event in _events) event.eventId: event
    };
    for (final event in incoming) {
      byId[event.eventId] = event;
    }
    final merged = byId.values.toList()
      ..sort((a, b) => a.sequenceNo.compareTo(b.sequenceNo));
    setState(() => _events = merged);
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    _loadingMore = true;
    try {
      final db = await ref.read(databaseProvider.future);
      final page = await db.eventsForRun(widget.run.runId,
          limit: _pageSize, offset: _events.length);
      if (!mounted) return;
      final byId = <String, RunEvent>{
        for (final event in _events) event.eventId: event
      };
      for (final event in page) {
        byId[event.eventId] = event;
      }
      final merged = byId.values.toList()
        ..sort((a, b) => a.sequenceNo.compareTo(b.sequenceNo));
      setState(() {
        _events = merged;
        _hasMore = page.length == _pageSize;
      });
    } finally {
      _loadingMore = false;
    }
  }

  Map<String, dynamic> _metadata(RunEvent event) {
    try {
      final decoded = jsonDecode(event.metadataJson);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    } catch (_) {
      return const {};
    }
  }

  String _eventSubtitle(RunEvent event) {
    final data = _metadata(event);
    final path = data['path'] ?? data['filePath'];
    final operation = data['operation'];
    if (path != null || operation != null) {
      return '${operation ?? '文件操作'} · ${path ?? '未知文件'}';
    }
    if (data['cacheSource'] != null) {
      return '缓存来源：${data['cacheSource']} · 节省 ${data['savedTokens'] ?? 0} Token';
    }
    if (event.outputSummary?.isNotEmpty == true) return event.outputSummary!;
    return event.status;
  }

  int? _savedCostCents() {
    int? saved;
    for (final event in _events) {
      final value = _metadata(event)['savedCostCents'];
      if (value is num) saved = value.toInt();
    }
    return saved;
  }

  RunAuditReport get _auditReport => RunAuditReport.fromEvents(_events);

  Map<String, dynamic> _reportMap() => {
        'run': {
          'runId': _run.runId,
          'conversationId': _run.conversationId,
          'model': _run.model,
          'status': _run.status,
          'startedAt': _run.startedAt.toIso8601String(),
          'endedAt': _run.endedAt?.toIso8601String(),
          'durationMs': _run.totalDurationMs,
          'firstTokenDurationMs': _run.firstTokenDurationMs,
          'outputRateTokensPerSecond': _run.outputRateMilli == null
              ? null
              : _run.outputRateMilli! / 1000,
          'maxStallDurationMs': _run.maxStallDurationMs ?? 0,
          'stallCount': _run.stallCount ?? 0,
          'cancelDurationMs': _run.cancelDurationMs,
          'promptTokens': _run.inputTokens,
          'completionTokens': _run.outputTokens,
          'cachedTokens': _run.cachedTokens,
          'estimatedCostCents': _run.estimatedCostCents,
          'estimatedSavedCostCents': _savedCostCents(),
          'retryCount': _run.retryCount,
        },
        'audit': _auditReport.toJson(),
        'rendering': _renderingReport(),
        'events': _events
            .map((event) => {
                  'eventId': event.eventId,
                  'sequence': event.sequenceNo,
                  'type': event.type,
                  'status': event.status,
                  'name': event.name,
                  'startedAt': event.startedAt.toIso8601String(),
                  'endedAt': event.endedAt?.toIso8601String(),
                  'durationMs': event.durationMs,
                  'inputSummary': event.inputSummary,
                  'outputSummary': event.outputSummary,
                  'metadata': _metadata(event),
                })
            .toList(),
      };

  Map<String, dynamic> _renderingReport() {
    final metrics = MarkdownRenderMetrics.instance;
    return {
      'markdownRenderCount': metrics.markdownRenderCount,
      'averageMarkdownMs': metrics.averageMarkdownMs,
      'codeBlockCount': metrics.codeBlockCount,
      'highlightedCodeBlockCount': metrics.highlightedCodeBlockCount,
      'averageHighlightMs': metrics.averageHighlightMs,
      'longCodeFallbackCount': metrics.longCodeFallbackCount,
    };
  }

  String _reportJson() =>
      const JsonEncoder.withIndent('  ').convert(_reportMap());

  String _reportMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Agent 运行报告')
      ..writeln()
      ..writeln('- 状态：${_run.status}')
      ..writeln('- 模型：${_run.model}')
      ..writeln('- 总耗时：${_run.totalDurationMs ?? '暂无数据'} ms')
      ..writeln('- 首字节：${_run.firstTokenDurationMs ?? '暂无数据'} ms')
      ..writeln('- 输出速率：${_formatRate()} Token/s')
      ..writeln(
          '- 最大停顿：${_run.maxStallDurationMs ?? 0} ms（${_run.stallCount ?? 0} 次）')
      ..writeln('- 取消耗时：${_run.cancelDurationMs ?? '暂无数据'} ms')
      ..writeln('- 输入 Token：${_run.inputTokens}')
      ..writeln('- 输出 Token：${_run.outputTokens}')
      ..writeln('- 缓存 Token：${_run.cachedTokens}')
      ..writeln('- 预计费用：${_run.estimatedCostCents ?? '暂无数据'} 分')
      ..writeln('- 缓存节省：${_savedCostCents() ?? '暂无数据'} 分')
      ..writeln()
      ..writeln('## 执行时间线');
    for (final event in _events) {
      buffer.writeln(
          '- ${event.sequenceNo}. ${event.name} [${event.status}] ${_eventSubtitle(event)} (${event.durationMs ?? '未知'} ms)');
    }
    return buffer.toString();
  }

  String _formatRate() => _run.outputRateMilli == null
      ? '暂无数据'
      : (_run.outputRateMilli! / 1000).toStringAsFixed(1);

  Future<void> _export(bool json) async {
    final path = await (json
        ? exportConversationJson('agent-run-${_run.runId}', _reportJson())
        : exportConversationMarkdown(
            'agent-run-${_run.runId}', _reportMarkdown()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(path.isEmpty ? '当前平台不支持文件导出' : '报告已导出：$path')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = _run.inputTokens + _run.outputTokens;
    final cacheRate = _run.inputTokens == 0
        ? '暂无数据'
        : '${(_run.cachedTokens / _run.inputTokens * 100).toStringAsFixed(1)}%';
    final savedCost = _savedCostCents();
    return Scaffold(
      backgroundColor: isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas,
      appBar: AppBar(
        title: const Text('任务详情'),
        actions: [
          IconButton(
            tooltip: '复制运行报告',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: _events.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(
                        ClipboardData(text: _reportMarkdown()));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('运行报告已复制')));
                  },
          ),
          PopupMenuButton<String>(
            tooltip: '导出运行报告',
            onSelected: (value) => _export(value == 'json'),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'markdown', child: Text('导出 Markdown')),
              PopupMenuItem(value: 'json', child: Text('导出 JSON')),
            ],
          ),
          IconButton(
            tooltip: '查看任务日志',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => LogViewerPage(runId: _run.runId))),
          ),
        ],
      ),
      body: AsyncStateView(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 20,
                    runSpacing: 14,
                    children: [
                      _metric('状态', _run.status),
                      _metric('总 Token', '$total'),
                      _metric('输入 Token', '${_run.inputTokens}'),
                      _metric('输出 Token', '${_run.outputTokens}'),
                      _metric(
                          '缓存 Token',
                          _run.cachedTokens == 0
                              ? '暂无数据'
                              : '${_run.cachedTokens}'),
                      _metric('缓存命中率', cacheRate),
                      _metric(
                          '预计费用',
                          _run.estimatedCostCents == null
                              ? '暂无数据'
                              : '${_run.estimatedCostCents} 分'),
                      _metric(
                          '缓存节省', savedCost == null ? '暂无数据' : '$savedCost 分'),
                      _metric(
                          '总耗时',
                          _run.totalDurationMs == null
                              ? '暂无数据'
                              : '${_run.totalDurationMs} ms'),
                      _metric(
                          '首字节',
                          _run.firstTokenDurationMs == null
                              ? '暂无数据'
                              : '${_run.firstTokenDurationMs} ms'),
                      _metric('输出速率', '${_formatRate()} Token/s'),
                      _metric('最大停顿', '${_run.maxStallDurationMs ?? 0} ms'),
                      _metric('停顿次数', '${_run.stallCount ?? 0}'),
                      _metric(
                          '取消耗时',
                          _run.cancelDurationMs == null
                              ? '暂无数据'
                              : '${_run.cancelDurationMs} ms'),
                      _metric('重试次数', '${_run.retryCount}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _buildAuditSection(),
              const SizedBox(height: 18),
              Text('执行时间线', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (_events.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('暂无事件详情')),
                )
              else
                ..._events.map((event) => Card(
                      child: ExpansionTile(
                        leading: Icon(
                          event.status == 'failed'
                              ? Icons.error_outline
                              : event.type == 'tool_call' ||
                                      event.type == 'file_operation'
                                  ? Icons.build_outlined
                                  : event.type == 'cache'
                                      ? Icons.cached_outlined
                                      : Icons.circle_outlined,
                          color: event.status == 'failed'
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                        ),
                        title: Text('${event.sequenceNo}. ${event.name}'),
                        subtitle: Text(_eventSubtitle(event)),
                        trailing: event.durationMs == null
                            ? null
                            : Text('${event.durationMs} ms'),
                        children: [
                          _EventMetadataView(data: _metadata(event)),
                          if (event.outputSummary?.isNotEmpty == true)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: SelectableText(event.outputSummary!),
                            ),
                        ],
                      ),
                    )),
              if (_loadingMore)
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator())),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metric(String label, String value) => SizedBox(
        width: 110,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      );

  Widget _buildAuditSection() {
    final report = _auditReport;
    if (report.entries.isEmpty) {
      return const SectionCard(
        child: ListTile(
          leading: Icon(Icons.verified_user_outlined),
          title: Text('副作用审计'),
          subtitle: Text('本次运行没有记录到文件、终端或设备副作用。'),
        ),
      );
    }
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined, size: 18),
              const SizedBox(width: 8),
              Text('副作用审计（${report.entries.length} 次）',
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _export(true),
                icon: const Icon(Icons.data_object, size: 16),
                label: const Text('JSON'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...report.entries.map((entry) {
            final color = switch (entry.effect) {
              'applied' => AppPalette.success,
              'unknown' => AppPalette.warning,
              _ => Theme.of(context).colorScheme.onSurfaceVariant,
            };
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                entry.effect == 'applied'
                    ? Icons.check_circle_outline
                    : entry.effect == 'unknown'
                        ? Icons.help_outline
                        : Icons.remove_circle_outline,
                color: color,
                size: 19,
              ),
              title: Text('${entry.tool} · effect=${entry.effect}'),
              subtitle: Text(
                [
                  if (entry.path != null) entry.path!,
                  if (entry.code.isNotEmpty) entry.code,
                  if (entry.evidence != null && entry.evidence!.isNotEmpty)
                    entry.evidence!,
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _EventMetadataView extends StatelessWidget {
  const _EventMetadataView({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    final diff = data['diff']?.toString();
    final entries = data.entries
        .where((entry) => entry.key != 'diff')
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('\n');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entries.isNotEmpty) SelectableText(entries),
          if (diff != null && diff.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Diff', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                diff,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
