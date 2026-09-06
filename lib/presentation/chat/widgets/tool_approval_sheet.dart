import 'dart:convert';

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

import '../../../domain/models.dart';
import '../../l10n/app_strings.dart';
import '../../../infrastructure/tools/tool_humanizer.dart';

/// 工具审批弹窗主体：按风险展示人性化摘要与关键参数，「技术细节」折叠完整 JSON，
/// 按钮返回 [ToolApproval] 决策由调用方处理（记录信任/审计）。
class ToolApprovalSheet extends StatelessWidget {
  const ToolApprovalSheet({super.key, required this.call, required this.risk});

  final ToolCall call;
  final ToolRisk risk;

  @override
  Widget build(BuildContext context) {
    final danger = risk == ToolRisk.dangerous;
    final riskColor =
        danger ? AppTheme.danger : AppTheme.warning;
    final riskLabel =
        danger ? AppStrings.dangerOperation : AppStrings.requiresConfirmation;
    final humanizer = const ToolHumanizer();
    final summary = humanizer.summaryOf(call);
    final paramLines = humanizer.paramLines(call);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: riskColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(
                  danger ? Icons.warning_amber_rounded : Icons.shield_outlined,
                  color: riskColor),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(AppStrings.confirmToolCall,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text(AppStrings.requiresAuthorization,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.outline,
                          fontSize: 13)),
                ])),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
                color: riskColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: riskColor.withValues(alpha: 0.4))),
            child: Row(children: [
              Icon(Icons.build_circle_outlined, size: 16, color: riskColor),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(call.name,
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700))),
              Text(riskLabel,
                  style: TextStyle(
                      color: riskColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
            ]),
          ),
          // 人性化摘要：默认展示一句话做的事 + 关键参数，代替原始 JSON。
          if (summary != null) ...[
            const SizedBox(height: 12),
            Text(summary,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            if (paramLines.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (final (k, v) in paramLines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text('· $k: $v',
                      style: TextStyle(
                          fontSize: 13,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
            ],
          ],
          // 完整 JSON 收进「技术细节」折叠区，供审计/核对，不干扰主决策。
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('技术细节',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline)),
              childrenPadding: const EdgeInsets.only(top: 6),
              children: [
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 160),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10)),
                  child: SingleChildScrollView(
                      child: SelectableText(_prettyJson(call.arguments),
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12))),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 按风险裁剪按钮：危险工具仅单次/拒绝；需确认工具多「本会话/始终允许」。
          if (!danger) ...[
            Row(children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed: () =>
                          Navigator.pop(context, ToolApproval.reject),
                      child: const Text(AppStrings.reject))),
              const SizedBox(width: 10),
              Expanded(
                  child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: riskColor),
                      onPressed: () =>
                          Navigator.pop(context, ToolApproval.allowOnce),
                      child: const Text(AppStrings.allowOnce))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed: () =>
                          Navigator.pop(context, ToolApproval.allowSession),
                      child: const Text('仅本次会话'))),
              const SizedBox(width: 10),
              Expanded(
                  child: FilledButton.tonal(
                      onPressed: () =>
                          Navigator.pop(context, ToolApproval.allowAlways),
                      child: const Text('始终允许'))),
            ]),
          ] else ...[
            Row(children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed: () =>
                          Navigator.pop(context, ToolApproval.reject),
                      child: const Text(AppStrings.reject))),
              const SizedBox(width: 10),
              Expanded(
                  child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: riskColor),
                      onPressed: () =>
                          Navigator.pop(context, ToolApproval.allowOnce),
                      child: const Text(AppStrings.allowOnce))),
            ]),
          ],
        ],
      ),
    );
  }

  static String _prettyJson(Map<String, dynamic> value) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }
}
