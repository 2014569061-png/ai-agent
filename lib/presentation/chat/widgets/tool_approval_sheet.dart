import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_tokens.dart';

import '../../../domain/models.dart';
import '../../../application/approval_policy.dart';
import '../../l10n/app_strings.dart';
import '../../../infrastructure/tools/tool_humanizer.dart';
import '../../widgets/nexus_disclosure.dart';

/// 工具审批弹窗主体：按风险展示人性化摘要与关键参数，「技术细节」折叠完整 JSON，
/// 按钮返回 [ToolApproval] 决策由调用方处理（记录信任/审计）。
class ToolApprovalSheet extends StatefulWidget {
  const ToolApprovalSheet({
    super.key,
    required this.call,
    required this.risk,
    this.allowPersistentTrust = true,
    this.timeout = const Duration(minutes: 5),
    this.onExpired,
  });

  final ToolCall call;
  final ToolRisk risk;
  final bool allowPersistentTrust;
  final Duration timeout;
  final VoidCallback? onExpired;

  @override
  State<ToolApprovalSheet> createState() => _ToolApprovalSheetState();
}

class _ToolApprovalSheetState extends State<ToolApprovalSheet> {
  Timer? _countdownTimer;
  Timer? _expiryCloseTimer;
  Duration _remaining = Duration.zero;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _remaining = widget.timeout;
    _countdownTimer = Timer.periodic(
      approvalUiCountdownTick,
      (_) => _updateCountdown(),
    );
    if (widget.timeout <= Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _expire());
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _expiryCloseTimer?.cancel();
    super.dispose();
  }

  void _updateCountdown() {
    if (!mounted || _expired) return;
    final remaining = _remaining - approvalUiCountdownTick;
    if (remaining <= Duration.zero) {
      _expire();
      return;
    }
    setState(() => _remaining = remaining);
  }

  void _expire() {
    if (!mounted || _expired) return;
    _countdownTimer?.cancel();
    setState(() {
      _remaining = Duration.zero;
      _expired = true;
    });
    widget.onExpired?.call();
    _expiryCloseTimer = Timer(approvalUiExpiryNotice, () {
      if (mounted) Navigator.of(context).pop(ToolApproval.reject);
    });
  }

  String _formatRemaining() {
    final totalSeconds = _remaining.inSeconds.clamp(0, 599999).toInt();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final danger = widget.risk == ToolRisk.dangerous;
    final riskColor = danger ? AppTheme.danger : AppTheme.warning;
    final riskLabel =
        danger ? AppStrings.dangerOperation : AppStrings.requiresConfirmation;
    final humanizer = const ToolHumanizer();
    final summary = humanizer.summaryOf(widget.call);
    final paramLines = humanizer.paramLines(widget.call);

    final command = (widget.call.arguments['CommandLine'] ??
            widget.call.arguments['command'] ??
            widget.call.arguments['cmd'])
        ?.toString();
    final targetContent = widget.call.arguments['TargetContent']?.toString();
    final replacementContent =
        widget.call.arguments['ReplacementContent']?.toString();
    final targetFile = (widget.call.arguments['TargetFile'] ??
            widget.call.arguments['path'] ??
            widget.call.arguments['file'])
        ?.toString();
    final codeContent = (widget.call.arguments['CodeContent'] ??
            widget.call.arguments['content'])
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
                      child: Semantics(
                        label: riskLabel,
                        child: Icon(
                            danger
                                ? Icons.warning_amber_rounded
                                : Icons.shield_outlined,
                            color: riskColor),
                      ),
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
                  Semantics(
                    liveRegion: true,
                    label: _expired
                        ? '瀹℃壒宸茶繃鏈燂紝宸茶嚜鍔ㄦ嫆缁?'
                        : '瀹℃壒鍓╀綑 ${_formatRemaining()}',
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color:
                            riskColor.withValues(alpha: _expired ? 0.16 : 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _expired
                                ? Icons.timer_off_outlined
                                : Icons.timer_outlined,
                            size: 16,
                            color: riskColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _expired
                                  ? '瀹℃壒宸茶繃鏈燂紝璇锋敹鍒伴噸璇曚换鍔?'
                                  : '瀹℃壒鏈夋晥鏃堕棿 ${_formatRemaining()}',
                              style: TextStyle(
                                color: riskColor,
                                fontSize: AppTokens.fontSizeFootnote,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                        color: riskColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: riskColor.withValues(alpha: 0.4))),
                    child: Row(children: [
                      ExcludeSemantics(
                        child: Icon(Icons.build_circle_outlined,
                            size: 16, color: riskColor),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(widget.call.name,
                              style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w500))),
                      Text(riskLabel,
                          style: TextStyle(
                              color: riskColor,
                              fontWeight: FontWeight.w500,
                              fontSize: AppTokens.fontSizeFootnote)),
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
                  NexusDisclosure(
                    headerPadding: EdgeInsets.zero,
                    contentPadding: const EdgeInsets.only(top: 6),
                    title: Text('技术细节',
                        style: TextStyle(
                            fontSize: AppTokens.fontSizeFootnote,
                            color: Theme.of(context).colorScheme.outline)),
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 160),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10)),
                      child: SingleChildScrollView(
                          child: SelectableText(
                              _prettyJson(widget.call.arguments),
                              style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: AppTokens.fontSizeFootnote))),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final buttonPadding = const EdgeInsets.fromLTRB(20, 10, 20, 14);
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.02),
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: buttonPadding,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      autofocus: true,
                      onPressed: _expired
                          ? null
                          : () {
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
                      onPressed: _expired
                          ? null
                          : () {
                              HapticFeedback.mediumImpact();
                              Navigator.pop(context, ToolApproval.allowOnce);
                            },
                      child: const Text('确认执行'),
                    ),
                  ),
                ],
              ),
              if (!danger && widget.allowPersistentTrust && !_expired) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          Navigator.pop(context, ToolApproval.allowSession);
                        },
                        child: const Text('仅本次允许'),
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
      ),
    );
  }

  Widget _commandPreview(String cmd) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.terminalBg,
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              ExcludeSemantics(
                child: Icon(Icons.terminal_rounded,
                    size: 14, color: AppPalette.brand),
              ),
              SizedBox(width: 6),
              Text('将要执行的指令',
                  style: TextStyle(
                      fontSize: AppTokens.fontSizeBadge,
                      color: AppPalette.darkTextMuted,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            cmd,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12.5,
              color: AppPalette.diffAddedText,
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
        color: AppPalette.terminalBg,
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
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
                  const ExcludeSemantics(
                    child: Icon(Icons.description_outlined,
                        size: 13, color: AppPalette.darkTextMuted),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      file,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: AppTokens.fontSizeBadge,
                          color: AppPalette.darkTextMuted,
                          fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: AppPalette.diffRemovedBg,
            child: Text(
              '- $target',
              style: const TextStyle(
                  fontSize: AppTokens.fontSizeFootnote,
                  fontFamily: 'monospace',
                  color: AppPalette.diffRemovedText,
                  height: 1.35),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: AppPalette.diffAddedBg,
            child: Text(
              '+ $replacement',
              style: const TextStyle(
                  fontSize: AppTokens.fontSizeFootnote,
                  fontFamily: 'monospace',
                  color: AppPalette.diffAddedText,
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
        color: AppPalette.terminalBg,
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
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
                const ExcludeSemantics(
                  child: Icon(Icons.edit_note_rounded,
                      size: 14, color: AppPalette.brand),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '写入文件: $file',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: AppTokens.fontSizeBadge,
                        color: AppPalette.darkTextMuted,
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
                    fontSize: AppTokens.fontSizeFootnote,
                    fontFamily: 'monospace',
                    color: AppPalette.darkText,
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
