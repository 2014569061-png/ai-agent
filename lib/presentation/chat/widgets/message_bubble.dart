import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../domain/models.dart';
import '../chat_layout_controller.dart';
import '../../markdown/code_block.dart';
import '../../markdown/math_block.dart';
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
    final assistantTextColor = theme.brightness == Brightness.dark
        ? const Color(0xFFEDF1F8)
        : const Color(0xFF243B53);
    final imageParts =
        message.parts.where((part) => part.type == 'image').toList();
    final audioParts =
        message.parts.where((part) => part.type == 'audio').toList();
    final videoParts =
        message.parts.where((part) => part.type == 'video').toList();
    final hasText = message.parts
        .any((part) => part.type == 'text' && part.value.trim().isNotEmpty);

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
              colors: isDark
                  ? [
                      const Color(0xFF4C8DFF).withValues(alpha: 0.55),
                      const Color(0xFF9333EA).withValues(alpha: 0.55),
                    ]
                  : [
                      const Color(0xFFFFFFFF).withValues(alpha: 0.62),
                      const Color(0xFFC7D7FE).withValues(alpha: 0.50),
                    ],
            ),
            boxShadow: isDark
                ? [
                    BoxShadow(
                      color: const Color(0xFF9333EA).withValues(alpha: 0.3),
                      blurRadius: 16,
                      spreadRadius: 1,
                    )
                  ]
                : null,
            child: SelectableText(
              message.text,
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF1E293B),
                height: 1.4,
                fontSize: 15,
                fontWeight: isDark ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          )
        : lightweight
            ? SelectableText(
                message.text,
                style: TextStyle(
                    color: assistantTextColor, height: 1.45, fontSize: 15),
              )
            : MathMarkdown(
                data: message.text,
                selectable: true,
                builders: {'pre': CodeBlockBuilder()},
                textColor: assistantTextColor,
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: TextStyle(
                      color: assistantTextColor, height: 1.45, fontSize: 15),
                  blockSpacing: 8,
                  listIndent: 20,
                ),
              );

    final reasoningText = message.reasoning;
    final content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (reasoningText != null && reasoningText.isNotEmpty) ...[
            ReasoningBlock(reasoning: reasoningText),
            const SizedBox(height: 8),
          ],
          AttachmentStrip(parts: [...imageParts, ...audioParts, ...videoParts]),
          if (hasText) body,
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
                                    MessageStatusPill(message: message),
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
                                            icon: const Icon(
                                                Icons.copy_outlined,
                                                color: Color(0xFF94A3B8)),
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
                                              icon: const Icon(
                                                  Icons.refresh_rounded,
                                                  color: Color(0xFF94A3B8)),
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
