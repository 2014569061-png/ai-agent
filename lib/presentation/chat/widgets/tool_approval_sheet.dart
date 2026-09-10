import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    final riskColor = danger ? AppTheme.danger : AppTheme.warning;
    final riskLabel =
        danger ? AppStrings.dangerOperation : AppStrings.requiresConfirmation;
    final humanizer = const ToolHumanizer();
    final summary = humanizer.summaryOf(call);
    final paramLines = humanizer.paramLines(call);

    final command = (call.arguments['CommandLine'] ??
            call.arguments['command'] ??
            call.arguments['cmd'])
        ?.toString();
    final targetContent = call.arguments['TargetContent']?.toString();
    final replacementContent = call.arguments['ReplacementContent']?.toString();
    final targetFile = (call.arguments['TargetFile'] ??
            call.arguments['path'] ??
            call.arguments['file'])
        ?.toString();
    final codeContent =
        (call.arguments['CodeContent'] ?? call.arguments['content'])
            ?.toString();

    return SizedBox(
      height: math.min(MediaQuery.sizeOf(context).height * 0.76, 640.0),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
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
                          danger
                              ? Icons.warning_amber_rounded
                              : Icons.shield_outlined,
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
                                  ?.copyWith(fontWeight: FontWeight.w500)),
                          Text(AppStrings.requiresAuthorization,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.outline,
                                  fontSize: 13)),
                        ])),
                  ]),
                  const SizedBox(height: 16),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                        color: riskColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: riskColor.withValues(alpha: 0.4))),
                    child: Row(children: [
                      Icon(Icons.build_circle_outlined,
                          size: 16, color: riskColor),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(call.name,
                              style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w500))),
                      Text(riskLabel,
                          style: TextStyle(
                              color: riskColor,
                              fontWeight: FontWeight.w500,
                              fontSize: 12)),
                    ]),
                  ),
                  // 人性化摘要：默认展示一句话做的事 + 关键参数，代替原始 JSON。
                  if (summary != null) ...[
                    const SizedBox(height: 12),
                    Text(summary,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500)),
                    if (paramLines.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      for (final (k, v) in paramLines)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Text('· $k: $v',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                        ),
                    ],
                  ],

                  // 代码与指令可视化预览 (Diff / Shell Command)
                  if (command != null && command.isNotEmpty)
                    _commandPreview(command),
                  if (targetContent != null && replacementContent != null)
                    _diffPreview(targetContent, replacementContent, targetFile)
                  else if (codeContent != null && targetFile != null)
                    _codeWritePreview(codeContent, targetFile),

                  // 完整 JSON 收进「技术细节」折叠区，供审计/核对，不干扰主决策。
                  Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
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
                ],
              ),
            ),
          ),
          _buildActions(context, danger, riskColor),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, bool danger, Color riskColor) {
    final buttonPadding = const EdgeInsets.fromLTRB(20, 10, 20, 14);
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.98),
      child: Padding(
        padding: buttonPadding,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      Navigator.pop(context, ToolApproval.reject);
                    },
                    child: const Text(AppStrings.reject),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: riskColor,
                    ),
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      Navigator.pop(context, ToolApproval.allowOnce);
                    },
                    child: const Text(AppStrings.allowOnce),
                  ),
                ),
              ],
            ),
            if (!danger) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        Navigator.pop(context, ToolApproval.allowSession);
                      },
                      child: const Text('仅本次会话'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        Navigator.pop(context, ToolApproval.allowAlways);
                      },
                      child: const Text('始终允许'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _commandPreview(String cmd) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.terminal_rounded, size: 14, color: Color(0xFF89B4FA)),
              SizedBox(width: 6),
              Text('将要执行的指令',
                  style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFFBAC2DE),
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            cmd,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12.5,
              color: Color(0xFFA6E3A1),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _diffPreview(String target, String replacement, String? file) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF181825),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (file != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined,
                      size: 13, color: Color(0xFFBAC2DE)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      file,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFBAC2DE),
                          fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: const Color(0xFFF38BA8).withValues(alpha: 0.15),
            child: Text(
              '- $target',
              style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: Color(0xFFF38BA8),
                  height: 1.35),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: const Color(0xFFA6E3A1).withValues(alpha: 0.15),
            child: Text(
              '+ $replacement',
              style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: Color(0xFFA6E3A1),
                  height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _codeWritePreview(String content, String file) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF181825),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.edit_note_rounded,
                    size: 14, color: Color(0xFF89B4FA)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '写入文件: $file',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFBAC2DE),
                        fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 140),
            padding: const EdgeInsets.all(10),
            child: SingleChildScrollView(
              child: Text(
                content,
                style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: Color(0xFFCDD6F4),
                    height: 1.35),
              ),
            ),
          ),
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
