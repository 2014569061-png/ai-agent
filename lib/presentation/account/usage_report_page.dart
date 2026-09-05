import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/billing_api.dart';
import '../../application/providers.dart';
import '../widgets/section_card.dart';

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
    setState(() {
      _error = null;
    });
    try {
      final account = await ref.read(accountServiceProvider).restoreSession();
      if (account == null) {
        if (mounted) setState(() => _report = const UsageReport());
        return;
      }
      final report =
          await ref.read(billingApiProvider).usage(access: account.access);
      if (mounted) setState(() => _report = report);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Token 用量报表')),
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
              TextButton(onPressed: _load, child: const Text('重新加载'))
            ]))
      ]);
    }
    if (_report == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_report!.isEmpty) {
      return ListView(children: const [
        Padding(
            padding: EdgeInsets.only(top: 140, left: 24, right: 24),
            child: Column(children: [
              Icon(Icons.data_usage_outlined, size: 56),
              SizedBox(height: 16),
              Text('暂无 Token 用量',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              Text('完成一次模型对话后，这里会显示用量统计。', textAlign: TextAlign.center)
            ]))
      ]);
    }
    final s = _report!.summary;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _SummaryCard(summary: s),
      const SizedBox(height: 24),
      const Text('按模型统计',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
      ..._report!.models.map((m) => ListTile(
          title: Text('${m['model']}'),
          subtitle: Text('${m['calls']} 次 · ${_num(m['total_tokens'])} tokens'),
          trailing: Text(
              '输入 ${_num(m['prompt_tokens'])}\n输出 ${_num(m['completion_tokens'])}',
              textAlign: TextAlign.right))),
      const SizedBox(height: 16),
      const Text('按日统计',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
      ..._report!.daily.map((d) => ListTile(
          title: Text(d.day),
          subtitle: Text(
              '${d.calls} 次 · 输入 ${d.promptTokens} · 输出 ${d.completionTokens}'),
          trailing: Text('${d.totalTokens} tokens'))),
    ]);
  }

  static String _num(dynamic v) => (v as num? ?? 0).toInt().toString();
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final Map<String, dynamic> summary;
  @override
  Widget build(BuildContext context) {
    final p = (summary['prompt_tokens'] as num? ?? 0).toInt(),
        c = (summary['completion_tokens'] as num? ?? 0).toInt(),
        cached = (summary['cached_tokens'] as num? ?? 0).toInt();
    return SectionCard(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(spacing: 24, runSpacing: 16, children: [
              _item('请求次数', summary['calls']),
              _item('总 Token', p + c),
              _item('输入 Token', p),
              _item('输出 Token', c),
              _item('缓存 Token', cached)
            ])));
  }

  Widget _item(String label, dynamic value) => SizedBox(
      width: 105,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 4),
        Text('${(value as num? ?? 0).toInt()}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))
      ]));
}
