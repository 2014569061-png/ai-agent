import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../motion/nexus_haptics.dart';
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
    this.allowSessionTrust = true,
    this.allowPersistentTrust = false,
    this.timeout = const Duration(minutes: 5),
    this.onExpired,
    this.onBackgrounded,
  });

  final ToolCall call;
  final ToolRisk risk;

  /// 是否提供「本会话允许」。授权只存在内存，退出应用即失效。
  final bool allowSessionTrust;

  /// 是否提供「始终允许」。会写入持久信任清单，因此默认关闭：
  /// 调用方只应在明确允许长期放行的场景显式打开。
  final bool allowPersistentTrust;
  final Duration timeout;
  final VoidCallback? onExpired;

  /// 审批期间应用被切到后台（或锁屏）时回调。
  ///
  /// 弹窗此时已经不可见，而 Dart 定时器在后台会被冻结，倒计时不会走完 —— 若什么
  /// 都不做，需要审批的工具会在后台一直等下去。调用方应据此改走通知裁决通道
  /// （[ApprovalBridge]），并让本弹窗以 [ToolApproval.reject] 收敛，避免留下一个
  /// 无人可见、又尚未结束的审批。
  final VoidCallback? onBackgrounded;

  @override
  State<ToolApprovalSheet> createState() => _ToolApprovalSheetState();
}

class _ToolApprovalSheetState extends State<ToolApprovalSheet>
    with WidgetsBindingObserver {
  Timer? _countdownTimer;
  Timer? _expiryCloseTimer;
  Duration _remaining = Duration.zero;
  bool _expired = false;

  /// 是否已经把这次审批交给后台通知通道（见 [widget.onBackgrounded]）。
  bool _handedOff = false;

  /// 审批的绝对截止时刻，用于回到前台时校正。
  ///
  /// 展示用的 [_remaining] 仍按 tick 递减，而不是每次 tick 都按墙钟重算：widget
  /// 测试用 fake async 推进定时器，`DateTime.now()` 走的却是真实时钟，若按墙钟
  /// 重算，测试里时间几乎不前进，倒计时永远不会走完。两者结合的效果是：前台按
  /// tick 递减（可测且与真实截止同步），后台定时器被冻结后回到前台按绝对截止
  /// 时刻校正（不撒谎）。
  late DateTime _deadline;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _deadline = DateTime.now().add(widget.timeout);
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
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _expiryCloseTimer?.cancel();
    super.dispose();
  }

  /// 回到前台时按绝对时钟校正一次。
  ///
  /// 应用切到后台、系统冻结 Dart timer 或设备休眠时定时器不再触发，递减值会原地
  /// 停住；而底层等待方（RunController 的审批等待、ApprovalBridge 的 TTL）用的是
  /// 真实时钟。若不校正，用户在"看起来还有时间"时会被静默拒绝。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 审批期间切到后台：弹窗已不可见，且后台期间定时器被冻结，倒计时不会走完。
    // 交给调用方改走通知通道，本弹窗立刻以 reject 收敛。
    //
    // 只看 paused / hidden，不看 inactive：inactive 会在下拉通知栏、来电、系统
    // 权限弹框等「瞬间失焦但又马上回来」的场景触发，据此中止审批会误伤正常流程。
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _handOffToBackground();
      return;
    }
    if (state != AppLifecycleState.resumed || !mounted || _expired) return;
    // 已经交还给后台通道的这次审批不再参与倒计时校正。
    if (_handedOff) return;
    final remaining = _deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _expire();
      return;
    }
    setState(() => _remaining = remaining);
  }

  /// 把不可见的审批交还调用方（转通知通道），并让本弹窗结束等待。
  ///
  /// 未注入 [ToolApprovalSheet.onBackgrounded] 时不改动行为：直接构造本组件的调用
  /// 方（例如无障碍测试）没有接通知通道，擅自 pop 反而会变成一次无提示的静默拒绝。
  void _handOffToBackground() {
    if (_handedOff || _expired || !mounted) return;
    final onBackgrounded = widget.onBackgrounded;
    if (onBackgrounded == null) return;
    _handedOff = true;
    _countdownTimer?.cancel();
    _expiryCloseTimer?.cancel();
    onBackgrounded();
    Navigator.of(context).pop(ToolApproval.reject);
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
    final approvalArguments = Map<String, dynamic>.from(widget.call.arguments)
      ..remove('_approvalDetails')
      ..remove('planId')
      ..remove('previewId');

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
                    label:
                        _expired ? '审批已过期，已自动拒绝' : '审批剩余 ${_formatRemaining()}',
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
                                  ? '审批已过期，请重试任务'
                                  : '审批有效时间 ${_formatRemaining()}',
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
                          child: SelectableText(_prettyJson(approvalArguments),
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
    // 危险级在任何入口都只提供「拒绝 / 本次执行」，不提供任何范围的信任。
    final showSessionTrust = widget.allowSessionTrust && !danger;
    final showPersistentTrust = widget.allowPersistentTrust && !danger;
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
                              NexusHaptics.selection(context);
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
                              NexusHaptics.medium(context);
                              Navigator.pop(context, ToolApproval.allowOnce);
                            },
                      child: const Text('确认执行'),
                    ),
                  ),
                ],
              ),
              // 信任按钮只渲染「当前入口真的能授予」的范围：
              // * 危险级：任何模式都逐次确认，两个按钮都不给；
              // * requiresConfirmation（终端、写文件）：只给会话级授权。持久放行会
              //   绕过 README 里「终端默认逐次确认」的承诺，想长期免打扰应显式改用
              //   「完全访问」模式（一个可随时撤回的全局开关）；
              // * 敏感工具：参数含凭据，同样只给会话级。
              // 此前这里恒为 false（只有 safe 能通过，而 safe 从不弹窗），两个按钮
              // 实际永远不显示，属于不可达的假 UI。
              if (showSessionTrust && !_expired) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          NexusHaptics.selection(context);
                          Navigator.pop(context, ToolApproval.allowSession);
                        },
                        // allowSession 的语义是「本会话内一直允许」。此前写作
                        // 「仅本次允许」，与上排 allowOnce（确认执行）重复，用户
                        // 无法区分两个按钮的差别。
                        child: const Text('本会话允许'),
                      ),
                    ),
                    if (showPersistentTrust) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: () {
                            NexusHaptics.medium(context);
                            Navigator.pop(context, ToolApproval.allowAlways);
                          },
                          child: const Text('始终允许'),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  showPersistentTrust
                      ? '「本会话允许」退出应用后失效；「始终允许」全局持久生效，'
                          '可在「设置 → 工具清单」中撤销。'
                      : '「本会话允许」只在本次应用运行期间生效，重启后需要重新确认。',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.outline,
                  ),
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
