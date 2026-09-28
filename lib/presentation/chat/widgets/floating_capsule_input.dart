import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../../domain/models.dart';
import '../../motion/motion_intensity.dart';
import '../../motion/motion_tier.dart';
import '../../motion/nexus_entrance.dart';
import '../../motion/nexus_haptics.dart';
import '../../motion/nexus_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/nexus_execution_status.dart';
import '../../widgets/nexus_pressable.dart';
import '../../widgets/glass_surface.dart';
import '../../motion/morph_icon.dart';
import '../../motion/nexus_spring.dart';
import '../../motion/send_flight.dart';

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
    this.bottomPadding,
  });

  final TextEditingController controller;
  final bool isRunning;
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

  /// 输入区底部留白。显式传入时直接使用（聊天页由 KeyboardSpacer 统一处理
  /// 键盘与底部安全区）；为 null 时按旧逻辑自适应。
  final double? bottomPadding;

  @override
  State<FloatingCapsuleInput> createState() => _FloatingCapsuleInputState();
}

class _FloatingCapsuleInputState extends State<FloatingCapsuleInput>
    with SingleTickerProviderStateMixin {
  late final ValueNotifier<bool> _focused;
  final FocusNode _focusNode = FocusNode();

  /// L2：输入框文字区域，发送时把它的位置交给 [SendFlightBus]。
  final GlobalKey _fieldKey = GlobalKey();

  /// 发送光圈（M5）：只在点击发送时从 0 播放到 1，其余时间静止不绘制。
  late final AnimationController _sendPulse = AnimationController(
    vsync: this,
    duration: NexusMotion.sendRipple,
  );

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
    _sendPulse.dispose();
    SendFlightBus.cancel();
    super.dispose();
  }

  void _playSendRipple() {
    if (!MotionBudget.of(context, listen: false).sendRipple) return;
    _sendPulse.forward(from: 0);
  }

  void _onFocusChange() {
    final now = _focusNode.hasFocus;
    if (now != _focused.value) _focused.value = now;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textFaint =
        isDark ? AppPalette.darkTextFaint : AppPalette.lightTextMuted;
    final surface = isDark ? AppPalette.darkSurface : AppPalette.lightSurface;

    final bottomPadding = widget.bottomPadding ??
        (MediaQuery.viewInsetsOf(context).bottom > 0
            ? 8.0
            : MediaQuery.paddingOf(context).bottom + 8.0);

    // M2：首屏入场槽位 3（120ms 后），只位移不淡入，每进程一次。
    return NexusEntrance(
      slot: 3,
      offset: const Offset(0, 12),
      fade: false,
      onceId: 'chat_composer',
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: _FocusMorphMargin(
          focused: _focused,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 运行状态提示（仅生成 / 计划模式时出现，首页态不显示）
              SpringAnimatedSize(child: _buildStatusLine()),

              // 外层容器：20px 圆角，聚焦时描边转 brand
              Builder(
                builder: (context) {
                  final inputCard = Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 输入行：最小高 44px
                      SpringAnimatedSize(
                        key: _fieldKey,
                        alignment: Alignment.bottomLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                              minHeight: AppTokens.kMinTouchTarget),
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

                      const SizedBox(height: 0),

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
                                  onTap: widget.onModeTap != null
                                      ? () {
                                          NexusHaptics.light(context);
                                          widget.onModeTap!();
                                        }
                                      : null,
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
                                    onTap: () {
                                      NexusHaptics.light(context);
                                      widget.onApprovalModeTap!();
                                    },
                                  ),
                              ],
                            ),
                            // 右：代码块快捷 +「＋」附件 + 尾键（发送/停止/置灰发送，靠右）
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PopupMenuButton<String>(
                                  tooltip: '更多输入工具',
                                  icon: const Icon(Icons.more_horiz_rounded,
                                      size: 20),
                                  constraints:
                                      const BoxConstraints(minWidth: 160),
                                  onSelected: (_) => _insertCodeBlock(),
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                        value: 'code', child: Text('插入代码块')),
                                  ],
                                ),
                                _buildAttachmentButton(),
                                if (widget.isRunning && widget.isPaused)
                                  _buildPausedStopButton(isDark),
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
                        padding: const EdgeInsets.fromLTRB(12, 6, 10, 4),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusComposer),
                          border: Border.all(
                            color: isDark
                                ? AppPalette.darkHairline
                                : AppPalette.lightHairline,
                            width: 1.0,
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
                      padding: const EdgeInsets.fromLTRB(12, 6, 10, 4),
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
      ),
    );
  }

  void _insertCodeBlock() {
    NexusHaptics.light(context);
    final text = widget.controller.text;
    final sel = widget.controller.selection;
    const snippet = '```\n\n```';
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    widget.controller.value = TextEditingValue(
      text: text.replaceRange(start, end, snippet),
      selection: TextSelection.collapsed(offset: start + 4),
    );
    _focusNode.requestFocus();
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
              builder: (context, focused, _) => AnimatedContainer(
                duration: NexusMotion.fast,
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: focused
                      ? Border.all(color: AppPalette.brand, width: 1.4)
                      : Border.all(color: Colors.transparent, width: 1.4),
                  boxShadow: focused
                      ? [
                          BoxShadow(
                            color: AppPalette.brand.withValues(alpha: 0.16),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : const [],
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

  /// 已暂停时在主按钮左侧额外给出「停止」：暂停态下用户最常见的下一步
  /// 就是继续或结束，不应再要求长按才能停止。
  Widget _buildPausedStopButton(bool isDark) {
    return _FilledCircleButton(
      key: const ValueKey('trailing_action_stop_when_paused'),
      color:
          isDark ? AppPalette.darkSurfaceHover : AppPalette.lightSurfaceHover,
      icon: Icons.stop_rounded,
      iconColor: Theme.of(context).colorScheme.error,
      tooltip: '停止',
      semanticLabel: '停止任务',
      onTap: () {
        NexusHaptics.medium(context);
        widget.onStop();
      },
    );
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
        builder: (context, _, __) => _buildTrailingActionForAttachments(
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
          NexusHaptics.medium(context);
          SendFlightBus.launchFrom(_fieldKey.currentContext);
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
          NexusHaptics.medium(context);
          (widget.onResume ?? widget.onStop)();
        },
      );
    } else if (widget.isRunning) {
      button = _FilledCircleButton(
        key: const ValueKey('trailing_action_pause'),
        color: AppPalette.warning,
        icon: Icons.pause_rounded,
        tooltip: '暂停（长按停止）',
        semanticLabel: '暂停（长按停止）',
        onTap: () {
          NexusHaptics.medium(context);
          (widget.onPause ?? widget.onStop)();
        },
        onLongPress: () {
          NexusHaptics.warning(context);
          widget.onStop();
        },
      );
    } else if (canSend) {
      button = _FilledCircleButton(
        key: const ValueKey('trailing_action_send_active'),
        color: AppPalette.brand,
        icon: Icons.arrow_upward_rounded,
        tooltip: '发送',
        semanticLabel: '发送',
        pressedScale: NexusMotion.sendPressedScale,
        releaseCurve: NexusMotion.curveSendRelease,
        releaseDuration: NexusMotion.pressRelease,
        onTap: () {
          NexusHaptics.light(context);
          _playSendRipple();
          SendFlightBus.launchFrom(_fieldKey.currentContext);
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

    return CustomPaint(
      // 光圈画在按钮与输入框玻璃之上的前景层，不参与命中测试。
      foregroundPainter: _SendRipplePainter(
        progress: _sendPulse,
        color: AppPalette.brand,
        gain: MotionTierScope.gainOf(context),
      ),
      child: SizedBox(
        key: const ValueKey('composer-primary-action-slot'),
        width: 48,
        height: 48,
        // L1：发送 ↔ 停止以弹簧形变切换（缩放 + 轻旋转，5% 回弹）。
        child: AnimatedSwitcher(
          duration: NexusMorph.duration(context),
          transitionBuilder: NexusMorph.transition(context),
          layoutBuilder: NexusMorph.layout,
          child: button,
        ),
      ),
    );
  }

  Widget _buildStatusLine() {
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
            child: NexusPressable(
              onTap: onTap,
              borderRadius: BorderRadius.circular(24),
              child: Center(
                child: AnimatedContainer(
                  duration: NexusMotion.durationFast(context),
                  curve: NexusMotion.curveStandard,
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
        child: NexusPressable(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
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
              // L2：＋ ↔ × 以弹簧旋转形变切换。
              child: AnimatedSwitcher(
                duration: NexusMorph.duration(context),
                transitionBuilder: NexusMorph.transition(context),
                layoutBuilder: NexusMorph.layout,
                child: Icon(
                  icon,
                  key: ValueKey(icon),
                  size: iconSize,
                  color: resolved,
                ),
              ),
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
    this.onLongPress,
    this.iconColor = Colors.white,
    this.pressedScale = 0.97,
    this.releaseCurve,
    this.releaseDuration,
  });

  final Color color;
  final IconData icon;
  final String semanticLabel;
  final String? tooltip;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color iconColor;
  final double pressedScale;
  final Curve? releaseCurve;
  final Duration? releaseDuration;

  @override
  Widget build(BuildContext context) {
    Widget button = SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: Colors.transparent,
        child: NexusPressable(
          onTap: onTap,
          onLongPress: onLongPress,
          pressedScale: pressedScale,
          releaseCurve: releaseCurve,
          releaseDuration: releaseDuration,
          borderRadius: BorderRadius.circular(24),
          child: Center(
            child: AnimatedContainer(
              duration: NexusMotion.durationFast(context),
              curve: NexusMotion.curveStandard,
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

/// 发送光圈：从按钮中心扩散的描边圆环，半径 0 → [maxRadius]，
/// 透明度 [startAlpha] → 0。静止（进度为 0 或 1）时不绘制任何东西。
/// S1：半径 / 透明度 / 线宽随强度放大（鲜明档 42dp、0.6、2.5dp）。
class _SendRipplePainter extends CustomPainter {
  _SendRipplePainter({
    required this.progress,
    required this.color,
    this.gain = 1,
  }) : super(repaint: progress);

  static const double maxRadius = 28;
  static const double startAlpha = 0.35;
  static const double strokeWidth = 1.5;

  final Animation<double> progress;
  final Color color;
  final double gain;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t <= 0 || t >= 1) return;
    final radius = amplify(maxRadius, gain, 0.5);
    final alpha = amplify(startAlpha, gain, 0.72).clamp(0.0, 0.6);
    final stroke = amplify(strokeWidth, gain, 0.67);
    final eased = NexusMotion.curveEnter.transform(t);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color.withValues(alpha: alpha * (1 - t));
    canvas.drawCircle(size.center(Offset.zero), radius * eased, paint);
  }

  @override
  bool shouldRepaint(covariant _SendRipplePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.gain != gain;
}

/// L2：聚焦时胶囊向两侧舒展（左右边距 12 → 8dp），失焦收回，弹簧驱动。
class _FocusMorphMargin extends StatelessWidget {
  const _FocusMorphMargin({required this.focused, required this.child});

  final ValueListenable<bool> focused;
  final Widget child;

  static const double rest = 12;
  static const double focusedInset = 8;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: focused,
        child: child,
        builder: (context, isFocused, child) => SpringValue(
          value: isFocused ? focusedInset : rest,
          spring: NexusSprings.smooth,
          child: child,
          builder: (context, inset, child) => Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: child,
          ),
        ),
      );
}
