import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/billing_api.dart';
import '../../application/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/immersive_list_tile.dart';
import '../widgets/section_card.dart';
import '../widgets/section_header.dart';
import 'usage_trend.dart';

class UsageReportPage extends ConsumerStatefulWidget {
  const UsageReportPage({super.key});

  @override
  ConsumerState<UsageReportPage> createState() => _UsageReportPageState();
}

class _UsageReportPageState extends ConsumerState<UsageReportPage> {
  UsageReport? _report;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final account = await ref.read(accountServiceProvider).restoreSession();
      if (account == null) {
        if (mounted) setState(() => _report = const UsageReport());
        return;
      }
      final report =
          await ref.read(billingApiProvider).usage(access: account.access);
      if (mounted) setState(() => _report = report);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Token 用量报告')),
        body: RefreshIndicator(onRefresh: _load, child: _body()),
      );

  Widget _body() {
    if (_error != null) {
      return ListView(children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            const Text('用量数据加载失败'),
            TextButton(onPressed: _load, child: const Text('重新加载')),
          ]),
        ),
      ]);
    }
    if (_report == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_report!.isEmpty) {
      return const EmptyStateView(
        icon: Icons.data_usage_outlined,
        title: '暂无 Token 用量',
        message: '完成一次模型对话后，这里会显示用量统计。',
      );
    }
    final report = _report!;
    final summary = report.summary;
    final theme = Theme.of(context);
    final colors = AppTheme.semanticOf(context);
    final cacheRate = summary['cache_hit_rate'] as num?;
    final saved = summary['estimated_saved_cents'] as num?;
    final cacheSources = (summary['cache_sources'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);

    return ListView(padding: const EdgeInsets.all(16), children: [
      SectionCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(spacing: 24, runSpacing: 16, children: [
            _item(context, '请求次数', summary['calls']),
            _item(context, '总 Token',
                summary['total_tokens'] ?? _totalTokens(summary)),
            _item(context, '输入 Token', summary['prompt_tokens']),
            _item(context, '输出 Token', summary['completion_tokens']),
            _item(context, '缓存 Token', summary['cached_tokens']),
            _item(
                context,
                '缓存命中率',
                cacheRate == null
                    ? '暂无数据'
                    : '${(cacheRate * 100).toStringAsFixed(1)}%'),
            _item(context, '节省 Token', summary['cached_tokens']),
            _item(
                context, '节省费用', saved == null ? '暂无数据' : '${saved.toInt()} 分'),
          ]),
        ),
      ),
      const SizedBox(height: 24),
      if (cacheSources.isNotEmpty) ...[
        const SectionHeader(title: '缓存来源'),
        SectionCard(
          child: Column(
            children: cacheSources.map((source) {
              final isLast = source == cacheSources.last;
              final savedCents = source['estimated_saved_cents'];
              return ImmersiveListTile(
                title: '${source['source'] ?? 'unknown'}',
                subtitle:
                    '缓存 ${_num(source['cached_tokens'])} Token · 节省 ${savedCents == null ? '暂无数据' : '${_num(savedCents)} 分'}',
                trailing: const Icon(Icons.cached_outlined),
                showDivider: !isLast,
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
      ],
      if (report.daily.isNotEmpty) ...[
        SectionCard(child: TokenTrend(days: report.daily.take(7).toList())),
        const SizedBox(height: 16),
      ],
      const SectionHeader(title: '按模型统计'),
      if (report.models.isNotEmpty)
        SectionCard(
          child: Column(
            children: report.models.map((model) {
              final isLast = model == report.models.last;
              return ImmersiveListTile(
                title: '${model['model']}',
                subtitle:
                    '${model['calls']} 次 · ${_num(model['total_tokens'])} tokens · 缓存 ${_num(model['cached_tokens'])}',
                trailing: Text(
                  '输入 ${_num(model['prompt_tokens'])}\n输出 ${_num(model['completion_tokens'])}',
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.textMuted),
                ),
                showDivider: !isLast,
              );
            }).toList(),
          ),
        ),
      const SizedBox(height: 16),
      const SectionHeader(title: '按日统计'),
      if (report.daily.isNotEmpty)
        SectionCard(
          child: Column(
            children: report.daily.map((day) {
              final isLast = day == report.daily.last;
              return ImmersiveListTile(
                title: day.day,
                subtitle:
                    '${day.calls} 次 · 输入 ${day.promptTokens} · 输出 ${day.completionTokens} · 缓存 ${day.cachedTokens}',
                trailing: Text('${day.totalTokens} tokens',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.textMuted)),
                showDivider: !isLast,
              );
            }).toList(),
          ),
        ),
    ]);
  }

  static int _totalTokens(Map<String, dynamic> summary) =>
      ((summary['prompt_tokens'] as num?)?.toInt() ?? 0) +
      ((summary['completion_tokens'] as num?)?.toInt() ?? 0);

  static String _num(dynamic value) => (value as num? ?? 0).toInt().toString();

  Widget _item(BuildContext context, String label, dynamic value) => SizedBox(
        width: 105,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(color: AppTheme.semanticOf(context).textMuted)),
          const SizedBox(height: 4),
          Text(
            value is String ? value : '${(value as num? ?? 0).toInt()}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ]),
      );
}
