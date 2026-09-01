import 'dart:convert';

import 'package:flutter/material.dart';

import '../../application/chat_controller.dart';
import '../../domain/models.dart';

/// 工具调用卡片：工具名 + 风险徽章 + 状态脉冲 + 可折叠参数/结果。
///
/// 对齐设计稿中"工具调用可视化"的交互：安全工具静默执行、需确认/危险
/// 工具以醒目徽章与状态颜色呈现，强化"危险操作可视化"的信任感。
class ToolCallCard extends StatelessWidget {
  const ToolCallCard({super.key, required this.activity});

  final ToolActivity activity;

  static (Color, String, IconData) _riskStyle(ToolRisk risk) => switch (risk) {
        ToolRisk.safe => (const Color(0xFF16A34A), '安全', Icons.shield_outlined),
        ToolRisk.requiresConfirmation => (const Color(0xFFF59E0B), '需确认', Icons.shield_outlined),
        ToolRisk.dangerous => (const Color(0xFFDC2626), '危险', Icons.warning_amber_rounded),
      };

  static (Color, bool) _statusStyle(String status) => switch (status) {
        '执行中' => (const Color(0xFF2563EB), true),
        '等待确认' => (const Color(0xFFF59E0B), true),
        '已完成' => (const Color(0xFF16A34A), false),
        '执行失败' => (const Color(0xFFDC2626), false),
        _ => (const Color(0xFF64748B), false),
      };

  String _prettyJson(Map<String, dynamic> value) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (riskColor, riskLabel, riskIcon) = _riskStyle(activity.risk);
    final (statusColor, pulsing) = _statusStyle(activity.status);
    final waiting = activity.status == '等待确认';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: waiting ? theme.colorScheme.error.withValues(alpha: 0.6) : theme.colorScheme.outlineVariant),
          boxShadow: const [BoxShadow(color: Color(0x0D1A4B84), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: riskColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.handyman_outlined, size: 18, color: riskColor),
          ),
          title: Text(
            activity.call.name,
            style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                _RiskBadge(color: riskColor, label: riskLabel, icon: riskIcon),
                const SizedBox(width: 10),
                pulsing
                    ? _PulseDot(color: statusColor)
                    : Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(activity.status, style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          children: [
            const Divider(height: 16),
            _JsonSection(label: '参数', content: _prettyJson(activity.call.arguments)),
            if (activity.result != null) ...[
              const SizedBox(height: 10),
              _JsonSection(label: '结果', content: activity.result!),
            ],
          ],
        ),
      ),
    );
  }
}

class _RiskBadge extends StatelessWidget {
  const _RiskBadge({required this.color, required this.label, required this.icon});
  final Color color;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _JsonSection extends StatelessWidget {
  const _JsonSection({required this.label, required this.content});
  final String label;
  final String content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: theme.colorScheme.outline, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 200),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              content,
              style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: theme.colorScheme.onSurfaceVariant, height: 1.45),
            ),
          ),
        ),
      ],
    );
  }
}

/// 脉冲状态指示点：执行中/等待确认时缩放呼吸。
class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color});
  final Color color;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.55, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: Container(width: 8, height: 8, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
    );
  }
}
