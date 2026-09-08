import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/models.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/floating_toast.dart';
import '../../widgets/immersive_surface.dart';
import 'input_tool_grid_sheet.dart';

/// 悬浮胶囊输入框 (FloatingCapsuleInput)
/// 严格依据 NEXUS UI 设计优化规范重构：
/// 1. 一级常驻动作：附件、计划模式开关、审批策略、发送/停止。
/// 2. 二级动作收纳进“更多工具”：提示词库、MCP 服务、终端预览、开发环境、语音。
/// 3. 计划模式开启时展示顶部提示条：“计划模式已开启 · 首轮需要确认”。
/// 4. 生成中在顶部展示当前阶段提示。
/// 5. 空输入点击发送时给予轻量提示，避免无反馈。
class FloatingCapsuleInput extends StatefulWidget {
  final TextEditingController controller;
  final bool isRunning;
  final String? runningStage;
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
  final int attachmentCount;
  final VoidCallback? onOpenDashboard;

  // 兼容性预留字段
  final String? modelLabel;
  final String? workspaceLabel;
  final VoidCallback? onModelTap;
  final VoidCallback? onWorkspaceTap;

  const FloatingCapsuleInput({
    super.key,
    required this.controller,
    required this.isRunning,
    this.runningStage,
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
    this.attachmentCount = 0,
    this.onOpenDashboard,
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

  bool _focused = false;
  final FocusNode _focusNode = FocusNode();

  bool get _canSend =>
      widget.controller.text.trim().isNotEmpty || widget.hasAttachments;

  void _openToolsSheet() {
    _focusNode.unfocus();
    InputToolGridSheet.show(
      context,
      onCommandMenu: widget.onCommandMenu,
      onMcpMenu: widget.onMcpMenu,
      onTerminalPreview: widget.onTerminalPreview,
      onEnvSetup: widget.onEnvSetup,
      onVoiceToggle: widget.onVoiceToggle,
      isListening: widget.isListening,
      onOpenDashboard: widget.onOpenDashboard,
      planModeEnabled: widget.planModeEnabled,
      onPlanModeToggle: widget.onPlanModeToggle,
      approvalMode: widget.approvalMode,
      onApprovalModeTap: widget.onApprovalModeTap,
    );
  }

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChange);
  }

  @override
  void didUpdateWidget(covariant FloatingCapsuleInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller.text.isNotEmpty &&
        oldWidget.controller.text.isEmpty &&
        !widget.isRunning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_focusNode.hasFocus) {
          _focusNode.requestFocus();
        }
      });
    }
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
    final foreground =
        isDark ? AppTheme.darkSemantic.textPrimary : AppTheme.textPrimary;
    final bottomPadding = MediaQuery.viewInsetsOf(context).bottom > 0
        ? 8.0
        : MediaQuery.paddingOf(context).bottom + 8.0;

    return AnimatedPadding(
      duration: AppTokens.durationBase,
      curve: AppTokens.curveStandard,
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 2, 12, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 状态指示条（计划模式提示 / 生成阶段提示）
            if (widget.isRunning && widget.runningStage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.brandBright.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppTheme.brandBright.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.runningStage!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.brandBright,
                      ),
                    ),
                  ],
                ),
              )
            else if (widget.planModeEnabled && !widget.isRunning)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppTheme.warning.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.front_hand_rounded,
                      size: 11,
                      color: AppTheme.warning,
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      '计划模式已开启 · 首轮执行前需确认',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.warning,
                      ),
                    ),
                  ],
                ),
              ),

            // 主胶囊输入面
            ImmersiveSurface(
              level: ImmersiveMaterialLevel.thick,
              borderRadius: BorderRadius.circular(22),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: _focused
                      ? Border.all(color: _focusBorder.withValues(alpha: 0.8), width: 1.2)
                      : null,
                ),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 输入文本域
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 10, 0),
                        child: TextField(
                          focusNode: _focusNode,
                          controller: widget.controller,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.newline,
                          onTapOutside: (_) => _focusNode.unfocus(),
                          decoration: const InputDecoration(
                            hintText: '输入任务或问题，Shift+Enter 换行…',
                            hintStyle: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 15,
                            ),
                            border: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            filled: false,
                            contentPadding: EdgeInsets.symmetric(vertical: 4),
                          ),
                          style: TextStyle(
                            color: foreground,
                            fontSize: 15,
                            height: 1.35,
                          ),
                        ),
                      ),

                      // 底部一级常驻动作行
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                        child: Row(
                          children: [
                            // 1. 工作台小工具面板呼出按钮 (8 宫格面板)
                            _ToolButton(
                              icon: Icons.add_circle_outline_rounded,
                              tooltip: '更多工具',
                              color: theme.colorScheme.primary,
                              onTap: _openToolsSheet,
                            ),

                            // 2. 附件按钮
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                _ToolButton(
                                  icon: Icons.attach_file_rounded,
                                  tooltip: '添加附件',
                                  color: widget.hasAttachments
                                      ? theme.colorScheme.primary
                                      : null,
                                  onTap: widget.onAttachmentMenu,
                                ),
                                if (widget.hasAttachments)
                                  Positioned(
                                    right: 4,
                                    top: 4,
                                    child: Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                              ],
                            ),

                            // 3. 计划模式即时指示胶囊 (若开启则醒目高亮呈现，点击可切换)
                            if (widget.planModeEnabled) ...[
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: widget.onPlanModeToggle,
                                borderRadius: BorderRadius.circular(999),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color:
                                        AppTheme.warning.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: AppTheme.warning
                                          .withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.front_hand_rounded,
                                          size: 11, color: AppTheme.warning),
                                      SizedBox(width: 4),
                                      Text(
                                        '计划',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.warning,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],

                            const Spacer(),

                            // 4. 发送 / 停止生成按钮 (一级常驻)
                            Semantics(
                              label: widget.isRunning
                                  ? '停止生成'
                                  : (_canSend ? '发送' : '发送(不可用)'),
                              child: GestureDetector(
                                onTap: () {
                                  if (widget.isRunning) {
                                    HapticFeedback.mediumImpact();
                                    widget.onStop();
                                  } else if (_canSend) {
                                    HapticFeedback.mediumImpact();
                                    widget.onSend();
                                  } else {
                                    HapticFeedback.selectionClick();
                                    FloatingToast.show(
                                        context, '请输入任务内容或添加附件');
                                  }
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  width: 40,
                                  height: 40,
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
                                                .surfaceContainerHighest
                                                .withValues(alpha: 0.6)),
                                    shape: BoxShape.circle,
                                    boxShadow: _canSend && !widget.isRunning
                                        ? [
                                            BoxShadow(
                                              color: AppTheme.brandGradientEnd
                                                  .withValues(alpha: 0.35),
                                              blurRadius: 10,
                                              spreadRadius: 1,
                                            )
                                          ]
                                        : null,
                                  ),
                                  child: widget.isRunning
                                      ? const Icon(Icons.stop_rounded,
                                          color: Colors.white, size: 20)
                                      : Icon(
                                          Icons.arrow_upward_rounded,
                                          color: _canSend
                                              ? Colors.white
                                              : theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.35),
                                          size: 20,
                                        ),
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
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
      color: color ?? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
      onPressed: onTap,
    );
  }
}
