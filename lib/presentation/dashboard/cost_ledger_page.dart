import '../widgets/empty_state_view.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/nexus_page_layout.dart';
import '../widgets/nexus_disclosure.dart';
import '../theme/desktop_theme.dart';
import 'package:flutter/material.dart';

import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/database/cost_budget_ledger.dart';

/// A local review surface, not a provider invoice or an automatic refund.
class CostLedgerPage extends StatefulWidget {
  const CostLedgerPage({super.key, required this.database});
  final Future<AppDatabase> Function() database;
  @override
  State<CostLedgerPage> createState() => _CostLedgerPageState();
}

class _CostLedgerPageState extends State<CostLedgerPage> {
  late final Future<CostBudgetLedger> _ledger;
  late Future<List<CostLedgerEntry>> _rows;
  var _offset = 0;
  var _reviewing = false;
  @override
  void initState() {
    super.initState();
    _ledger = widget.database().then(CostBudgetLedger.new);
    _rows = _read();
  }

  Future<List<CostLedgerEntry>> _read() async =>
      (await _ledger).entries(limit: 50, offset: _offset);
  void _refresh([int? offset]) => setState(() {
        _offset = offset ?? _offset;
        _rows = _read();
      });

  Future<void> _review(CostLedgerEntry entry) async {
    if (_reviewing) return;
    setState(() => _reviewing = true);
    try {
      if (entry.state == 'reserved') {
        final stopped = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
                  title: const Text('确认关联运行已经停止？'),
                  content: const Text(
                      '预留可能仍属于正在发送的请求。只有你确认对应运行已经停止后，才可转为待确认；此操作不释放费用、不重试模型。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('已停止，标记待确认'))
                  ],
                ));
        if (stopped == true) {
          await (await _ledger).markPending(entry.id, 'interrupted_review');
          if (mounted) _refresh();
        }
        return;
      }
      if (!mounted) return;
      final changed = await showDialog<bool>(
          context: context,
          builder: (_) => _CostBillReviewDialog(entry: entry, ledger: _ledger));
      if (changed == true && mounted) _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('费用记录操作失败，请刷新后检查')));
      }
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  String _state(String value) => switch (value) {
        'reserved' => '预留（运行状态未核实）',
        'pending' => '待确认（仍占预算）',
        'settled' => 'usage结算估算（非账单）',
        'reconciled' => '已人工核对账单',
        _ => '未知状态，需核查',
      };
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: NexusPageHeader(title: '逐请求费用账本', actions: [
          IconButton(
              tooltip: '刷新费用账本',
              onPressed: () => _refresh(),
              icon: const Icon(Icons.refresh))
        ]),
        body: NexusPageLayout(
            child: SafeArea(
                child: Column(children: [
          if (DesktopTheme.maybeOf(context) == null)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('预留和待确认计入预算；未知费用不代表免费。估算不等于服务商账单。'),
                  NexusDisclosure(
                    title: Text('账本记录说明'),
                    headerPadding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('重启不清零；本账本暂未纳入跨机备份。每条记录对应一次发送尝试，重试共用请求编号。'),
                  ),
                ],
              ),
            )
          else
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    '预留和待确认都计入预算。未知费用不是免费；usage估算不等于服务商账单。重启不清零；本账本暂未纳入跨机备份。每条记录对应一次发送尝试，重试共用请求编号。')),
          Expanded(
              child: FutureBuilder<List<CostLedgerEntry>>(
                  future: _rows,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return EmptyStateView(
                          icon: Icons.error_outline_rounded,
                          title: '账本读取失败',
                          message: '请重试；读取失败不代表零花费',
                          actionLabel: '重试',
                          onAction: () => _refresh());
                    }
                    final rows = snapshot.data;
                    if (rows == null) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (rows.isEmpty) {
                      return const EmptyStateView(
                          icon: Icons.receipt_long_outlined,
                          title: '本页没有费用记录',
                          message: '有模型请求记录后，可在这里核对预留、待确认与结算估算');
                    }
                    return ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          final entry = rows[index];
                          final unknown = entry.priced == false &&
                              const {'reserved', 'pending'}
                                  .contains(entry.state);
                          return Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 6),
                              child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            '${_state(entry.state)} · ${unknown ? '费用未知（非零费用）' : '¥${(entry.amountCents / 100).toStringAsFixed(2)}'}'),
                                        Text(
                                            '${entry.day} · ${entry.providerId ?? '历史来源'} · ${entry.model ?? '未记录模型'} · ${entry.purpose ?? '历史估算'}'),
                                        if (DesktopTheme.maybeOf(context) ==
                                            null)
                                          NexusDisclosure(
                                            title: const Text('运行与请求编号'),
                                            headerPadding:
                                                const EdgeInsets.symmetric(
                                                    vertical: 12),
                                            child: SelectableText(
                                                '运行：${entry.runId ?? '未关联'}\n请求：${entry.requestId ?? '未记录'}\n尝试：${entry.id}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall),
                                          )
                                        else
                                          SelectableText(
                                              '运行：${entry.runId ?? '未关联'}\n请求：${entry.requestId ?? '未记录'}\n尝试：${entry.id}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall),
                                        Text(
                                            '原预留 ¥${(entry.originalCents / 100).toStringAsFixed(2)} · ${entry.reason ?? '历史/未决记录'}'),
                                        TextButton(
                                            onPressed: _reviewing
                                                ? null
                                                : () => _review(entry),
                                            child: Text(
                                                entry.state == 'reserved'
                                                    ? '运行已停止？标记待确认'
                                                    : '按账单人工核对')),
                                      ])));
                        });
                  })),
          FutureBuilder<List<CostLedgerEntry>>(
              future: _rows,
              builder: (context, snapshot) {
                if (_offset == 0 && (snapshot.data?.isEmpty ?? true)) {
                  return const SizedBox.shrink();
                }
                return Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    children: [
                      TextButton(
                          onPressed: _offset == 0
                              ? null
                              : () => _refresh(_offset - 50),
                          child: const Text('上一页')),
                      Text('第 ${_offset ~/ 50 + 1} 页'),
                      TextButton(
                          onPressed: (snapshot.data?.length ?? 0) < 50
                              ? null
                              : () => _refresh(_offset + 50),
                          child: const Text('下一页')),
                    ]);
              }),
        ]))),
      );
}

class _CostBillReviewDialog extends StatefulWidget {
  const _CostBillReviewDialog({required this.entry, required this.ledger});
  final CostLedgerEntry entry;
  final Future<CostBudgetLedger> ledger;
  @override
  State<_CostBillReviewDialog> createState() => _CostBillReviewDialogState();
}

class _CostBillReviewDialogState extends State<_CostBillReviewDialog> {
  late final TextEditingController _amount;
  final _reference = TextEditingController();
  var _confirmed = false, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
        text: (widget.entry.amountCents / 100).toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _amount.text.trim();
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text) ||
        _reference.text.trim().isEmpty) {
      setState(() => _error = '请输入非负金额及核对依据');
      return;
    }
    final parts = text.split('.');
    final whole = int.tryParse(parts[0]);
    if (whole == null || whole > 1000000000) {
      setState(() => _error = '金额超出支持范围');
      return;
    }
    final cents = whole * 100 +
        int.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await (await widget.ledger).reconcile(
          widget.entry.id, cents,
          expectedRevision: widget.entry.revision, reference: _reference.text);
      if (!mounted) return;
      if (saved) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _busy = false;
          _error = '记录已变化，请取消并刷新后重新核对';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '保存失败；未确认成功，请刷新后检查';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('人工账单对账'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('仅修改本地预算账本，不退款、不向服务商发请求。请填写这一请求/尝试的费用，不要将整张账单重复分配给多笔请求。'),
          TextField(
              key: const ValueKey('cost-review-amount'),
              controller: _amount,
              enabled: !_busy,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: '已核对金额（人民币元，最多2位小数）')),
          TextField(
              key: const ValueKey('cost-review-reference'),
              controller: _reference,
              enabled: !_busy,
              maxLength: 200,
              decoration: const InputDecoration(
                  labelText: '账单日期/请求编号等核对依据',
                  helperText: '只存本机；不要填写API Key或其他密钥')),
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _confirmed,
              onChanged:
                  _busy ? null : (v) => setState(() => _confirmed = v ?? false),
              title: const Text('我已核对服务商账单，而非猜测；0元也有依据')),
          if (_error != null)
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ])),
        actions: [
          TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              key: const ValueKey('cost-review-save'),
              onPressed: !_confirmed || _busy ? null : _save,
              child: const Text('保存已核对金额'))
        ],
      );
}
