import '../theme/mobile_theme.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../widgets/nexus_page_layout.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/audit_service.dart';
import '../../application/providers.dart';
import '../../infrastructure/database/app_database.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../theme/desktop_theme.dart';
import '../widgets/desktop_page_summary.dart';
import '../widgets/async_state_view.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/section_card.dart';
import '../widgets/nexus_switch.dart';

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

  Map<String, dynamic>? _deviceOperationDetail(AuditLog log) {
    if (log.type != 'android_device_operation' &&
        log.type != 'scheduled_task_run' &&
        log.type != 'device_automation') {
      return null;
    }
    try {
      final decoded = jsonDecode(log.detail);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  String _automationEventLabel(Object? event) {
    final value = event?.toString() ?? '';
    return switch (value) {
      'created' => '创建规则',
      'enabled' => '启用规则',
      'paused' => '暂停规则',
      'deleted' => '删除规则',
      'dismissed' => '触发后用户放弃',
      'executed_executed' => '确认后执行成功',
      'executed_partial' => '确认后部分成功',
      'executed_failed' => '确认后执行失败',
      _ when value.startsWith('agent_') => '助手请求 · ${value.substring(6)}',
      _ => value.isEmpty ? '未知事件' : value,
    };
  }

  String _auditValueText(Object? value) {
    if (value is Map) {
      return value.entries
          .map((entry) => '${entry.key}: ${_auditValueText(entry.value)}')
          .join('，');
    }
    if (value is Iterable) {
      return value.map(_auditValueText).join('、');
    }
    return value?.toString() ?? '';
  }

  String _logTitle(AuditLog log) {
    final detail = _deviceOperationDetail(log);
    if (detail == null) return '${log.type} · ${log.detail}';
    if (log.type == 'scheduled_task_run') {
      return '定时任务 · ${detail['taskName'] ?? detail['taskId'] ?? '未知任务'}';
    }
    if (log.type == 'device_automation') {
      return '设备自动化 · ${detail['ruleName'] ?? detail['ruleId'] ?? '未知规则'}'
          ' · ${_automationEventLabel(detail['event'])}'
          '${detail['requiresRoot'] == true ? ' · Root' : ''}';
    }
    final operation = detail['operation']?.toString() ?? '未知操作';
    final target = _auditValueText(detail['target']);
    return target.isEmpty ? '手机操作 · $operation' : '手机操作 · $operation · $target';
  }

  String _logDetails(AuditLog log) {
    final detail = _deviceOperationDetail(log);
    if (detail == null) return log.detail;
    if (log.type == 'scheduled_task_run') {
      return [
        '任务：${detail['taskName'] ?? detail['taskId'] ?? ''}',
        '状态：${detail['status'] ?? '未知'}',
        '开始：${detail['startedAt'] ?? ''}',
        '完成：${detail['completedAt'] ?? ''}',
        '耗时：${detail['durationMs'] ?? 0} ms',
        if (detail['result'] is String &&
            (detail['result'] as String).isNotEmpty)
          '结果：${detail['result']}',
        if (detail['truncated'] == true) '结果已截断（最多显示 4000 个字符）',
      ].join('\n');
    }
    if (log.type == 'device_automation') {
      final actions = detail['actions'] is List
          ? (detail['actions'] as List).map((e) => '  · $e').join('\n')
          : '';
      return [
        '规则：${detail['ruleName'] ?? ''}（${detail['ruleId'] ?? ''}）',
        '事件：${_automationEventLabel(detail['event'])}',
        '触发：${detail['trigger'] ?? ''}',
        if (actions.isNotEmpty) '动作：\n$actions',
        '需要 Root：${detail['requiresRoot'] == true ? '是' : '否'}',
        if (detail['irreversible'] == true) '包含不可撤销动作',
        if (detail['userRequest'] != null) '用户原话：${detail['userRequest']}',
        '时间：${log.createdAt.toLocal().toString().substring(0, 19)}',
      ].join('\n');
    }
    final result = detail['result'] is Map
        ? Map<String, dynamic>.from(detail['result'] as Map)
        : const <String, dynamic>{};
    final target = _auditValueText(detail['target']);
    final parameters = _auditValueText(detail['parameters']);
    final intent = detail['intent'] is Map
        ? Map<String, dynamic>.from(detail['intent'] as Map)
        : const <String, dynamic>{};
    final execution = detail['execution'] is Map
        ? Map<String, dynamic>.from(detail['execution'] as Map)
        : const <String, dynamic>{};
    final timing = detail['timing'] is Map
        ? Map<String, dynamic>.from(detail['timing'] as Map)
        : const <String, dynamic>{};
    return [
      '用户请求：${detail['userRequest'] ?? ''}',
      '操作：${detail['operation'] ?? '未知操作'}',
      if (target.isNotEmpty) '目标：$target',
      if (parameters.isNotEmpty) '参数：$parameters',
      '阶段：${detail['preview'] == true ? '预览' : '执行'}',
      if (intent.isNotEmpty)
        '模型意图：${intent['tool'] ?? ''} · ${intent['operation'] ?? ''}',
      if (execution.isNotEmpty) ...[
        '实际执行：${execution['executed'] == true ? '已执行' : '未执行'}'
            '${execution['mode'] != null ? ' · ${execution['mode']}' : ''}'
            '${execution['riskClass'] != null ? ' · ${execution['riskClass']}' : ''}',
        if (execution['command'] != null) '实际命令：${execution['command']}',
        if (execution['executionPlan'] != null)
          '执行流程：${execution['executionPlan']}',
        if (execution['reason'] != null) '未执行原因：${execution['reason']}',
        if (execution['reversible'] != null)
          '可撤销：${execution['reversible'] == true ? '是' : '否（不可撤销）'}',
        if (execution['rollback'] != null) '恢复方案：${execution['rollback']}',
      ],
      if (timing['durationMs'] != null) '耗时：${timing['durationMs']} ms',
      '结果：${result['status'] ?? '未知'} · ${result['code'] ?? ''} · ${result['effect'] ?? ''}',
      '时间：${log.createdAt.toLocal().toString().substring(0, 19)}',
    ].join('\n');
  }

  Future<void> _showLogDetails(AuditLog log) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(switch (log.type) {
          'android_device_operation' => '手机操作记录',
          'scheduled_task_run' => '定时任务执行记录',
          'device_automation' => '设备自动化记录',
          _ => log.type,
        }),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(_logDetails(log)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  String _markdown() {
    final buffer = StringBuffer('# 审计日志\n\n');
    for (final log in _logs) {
      buffer.writeln(
          '- [${log.createdAt.toLocal().toString().substring(0, 19)}] ${_logTitle(log)}'
          '${log.decision != null ? '（${log.decision}）' : ''}');
      if (log.type == 'android_device_operation') {
        buffer.writeln('  ${_logDetails(log).replaceAll('\n', '\n  ')}');
      } else if (log.type == 'scheduled_task_run') {
        buffer.writeln('  ${_logDetails(log).replaceAll('\n', '\n  ')}');
      } else if (log.type == 'device_automation') {
        buffer.writeln('  ${_logDetails(log).replaceAll('\n', '\n  ')}');
      } else {
        buffer.writeln('  ${log.detail}');
      }
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final desktop = DesktopTheme.maybeOf(context);

    return Scaffold(
      backgroundColor: MobileTheme.pageBackground(context),
      appBar: NexusPageHeader(
        title: '审计日志',
        subtitle: '工具调用与审批追踪记录',
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_outlined, size: 20),
            tooltip: '复制 Markdown',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _markdown()));
              if (!context.mounted) return;
              FloatingToast.show(context, '已复制 Markdown');
            },
          ),
        ],
      ),
      body: NexusPageLayout(
          child: Column(children: [
        if (desktop != null)
          DesktopPageSummary(items: [
            (
              icon: Icons.receipt_long_outlined,
              label: '近期记录',
              value: _loading
                  ? '读取中'
                  : _error != null
                      ? '读取失败'
                      : '${_logs.length}'
            ),
            (
              icon: Icons.policy_outlined,
              label: '普通工具审计',
              value: _loading
                  ? '读取中'
                  : _error != null
                      ? '未知'
                      : _enabled
                          ? '已启用'
                          : '已关闭'
            ),
          ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SectionCard(
            child: NexusSwitchListTile(
              secondary: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppPalette.brandSoftDark
                      : AppPalette.brandSoftLight,
                  borderRadius:
                      BorderRadius.circular(MobileTheme.controlRadius(context)),
                ),
                child: Icon(Icons.security_outlined,
                    size: 20, color: MobileTheme.brand(context)),
              ),
              title: const Text(
                '启用审计',
                style: TextStyle(
                    fontSize: AppTokens.fontSizeBody,
                    fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '普通工具日志按此开关记录；安全审批和手机操作请求、目标及结果始终保存在本机',
                style: TextStyle(
                  fontSize: AppTokens.fontSizeCaption,
                  color: isDark
                      ? AppPalette.darkTextMuted
                      : AppPalette.lightTextMuted,
                ),
              ),
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
                    message: '安全审批和手机设备操作记录会保存在此处')
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
                          leading: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppPalette.darkSurface
                                  : AppPalette.lightSurface,
                              borderRadius: BorderRadius.circular(
                                  MobileTheme.controlRadius(context)),
                              border: Border.all(
                                color: isDark
                                    ? AppPalette.darkHairline
                                    : AppPalette.lightHairline,
                              ),
                            ),
                            child: Icon(
                              log.type == 'approval'
                                  ? Icons.fact_check_outlined
                                  : log.type == 'scheduled_task_run'
                                      ? Icons.schedule_outlined
                                      : log.type == 'device_automation'
                                          ? Icons.bolt_outlined
                                          : Icons.build_outlined,
                              size: 16,
                              color: isDark
                                  ? AppPalette.darkText
                                  : AppPalette.lightText,
                            ),
                          ),
                          title: Text(
                            _logTitle(log),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: AppTokens.fontSizeBody,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${log.createdAt.toLocal().toString().substring(0, 19)}'
                            '${log.decision != null ? ' · ${log.decision}' : ''}',
                            style: TextStyle(
                              fontSize: AppTokens.fontSizeCaption,
                              fontFamily: AppTokens.fontFamilyMono,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                              color: isDark
                                  ? AppPalette.darkTextMuted
                                  : AppPalette.lightTextMuted,
                            ),
                          ),
                          onTap: () => _showLogDetails(log),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ])),
    );
  }
}
