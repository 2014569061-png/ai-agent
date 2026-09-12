import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';

/// 首页输入区（对标 DeepSeek App）。
///
/// 结构：
///   外层 24px 大圆角 + surface 底色，聚焦时描边转 brand
///   ├─ 输入行：最小高 44px，占位符「发消息」
///   └─ 操作行：高 30px
///        ├─ 左：深度思考 / 智能搜索 两个能力 chip（胶囊）
///        └─ 右：「＋」圆形描边按钮 + 尾键
///           （生成中 = 停止 / 有内容 = 发送 / 空输入 = 置灰发送，不可点）
///
/// 尾键不再有语音入口：本项目未接入语音识别，此前那个"看着能用、点了只弹提示"
/// 的语音键是纯假按钮（2026-09-12 移除）。**若将来接入语音，请在这里新增一个真实
/// 可用的入口，不要恢复成占位 toast。**
class FloatingCapsuleInput extends StatefulWidget {
  const FloatingCapsuleInput({
    super.key,
    required this.controller,
    required this.isRunning,
    this.runningStage,
    required this.onSend,
    required this.onStop,
    required this.onAttachmentMenu,
    this.deepThinking = true,
    this.onDeepThinkingToggle,
    this.webSearch = true,
    this.onWebSearchToggle,
    this.planModeEnabled = false,
    this.hasAttachments = false,
  });

  final TextEditingController controller;
  final bool isRunning;
  final String? runningStage;
  final VoidCallback onSend;
  final VoidCallback onStop;

  /// 「＋」按钮：附件与更多工具
  final VoidCallback onAttachmentMenu;

  final bool deepThinking;
  final VoidCallback? onDeepThinkingToggle;
  final bool webSearch;
  final VoidCallback? onWebSearchToggle;

  final bool planModeEnabled;
  final bool hasAttachments;

  @override
  State<FloatingCapsuleInput> createState() => _FloatingCapsuleInputState();
}

class _FloatingCapsuleInputState extends State<FloatingCapsuleInput> {
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final textFaint =
        isDark ? AppPalette.darkTextFaint : AppPalette.lightTextFaint;
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

            // 外层容器：24px 圆角 + surface 底色，聚焦时描边转 brand
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(AppTokens.radiusComposer),
                border: _focused
                    ? Border.all(color: AppPalette.brand, width: 1.0)
                    : null,
              ),
              child: Column(
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
                          hintText: '发消息',
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

                  // 操作行：高 48px，各控件垂直居中
                  SizedBox(
                    height: 48,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _ModeChip(
                          label: '深度思考',
                          icon: Icons.auto_awesome_outlined,
                          selected: widget.deepThinking,
                          onTap: widget.onDeepThinkingToggle,
                        ),
                        const SizedBox(width: 8),
                        _ModeChip(
                          label: '智能搜索',
                          icon: Icons.language_rounded,
                          selected: widget.webSearch,
                          onTap: widget.onWebSearchToggle,
                        ),
                        const Spacer(),
                        // 「＋」：附件与更多工具（48x48 触控区）
                        _CircleIconButton(
                          icon: Icons.add_rounded,
                          iconSize: 18,
                          tooltip: '添加附件或更多工具',
                          semanticLabel: '添加附件或更多工具',
                          onTap: widget.onAttachmentMenu,
                        ),
                        _buildTrailingAction(textFaint, isDark),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 生成中 → 停止键；有内容 → 发送键；空输入 → 置灰的发送键（不可点）。
  ///
  /// 空输入保留一个置灰发送键，而不是留空：位置固定、用户能预期"打完字这个按钮就能用"，
  /// 也让操作行右侧不会因为状态切换而左右跳动。
  Widget _buildTrailingAction(Color textFaint, bool isDark) {
    if (widget.isRunning) {
      return _FilledCircleButton(
        color: AppPalette.danger,
        icon: Icons.stop_rounded,
        tooltip: '停止生成',
        semanticLabel: '停止生成',
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.onStop();
        },
      );
    }
    if (_canSend) {
      return _FilledCircleButton(
        color: AppPalette.brand,
        icon: Icons.arrow_upward_rounded,
        tooltip: '发送',
        semanticLabel: '发送',
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.onSend();
        },
      );
    }
    return _FilledCircleButton(
      color: isDark ? AppPalette.darkSurfaceHover : AppPalette.lightSurfaceHover,
      icon: Icons.arrow_upward_rounded,
      iconColor: textFaint,
      tooltip: '发送',
      semanticLabel: '发送',
      onTap: null,
    );
  }

  Widget _buildStatusLine(Color textMuted) {
    if (widget.isRunning && widget.runningStage != null) {
      return Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: AppPalette.brand,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              widget.runningStage!,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 1.4,
                color: textMuted,
              ),
            ),
          ],
        ),
      );
    }
    if (widget.planModeEnabled && !widget.isRunning) {
      return const Padding(
        padding: EdgeInsets.only(left: 4, bottom: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded,
                size: 12, color: AppPalette.warning),
            SizedBox(width: 4),
            Text(
              '计划模式开启 · 需执行确认',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 1.4,
                color: AppPalette.warning,
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// 能力 chip（深度思考 / 智能搜索）。
/// 选中：brandSoft 底 + 品牌色文字图标；未选中：白底 + hairline 描边 + 灰字。
class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hairline =
        isDark ? AppPalette.darkHairline : AppPalette.lightHairline;
    final canvas = isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas;
    final brandSoft =
        isDark ? AppPalette.darkBrandSoft : AppPalette.lightBrandSoft;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    final bg = selected ? brandSoft : canvas;
    final color = selected ? AppPalette.brandAction : textMuted;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        child: Container(
          height: AppTokens.composerChipHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            border: selected
                ? Border.all(
                    color: AppPalette.brandAction.withValues(alpha: 0.28),
                    width: 1.0)
                : Border.all(color: hairline, width: 1.0),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  height: 1.4,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 圆形描边按钮（「＋」附件与工具入口）。48x48 触控区，视觉尺寸 30dp。
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
                shape: BoxShape.circle,
                border: Border.all(color: resolved, width: 1.5),
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

/// 实心圆形按钮（发送 / 停止 / 置灰发送）。48x48 触控区，视觉尺寸 30dp。
///
/// [onTap] 为 null 时渲染为不可点的置灰态 —— 视觉位置不变，但语义上 `enabled: false`，
/// 读屏会把它读成"不可用"，而不是一个点了没反应的按钮。
class _FilledCircleButton extends StatelessWidget {
  const _FilledCircleButton({
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
              child: Icon(icon, size: 18, color: iconColor),
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
