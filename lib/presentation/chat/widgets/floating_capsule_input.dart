import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'package:flutter/services.dart';

import '../../theme/app_tokens.dart';
import '../../../domain/models.dart';
import '../../widgets/immersive_effects_controller.dart';
import '../../widgets/immersive_motion.dart';
import '../../widgets/immersive_surface.dart';

class FloatingCapsuleInput extends StatefulWidget {
  final TextEditingController controller;
  final bool isRunning;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onAttachmentMenu;
  final VoidCallback onCommandMenu;
  final VoidCallback onMcpMenu;
  final VoidCallback onPlanModeToggle;
  final VoidCallback onApprovalModeTap;
  final VoidCallback onTerminalPreview;
  final VoidCallback onEnvSetup;
  final bool planModeEnabled;
  final ApprovalMode approvalMode;
  final VoidCallback? onVoiceToggle;
  final bool isListening;
  final bool hasAttachments;
  // Deprecated properties kept for backward compatibility if used directly
  final String? modelLabel;
  final String? workspaceLabel;
  final VoidCallback? onModelTap;
  final VoidCallback? onWorkspaceTap;

  const FloatingCapsuleInput({
    super.key,
    required this.controller,
    required this.isRunning,
    required this.onSend,
    required this.onStop,
    required this.onAttachmentMenu,
    required this.onCommandMenu,
    required this.onMcpMenu,
    required this.onPlanModeToggle,
    required this.onApprovalModeTap,
    required this.onTerminalPreview,
    required this.onEnvSetup,
    required this.planModeEnabled,
    this.approvalMode = ApprovalMode.ask,
    this.onVoiceToggle,
    this.isListening = false,
    this.hasAttachments = false,
    this.modelLabel,
    this.workspaceLabel,
    this.onModelTap,
    this.onWorkspaceTap,
  });

  @override
  State<FloatingCapsuleInput> createState() => _FloatingCapsuleInputState();
}

class _FloatingCapsuleInputState extends State<FloatingCapsuleInput>
    with SingleTickerProviderStateMixin {
  static const _focusBorder = AppTheme.brandBright;

  bool _showTools = false;
  bool _focused = false;
  final FocusNode _focusNode = FocusNode();

  bool get _canSend =>
      widget.controller.text.trim().isNotEmpty || widget.hasAttachments;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    widget.controller.removeListener(_onTextChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    final now = _focusNode.hasFocus;
    if (now != _focused) setState(() => _focused = now);
  }

  void _onTextChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final effect = ImmersiveEffectsController.resolve(context);
    final foreground =
        isDark ? AppTheme.darkSemantic.textPrimary : AppTheme.textPrimary;
    final bottomPadding = MediaQuery.viewInsetsOf(context).bottom > 0
        ? 8.0
        : MediaQuery.paddingOf(context).bottom + 8.0;

    final input = AnimatedPadding(
      duration: AppTokens.durationBase,
      curve: AppTokens.curveStandard,
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 2, 12, 0),
        constraints: const BoxConstraints(minHeight: 64),
        child: ImmersiveSurface(
          level: ImmersiveMaterialLevel.thick,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: _focused && ImmersiveEffectsController.glowEnabled(effect)
                  ? Border.all(color: _focusBorder, width: 1)
                  : null,
            ),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 0),
                    child: TextField(
                      focusNode: _focusNode,
                      controller: widget.controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      onTapOutside: (_) => _focusNode.unfocus(),
                      decoration: const InputDecoration(
                        hintText: '发送消息……',
                        hintStyle: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 16),
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        filled: false,
                        contentPadding: EdgeInsets.symmetric(vertical: 4),
                      ),
                      style: TextStyle(
                          color: foreground, fontSize: 16, height: 1.3),
                    ),
                  ),
                  ImmersiveMotion.expand(
                    child: _showTools ? _toolsRow : const SizedBox.shrink(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Row(
                      children: [
                        _ToolButton(
                          icon: _showTools
                              ? Icons.expand_less_rounded
                              : Icons.add_rounded,
                          tooltip: _showTools ? '收起工具' : '更多工具',
                          onTap: () => setState(() => _showTools = !_showTools),
                        ),
                        if (widget.onVoiceToggle != null)
                          _ToolButton(
                            icon: widget.isListening
                                ? Icons.mic_rounded
                                : Icons.mic_none_rounded,
                            tooltip: widget.isListening ? '正在聆听，点击停止' : '语音输入',
                            color: widget.isListening ? AppTheme.danger : null,
                            onTap: widget.onVoiceToggle!,
                          ),
                        _ToolButton(
                          icon: widget.approvalMode == ApprovalMode.ask
                              ? Icons.verified_user_outlined
                              : Icons.shield_outlined,
                          tooltip: _approvalLabel(widget.approvalMode),
                          color: widget.approvalMode == ApprovalMode.fullAccess
                              ? AppTheme.warning
                              : null,
                          onTap: widget.onApprovalModeTap,
                        ),
                        const Spacer(),
                        Semantics(
                          label: widget.isRunning
                              ? '停止生成'
                              : (_canSend ? '发送' : '发送(不可用)'),
                          child: GestureDetector(
                            onTap: (widget.isRunning || _canSend)
                                ? () {
                                    HapticFeedback.mediumImpact();
                                    if (widget.isRunning) {
                                      widget.onStop();
                                    } else {
                                      widget.onSend();
                                    }
                                  }
                                : null,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: widget.isRunning
                                    ? null
                                    : (_canSend
                                        ? const LinearGradient(
                                            colors: [
                                              AppTheme.brandGradientStart,
                                              AppTheme.brandGradientEnd
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          )
                                        : null),
                                color: widget.isRunning
                                    ? AppTheme.danger
                                    : (_canSend
                                        ? null
                                        : theme.colorScheme
                                            .surfaceContainerHighest),
                                shape: BoxShape.circle,
                                boxShadow: _canSend && !widget.isRunning
                                    ? [
                                        BoxShadow(
                                          color: AppTheme.brandGradientEnd
                                              .withValues(alpha: 0.4),
                                          blurRadius: 12,
                                          spreadRadius: 2,
                                        )
                                      ]
                                    : null,
                              ),
                              child: widget.isRunning
                                  ? const Icon(Icons.stop_rounded,
                                      color: Colors.white, size: 20)
                                  : Icon(Icons.arrow_upward_rounded,
                                      color: _canSend
                                          ? Colors.white
                                          : theme.colorScheme.onSurface
                                              .withValues(alpha: 0.3),
                                      size: 20),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return input;
  }

  Widget get _toolsRow => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: _ToolButton(
                  icon: Icons.add_circle_outline_rounded,
                  tooltip: '添加附件',
                  onTap: widget.onAttachmentMenu),
            ),
            Expanded(
              child: _ToolButton(
                  icon: Icons.keyboard_command_key_rounded,
                  tooltip: '命令库',
                  onTap: widget.onCommandMenu),
            ),
            Expanded(
              child: _ToolButton(
                  icon: Icons.widgets_outlined,
                  tooltip: '工具与 MCP',
                  onTap: widget.onMcpMenu),
            ),
            Expanded(
              child: _ToolButton(
                  icon: widget.planModeEnabled
                      ? Icons.front_hand_rounded
                      : Icons.pan_tool_alt_rounded,
                  tooltip: widget.planModeEnabled ? '关闭计划模式' : '开启计划模式',
                  color: widget.planModeEnabled ? AppTheme.warning : null,
                  onTap: widget.onPlanModeToggle),
            ),
            Expanded(
              child: _ToolButton(
                  icon: Icons.terminal_rounded,
                  tooltip: '终端预览',
                  onTap: widget.onTerminalPreview),
            ),
            Expanded(
              child: _ToolButton(
                  icon: Icons.build_circle_outlined,
                  tooltip: '开发环境',
                  onTap: widget.onEnvSetup),
            ),
          ],
        ),
      );

  String _approvalLabel(ApprovalMode mode) => switch (mode) {
        ApprovalMode.ask => '审批：询问',
        ApprovalMode.autoSafe => '审批：自动批准低风险',
        ApprovalMode.fullAccess => '审批：完全访问',
      };
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const _ToolButton(
      {required this.icon,
      required this.tooltip,
      required this.onTap,
      this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon,
            color: color ?? theme.colorScheme.onSurfaceVariant, size: 22),
        onPressed: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
