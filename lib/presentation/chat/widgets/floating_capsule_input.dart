import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../domain/models.dart';
import '../../motion/nexus_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/nexus_execution_status.dart';
import '../../widgets/glass_surface.dart';

/// 首页输入区（对标 DeepSeek App）。
///
/// 结构：
///   外层 24px 大圆角 + surface 底色，聚焦时描边转 brand
///   ├─ 输入行：最小高 44px，占位符「发消息」
///   └─ 操作行：高 48px，左右两端对齐
///        ├─ 左：模式与审批策略的圆形磁贴（26dp 图标 + 选中态品牌色底）
///        └─ 右：代码块快捷 +「＋」圆形描边磁贴 + 尾键磁贴
///           （生成中 = 停止 / 有内容 = 发送 / 空输入 = 置灰发送，不可点）
///
/// 磁贴 = 26dp 圆形图标按钮（触控区仍为 48x48）：文案不落在磁贴上，
/// 避免中英文长度差异把小屏输入区撑开，可读名称保留在语义标签与 tooltip 中。
class FloatingCapsuleInput extends StatefulWidget {
  const FloatingCapsuleInput({
    super.key,
    required this.controller,
    required this.isRunning,
    this.runningStage,
    required this.onSend,
    required this.onStop,
    this.onPause,
    this.onResume,
    required this.onAttachmentMenu,
    this.modeLabel = '聊天',
    this.onModeTap,
    this.approvalMode = ApprovalMode.ask,
    this.onApprovalModeTap,
    this.planModeEnabled = false,
    this.hasAttachments = false,
    this.hasAttachmentsListenable,
    this.isAttachmentExpanded = false,
    this.attachmentExpandedListenable,
    this.isPaused = false,
    this.glassIntensity = GlassIntensity.liquid,
  });

  final TextEditingController controller;
  final bool isRunning;
  final String? runningStage;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  /// 「＋」按钮：附件与更多工具
  final VoidCallback onAttachmentMenu;

  final String modeLabel;
  final VoidCallback? onModeTap;
  final ApprovalMode approvalMode;
  final VoidCallback? onApprovalModeTap;

  final bool planModeEnabled;
  final bool hasAttachments;
  final ValueListenable<bool>? hasAttachmentsListenable;
  final bool isAttachmentExpanded;
  final ValueListenable<bool>? attachmentExpandedListenable;
  final bool isPaused;
  final GlassIntensity glassIntensity;

  @override
  State<FloatingCapsuleInput> createState() => _FloatingCapsuleInputState();
}

class _FloatingCapsuleInputState extends State<FloatingCapsuleInput> {
  late final ValueNotifier<bool> _focused;
  final FocusNode _focusNode = FocusNode();

  String _approvalModeLabel(ApprovalMode mode) => switch (mode) {
        ApprovalMode.ask => '每次询问',
        ApprovalMode.autoSafe => '自动低风险',
        ApprovalMode.fullAccess => '完全访问',
      };

  @override
  void initState() {
    super.initState();
    _focused = ValueNotifier(false);
    _focusNode.addListener(_onFocusChange);
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
    _focusNode.dispose();
    _focused.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    final now = _focusNode.hasFocus;
    if (now != _focused.value) _focused.value = now;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final textFaint =
        isDark ? AppPalette.darkTextFaint : AppPalette.lightTextMuted;
    final surface = isDark ? AppPalette.darkSurface : AppPalette.lightSurface;

    final bottomPadding = MediaQuery.viewInsetsOf(context).bottom > 0
        ? 8.0
        : MediaQuery.paddingOf(context).bottom + 8.0;

    return AnimatedPadding(
      duration: AppTokens.durationBase,
      curve: AppTokens.curveStandard,
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 运行状态提示（仅生成 / 计划模式时出现，首页态不显示）
            _buildStatusLine(textMuted),

            // 外层容器：20px 圆角，聚焦时描边转 brand
            Builder(
              builder: (context) {
                final inputCard = Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 输入行：最小高 44px
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                          minHeight: AppTokens.kControlHeight),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextField(
                          focusNode: _focusNode,
                          controller: widget.controller,
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: TextInputAction.newline,
                          onTapOutside: (_) => _focusNode.unfocus(),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            height: 1.6,
                            color: textColor,
                          ),
                          decoration: InputDecoration(
                            hintText: widget.isRunning
                                ? (widget.isPaused ? '补充要求后继续' : '补充要求')
                                : '发消息',
                            hintStyle: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              color: textFaint,
                            ),
                            isDense: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 6),

                    // 操作行：高 48px，左右两端对齐（左2靠左，右3靠右）
                    SizedBox(
                      height: 48,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 左：模式 + 审批策略（圆形磁贴，靠左）
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _ModeTile(
                                icon: Icons.tune_rounded,
                                semanticLabel: '${widget.modeLabel}模式',
                                selected: true,
                                onTap: widget.onModeTap,
                              ),
                              if (widget.onApprovalModeTap != null)
                                _ModeTile(
                                  icon: widget.approvalMode ==
                                          ApprovalMode.fullAccess
                                      ? Icons.shield_outlined
                                      : Icons.verified_user_outlined,
                                  semanticLabel:
                                      _approvalModeLabel(widget.approvalMode),
                                  selected: widget.approvalMode ==
                                      ApprovalMode.fullAccess,
                                  onTap: widget.onApprovalModeTap,
                                ),
                            ],
                          ),
                          // 右：代码块快捷 +「＋」附件 + 尾键（发送/停止/置灰发送，靠右）
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _CircleIconButton(
                                icon: Icons.code_rounded,
                                iconSize: 15,
                                tooltip: '插入代码块',
                                semanticLabel: '插入代码块',
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  final text = widget.controller.text;
                                  final sel = widget.controller.selection;
                                  const snippet = '```\n\n```';
                                  if (sel.isValid && sel.start >= 0) {
                                    final newText = text.replaceRange(
                                        sel.start, sel.end, snippet);
                                    widget.controller.value = TextEditingValue(
                                      text: newText,
                                      selection: TextSelection.collapsed(
                                          offset: sel.start + 4),
                                    );
                                  } else {
                                    widget.controller.text = '$text\n$snippet';
                                  }
                                },
                              ),
                              _buildAttachmentButton(),
                              _buildTrailingActionListenable(
                                  textFaint, isDark),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );

                if (widget.glassIntensity == GlassIntensity.flat) {
                  return _withFocusRing(
                    radius: BorderRadius.circular(AppTokens.radiusComposer),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusComposer),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : const Color(0xFFE2E8F0),
                          width: 0.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isDark
                                ? AppPalette.darkShadowAmbient
                                : AppPalette.lightShadowAmbient,
                            blurRadius: AppTokens.shadowFloatingBlur,
                            offset: AppTokens.shadowFloatingOffset,
                          ),
                        ],
                      ),
                      child: inputCard,
                    ),
                  );
                }

                return _withFocusRing(
                  radius: BorderRadius.circular(AppTokens.radiusComposer),
                  child: GlassSurface(
                    role: GlassRole.control,
                    variant: GlassVariant.regular,
                    intensity: widget.glassIntensity,
                    borderRadius:
                        BorderRadius.circular(AppTokens.radiusComposer),
                    blurSigma: 28,
                    refraction: 20,
                    edgeWidth: 24,
                    gloss: 0.55,
                    borderColor: isDark
                        ? const Color(0x38FFFFFF)
                        : const Color(0x90FFFFFF),
                    borderWidth: 1.0,
                    tint: isDark
                        ? AppPalette.darkSurface.withValues(alpha: 0.36)
                        : AppPalette.lightCanvas.withValues(alpha: 0.32),
                    padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? const Color(0x60000000)
                            : const Color(0x1A1E3A8A),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                    child: inputCard,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _withFocusRing({
    required BorderRadius radius,
    required Widget child,
  }) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder<bool>(
              valueListenable: _focused,
              builder: (context, focused, _) => DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: focused
                      ? Border.all(color: AppPalette.brand, width: 1.4)
                      : null,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAttachmentButton() {
    Widget buildButton(bool expanded) => _CircleIconButton(
          icon: expanded ? Icons.close_rounded : Icons.add_rounded,
          iconSize: 16,
          tooltip: expanded ? '收起附件面板' : '添加附件或更多工具',
          semanticLabel: expanded ? '收起附件面板' : '添加附件或更多工具',
          onTap: widget.onAttachmentMenu,
        );

    final listenable = widget.attachmentExpandedListenable;
    if (listenable == null) return buildButton(widget.isAttachmentExpanded);
    return ValueListenableBuilder<bool>(
      valueListenable: listenable,
      builder: (context, expanded, _) => buildButton(expanded),
    );
  }

  /// 生成中 → 停止键；有内容 → 发送键；空输入 → 置灰的发送键（不可点）。
  /// 使用 AnimatedSwitcher 进行 150ms 状态平滑过渡。
  Widget _buildTrailingAction(Color textFaint, bool isDark) {
    return _buildTrailingActionForAttachments(
        textFaint, isDark, widget.hasAttachments);
  }

  Widget _buildTrailingActionListenable(Color textFaint, bool isDark) {
    final listenable = widget.hasAttachmentsListenable;
    if (listenable == null) {
      return ValueListenableBuilder<TextEditingValue>(
        valueListenable: widget.controller,
        builder: (context, _, __) => _buildTrailingAction(textFaint, isDark),
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: listenable,
      builder: (context, hasAttachments, _) =>
          ValueListenableBuilder<TextEditingValue>(
        valueListenable: widget.controller,
        builder: (context, _, __) =>
            _buildTrailingActionForAttachments(
                textFaint, isDark, hasAttachments),
      ),
    );
  }

  Widget _buildTrailingActionForAttachments(
      Color textFaint, bool isDark, bool hasAttachments) {
    final canSend = widget.controller.text.trim().isNotEmpty || hasAttachments;
    final Widget button;
    if (widget.isRunning && canSend) {
      button = _FilledCircleButton(
        key: const ValueKey('trailing_action_follow_up'),
        color: AppPalette.brand,
        icon: Icons.playlist_add_rounded,
        tooltip: '补充要求',
        semanticLabel: '补充要求',
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.onSend();
        },
      );
    } else if (widget.isRunning && widget.isPaused) {
      button = _FilledCircleButton(
        key: const ValueKey('trailing_action_resume'),
        color: AppPalette.brand,
        icon: Icons.play_arrow_rounded,
        tooltip: '继续',
        semanticLabel: '继续',
        onTap: () {
          HapticFeedback.mediumImpact();
          (widget.onResume ?? widget.onStop)();
        },
      );
    } else if (widget.isRunning) {
      button = _FilledCircleButton(
        key: const ValueKey('trailing_action_pause'),
        color: AppPalette.warning,
        icon: Icons.pause_rounded,
        tooltip: '暂停',
        semanticLabel: '暂停',
        onTap: () {
          HapticFeedback.mediumImpact();
          (widget.onPause ?? widget.onStop)();
        },
      );
    } else if (canSend) {
      button = _FilledCircleButton(
        key: const ValueKey('trailing_action_send_active'),
        color: AppPalette.brand,
        icon: Icons.arrow_upward_rounded,
        tooltip: '发送',
        semanticLabel: '发送',
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.onSend();
        },
      );
    } else {
      button = _FilledCircleButton(
        key: const ValueKey('trailing_action_send_disabled'),
        color:
            isDark ? AppPalette.darkSurfaceHover : AppPalette.lightSurfaceHover,
        icon: Icons.arrow_upward_rounded,
        iconColor: textFaint,
        tooltip: '发送',
        semanticLabel: '发送（请输入内容）',
        onTap: null,
      );
    }

    return AnimatedSwitcher(
      duration: NexusMotion.fast,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(
              CurvedAnimation(
                  parent: animation, curve: NexusMotion.curveStandard),
            ),
            child: child,
          ),
        );
      },
      child: button,
    );
  }

  static NexusExecutionState _mapRunningStage(String? stage) {
    if (stage == null) return NexusExecutionState.idle;
    if (stage.contains('等待') || stage.contains('确认') || stage.contains('授权')) {
      return NexusExecutionState.waitingForUser;
    }
    if (stage.contains('准备') || stage.contains('思考')) {
      return NexusExecutionState.preparing;
    }
    if (stage.contains('完成') || stage.contains('成功')) {
      return NexusExecutionState.succeeded;
    }
    if (stage.contains('失败') || stage.contains('错误')) {
      return NexusExecutionState.failed;
    }
    if (stage.contains('取消') || stage.contains('停止')) {
      return NexusExecutionState.cancelled;
    }
    return NexusExecutionState.running;
  }

  Widget _buildStatusLine(Color textMuted) {
    if (widget.isRunning && widget.runningStage != null) {
      return Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: NexusExecutionStatus(
          compact: true,
          state: _mapRunningStage(widget.runningStage),
          label: widget.runningStage!,
        ),
      );
    }
    if (widget.planModeEnabled && !widget.isRunning) {
      return const Padding(
        padding: EdgeInsets.only(left: 4, bottom: 8),
        child: NexusExecutionStatus(
          compact: true,
          state: NexusExecutionState.waitingForUser,
          label: '计划模式开启 · 需执行确认',
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// 模式 / 审批策略磁贴：与「＋」同一套圆形磁贴样式（30dp 圆形 + 1.5px 圆环）。
///
/// 选中：brandSoft 底 + 品牌色图标；未选中：透明底 + hairline 圆环 + 灰图标。
/// 磁贴上只放图标，可读名称走 [semanticLabel] 与 tooltip（长按可见），
/// 因此「聊天模式」「完全访问」在 360dp 小屏上也不会互相挤压或溢出。
class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.icon,
    required this.semanticLabel,
    required this.selected,
    this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    final bg = selected
        ? (isDark
            ? AppPalette.darkBrandSoft.withValues(alpha: 0.85)
            : AppPalette.lightBrandSoft.withValues(alpha: 0.90))
        : (isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.035));
    final border = selected
        ? AppPalette.brandAction.withValues(alpha: isDark ? 0.65 : 0.50)
        : (isDark
            ? Colors.white.withValues(alpha: 0.14)
            : Colors.black.withValues(alpha: 0.08));
    final color = selected ? AppPalette.brandAction : textMuted;

    return Semantics(
      label: semanticLabel,
      button: true,
      selected: selected,
      enabled: onTap != null,
      child: Tooltip(
        message: semanticLabel,
        child: SizedBox(
          width: AppTokens.kMinTouchTarget,
          height: AppTokens.kMinTouchTarget,
          child: Material(
            color: Colors.transparent,
            child: InkResponse(
              onTap: onTap,
              radius: 24,
              child: Center(
                child: AnimatedContainer(
                  duration: AppTokens.durationFast,
                  curve: AppTokens.curveStandard,
                  width: AppTokens.composerCircleButton,
                  height: AppTokens.composerCircleButton,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: bg,
                    border: Border.all(
                      color: border,
                      width: 1.0,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 15, color: color),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 圆形描边按钮（「＋」附件入口）。48x48 触控区，视觉尺寸 26dp。
class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.iconSize,
    required this.semanticLabel,
    this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final double iconSize;
  final String semanticLabel;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resolved = isDark ? AppPalette.darkText : AppPalette.lightText;

    Widget button = SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: Colors.transparent,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: Center(
            child: Container(
              width: AppTokens.composerCircleButton,
              height: AppTokens.composerCircleButton,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.035),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.08),
                  width: 1.0,
                ),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: iconSize, color: resolved),
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }

    return Semantics(
      label: semanticLabel,
      button: true,
      enabled: onTap != null,
      child: button,
    );
  }
}

/// 实心圆形按钮（发送 / 停止 / 置灰发送）。48x48 触控区，视觉尺寸 26dp。
///
/// [onTap] 为 null 时渲染为不可点的置灰态 —— 视觉位置不变，但语义上 `enabled: false`，
/// 读屏会把它读成"不可用"，而不是一个点了没反应的按钮。
class _FilledCircleButton extends StatelessWidget {
  const _FilledCircleButton({
    super.key,
    required this.color,
    required this.icon,
    required this.semanticLabel,
    this.tooltip,
    this.onTap,
    this.iconColor = Colors.white,
  });

  final Color color;
  final IconData icon;
  final String semanticLabel;
  final String? tooltip;
  final VoidCallback? onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    Widget button = SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: Colors.transparent,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: Center(
            child: AnimatedContainer(
              duration: AppTokens.durationFast,
              curve: AppTokens.curveStandard,
              width: AppTokens.composerCircleButton,
              height: AppTokens.composerCircleButton,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              alignment: Alignment.center,
              child: Icon(icon, size: 15, color: iconColor),
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }

    return Semantics(
      label: semanticLabel,
      button: true,
      enabled: onTap != null,
      child: button,
    );
  }
}
