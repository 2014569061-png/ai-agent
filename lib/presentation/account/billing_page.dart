import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/account_services.dart';
import '../../application/billing_api.dart';
import '../../application/providers.dart';

/// 充值页（§4.3）：余额卡片 + 充值档位 + 下单/轮询。
class BillingPage extends ConsumerStatefulWidget {
  const BillingPage({super.key});
  @override
  ConsumerState<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends ConsumerState<BillingPage> {
  static const _tiers = <int, String>{500: '¥5', 1000: '¥10', 3000: '¥30', 5000: '¥50'};
  BalanceInfo? _balance;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _busy = true; _error = null; });
    try {
      final api = ref.read(billingApiProvider);
      final access = await ref.read(accountServiceProvider).accessTokenOrThrow();
      final b = await api.balance(access: access);
      if (mounted) setState(() { _balance = b; _busy = false; });
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.toString(); });
    }
  }

  Future<void> _recharge(int cents) async {
    setState(() => _busy = true);
    try {
      final api = ref.read(billingApiProvider);
      final access = await ref.read(accountServiceProvider).accessTokenOrThrow();
      final order = await api.createOrder(access: access, amountCents: cents);
      // mock 模式：直接模拟回调到账；真实模式在此展示 code_url/二维码并引导轮询。
      await api.mockPay(outTradeNo: order.outTradeNo);
      for (var i = 0; i < 10; i++) {
        final o = await api.pollOrder(access: access, id: order.outTradeNo);
        if (o.status == 'paid') break;
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('充值成功：${_tiers[cents] ?? '¥${cents / 100}'}')));
      }
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('充值 / 额度')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('当前余额', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text('¥${(_balance?.balanceCents ?? 0) / 100}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                  if ((_balance?.balanceCents ?? 0) <
                      ref.watch(remoteConfigServiceProvider).intFlag('billing.balance_warning_min_cents', 500))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('余额较低，请及时充值以免影响使用', style: TextStyle(fontSize: 13)),
                      ),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            const Text('选择充值档位', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _tiers.entries
                  .map((e) => ActionChip(
                        label: Text(e.value),
                        onPressed: _busy ? null : () => _recharge(e.key),
                      ))
                  .toList(),
            ),
            if (ref.watch(remoteConfigServiceProvider).boolFlag('subscription.monthly_1990', false)) ...[
              const SizedBox(height: 16),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.auto_awesome),
                title: const Text('订阅计划'),
                subtitle: const Text('月 ¥19.9，含固定额度（灰度中）'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('订阅功能灰度中，敬请期待')));
                },
              ),
            ],
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_error!, style: const TextStyle(color: Colors.red))),
            if (_busy) const Padding(padding: EdgeInsets.only(top: 24), child: Center(child: CircularProgressIndicator())),
          ],
        ),
      ),
    );
  }
}
