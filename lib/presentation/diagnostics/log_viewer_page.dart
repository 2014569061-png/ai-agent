import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/files/conversation_exporter.dart';
import '../theme/app_tokens.dart';
import '../widgets/async_state_view.dart';
import '../widgets/confirm_action.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_page_header.dart';

class LogViewerPage extends ConsumerStatefulWidget {
  const LogViewerPage({super.key, this.runId});

  final String? runId;

  @override
  ConsumerState<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends ConsumerState<LogViewerPage> {
  static const _pageSize = 200;
  final TextEditingController _keywordController = TextEditingController();
  List<LogRecord> _logs = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;
  String? _level;
  String? _category;
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = true}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final db = await ref.read(databaseProvider.future);
      final logs = await db.recentLogRecords(
        limit: _pageSize,
        offset: reset ? 0 : _logs.length,
        runId: widget.runId,
        level: _level,
        category: _category,
        keyword: _keywordController.text,
        from: _from,
        to: _to,
      );
      if (!mounted) return;
      setState(() {
        _logs = reset ? logs : [..._logs, ...logs];
        _hasMore = logs.length == _pageSize;
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

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      await _load(reset: false);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  String _exportText() => _logs.map((log) {
        final detail = log.detailJson == null ? '' : ' ${log.detailJson}';
        return '[${log.createdAt.toLocal().toIso8601String()}] '
            '${log.level.toUpperCase()} [${log.category}] ${log.message}'
            '${log.errorCode == null ? '' : ' (${log.errorCode})'}$detail';
      }).join('\n');

  String _exportJson() => const JsonEncoder.withIndent('  ').convert({
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'runId': widget.runId,
        'filters': {
          'level': _level,
          'category': _category,
          'keyword': _keywordController.text,
          'from': _from?.toIso8601String(),
          'to': _to?.toIso8601String(),
        },
        'logs': _logs
            .map((log) => {
                  'logId': log.logId,
                  'runId': log.runId,
                  'eventId': log.eventId,
                  'level': log.level,
                  'category': log.category,
                  'message': log.message,
                  'detail': _decodeDetail(log.detailJson),
                  'errorCode': log.errorCode,
                  'createdAt': log.createdAt.toIso8601String(),
                  'retryable': log.retryable,
                })
            .toList(),
      });

  dynamic _decodeDetail(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }

  Future<void> _openFilters() async {
    var level = _level;
    var category = _category;
    var from = _from;
    var to = _to;
    final keyword = TextEditingController(text: _keywordController.text);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('筛选日志', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: keyword,
                decoration: const InputDecoration(
                    labelText: '关键词', prefixIcon: Icon(Icons.search)),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: level,
                decoration: const InputDecoration(labelText: '级别'),
                items: const [
                  DropdownMenuItem<String?>(value: null, child: Text('全部级别')),
                  DropdownMenuItem(value: 'error', child: Text('错误')),
                  DropdownMenuItem(value: 'warning', child: Text('警告')),
                  DropdownMenuItem(value: 'info', child: Text('信息')),
                ],
                onChanged: (value) => setSheetState(() => level = value),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: category,
                decoration: const InputDecoration(labelText: '分类'),
                items: const [
                  DropdownMenuItem<String?>(value: null, child: Text('全部分类')),
                  DropdownMenuItem(value: 'model', child: Text('模型')),
                  DropdownMenuItem(value: 'tool', child: Text('工具')),
                  DropdownMenuItem(value: 'file', child: Text('文件')),
                  DropdownMenuItem(value: 'cache', child: Text('缓存')),
                  DropdownMenuItem(value: 'network', child: Text('网络')),
                  DropdownMenuItem(value: 'system', child: Text('系统')),
                ],
                onChanged: (value) => setSheetState(() => category = value),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.date_range_outlined),
                      label: Text(from == null ? '开始日期' : _date(from!)),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          initialDate: from ?? DateTime.now(),
                        );
                        if (picked != null) setSheetState(() => from = picked);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event_outlined),
                      label: Text(to == null ? '结束日期' : _date(to!)),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          initialDate: to ?? DateTime.now(),
                        );
                        if (picked != null) setSheetState(() => to = picked);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  _level = level;
                  _category = category;
                  _from = from;
                  _to = to == null
                      ? null
                      : DateTime(to!.year, to!.month, to!.day + 1);
                  _keywordController.text = keyword.text;
                  Navigator.pop(context);
                },
                child: const Text('应用筛选'),
              ),
            ],
          ),
        ),
      ),
    );
    keyword.dispose();
    if (mounted) await _load();
  }

  String _date(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<void> _clear() async {
    final confirmed = await showConfirmAction(
      context,
      title: '清理诊断日志',
      message: '将删除本设备上的全部运行日志，无法恢复。',
      confirmLabel: '清理',
      isDanger: true,
    );
    if (!confirmed) return;
    final db = await ref.read(databaseProvider.future);
    await db.clearLogRecords();
    await _load();
  }

  Future<void> _export() async {
    final path = await exportConversationJson(
        widget.runId == null ? 'diagnostic-logs' : 'run-${widget.runId}',
        _exportJson());
    if (!mounted) return;
    FloatingToast.show(context, path.isEmpty ? '当前平台不支持文件导出' : '诊断包已导出：$path');
  }

  Color _levelColor(BuildContext context, String level) {
    final scheme = Theme.of(context).colorScheme;
    return switch (level) {
      'error' => scheme.error,
      'warning' => Colors.orange.shade700,
      _ => scheme.primary,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: NexusPageHeader(
        title: widget.runId == null ? '诊断日志' : '任务日志',
        subtitle: widget.runId == null ? '运行追踪与错误排查' : 'Run: ${widget.runId}',
        actions: [
          IconButton(
            tooltip: '筛选日志',
            constraints: const BoxConstraints(
              minWidth: AppTokens.kMinTouchTarget,
              minHeight: AppTokens.kMinTouchTarget,
            ),
            icon: const Icon(Icons.filter_alt_outlined),
            onPressed: _openFilters,
          ),
          IconButton(
            tooltip: '复制日志',
            constraints: const BoxConstraints(
              minWidth: AppTokens.kMinTouchTarget,
              minHeight: AppTokens.kMinTouchTarget,
            ),
            icon: const Icon(Icons.copy_outlined),
            onPressed: _logs.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: _exportText()));
                    if (!context.mounted) return;
                    FloatingToast.show(context, '日志已复制');
                  },
          ),
          IconButton(
            tooltip: '导出诊断包',
            constraints: const BoxConstraints(
              minWidth: AppTokens.kMinTouchTarget,
              minHeight: AppTokens.kMinTouchTarget,
            ),
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _logs.isEmpty ? null : _export,
          ),
          IconButton(
            tooltip: '清理日志',
            constraints: const BoxConstraints(
              minWidth: AppTokens.kMinTouchTarget,
              minHeight: AppTokens.kMinTouchTarget,
            ),
            icon: const Icon(Icons.delete_outline),
            onPressed: _clear,
          ),
        ],
      ),
      body: AsyncStateView(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: _logs.isEmpty
            ? const EmptyStateView(
                icon: Icons.receipt_long_outlined,
                title: '暂无诊断日志',
                message: '模型、工具和文件操作发生异常后，日志会显示在这里。')
            : NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.metrics.extentAfter < 320) {
                    _loadMore();
                  }
                  return false;
                },
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _logs.length + (_loadingMore ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      if (index >= _logs.length) {
                        return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()));
                      }
                      final log = _logs[index];
                      final detail = _decodeDetail(log.detailJson)?.toString();
                      return Card(
                        child: ExpansionTile(
                          leading: Icon(Icons.circle,
                              size: 11, color: _levelColor(context, log.level)),
                          title: Text(log.message),
                          subtitle: Text(
                            '${log.level.toUpperCase()} · ${log.category} · '
                            '${log.createdAt.toLocal().toString().substring(0, 19)}',
                          ),
                          children: [
                            if (log.errorCode != null)
                              ListTile(
                                  title: const Text('错误码'),
                                  subtitle: Text(log.errorCode!)),
                            if (log.runId != null)
                              ListTile(
                                  title: const Text('运行 ID'),
                                  subtitle: Text(log.runId!)),
                            if (detail != null)
                              ListTile(
                                  title: const Text('详细信息'),
                                  subtitle: SelectableText(detail)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
      ),
    );
  }
}
