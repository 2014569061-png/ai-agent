import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/account_services.dart';
import '../../application/billing_api.dart';
import '../../application/providers.dart';

/// 用量报表（M3）：按日聚合 + 模型分布。
class UsageReportPage extends ConsumerStatefulWidget {
  const UsageReportPage({super.key});
  @override
  ConsumerState<UsageReportPage> createState() => _UsageReportPageState();
}

class _UsageReportPageState extends ConsumerState<UsageReportPage> {
  UsageReport? _report;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(billingApiProvider);
      final access = await ref.read(accountServiceProvider).accessTokenOrThrow();
      final r = await api.usage(access: access);
      if (mounted) setState(() => _report = r);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('用量报表')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _error != null
            ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.red)))])
            : _report == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text('按日', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      ..._report!.daily.map((d) => ListTile(
                            dense: true,
                            title: Text(d.day),
                            subtitle: Text('输入 ${d.promptTokens} · 输出 ${d.completionTokens} · 缓存 ${d.cachedTokens}'),
                            trailing: Text('¥${d.spendCents / 100}'),
                          )),
                      const Divider(height: 24),
                      const Text('按模型', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      ..._report!.models.map((m) => ListTile(
                            dense: true,
                            title: Text('${m['model']}'),
                            subtitle: Text('${m['calls']} 次'),
                            trailing: Text('¥${(m['spend_cents'] as num? ?? 0) / 100}'),
                          )),
                    ],
                  ),
      ),
    );
  }
}
