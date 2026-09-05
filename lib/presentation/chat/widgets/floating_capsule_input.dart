import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_tokens.dart';
import '../../widgets/immersive_effects_controller.dart';
import '../../widgets/immersive_motion.dart';
import '../../widgets/immersive_surface.dart';

/// 底部对话输入框：实心深色背景 + 一行文本区 + 一行工具栏。
/// 默认高度 104，圆角 22，背景 #172132，边框白 10%。
class FloatingCapsuleInput extends StatefulWidget {
  final TextEditingController controller;
  final bool isRunning;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onAttachmentMenu;
  final VoidCallback onCommandMenu;
  final VoidCallback onMcpMenu;
  final VoidCallback onPlanModeToggle;
  final VoidCallback onTerminalPreview;
  final bool planModeEnabled;
  final VoidCallback? onVoiceToggle;
  final bool isListening;
  final String? modelLabel;
  final String? workspaceLabel;
  final VoidCallback? onModelTap;
  final VoidCallback? onWorkspaceTap;

  /// 是否存在待发送附件；存在时即使无文本也允许发送（文档 7.4）。
  final bool hasAttachments;

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
    required this.onTerminalPreview,
    required this.planModeEnabled,
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
  static const _focusBorder = Color(0xFF2F81F7);

  bool _showTools = false;
  bool _focused = false;
  final FocusNode _focusNode = FocusNode();

  /// 输入非空或存在附件时才能发送（文档 7.4 / 7.5）。
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
        isDark ? const Color(0xFFEDF1F8) : const Color(0xFF1E293B);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    final input = AnimatedPadding(
      duration: AppTokens.durationBase,
      curve: AppTokens.curveStandard,
      padding: EdgeInsets.only(bottom: keyboardInset > 0 ? keyboardInset : 0),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        constraints: const BoxConstraints(minHeight: 82),
        child: ImmersiveSurface(
          level: ImmersiveMaterialLevel.ultraThick,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: _focused && ImmersiveEffectsController.glowEnabled(effect)
                  ? Border.all(color: _focusBorder, width: 1)
                  : null,
            ),
        // 多行增高 / 发送后回落均在此做柔和的高度过渡（文档 10：180~220ms）。
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
                child: TextField(
                  focusNode: _focusNode,
                  controller: widget.controller,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  onTapOutside: (_) => _focusNode.unfocus(),
                  decoration: const InputDecoration(
                    hintText: '发送消息……',
                    hintStyle:
                        TextStyle(color: Color(0xFF6F7B8F), fontSize: 17),
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  style:
                      TextStyle(color: foreground, fontSize: 17, height: 1.35),
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
                    if (widget.modelLabel != null &&
                        widget.modelLabel!.trim().isNotEmpty)
                      Flexible(
                        child: _ContextPill(
                          icon: Icons.auto_awesome_rounded,
                          label: widget.modelLabel!,
                          onTap: widget.onModelTap,
                        ),
                      ),
                    if (widget.workspaceLabel != null &&
                        widget.workspaceLabel!.trim().isNotEmpty)
                      Flexible(
                        child: _ContextPill(
                          icon: Icons.folder_open_outlined,
                          label: widget.workspaceLabel!,
                          onTap: widget.onWorkspaceTap,
                        ),
                      ),
                    if (widget.onVoiceToggle != null)
                      _ToolButton(
                        icon: widget.isListening
                            ? Icons.mic_rounded
                            : Icons.mic_none_rounded,
                        tooltip: widget.isListening ? '正在聆听，点击停止' : '语音输入',
                        color:
                            widget.isListening ? const Color(0xFFDC2626) : null,
                        onTap: widget.onVoiceToggle!,
                      ),
                    if (widget.planModeEnabled)
                      _ToolButton(
                        icon: Icons.front_hand_rounded,
                        tooltip: '计划审批模式已开启',
                        color: const Color(0xFFF59E0B),
                        onTap: widget.onPlanModeToggle,
                      ),
                    const Spacer(),
                    GestureDetector(
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
                                      colors: [Color(0xFF4C8DFF), Color(0xFF9333EA)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null),
                          color: widget.isRunning
                              ? const Color(0xFFDC2626)
                              : (_canSend ? null : theme.colorScheme.surfaceContainerHighest),
                          shape: BoxShape.circle,
                          boxShadow: _canSend && !widget.isRunning
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF9333EA).withValues(alpha: 0.4),
                                    blurRadius: 12,
                                    spreadRadius: 2,
                                  )
                                ]
                              : null,
                        ),
                        child: Icon(
                            widget.isRunning
                                ? Icons.stop_rounded
                                : Icons.arrow_upward_rounded,
                            color: _canSend || widget.isRunning 
                                ? Colors.white
                                : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                            size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          ), // AnimatedSize
        ), // inner Container
        ), // ImmersiveSurface
      ), // outer Container
    ); // AnimatedPadding
    return input;
  }

  Widget get _toolsRow => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
        child: Row(
          children: [
            _ToolButton(
                icon: Icons.add_circle_outline_rounded,
                tooltip: '添加附件',
                onTap: widget.onAttachmentMenu),
            _ToolButton(
                icon: Icons.keyboard_command_key_rounded,
                tooltip: '命令库',
                onTap: widget.onCommandMenu),
            const Spacer(),
            _ToolButton(
                icon: Icons.widgets_outlined,
                tooltip: '工具与 MCP',
                onTap: widget.onMcpMenu),
            _ToolButton(
                icon: widget.planModeEnabled
                    ? Icons.front_hand_rounded
                    : Icons.pan_tool_alt_rounded,
                tooltip: widget.planModeEnabled ? '关闭计划模式' : '开启计划模式',
                color: widget.planModeEnabled ? const Color(0xFFF59E0B) : null,
                onTap: widget.onPlanModeToggle),
            _ToolButton(
                icon: Icons.terminal_rounded,
                tooltip: '终端预览',
                onTap: widget.onTerminalPreview),
          ],
        ),
      );
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
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, color: color ?? theme.colorScheme.onSurfaceVariant, size: 22),
      onPressed: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      padding: EdgeInsets.zero,
    );
  }
}

class _ContextPill extends StatelessWidget {
  const _ContextPill({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (onTap != null)
                  Icon(Icons.keyboard_arrow_down_rounded,
                      size: 16, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
