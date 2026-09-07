import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/files/conversation_exporter.dart';
import '../widgets/async_state_view.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/section_card.dart';
import 'log_viewer_page.dart';

class RunAnalysisPage extends ConsumerStatefulWidget {
  const RunAnalysisPage({super.key});

  @override
  ConsumerState<RunAnalysisPage> createState() => _RunAnalysisPageState();
}

class _RunAnalysisPageState extends ConsumerState<RunAnalysisPage> {
  List<RunRecord> _runs = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
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

  String _tokens(RunRecord run) =>
      '${run.inputTokens + run.outputTokens} Token · 缓存 ${run.cachedTokens}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('运行分析'),
        actions: [
          IconButton(
            tooltip: '查看全部日志',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LogViewerPage()),
            ),
          ),
        ],
      ),
      body: AsyncStateView(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: _runs.isEmpty
            ? const EmptyStateView(
                icon: Icons.timeline_outlined,
                title: '暂无运行记录',
                message: '完成一次 Agent 任务后，这里会显示执行步骤和资源消耗。')
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _runs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final run = _runs[index];
                    return SectionCard(
                      child: ListTile(
                        leading: Icon(
                          run.status == 'success'
                              ? Icons.check_circle_outline
                              : run.status == 'failed'
                                  ? Icons.error_outline
                                  : Icons.timelapse_outlined,
                          color: run.status == 'failed'
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(run.model),
                        subtitle: Text(
                          '${run.startedAt.toLocal().toString().substring(0, 19)}\n'
                          '${run.status} · ${run.eventCount} 个步骤 · ${_tokens(run)}',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => RunDetailPage(run: run)),
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

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
          'promptTokens': _run.inputTokens,
          'completionTokens': _run.outputTokens,
          'cachedTokens': _run.cachedTokens,
          'estimatedCostCents': _run.estimatedCostCents,
          'estimatedSavedCostCents': _savedCostCents(),
          'retryCount': _run.retryCount,
        },
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
    final total = _run.inputTokens + _run.outputTokens;
    final cacheRate = _run.inputTokens == 0
        ? '暂无数据'
        : '${(_run.cachedTokens / _run.inputTokens * 100).toStringAsFixed(1)}%';
    final savedCost = _savedCostCents();
    return Scaffold(
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
                      _metric('重试次数', '${_run.retryCount}'),
                    ],
                  ),
                ),
              ),
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
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
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
            const Text('Diff', style: TextStyle(fontWeight: FontWeight.w700)),
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
