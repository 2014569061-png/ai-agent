import '../../theme/mobile_theme.dart';
import 'package:flutter/material.dart';
import '../../../application/desktop_host_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../domain/models.dart';
import 'chat_mode_switcher.dart';
import '../../motion/mobile_motion.dart';
import '../../motion/motion_preferences.dart';
import '../../motion/nexus_haptics.dart';
import '../../motion/nexus_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';
import '../../theme/desktop_theme.dart';
import '../../widgets/desktop_reading_column.dart';
import '../../widgets/nexus_execution_status.dart';
import '../../widgets/nexus_pressable.dart';
import '../../widgets/glass_surface.dart';
import '../../motion/morph_icon.dart';
import '../../motion/send_flight.dart';
import '../../../application/local_error_copy.dart';

/// Two-row phone composer: multiline input above attachments, model, settings
/// and the primary action. Every icon retains a 48dp accessible hit target.
/// Desktop uses its existing independent composer layout.
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
    this.modelLabel,
    this.desktopChatMode,
    this.onDesktopChatModeChanged,
    this.desktopMaxLines = 5,
    this.onModelTap,
    this.onSpeechInput,
    this.onMetricsTap,
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
  final String? modelLabel;
  final ChatMode? desktopChatMode;
  final ValueChanged<ChatMode>? onDesktopChatModeChanged;
  final int desktopMaxLines;
  final VoidCallback? onModelTap;
  final VoidCallback? onSpeechInput;
  final VoidCallback? onMetricsTap;
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

class _FloatingCapsuleInputState extends State<FloatingCapsuleInput> {
  late final ValueNotifier<bool> _focused;
  final FocusNode _focusNode = FocusNode();

  /// L2：输入框文字区域，发送时把它的位置交给 [SendFlightBus]。
  final GlobalKey _fieldKey = GlobalKey();

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
    SendFlightBus.cancel();
    super.dispose();
  }

  void _onFocusChange() {
    final now = _focusNode.hasFocus;
    if (now != _focused.value) _focused.value = now;
  }

  @override
  Widget build(BuildContext context) {
    if (DesktopTheme.maybeOf(context) != null) return _desktopInput(context);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = scheme.onSurface;
    final textFaint = scheme.onSurfaceVariant;
    final surface =
        isDark ? scheme.surfaceContainerHighest : const Color(0xFFF4F5F7);

    final bottomPadding = widget.bottomPadding ??
        (MediaQuery.viewInsetsOf(context).bottom > 0
            ? 8.0
            : MediaQuery.paddingOf(context).bottom + 8.0);

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 8, 12, bottomPadding),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedSize(
          duration: MobileMotion.duration(context, MobileMotion.message),
          curve: MobileMotion.curve,
          alignment: Alignment.bottomCenter,
          child: _buildStatusLine(),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: _focused,
          builder: (context, focused, _) => AnimatedContainer(
            duration: MotionPreferences.adjustDuration(
                context, const Duration(milliseconds: 180)),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: focused
                      ? Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: .38)
                      : Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ConstrainedBox(
                  key: _fieldKey,
                  constraints:
                      const BoxConstraints(minHeight: 48, maxHeight: 128),
                  child: TextField(
                    focusNode: _focusNode,
                    controller: widget.controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    onTapOutside: (_) => _focusNode.unfocus(),
                    style:
                        TextStyle(fontSize: 16, height: 1.5, color: textColor),
                    decoration: InputDecoration(
                      hintText: widget.isRunning ? '补充要求…' : '给 NEXUS 发送消息',
                      hintStyle: TextStyle(fontSize: 15, color: textFaint),
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                  ),
                ),
              ),
              Row(children: [
                Align(
                  widthFactor: 1,
                  alignment: Alignment.centerLeft,
                  child: Tooltip(
                      message: widget.modelLabel?.isNotEmpty == true
                          ? '当前模型：${widget.modelLabel}'
                          : '选择模型',
                      excludeFromSemantics: true,
                      child: TextButton(
                        onPressed: widget.onModelTap,
                        style: TextButton.styleFrom(
                          foregroundColor: textFaint,
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          shape: const StadiumBorder(),
                        ),
                        child: Container(
                          constraints: BoxConstraints(
                              maxWidth: (MediaQuery.sizeOf(context).width -
                                      (MediaQuery.sizeOf(context).width >=
                                                  360 &&
                                              MediaQuery.textScalerOf(context)
                                                      .scale(1) <
                                                  1.3
                                          ? 240
                                          : 200) -
                                      (widget.isRunning && widget.isPaused
                                          ? 56
                                          : 0))
                                  .clamp(48.0, 150.0)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Flexible(
                                child: Text(
                              widget.modelLabel?.isNotEmpty == true
                                  ? widget.modelLabel!
                                  : '选择模型',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12.5, fontWeight: FontWeight.w400),
                            )),
                            const SizedBox(width: 4),
                            Icon(Icons.keyboard_arrow_down_rounded,
                                size: 15, color: textFaint),
                          ]),
                        ),
                      )),
                ),
                PopupMenuButton<String>(
                  tooltip: '更多输入工具',
                  icon: MediaQuery.sizeOf(context).width >= 360 &&
                          MediaQuery.textScalerOf(context).scale(1) < 1.3
                      ? Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('执行选项',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w400,
                                    color: textFaint)),
                            const SizedBox(width: 2),
                            Icon(Icons.keyboard_arrow_down_rounded,
                                size: 16, color: textFaint),
                          ]))
                      : Icon(Icons.tune_rounded, size: 20, color: textFaint),
                  onSelected: (value) {
                    switch (value) {
                      case 'code':
                        _insertCodeBlock();
                      case 'mode':
                        widget.onModeTap?.call();
                      case 'approval':
                        widget.onApprovalModeTap?.call();
                      case 'speech':
                        widget.onSpeechInput?.call();
                      case 'metrics':
                        widget.onMetricsTap?.call();
                      case 'pause':
                        widget.onPause?.call();
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        value: 'mode',
                        enabled: widget.onModeTap != null,
                        child: Text('执行模式 · ${widget.modeLabel}')),
                    PopupMenuItem(
                        value: 'approval',
                        enabled: widget.onApprovalModeTap != null,
                        child: Text(
                            '审批 · ${_approvalModeLabel(widget.approvalMode)}')),
                    if (widget.onSpeechInput != null)
                      PopupMenuItem(
                          value: 'speech',
                          enabled: !widget.isRunning,
                          child: const Text('语音输入（前台单句）')),
                    if (widget.onMetricsTap != null)
                      const PopupMenuItem(
                          value: 'metrics', child: Text('用量与上下文')),
                    if (widget.isRunning &&
                        !widget.isPaused &&
                        widget.onPause != null)
                      const PopupMenuItem(value: 'pause', child: Text('暂停任务')),
                    const PopupMenuItem(value: 'code', child: Text('插入代码块')),
                  ],
                ),
                const Spacer(),
                _buildAttachmentButton(),
                if (widget.isRunning && widget.isPaused)
                  _buildPausedStopButton(isDark),
                _buildTrailingActionListenable(textFaint, isDark),
              ]),
            ]),
          ),
        ),
      ]),
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

  Future<void> _pasteDesktop() async {
    try {
      if (await DesktopHostService.instance.pasteImage()) return;
      final text = (await Clipboard.getData('text/plain'))?.text;
      if (text == null || !mounted) return;
      final value = widget.controller.value;
      final selection = value.selection;
      final start = selection.isValid ? selection.start : value.text.length;
      final end = selection.isValid ? selection.end : start;
      widget.controller.value = TextEditingValue(
          text: value.text.replaceRange(start, end, text),
          selection: TextSelection.collapsed(offset: start + text.length));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(LocalErrorCopy.of(error, action: '粘贴').headline())));
      }
    }
  }

  Widget _desktopInput(BuildContext context) {
    final colors = DesktopTheme.maybeOf(context)!;
    Widget menu(IconData icon, String label, VoidCallback? action,
            {String? explanation}) =>
        Tooltip(
            message: explanation ?? label,
            child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: TextButton.icon(
                    onPressed: action,
                    style: TextButton.styleFrom(
                        backgroundColor: colors.hover,
                        minimumSize: const Size(0, 26),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7),
                            side: BorderSide(color: colors.border))),
                    icon: Icon(icon, size: 13, color: colors.muted),
                    label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    fontSize: AppTokens.fontSizeFootnote,
                                    fontWeight: FontWeight.w500,
                                    color: colors.text))))));
    return DesktopReadingColumn(
        child: Padding(
            padding: EdgeInsets.fromLTRB(16, 2, 16, widget.bottomPadding ?? 6),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.desktopChatMode == ChatMode.plan &&
                      !widget.planModeEnabled)
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 4),
                      child: NexusExecutionStatus(
                        compact: true,
                        state: NexusExecutionState.waitingForUser,
                        label: '计划模式已开启 · 首轮需要确认',
                      ),
                    )
                  else
                    _buildStatusLine(),
                  ValueListenableBuilder<bool>(
                      valueListenable: _focused,
                      builder: (context, focused, _) => Container(
                          key: const ValueKey('desktop-composer-surface'),
                          padding: const EdgeInsets.fromLTRB(12, 6, 8, 4),
                          decoration: BoxDecoration(
                              color: colors.panel,
                              border: Border.all(
                                  color:
                                      focused ? colors.accent : colors.border,
                                  width: focused ? 1.3 : 1.0),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                    color: colors.accent.withValues(
                                        alpha: focused ? .10 : .035),
                                    blurRadius: focused ? 18 : 10,
                                    offset: const Offset(0, 3))
                              ]),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            CallbackShortcuts(
                                bindings: {
                                  const SingleActivator(LogicalKeyboardKey.keyV,
                                      control: true): _pasteDesktop,
                                  const SingleActivator(LogicalKeyboardKey.keyV,
                                      meta: true): _pasteDesktop,
                                  const SingleActivator(
                                      LogicalKeyboardKey.enter,
                                      shift: true): () {
                                    final value = widget.controller.value;
                                    final selection = value.selection;
                                    final start = selection.isValid
                                        ? selection.start
                                        : value.text.length;
                                    final end = selection.isValid
                                        ? selection.end
                                        : value.text.length;
                                    widget.controller.value = TextEditingValue(
                                        text: value.text
                                            .replaceRange(start, end, '\n'),
                                        selection: TextSelection.collapsed(
                                            offset: start + 1));
                                  },
                                  const SingleActivator(
                                      LogicalKeyboardKey.enter): () {
                                    if (widget.controller.value.composing
                                            .isValid &&
                                        !widget.controller.value.composing
                                            .isCollapsed) {
                                      return;
                                    }
                                    if (widget.controller.text
                                            .trim()
                                            .isNotEmpty ||
                                        widget.hasAttachments ||
                                        widget.hasAttachmentsListenable
                                                ?.value ==
                                            true) {
                                      widget.onSend();
                                    }
                                  },
                                },
                                child: Align(
                                    key: _fieldKey,
                                    alignment: Alignment.centerLeft,
                                    child: TextField(
                                        key: const ValueKey(
                                            'desktop-composer-field'),
                                        controller: widget.controller,
                                        focusNode: _focusNode,
                                        minLines: 1,
                                        maxLines:
                                            widget.desktopMaxLines.clamp(1, 5),
                                        textInputAction:
                                            TextInputAction.newline,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium,
                                        decoration: InputDecoration(
                                            hintText: widget.isRunning
                                                ? '补充要求…'
                                                : '描述任务，使用 / 选择技能…',
                                            hintStyle: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                            filled: false,
                                            border: InputBorder.none,
                                            enabledBorder: InputBorder.none,
                                            focusedBorder: InputBorder.none,
                                            contentPadding: EdgeInsets.zero)))),
                            Row(children: [
                              Expanded(
                                  child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(children: [
                                        IconButton(
                                            tooltip: '添加附件',
                                            onPressed: widget.onAttachmentMenu,
                                            icon: const Icon(Icons.add,
                                                size: 18)),
                                        menu(
                                            Icons.tune,
                                            widget.modelLabel?.isNotEmpty ==
                                                    true
                                                ? widget.modelLabel!
                                                : '选择模型',
                                            widget.onModelTap),
                                        if (widget.desktopChatMode != null &&
                                            widget.onDesktopChatModeChanged !=
                                                null)
                                          ChatModeSwitcher(
                                            inline: true,
                                            mode: widget.desktopChatMode!,
                                            running: widget.isRunning,
                                            onChanged: widget
                                                .onDesktopChatModeChanged!,
                                          )
                                        else
                                          menu(
                                              Icons.smart_toy_outlined,
                                              widget.modeLabel,
                                              widget.onModeTap),
                                        menu(
                                            Icons.shield_outlined,
                                            widget.approvalMode ==
                                                    ApprovalMode.ask
                                                ? '操作前询问'
                                                : _approvalModeLabel(
                                                    widget.approvalMode),
                                            widget.onApprovalModeTap,
                                            explanation: '审批策略：决定执行操作前是否需要确认'),
                                        PopupMenuButton<String>(
                                            tooltip:
                                                '更多输入工具 · Enter 发送 / Shift + Enter 换行',
                                            icon: const Icon(Icons.more_horiz,
                                                size: 18),
                                            onSelected: (value) {
                                              if (value == 'code') {
                                                _insertCodeBlock();
                                              }
                                              if (value == 'session') {
                                                widget.onModeTap?.call();
                                              }
                                            },
                                            itemBuilder: (_) => [
                                                  const PopupMenuItem(
                                                      value: 'code',
                                                      child: Text('插入代码块')),
                                                  if (widget.onModeTap != null)
                                                    const PopupMenuItem(
                                                      value: 'session',
                                                      child: Text('会话设置'),
                                                    ),
                                                  const PopupMenuItem(
                                                    enabled: false,
                                                    child: Text(
                                                        'Enter 发送 · Shift + Enter 换行'),
                                                  ),
                                                ]),
                                      ]))),
                              if (widget.isRunning && widget.isPaused)
                                _buildPausedStopButton(
                                    Theme.of(context).brightness ==
                                        Brightness.dark),
                              _buildTrailingActionListenable(
                                  colors.muted,
                                  Theme.of(context).brightness ==
                                      Brightness.dark),
                            ]),
                            if (focused)
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 2, bottom: 2),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Enter 发送 · Shift+Enter 换行',
                                    key: const ValueKey(
                                        'desktop-composer-shortcut-hint'),
                                    style: TextStyle(
                                      fontSize: DesktopTheme.smallSize,
                                      color: colors.muted,
                                    ),
                                  ),
                                ),
                              ),
                          ]))),
                ])));
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
        color:
            DesktopTheme.maybeOf(context)?.accent ?? MobileTheme.brand(context),
        icon: Icons.playlist_add_rounded,
        tooltip: '补充要求',
        semanticLabel: '补充要求',
        onTap: () {
          NexusHaptics.medium(context);
          if (DesktopTheme.maybeOf(context) != null) {
            SendFlightBus.launchFrom(_fieldKey.currentContext);
          }
          widget.onSend();
        },
      );
    } else if (widget.isRunning && widget.isPaused) {
      button = _FilledCircleButton(
        key: const ValueKey('trailing_action_resume'),
        color:
            DesktopTheme.maybeOf(context)?.accent ?? MobileTheme.brand(context),
        icon: Icons.play_arrow_rounded,
        tooltip: '继续',
        semanticLabel: '继续',
        onTap: () {
          NexusHaptics.medium(context);
          (widget.onResume ?? widget.onStop)();
        },
      );
    } else if (widget.isRunning) {
      final stopErr = Theme.of(context).colorScheme.error;
      button = _FilledCircleButton(
        key: const ValueKey('trailing_action_pause'),
        color: DesktopTheme.maybeOf(context) != null
            ? AppPalette.warning
            : stopErr.withValues(alpha: isDark ? 0.22 : 0.13),
        borderColor: DesktopTheme.maybeOf(context) != null
            ? null
            : stopErr.withValues(alpha: isDark ? 0.40 : 0.28),
        icon: DesktopTheme.maybeOf(context) != null
            ? Icons.pause_rounded
            : Icons.stop_rounded,
        iconColor:
            DesktopTheme.maybeOf(context) != null ? Colors.white : stopErr,
        tooltip: DesktopTheme.maybeOf(context) != null ? '暂停（长按停止）' : '停止任务',
        semanticLabel:
            DesktopTheme.maybeOf(context) != null ? '暂停（长按停止）' : '停止任务',
        onTap: () {
          NexusHaptics.medium(context);
          if (DesktopTheme.maybeOf(context) != null) {
            (widget.onPause ?? widget.onStop)();
          } else {
            widget.onStop();
          }
        },
        onLongPress: () {
          NexusHaptics.warning(context);
          widget.onStop();
        },
      );
    } else if (canSend) {
      button = _FilledCircleButton(
        key: const ValueKey('trailing_action_send_active'),
        color:
            DesktopTheme.maybeOf(context)?.accent ?? MobileTheme.brand(context),
        icon: Icons.arrow_upward_rounded,
        tooltip: '发送',
        semanticLabel: '发送',
        pressedScale: DesktopTheme.maybeOf(context) != null
            ? NexusMotion.sendPressedScale
            : 0.97,
        releaseCurve: DesktopTheme.maybeOf(context) != null
            ? NexusMotion.curveSendRelease
            : MobileMotion.curve,
        releaseDuration: DesktopTheme.maybeOf(context) != null
            ? NexusMotion.pressRelease
            : MobileMotion.control,
        onTap: () {
          NexusHaptics.light(context);
          if (DesktopTheme.maybeOf(context) != null) {
            SendFlightBus.launchFrom(_fieldKey.currentContext);
          }
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

    final phone = DesktopTheme.maybeOf(context) == null;
    return SizedBox(
      key: const ValueKey('composer-primary-action-slot'),
      width: DesktopTheme.maybeOf(context) != null ? 36 : 48,
      height: DesktopTheme.maybeOf(context) != null ? 36 : 48,
      // Phone actions keep a stable 48dp slot and only crossfade.
      child: AnimatedSwitcher(
        duration: phone
            ? MobileMotion.duration(context, MobileMotion.control)
            : NexusMorph.duration(context),
        transitionBuilder: phone
            ? (child, animation) =>
                FadeTransition(opacity: animation, child: child)
            : NexusMorph.transition(context),
        layoutBuilder: NexusMorph.layout,
        child: button,
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
    final desktop = DesktopTheme.maybeOf(context);
    if (desktop != null) {
      final enabled = onTap != null;
      return Semantics(
        label: semanticLabel,
        button: true,
        enabled: enabled,
        child: Tooltip(
          message: tooltip ?? semanticLabel,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(DesktopTheme.radius),
              child: InkWell(
                borderRadius: BorderRadius.circular(DesktopTheme.radius),
                onTap: onTap,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(DesktopTheme.radius),
                    border: Border.all(color: desktop.border),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon,
                      size: 16, color: enabled ? desktop.text : desktop.muted),
                ),
              ),
            ),
          ),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final resolved = scheme.onSurfaceVariant;

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
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Colors.transparent,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              // The attachment affordance crossfades without rotating.
              child: AnimatedSwitcher(
                duration: MobileMotion.duration(context, MobileMotion.control),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                layoutBuilder: NexusMorph.layout,
                child: Icon(
                  icon,
                  key: ValueKey(icon),
                  size: 20,
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
    this.borderColor,
    this.tooltip,
    this.onTap,
    this.onLongPress,
    this.iconColor = Colors.white,
    this.pressedScale = 0.97,
    this.releaseCurve,
    this.releaseDuration,
  });

  final Color color;
  final Color? borderColor;
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
    final desktop = DesktopTheme.maybeOf(context);
    if (desktop != null) {
      final enabled = onTap != null || onLongPress != null;
      final effectiveBg = enabled ? color : desktop.hover;
      final effectiveFg = enabled ? iconColor : desktop.muted;
      return Semantics(
        label: semanticLabel,
        button: true,
        enabled: enabled,
        child: Tooltip(
          message: tooltip ?? semanticLabel,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Material(
              color: effectiveBg,
              borderRadius: BorderRadius.circular(DesktopTheme.radius),
              child: InkWell(
                borderRadius: BorderRadius.circular(DesktopTheme.radius),
                onTap: onTap,
                onLongPress: onLongPress,
                child: Center(
                  child: Icon(icon, size: 16, color: effectiveFg),
                ),
              ),
            ),
          ),
        ),
      );
    }
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
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: borderColor == null
                    ? null
                    : Border.all(color: borderColor!),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 21, color: iconColor),
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
