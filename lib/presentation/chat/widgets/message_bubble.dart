import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../application/error_humanizer.dart';
import '../../../domain/models.dart';
import '../chat_layout_controller.dart';
import '../../markdown/code_block.dart';
import '../../markdown/math_block.dart';
import '../../markdown/markdown_render_policy.dart';
import '../../markdown/markdown_render_metrics.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/floating_toast.dart';
import 'mascot_avatar.dart';
import 'attachment_strip.dart';
import 'reasoning_block.dart';

/// 单个消息气泡：负责气泡布局、正文/思考/附件渲染与轻量操作（复制、重生成）。
/// 用户消息：底 brandSoft、文字 text 15/400、内边距 10×14、圆角 16 16 8 16、最大宽 78%
/// AI 消息：不使用气泡，直接排版，左右各 16px 边距；正文 15/1.6、段间距 12px、回答内小标题 17/500（上 20 下 8）
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isLast,
    required this.running,
    required this.onLongPress,
    required this.onRegenerate,
    this.onEditPrompt,
    this.onSwitchModel,
  });

  final ChatMessage message;
  final bool isLast;
  final bool running;
  final VoidCallback? onLongPress;
  final VoidCallback onRegenerate;
  final VoidCallback? onEditPrompt;
  final VoidCallback? onSwitchModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isUser = message.role == MessageRole.user;
    final isTool = message.role == MessageRole.tool;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final surface = isDark ? AppPalette.darkSurface : AppPalette.lightSurface;
    final brandSoft =
        isDark ? AppPalette.darkBrandSoft : AppPalette.lightBrandSoft;

    final imageParts =
        message.parts.where((part) => part.type == 'image').toList();
    final audioParts =
        message.parts.where((part) => part.type == 'audio').toList();
    final videoParts =
        message.parts.where((part) => part.type == 'video').toList();
    final hasText = message.parts
        .any((part) => part.type == 'text' && part.value.trim().isNotEmpty);
    // 错误消息拆分：人话正文正常渲染，原文技术细节折叠展示。
    final errorSplit = splitErrorDetail(message.text);
    final errorDetail = errorSplit.detail;
    final canRetryFailure = errorDetail != null &&
        isLast &&
        message.role == MessageRole.assistant &&
        !running;

    // 流式生成中的最后一条助手消息使用纯文本，避免每个增量都重新解析 Markdown。
    final lightweight = !isUser && !isTool && isLast && running;

    // 无障碍：把原本只能长按触发的「复制 / 重新生成」暴露成读屏可操作的自定义
    // 语义动作（不新增可见按钮，避免改变视觉）。
    final customActions = <CustomSemanticsAction, VoidCallback>{
      const CustomSemanticsAction(label: '复制'): () {
        Clipboard.setData(ClipboardData(text: message.text));
        HapticFeedback.lightImpact();
        FloatingToast.show(
          context,
          '已复制全文',
          tone: ToastTone.success,
        );
      },
      if (isLast && message.role == MessageRole.assistant && !running)
        const CustomSemanticsAction(label: '重新生成'): onRegenerate,
    };

    final body = isUser
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: brandSoft,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(8),
              ),
            ),
            child: SelectableText(
              message.text,
              style: TextStyle(
                color: textColor,
                height: 1.6,
                fontSize: 15,
                fontWeight: FontWeight.w400,
              ),
            ),
          )
        : lightweight
            ? SelectableText(
                errorSplit.main,
                style: TextStyle(
                  color: textColor,
                  height: 1.6,
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
              )
            : _DeferredMarkdown(
                data: errorSplit.main,
                selectable: true,
                builders: {'pre': CodeBlockBuilder()},
                textColor: textColor,
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: TextStyle(
                    color: textColor,
                    height: 1.6,
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                  blockSpacing: 12,
                  listIndent: 20,
                  h1: TextStyle(
                    color: textColor,
                    fontSize: 17,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                  h1Padding: const EdgeInsets.only(top: 20, bottom: 8),
                  h2: TextStyle(
                    color: textColor,
                    fontSize: 17,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                  h2Padding: const EdgeInsets.only(top: 20, bottom: 8),
                  h3: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                  h3Padding: const EdgeInsets.only(top: 16, bottom: 6),
                  h4: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                  h5: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                  h6: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                  listBullet: TextStyle(
                    color: textColor,
                    height: 1.6,
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                  code: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontFamily: 'JetBrains Mono',
                  ),
                  blockquote: TextStyle(
                    color: textColor,
                    height: 1.6,
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                  tableHead: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  tableBody: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    height: 1.55,
                    fontWeight: FontWeight.w400,
                  ),
                  blockquoteDecoration: BoxDecoration(
                    color: surface,
                    borderRadius:
                        BorderRadius.circular(AppTokens.radiusControl),
                    border: const Border(
                      left: BorderSide(
                        color: AppPalette.brand,
                        width: 3,
                      ),
                    ),
                  ),
                ),
              );

    final reasoningText = message.reasoning;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AttachmentStrip(parts: [...imageParts, ...audioParts, ...videoParts]),
        if (hasText) body,
        if (errorDetail != null) ...[
          const SizedBox(height: 6),
          _ErrorDetailBlock(detail: errorDetail),
        ],
      ],
    );

    final screenWidth = MediaQuery.sizeOf(context).width;
    final factor = ChatLayoutController.widthFactor.value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(builder: (context, constraints) {
        final avatarSpace = isUser ? 0.0 : 36.0;
        final availableWidth = (constraints.maxWidth - avatarSpace)
            .clamp(0.0, double.infinity)
            .toDouble();
        final desiredWidth = factor == ChatLayoutController.adaptive
            ? (isUser ? screenWidth * 0.78 : availableWidth)
            : screenWidth * factor;
        final maxWidth = math.min(desiredWidth, availableWidth).toDouble();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment:
              isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!isUser) ...[
              if (isTool)
                Semantics(
                  label: '工具调用',
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: surface,
                    child: Icon(Icons.handyman_outlined,
                        size: 14, color: textMuted),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Semantics(
                    label: '${message.modelName ?? "AI 助手"}模型',
                    child: MascotAvatar(modelName: message.modelName ?? ''),
                  ),
                ),
              const SizedBox(width: 8),
            ],
            GestureDetector(
              onLongPress: isTool ? null : onLongPress,
              child: Tooltip(
                message: isUser ? '长按可编辑 / 复制' : '长按可朗读 / 复制',
                triggerMode: TooltipTriggerMode.longPress,
                showDuration: const Duration(milliseconds: 1800),
                child: Semantics(
                  onLongPressHint: isUser ? '编辑或复制' : '朗读或复制',
                  customSemanticsActions: customActions,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: isUser
                        ? IntrinsicWidth(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: content,
                                ),
                              ],
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 只在确实有思考内容（或正在思考）时才出现这一行。
                                // 原先只要消息带 elapsed/usage 就渲染一行指标，与底部会话指标条重复，已移除。
                                if (!isTool &&
                                    ((reasoningText?.trim().isNotEmpty ??
                                            false) ||
                                        (running && !isUser)))
                                  ReasoningCompactBlock(
                                    reasoning: reasoningText ?? '',
                                    streaming: running && !hasText,
                                    duration: message.reasoningDuration,
                                  ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: content,
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        iconSize: 18,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                            minWidth: 48, minHeight: 48),
                                        onPressed: () {
                                          Clipboard.setData(ClipboardData(
                                              text: message.text));
                                          HapticFeedback.lightImpact();
                                          FloatingToast.show(
                                            context,
                                            '已复制全文',
                                            tone: ToastTone.success,
                                          );
                                        },
                                        icon: Icon(Icons.copy_outlined,
                                            color: textMuted),
                                        tooltip: '复制',
                                      ),
                                      if (canRetryFailure)
                                        Wrap(
                                          spacing: 4,
                                          children: [
                                            _failureAction(
                                              label: '重试',
                                              icon: Icons.refresh_rounded,
                                              onPressed: onRegenerate,
                                            ),
                                            if (onEditPrompt != null)
                                              _failureAction(
                                                label: '编辑问题',
                                                icon: Icons.edit_outlined,
                                                onPressed: onEditPrompt!,
                                              ),
                                            if (onSwitchModel != null)
                                              _failureAction(
                                                label: '切换模型',
                                                icon: Icons.tune_rounded,
                                                onPressed: onSwitchModel!,
                                              ),
                                          ],
                                        )
                                      else if (isLast &&
                                          message.role ==
                                              MessageRole.assistant &&
                                          !running)
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          iconSize: 18,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                              minWidth: 48, minHeight: 48),
                                          onPressed: onRegenerate,
                                          icon: Icon(Icons.refresh_rounded,
                                              color: textMuted),
                                          tooltip: '重新生成',
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
            ),
          ],
        );
      }),
    );
  }

  Widget _failureAction({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) =>
      TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
      );
}

/// Delays expensive Markdown and math parsing for long completed replies.
class _DeferredMarkdown extends StatefulWidget {
  const _DeferredMarkdown({
    required this.data,
    required this.selectable,
    required this.builders,
    required this.textColor,
    required this.styleSheet,
  });

  final String data;
  final bool selectable;
  final Map<String, MarkdownElementBuilder> builders;
  final Color textColor;
  final MarkdownStyleSheet styleSheet;

  @override
  State<_DeferredMarkdown> createState() => _DeferredMarkdownState();
}

class _DeferredMarkdownState extends State<_DeferredMarkdown> {
  bool _ready = false;
  bool _markdownMetricRecorded = false;

  bool _shouldDefer(BuildContext context) => MarkdownRenderPolicy.shouldDefer(
        widget.data,
        MediaQuery.sizeOf(context).width,
      );

  @override
  void initState() {
    super.initState();
    _scheduleMarkdown();
  }

  @override
  void didUpdateWidget(covariant _DeferredMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _ready = false;
      _markdownMetricRecorded = false;
      _scheduleMarkdown();
    }
  }

  void _scheduleMarkdown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _ready = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final shouldDefer = _shouldDefer(context);
    if (shouldDefer && !_ready) {
      return SelectableText(
        widget.data,
        style: TextStyle(
          color: widget.textColor,
          height: 1.6,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
      );
    }
    if (!_markdownMetricRecorded) {
      _markdownMetricRecorded = true;
      final stopwatch = Stopwatch()..start();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        stopwatch.stop();
        MarkdownRenderMetrics.instance.recordMarkdown(
          durationMs: stopwatch.elapsedMilliseconds,
        );
      });
    }
    return MathMarkdown(
      data: widget.data,
      selectable: widget.selectable,
      builders: widget.builders,
      textColor: widget.textColor,
      styleSheet: widget.styleSheet,
    );
  }
}

/// 错误原文折叠块：遵循统一折叠行规范（13/400 textMuted + 12px 箭头，展开 220ms easeOutCubic）。
class _ErrorDetailBlock extends StatefulWidget {
  const _ErrorDetailBlock({required this.detail});

  final String detail;

  @override
  State<_ErrorDetailBlock> createState() => _ErrorDetailBlockState();
}

class _ErrorDetailBlockState extends State<_ErrorDetailBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final surface = isDark ? AppPalette.darkSurface : AppPalette.lightSurface;
    final hairline =
        isDark ? AppPalette.darkHairline : AppPalette.lightHairline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _expanded = !_expanded);
          },
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '技术细节',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    height: 1.55,
                    color: textMuted,
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _expanded ? 0.25 : 0.0,
                  duration: AppTokens.durationSlow,
                  curve: AppTokens.curveStandard,
                  child: Icon(
                    Icons.keyboard_arrow_right_rounded,
                    size: 12,
                    color: textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(AppTokens.radiusControl),
              border: Border.all(color: hairline, width: 1.0),
            ),
            child: SelectableText(
              widget.detail,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 1.55,
                color: textMuted,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ),
          crossFadeState:
              _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: AppTokens.durationSlow,
          firstCurve: AppTokens.curveStandard,
          secondCurve: AppTokens.curveStandard,
          sizeCurve: AppTokens.curveStandard,
        ),
      ],
    );
  }
}
