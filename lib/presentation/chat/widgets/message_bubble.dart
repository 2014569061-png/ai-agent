import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../application/error_humanizer.dart';
import '../../../domain/models.dart';
import '../chat_layout_controller.dart';
import '../../markdown/code_block.dart';
import '../../markdown/math_block.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/immersive_surface.dart';
import 'mascot_avatar.dart';
import 'message_metrics_sheet.dart';
import 'attachment_strip.dart';
import 'reasoning_block.dart';

/// 单个消息气泡：负责气泡布局、正文/思考/附件渲染与轻量操作（复制、重生成）。
/// 长按动作菜单与「重新生成」由页面通过回调注入，保持流式/状态逻辑留在 ChatPage。
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isLast,
    required this.running,
    required this.onLongPress,
    required this.onRegenerate,
  });

  final ChatMessage message;
  final bool isLast;
  final bool running;
  final VoidCallback? onLongPress;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == MessageRole.user;
    final isTool = message.role == MessageRole.tool;
    final glass = AppTheme.semanticOf(context);
    final assistantTextColor = glass.textPrimary;
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

    // 流式生成中的最后一条助手消息使用纯文本，避免每个增量都重新解析 Markdown。
    final lightweight = !isUser && !isTool && isLast && running;
    final isDark = theme.brightness == Brightness.dark;
    final body = isUser
        ? ImmersiveSurface(
            level: ImmersiveMaterialLevel.ultraThick,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
              topRight: Radius.circular(4),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            // 彩色玻璃：渐变自带透明度叠在高斯模糊上，保留蓝紫品牌色身份。
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [glass.userBubbleStart, glass.userBubbleEnd],
            ),
            boxShadow: isDark
                ? [
                    BoxShadow(
                      color: glass.userBubbleGlow,
                      blurRadius: 16,
                      spreadRadius: 1,
                    )
                  ]
                : null,
            child: SelectableText(
              message.text,
              style: TextStyle(
                color: glass.onGlass,
                height: 1.4,
                fontSize: 13.5,
                fontWeight: isDark ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          )
        : lightweight
            ? SelectableText(
                errorSplit.main,
                style: TextStyle(
                    color: assistantTextColor, height: 1.45, fontSize: 13.5),
              )
            : MathMarkdown(
                data: errorSplit.main,
                selectable: true,
                builders: {'pre': CodeBlockBuilder()},
                textColor: assistantTextColor,
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: TextStyle(
                      color: assistantTextColor, height: 1.45, fontSize: 13),
                  blockSpacing: 6,
                  listIndent: 18,
                  // 标题统一压到与系统正文协调的档位(flutter_markdown 默认 22-24,过大)
                  h1: TextStyle(
                      color: assistantTextColor,
                      fontSize: 16,
                      height: 1.35,
                      fontWeight: FontWeight.w700),
                  h1Padding: const EdgeInsets.only(top: 10, bottom: 4),
                  h2: TextStyle(
                      color: assistantTextColor,
                      fontSize: 15,
                      height: 1.35,
                      fontWeight: FontWeight.w700),
                  h2Padding: const EdgeInsets.only(top: 8, bottom: 4),
                  h3: TextStyle(
                      color: assistantTextColor,
                      fontSize: 14,
                      height: 1.4,
                      fontWeight: FontWeight.w600),
                  h3Padding: const EdgeInsets.only(top: 6, bottom: 2),
                  h4: TextStyle(
                      color: assistantTextColor,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600),
                  h5: TextStyle(
                      color: assistantTextColor,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600),
                  h6: TextStyle(
                      color: assistantTextColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                  listBullet: TextStyle(
                      color: assistantTextColor,
                      height: 1.45,
                      fontSize: 13),
                  code: TextStyle(
                      color: assistantTextColor,
                      fontSize: 12,
                      fontFamily: 'monospace'),
                  blockquote: TextStyle(
                      color: assistantTextColor,
                      height: 1.4,
                      fontSize: 13),
                  tableHead: TextStyle(
                      color: assistantTextColor,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600),
                  tableBody: TextStyle(
                      color: assistantTextColor,
                      fontSize: 12.5,
                      height: 1.35),
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
        ]);

    final screenWidth = MediaQuery.sizeOf(context).width;
    final factor = ChatLayoutController.widthFactor.value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LayoutBuilder(builder: (context, constraints) {
        final avatarSpace = isUser ? 0.0 : 44.0;
        final availableWidth = (constraints.maxWidth - avatarSpace)
            .clamp(0.0, double.infinity)
            .toDouble();
        final desiredWidth = factor == ChatLayoutController.adaptive
            ? (screenWidth < 640
                ? screenWidth * .85
                : math.min(screenWidth * .65, 720.0))
            : screenWidth * factor;
        final maxWidth = math.min(desiredWidth, availableWidth).toDouble();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment:
              isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!isUser) ...[
              if (isTool)
                CircleAvatar(
                    radius: 14,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    child: Icon(Icons.handyman_outlined,
                        size: 14, color: theme.colorScheme.onSurfaceVariant))
              else
                MascotAvatar(modelName: message.modelName ?? ''),
              const SizedBox(width: 8)
            ],
            GestureDetector(
              onLongPress: isTool ? null : onLongPress,
              child: Tooltip(
                message: isUser ? '长按可编辑 / 复制' : '长按可朗读 / 复制',
                triggerMode: TooltipTriggerMode.longPress,
                showDuration: const Duration(milliseconds: 1800),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: IntrinsicWidth(
                    child: isUser
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Align(
                                  alignment: Alignment.centerRight,
                                  child: content),
                            ],
                          )
                        : ImmersiveSurface(
                            level: ImmersiveMaterialLevel.ultraThick,
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_hasMeta(message) && !isTool)
                                    ReasoningCompactBlock(
                                      reasoning: reasoningText ?? '',
                                      leading:
                                          MessageStatusPill(message: message),
                                    ),
                                  Align(
                                      alignment: Alignment.centerLeft,
                                      child: content),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            iconSize: 16,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                                minWidth: 28, minHeight: 28),
                                            onPressed: () => Clipboard.setData(
                                                ClipboardData(
                                                    text: message.text)),
                                            icon: Icon(
                                                Icons.copy_outlined,
                                                color: glass.textMuted),
                                            tooltip: '复制'),
                                        if (isLast &&
                                            message.role ==
                                                MessageRole.assistant &&
                                            !running)
                                          IconButton(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              iconSize: 16,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                  minWidth: 28, minHeight: 28),
                                              onPressed: onRegenerate,
                                              icon: Icon(
                                                  Icons.refresh_rounded,
                                                  color: glass.textMuted),
                                              tooltip: '重新生成'),
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
            ),
          ],
        );
      }),
    );
  }

  static bool _hasMeta(ChatMessage message) =>
      message.modelName != null ||
      message.elapsed != null ||
      (message.usage?.totalTokens ?? 0) > 0;
}

/// 错误原文折叠块：默认收起，点开展开底层异常全文（样式对齐 ReasoningBlock 的弱化文本）。
class _ErrorDetailBlock extends StatelessWidget {
  const _ErrorDetailBlock({required this.detail});

  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.semanticOf(context);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        iconColor: colors.textMuted,
        collapsedIconColor: colors.textMuted,
        title: Text('技术细节',
            style: TextStyle(fontSize: 12, color: colors.textMuted)),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              detail,
              style:
                  TextStyle(fontSize: 12, height: 1.4, color: colors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
