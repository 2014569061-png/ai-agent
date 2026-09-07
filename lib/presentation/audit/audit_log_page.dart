import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/audit_service.dart';
import '../../application/providers.dart';
import '../../infrastructure/database/app_database.dart';
import '../widgets/async_state_view.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/floating_toast.dart';
import '../widgets/section_card.dart';

/// 审计日志页（G2）：展示工具调用审批链路，支持导出 Markdown / CSV。
class AuditLogPage extends ConsumerStatefulWidget {
  const AuditLogPage({super.key});

  @override
  ConsumerState<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends ConsumerState<AuditLogPage> {
  bool _loading = true;
  Object? _error;
  bool _enabled = false;
  List<AuditLog> _logs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final db = await ref.read(databaseProvider.future);
      final enabled = await ref.read(auditServiceProvider).isEnabled();
      final logs = await db.recentAuditLogs();
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _logs = logs;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _toggle(bool value) async {
    await ref.read(auditServiceProvider).setEnabled(value);
    if (mounted) setState(() => _enabled = value);
  }

  String _markdown() {
    final buffer = StringBuffer('# 审计日志\n\n');
    for (final log in _logs) {
      buffer.writeln(
          '- [${log.createdAt.toLocal().toString().substring(0, 19)}] ${log.type} ${log.detail}'
          '${log.decision != null ? '（${log.decision}）' : ''}');
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('审计日志'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: '复制 Markdown',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _markdown()));
              if (!context.mounted) return;
              FloatingToast.show(context, '已复制 Markdown');
            },
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SectionCard(
            child: SwitchListTile(
              secondary: const Icon(Icons.security_outlined),
              title: const Text('启用审计'),
              subtitle: const Text('开启后记录工具调用与审批（本设备可被查看）'),
              value: _enabled,
              onChanged: _toggle,
            ),
          ),
        ),
        Expanded(
          child: AsyncStateView(
            loading: _loading,
            error: _error,
            onRetry: _load,
            child: _logs.isEmpty
                ? const EmptyStateView(
                    icon: Icons.security_outlined,
                    title: '暂无审计记录',
                    message: '启用审计后，工具调用会记录在此')
                : ListView.separated(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _logs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      return SectionCard(
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                              log.type == 'approval'
                                  ? Icons.fact_check_outlined
                                  : Icons.build_outlined,
                              size: 20),
                          title: Text('${log.type} · ${log.detail}',
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              '${log.createdAt.toLocal().toString().substring(0, 19)}'
                              '${log.decision != null ? ' · ${log.decision}' : ''}'),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}
