import '../widgets/nexus_error_notice.dart';
import '../widgets/nexus_disclosure.dart';
import '../widgets/nexus_page_layout.dart';
import 'package:flutter/material.dart';

import '../../application/remote_execution_probe.dart';
import '../widgets/nexus_page_header.dart';

/// Connection diagnostics only. No fake handshake and no automatic job replay.
class RemoteExecutionPage extends StatefulWidget {
  const RemoteExecutionPage({super.key});
  @override
  State<RemoteExecutionPage> createState() => _RemoteExecutionPageState();
}

class _RemoteExecutionPageState extends State<RemoteExecutionPage> {
  final _endpoint = TextEditingController();
  final _token = TextEditingController();
  RemoteHandshake? _handshake;
  RemotePairingLease? _lease;
  String? _error;
  bool _loading = false;
  bool _confirmed = false;

  @override
  void dispose() {
    _endpoint.dispose();
    _token.dispose();
    super.dispose();
  }

  void _edited() => setState(() {
        _confirmed = false;
        _handshake = null;
        _lease = null;
        _error = null;
      });

  Future<void> _probe() async {
    if (!_confirmed || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _handshake = null;
    });
    try {
      final probe = RemoteExecutionProbe.forEndpoint(
          Uri.parse(_endpoint.text.trim()), _token.text.trim());
      final handshake = await probe.handshake();
      final now = DateTime.now().toUtc();
      if (mounted) {
        setState(() {
          _handshake = handshake;
          _lease = RemotePairingLease(
            pairingId: 'pair-${now.millisecondsSinceEpoch}',
            endpoint: _endpoint.text.trim(),
            arch: handshake.arch,
            protocolVersion: handshake.protocolVersion,
            pairedAtUtc: now,
            leaseExpiresAtUtc: now.add(const Duration(minutes: 30)),
          );
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is FormatException
            ? error.message
            : '连接未通过，请检查地址、执行器状态和本机令牌。');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final handshake = _handshake;
    return Scaffold(
      appBar: const NexusPageHeader(
          title: '远程执行连接', subtitle: '真实握手 · 不自动同步代码或启动任务'),
      body: NexusPageLayout(
          child: SafeArea(
              child: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('验证与电脑端执行器的连接，不会自动同步代码或运行任务。'),
        const NexusDisclosure(
            title: Text('电脑端连接说明'),
            headerPadding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
                '先在 Windows 电脑启动本地自托管执行器。Android 模拟器可用 http://10.0.2.2:8767 访问宿主；手机上的 localhost 不指向电脑。当前执行器只监听电脑回环地址，不支持公网部署。')),
        const SizedBox(height: 16),
        TextField(
            key: const ValueKey('remote-endpoint'),
            controller: _endpoint,
            enabled: !_loading,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
                labelText: '执行器地址', hintText: 'http://10.0.2.2:8767'),
            onChanged: (_) => _edited()),
        const SizedBox(height: 12),
        TextField(
            key: const ValueKey('remote-token'),
            controller: _token,
            enabled: !_loading,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: '本机执行器令牌（仅本次连接，不保存）'),
            onChanged: (_) => _edited()),
        const SizedBox(height: 8),
        const Text(
            '令牌位于电脑 local/remote-executor/token，请勿发送到聊天或日志。只有明确点击连接才会发起请求；页面不会保存令牌、上传项目或运行命令。'),
        Material(
          color: Colors.transparent,
          child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _confirmed,
              title: const Text('我已核对执行器地址，允许进行认证握手'),
              onChanged: _loading
                  ? null
                  : (value) => setState(() => _confirmed = value ?? false)),
        ),
        FilledButton(
            key: const ValueKey('remote-connect'),
            onPressed: _confirmed && !_loading ? _probe : null,
            child: Text(_loading ? '正在连接…' : '连接并验证')),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.only(top: 16),
              child: NexusErrorNotice(
                  title: '未能完成连接验证',
                  message: '请检查电脑端执行器是否启动、地址是否可达，以及令牌是否正确。',
                  details: _error,
                  onRetry: _confirmed && !_loading ? _probe : null,
                  retryLabel: '重新验证')),
        if (handshake != null)
          Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SelectableText(
                  '真实连接已通过\n协议 ${handshake.protocolVersion}\n架构 ${handshake.arch}\n并发 ${handshake.maxConcurrency}\n可用空间 ${handshake.freeBytes} bytes\n工具链 ${handshake.toolchain.join(', ')}')),
        if (_lease != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '本地连接记录：${_lease!.revoked ? "已清除" : (_lease!.isLeaseActive() ? "诊断记录有效" : "需重新握手")}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '本地记录到期（UTC）：${_lease!.leaseExpiresAtUtc.toIso8601String()}；不是服务端授权租约。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          key: const ValueKey('remote-lease-renew'),
                          onPressed: _lease!.revoked
                              ? null
                              : () => setState(() => _lease = _lease!.renew()),
                          child: const Text('延长本地记录 (+30m)'),
                        ),
                        OutlinedButton(
                          key: const ValueKey('remote-pairing-revoke'),
                          onPressed: _lease!.revoked
                              ? null
                              : () => setState(() => _lease = _lease!.revoke()),
                          child: const Text('清除本地连接记录'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 20),
        const Text(
            '当前页面仅用于连接诊断。持久作业 API 已提供，但手机任务提交的统一审批接线、设备配对/撤销和跨设备同步尚未完成；连接成功不代表这些能力已验收。'),
      ]))),
    );
  }
}
