import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show ValueListenable, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../../../application/error_humanizer.dart';
import '../../../domain/models.dart';
import '../../l10n/app_strings.dart';
import '../chat_layout_controller.dart';
import '../../markdown/code_block.dart';
import '../../motion/motion_preferences.dart';
import '../../motion/nexus_haptics.dart';
import '../../motion/nexus_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/nexus_disclosure.dart';
import '../../widgets/floating_toast.dart';
import '../../widgets/speaking_wave.dart';
import 'attachment_strip.dart';
import 'reasoning_block.dart';
import 'streaming_markdown.dart';

/// 单个消息气泡：负责气泡布局、正文/思考/附件渲染与轻量操作（复制、重生成）。
/// 用户消息：底 brandSoft、无描边、文字 15/400、内边距 10×14、圆角 20 20 6 20、最大宽 78%
/// AI 消息（DeepSeek 式）：无头像、无卡片、无标题，正文铺满并与列表 16px 边距对齐；
/// 操作行左侧复制 / 朗读 / 分享，右侧弱化显示模型名 · 耗时与「重新生成」
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isLast,
    required this.running,
    this.runProgress,
    required this.onLongPress,
    required this.onRegenerate,
    this.onStop,
    this.onEditPrompt,
    this.onSwitchModel,
    this.onResumeRun,
    this.onSpeak,
    this.speakingListenable,
    this.selecting = false,
    this.onExitSelection,
  });

  final ChatMessage message;
  final bool isLast;
  final bool running;
  final ChatRunProgress? runProgress;
  final VoidCallback? onLongPress;
  final VoidCallback onRegenerate;
  final VoidCallback? onStop;
  final VoidCallback? onEditPrompt;
  final VoidCallback? onSwitchModel;

  /// 暂停提示卡上的「继续执行」：从断点续跑（null 时不显示该按钮）。
  final VoidCallback? onResumeRun;

  /// 朗读回调（仅助手消息且平台支持时非空）；null 表示不暴露该读屏动作。
  final VoidCallback? onSpeak;

  /// 朗读状态监听：存在时读屏动作标签在「朗读 / 停止朗读」之间切换。
  final ValueListenable<bool>? speakingListenable;

  /// 文本选择模式。**默认必须为 false**：正文一旦可选择（SelectableText），
  /// 长按会被文本选择器截走，气泡外层 `onLongPress`（消息菜单的唯一入口）就永远
  /// 收不到手势 —— 这是实测确认过的缺陷。需要局部选词时由菜单里的「选择文本」
  /// 临时打开，并用 [onExitSelection] 退出。
  final bool selecting;
  final VoidCallback? onExitSelection;

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
    // Z2：表格只保留横向细分隔线，表头左对齐 + 浅底，与正文对齐。
    final tableRule = BorderSide(
      color: textColor.withValues(alpha: isDark ? 0.12 : 0.10),
    );
    final tableHeadFill = BoxDecoration(
      color: textColor.withValues(alpha: isDark ? 0.06 : 0.04),
    );

    final imageParts =
        message.parts.where((part) => part.type == 'image').toList();
    final audioParts =
        message.parts.where((part) => part.type == 'audio').toList();
    final videoParts =
        message.parts.where((part) => part.type == 'video').toList();
    final hasText = message.parts
        .any((part) => part.type == 'text' && part.value.trim().isNotEmpty);
    // 可续跑暂停（预算用尽 / 连续失败熔断）：拆出暂停提示渲染成暂停卡，不再
    // 显示成「错误：遇到未预期的错误」；旧版本写入的正文同样兼容识别。
    final pauseSplit = splitRunPauseNotice(message.text);
    final pauseNotice =
        message.role == MessageRole.assistant ? pauseSplit.notice : null;
    // 复制 / 选择文本时去掉暂停标记里的元数据，只保留人话。
    final plainText = stripRunPauseMarker(message.text);
    // 错误消息拆分：人话正文正常渲染，原文技术细节折叠展示。
    final errorSplit =
        splitErrorDetail(pauseNotice == null ? message.text : pauseSplit.main);
    final errorDetail = errorSplit.detail;
    final canRetryFailure = errorDetail != null &&
        isLast &&
        message.role == MessageRole.assistant &&
        !running;

    // 流式生成中的最后一条助手消息使用纯文本，避免每个增量都重新解析 Markdown。
    final lightweight = !isUser && !isTool && isLast && running;
    final quietReply = !isUser &&
        !isTool &&
        !(running && isLast) &&
        errorDetail == null &&
        message.text.length <= 160 &&
        !message.text.contains('```') &&
        !message.parts.any((part) => part.type != 'text');

    // 无障碍：把原本只能长按触发的「复制 / 重新生成」暴露成读屏可操作的自定义
    // 语义动作（不新增可见按钮，避免改变视觉）。
    final customActions = <CustomSemanticsAction, VoidCallback>{
      const CustomSemanticsAction(label: '复制'): () {
        Clipboard.setData(ClipboardData(text: plainText));
        NexusHaptics.light(context);
        FloatingToast.show(
          context,
          '已复制全文',
          tone: ToastTone.success,
        );
      },
      if (isLast && message.role == MessageRole.assistant && !running)
        const CustomSemanticsAction(label: '重新生成'): onRegenerate,
    };

    // 正文统一用普通 Text；只有「选择文本」模式才切换为 SelectableText。
    //
    // 为什么不靠 Markdown 自带的可选性：`MarkdownBody(selectable: true)` 在
    // flutter_markdown 0.7.7+1 下实测**并不产出 SelectableText**（selectable 真假
    // 渲染结果一致），可选性不可控也不可测；而 SelectableText 提供原生拖选 +
    // 系统复制工具条，行为确定、可断言。代价是选择模式下看不到 Markdown 排版，
    // 这对"挑一段话复制"的场景可以接受。
    final plainStyle = TextStyle(
      color: textColor,
      height: 1.6,
      fontSize: AppTokens.fontSizeBody,
      fontWeight: FontWeight.w400,
    );

    final userTextStyle = TextStyle(
      color: isDark ? AppPalette.darkText : AppPalette.brandOnSoft,
      height: 1.5,
      fontSize: AppTokens.fontSizeBody,
      fontWeight: FontWeight.w400,
    );

    // 行内代码：与卡片同一级的浅填充（不再是刺眼的纯白块），等宽字体，
    // 字号为正文的 0.9 倍，与正文基线更协调。Markdown 的行内样式只支持
    // TextStyle，所以没有圆角和内边距（自定义行内组件会打断文字换行）。
    final inlineCodeStyle = TextStyle(
      color: textColor,
      fontSize: AppTokens.fontSizeBody * 0.9,
      fontFamily: AppTokens.fontFamilyMono,
      backgroundColor: textColor.withValues(alpha: isDark ? 0.10 : 0.06),
    );

    final body = isUser
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color:
                  isDark ? AppPalette.darkBrandSoft : AppPalette.lightBrandSoft,
              // DeepSeek 式用户气泡：浅色品牌底、无描边，右下角收成小圆角。
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(6),
              ),
            ),
            child: selecting
                ? SelectableText(message.text, style: userTextStyle)
                : Text(message.text, style: userTextStyle),
          )
        : selecting
            ? SelectableText(plainText, style: plainStyle)
            : lightweight
                ? StreamingMarkdown(
                    data: errorSplit.main,
                    textColor: textColor,
                    tailStyle: plainStyle,
                    styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                      p: plainStyle,
                      blockSpacing: 6,
                      listIndent: 24,
                      // 段落自带 6dp 上边距：段落之间、列表结束后接段落都是 12；
                      // 引导句与紧随其后的列表之间 6，列表项之间 6。
                      pPadding: const EdgeInsets.only(top: 6),
                      // 代码块由 CodeBlockWidget 自绘圆角卡片；去掉 Markdown 外层
                      // 默认的直角底板，避免四角露出、形成两层卡片错位。
                      codeblockPadding: EdgeInsets.zero,
                      codeblockDecoration: const BoxDecoration(),
                      h1: TextStyle(
                        color: textColor,
                        fontSize: AppTokens.fontSizeTitle,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                      h1Padding: const EdgeInsets.only(top: 20, bottom: 2),
                      h2: TextStyle(
                        color: textColor,
                        fontSize: AppTokens.fontSizeTitle,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                      h2Padding: const EdgeInsets.only(top: 20, bottom: 2),
                      h3: TextStyle(
                        color: textColor,
                        fontSize: AppTokens.fontSizeBody,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                      h3Padding: const EdgeInsets.only(top: 16, bottom: 2),
                      h4: TextStyle(
                        color: textColor,
                        fontSize: AppTokens.fontSizeBody,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                      h5: TextStyle(
                        color: textColor,
                        fontSize: AppTokens.fontSizeBody,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                      h6: TextStyle(
                        color: textColor,
                        fontSize: AppTokens.fontSizeBody,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                      listBullet: TextStyle(
                        color: textColor,
                        height: 1.6,
                        fontSize: AppTokens.fontSizeBody,
                        fontWeight: FontWeight.w400,
                      ),
                      code: inlineCodeStyle,
                      blockquote: TextStyle(
                        color: textColor,
                        height: 1.6,
                        fontSize: AppTokens.fontSizeBody,
                        fontWeight: FontWeight.w400,
                      ),
                      tableHead: TextStyle(
                        color: textColor,
                        fontSize: AppTokens.fontSizeCaption,
                        fontWeight: FontWeight.w500,
                      ),
                      tableBody: TextStyle(
                        color: textColor,
                        fontSize: AppTokens.fontSizeCaption,
                        height: 1.55,
                        fontWeight: FontWeight.w400,
                      ),
                      tableHeadAlign: TextAlign.left,
                      tableHeadCellsDecoration: tableHeadFill,
                      tableBorder: TableBorder(
                        top: tableRule,
                        bottom: tableRule,
                        horizontalInside: tableRule,
                      ),
                      tableCellsPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      tableHeadCellsPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
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
                  )
                : DeferredMarkdown(
                    data: errorSplit.main,
                    selectable: false,
                    builders: {'pre': CodeBlockBuilder()},
                    textColor: textColor,
                    styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                      p: plainStyle,
                      blockSpacing: 6,
                      listIndent: 24,
                      // 段落自带 6dp 上边距：段落之间、列表结束后接段落都是 12；
                      // 引导句与紧随其后的列表之间 6，列表项之间 6。
                      pPadding: const EdgeInsets.only(top: 6),
                      codeblockPadding: EdgeInsets.zero,
                      codeblockDecoration: const BoxDecoration(),
                      h1: TextStyle(
                        color: textColor,
                        fontSize: AppTokens.fontSizeTitle,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                      h1Padding: const EdgeInsets.only(top: 20, bottom: 2),
                      h2: TextStyle(
                        color: textColor,
                        fontSize: AppTokens.fontSizeTitle,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                      h2Padding: const EdgeInsets.only(top: 20, bottom: 2),
                      h3: TextStyle(
                        color: textColor,
                        fontSize: AppTokens.fontSizeBody,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                      h3Padding: const EdgeInsets.only(top: 16, bottom: 2),
                      h4: TextStyle(
                        color: textColor,
                        fontSize: AppTokens.fontSizeBody,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                      h5: TextStyle(
                        color: textColor,
                        fontSize: AppTokens.fontSizeBody,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                      h6: TextStyle(
                        color: textColor,
                        fontSize: AppTokens.fontSizeBody,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                      listBullet: TextStyle(
                        color: textColor,
                        height: 1.6,
                        fontSize: AppTokens.fontSizeBody,
                        fontWeight: FontWeight.w400,
                      ),
                      code: inlineCodeStyle,
                      blockquote: TextStyle(
                        color: textColor,
                        height: 1.6,
                        fontSize: AppTokens.fontSizeBody,
                        fontWeight: FontWeight.w400,
                      ),
                      tableHead: TextStyle(
                        color: textColor,
                        fontSize: AppTokens.fontSizeCaption,
                        fontWeight: FontWeight.w500,
                      ),
                      tableBody: TextStyle(
                        color: textColor,
                        fontSize: AppTokens.fontSizeCaption,
                        height: 1.55,
                        fontWeight: FontWeight.w400,
                      ),
                      tableHeadAlign: TextAlign.left,
                      tableHeadCellsDecoration: tableHeadFill,
                      tableBorder: TableBorder(
                        top: tableRule,
                        bottom: tableRule,
                        horizontalInside: tableRule,
                      ),
                      tableCellsPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      tableHeadCellsPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
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
        if (hasText) _AnswerReveal(animate: lightweight, child: body),
        // 选择模式的退出入口：必须留在气泡内、且始终可达 —— 进入选择模式后
        // 长按会被文本选择器占用，菜单打不开，所以不能依赖菜单来退出。
        if (selecting && onExitSelection != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onExitSelection,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text(AppStrings.finishSelecting),
            ),
          ),
        if (errorDetail != null) ...[
          const SizedBox(height: 6),
          _ErrorDetailBlock(detail: errorDetail),
        ],
        if (pauseNotice != null) ...[
          const SizedBox(height: 8),
          _RunPauseNoticeCard(
            notice: pauseNotice,
            actionable: isLast && !running,
            onContinue: onResumeRun,
            onRestart: onRegenerate,
            onSwitchModel: onSwitchModel,
          ),
        ],
      ],
    );

    final screenWidth = MediaQuery.sizeOf(context).width;
    final factor = ChatLayoutController.widthFactor.value;
    final showActions = !isUser && !isTool && !(running && isLast);
    final canRegenerate = isLast &&
        message.role == MessageRole.assistant &&
        !running &&
        !canRetryFailure &&
        pauseNotice == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(builder: (context, constraints) {
        final availableWidth =
            constraints.maxWidth.clamp(0.0, double.infinity).toDouble();
        final desiredWidth = factor == ChatLayoutController.adaptive
            ? (isUser ? screenWidth * 0.78 : availableWidth)
            : screenWidth * factor;
        final maxWidth = math.min(desiredWidth, availableWidth).toDouble();
        // DeepSeek 式排版：AI 回复不再有头像、卡片和标题，正文与列表左右边距
        // 对齐、铺满宽度；模型名与耗时移到操作行右侧，做成小号弱化文字。
        final Widget bubble;
        if (isUser) {
          bubble = IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Align(alignment: Alignment.centerRight, child: content),
              ],
            ),
          );
        } else if (isTool) {
          // 工具消息降一级：自适应宽度的胶囊芯片，14dp 图标 + 弱化小字，
          // 只显示结果摘要（完整结果在工具活动面板里查看）。
          bubble = _ToolResultChip(
            summary: toolResultSummary(message.text),
            textColor: textColor,
            textMuted: textMuted,
            isDark: isDark,
          );
        } else {
          bubble = Column(
            key: ValueKey(
                quietReply ? 'quiet-assistant-reply' : 'assistant-reply'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((reasoningText?.trim().isNotEmpty ?? false) ||
                  (running && isLast && (runProgress != null || !hasText)))
                ReasoningCompactBlock(
                  reasoning: reasoningText ?? '',
                  streaming: running && isLast,
                  hasStartedAnswer: hasText,
                  duration: message.reasoningDuration,
                  progress: isLast ? runProgress : null,
                  onStop: isLast ? onStop : null,
                ),
              content,
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
                ),
              if (showActions)
                _ReplyActionRow(
                  copyText: plainText,
                  textMuted: textMuted,
                  metaLabel: _replyMetaLabel(message),
                  onRegenerate: canRegenerate ? onRegenerate : null,
                  onSpeak: onSpeak,
                  speakingListenable: speakingListenable,
                ),
            ],
          );
        }
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: GestureDetector(
            onLongPress: isTool ? null : onLongPress,
            child: Tooltip(
              message: isUser ? '长按可编辑 / 复制' : '长按可朗读 / 复制',
              // 触发方式必须是 tap：`longPress` 会把长按从外层 GestureDetector
              // 手里抢走（实测对照：Tooltip(longPress)+Text 时父层收不到长按，
              // 改成 tap 就能收到），那样消息菜单就永远弹不出来。
              triggerMode: TooltipTriggerMode.tap,
              showDuration: const Duration(milliseconds: 1800),
              child: _SpeakSemantics(
                speakingListenable: speakingListenable,
                onSpeak: onSpeak,
                onLongPressHint: isUser ? '编辑或复制' : '朗读或复制',
                baseActions: customActions,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: bubble,
                ),
              ),
            ),
          ),
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

/// 可续跑暂停提示卡：预算用尽或连续失败熔断时显示在回复末尾。
///
/// 只有最后一条、且当前没有在运行时才显示操作按钮；历史里的旧提示只保留
/// 文字说明，避免在已经续跑过的旧消息上重复触发。
class _RunPauseNoticeCard extends StatelessWidget {
  const _RunPauseNoticeCard({
    required this.notice,
    required this.actionable,
    required this.onRestart,
    this.onContinue,
    this.onSwitchModel,
  });

  final RunPauseNotice notice;
  final bool actionable;
  final VoidCallback onRestart;
  final VoidCallback? onContinue;
  final VoidCallback? onSwitchModel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    const accent = AppPalette.warning;
    final buttonStyle = TextButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 10),
    );
    return Semantics(
      container: true,
      label: '任务已暂停：${notice.title}',
      child: Container(
        key: const ValueKey('run-pause-notice'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: isDark ? 0.14 : 0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pause_circle_outline_rounded,
                    size: 18, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    notice.title,
                    style: TextStyle(
                      color: textColor,
                      fontSize: AppTokens.fontSizeSubhead,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              notice.description,
              style: TextStyle(
                color: textMuted,
                fontSize: AppTokens.fontSizeCaption,
                height: 1.5,
              ),
            ),
            if (actionable)
              Wrap(
                spacing: 4,
                children: [
                  if (onContinue != null)
                    TextButton.icon(
                      key: const ValueKey('run-pause-continue'),
                      onPressed: onContinue,
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('继续执行'),
                      style: buttonStyle,
                    ),
                  TextButton.icon(
                    key: const ValueKey('run-pause-restart'),
                    onPressed: onRestart,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('从头重试'),
                    style: buttonStyle,
                  ),
                  if (onSwitchModel != null)
                    TextButton.icon(
                      key: const ValueKey('run-pause-switch-model'),
                      onPressed: onSwitchModel,
                      icon: const Icon(Icons.tune_rounded, size: 16),
                      label: const Text('切换模型'),
                      style: buttonStyle,
                    ),
                ],
              )
            else
              const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

/// 操作行右侧的弱化元信息：模型名 · 耗时（任一缺失时只显示另一项）。
String? _replyMetaLabel(ChatMessage message) {
  final model = message.modelName?.trim();
  final elapsed = message.elapsed;
  final parts = <String>[
    if (model != null && model.isNotEmpty) model,
    if (elapsed != null)
      '${(elapsed.inMilliseconds / 1000).toStringAsFixed(1)}s',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// AI 回复底部操作行（DeepSeek 式）：左侧复制 / 朗读 / 分享，右侧是弱化的
/// 模型名与耗时，以及最后一条回复的「重新生成」。
class _ReplyActionRow extends StatelessWidget {
  const _ReplyActionRow({
    required this.copyText,
    required this.textMuted,
    this.metaLabel,
    this.onRegenerate,
    this.onSpeak,
    this.speakingListenable,
  });

  final String copyText;
  final Color textMuted;
  final String? metaLabel;
  final VoidCallback? onRegenerate;
  final VoidCallback? onSpeak;
  final ValueListenable<bool>? speakingListenable;

  Widget _action({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) =>
      IconButton(
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: onPressed,
        icon: Icon(icon, color: textMuted),
        tooltip: tooltip,
      );

  @override
  Widget build(BuildContext context) {
    final speak = onSpeak;
    final speaking = speakingListenable;
    final regenerate = onRegenerate;
    final meta = metaLabel;
    return Row(
      children: [
        _action(
          icon: Icons.copy_outlined,
          tooltip: '复制',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: copyText));
            NexusHaptics.light(context);
            FloatingToast.show(context, '已复制全文', tone: ToastTone.success);
          },
        ),
        if (speak != null)
          speaking == null
              ? _action(
                  icon: Icons.volume_up_outlined,
                  tooltip: '朗读',
                  onPressed: speak,
                )
              : ValueListenableBuilder<bool>(
                  valueListenable: speaking,
                  builder: (context, active, _) => active
                      // M10：朗读中用声波条代替停止图标（伪波形，只表示正在发声）。
                      ? IconButton(
                          key: const ValueKey('speaking-wave-action'),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 48, minHeight: 48),
                          onPressed: speak,
                          tooltip: '停止朗读',
                          icon: SpeakingWave(
                            color: AppPalette.brandText(context),
                          ),
                        )
                      : _action(
                          icon: Icons.volume_up_outlined,
                          tooltip: '朗读',
                          onPressed: speak,
                        ),
                ),
        _action(
          icon: Icons.ios_share_rounded,
          tooltip: '分享',
          onPressed: () => unawaited(
            SharePlus.instance.share(ShareParams(text: copyText)),
          ),
        ),
        Expanded(
          child: meta == null
              ? const SizedBox.shrink()
              : Text(
                  meta,
                  key: const ValueKey('reply-meta'),
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTokens.fontSizeFootnote - 1,
                    color: textMuted,
                  ),
                ),
        ),
        if (regenerate != null)
          _action(
            icon: Icons.refresh_rounded,
            tooltip: '重新生成',
            onPressed: regenerate,
          ),
      ],
    );
  }
}

/// 消息气泡的读屏语义外壳。
///
/// 存在的唯一理由：朗读动作的标签要随朗读状态在「朗读 / 停止朗读」之间切换，
/// 而朗读状态来自一个 [ValueListenable]。把这一层单独拆出来，状态变化就只重建
/// 语义节点，不会顺带重建气泡正文（Markdown 解析成本高，且这是高频路径）。
class _SpeakSemantics extends StatelessWidget {
  const _SpeakSemantics({
    required this.onLongPressHint,
    required this.baseActions,
    required this.onSpeak,
    required this.speakingListenable,
    required this.child,
  });

  final String onLongPressHint;
  final Map<CustomSemanticsAction, VoidCallback> baseActions;
  final VoidCallback? onSpeak;
  final ValueListenable<bool>? speakingListenable;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final listenable = speakingListenable;
    final speak = onSpeak;
    if (listenable == null || speak == null) {
      return Semantics(
        onLongPressHint: onLongPressHint,
        customSemanticsActions: baseActions,
        child: child,
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: listenable,
      builder: (context, speaking, child) => Semantics(
        onLongPressHint: onLongPressHint,
        customSemanticsActions: {
          ...baseActions,
          CustomSemanticsAction(
            label: speaking ? AppStrings.stopSpeaking : AppStrings.speakAloud,
          ): speak,
        },
        child: child,
      ),
      child: child,
    );
  }
}

/// 错误原文折叠块：使用统一的顶部锚定尺寸过渡，避免长文本在交叉淡入期间
/// 同时保留两棵子树造成跳动或额外布局。
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NexusDisclosure(
          semanticLabel: _expanded ? '技术细节已展开，点击收起' : '技术细节已收起，点击展开',
          initiallyExpanded: false,
          onExpansionChanged: (expanded) =>
              setState(() => _expanded = expanded),
          headerPadding: const EdgeInsets.symmetric(vertical: 4),
          contentPadding: EdgeInsets.zero,
          title: Text(
            '技术细节',
            style: TextStyle(
              fontSize: AppTokens.fontSizeCaption,
              fontWeight: FontWeight.w400,
              height: 1.55,
              color: textMuted,
            ),
          ),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(AppTokens.radiusCard),
            ),
            child: SelectableText(
              widget.detail,
              style: TextStyle(
                fontSize: AppTokens.fontSizeCaption,
                fontWeight: FontWeight.w400,
                height: 1.55,
                color: textMuted,
                fontFamily: AppTokens.fontFamilyMono,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 流式回复首个 token 到达时正文淡入一次（M6）。
///
/// 只在流式中首次挂载时播放；历史消息和已完成消息不创建 controller。
/// 包装结构始终存在，流式结束切换为完整 Markdown 时子树不会被重新挂载。
/// 不对逐个 token 做动画。
class _AnswerReveal extends StatefulWidget {
  const _AnswerReveal({required this.animate, required this.child});

  final bool animate;
  final Widget child;

  @override
  State<_AnswerReveal> createState() => _AnswerRevealState();
}

class _AnswerRevealState extends State<_AnswerReveal>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) {
      // 淡入途中切换到 reduced / off：立即完成，不留运行中的 ticker。
      final controller = _controller;
      if (controller != null &&
          controller.isAnimating &&
          MotionPreferences.shouldReduceMotion(context)) {
        controller
          ..stop()
          ..value = 1.0;
      }
      return;
    }
    _decided = true;
    if (!widget.animate || MotionPreferences.shouldReduceMotion(context)) {
      return;
    }
    _controller = AnimationController(
      vsync: this,
      duration: NexusMotion.answerReveal,
    )..forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return FadeTransition(
      opacity: controller == null
          ? kAlwaysCompleteAnimation
          : CurvedAnimation(parent: controller, curve: NexusMotion.curveEnter),
      child: widget.child,
    );
  }
}

/// 工具消息的一行摘要：结构化结果（`ToolResult.encode` 的 JSON）取 message，
/// 失败时加「失败：」前缀；其他文本取第一行。只影响展示，不改消息内容。
@visibleForTesting
String toolResultSummary(String raw) {
  final text = raw.trim();
  final firstLine = text.split('\n').first.trim();
  if (!text.startsWith('{')) return firstLine;
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    // 不是合法 JSON：按普通文本显示第一行。
    return firstLine;
  }
  if (decoded is! Map) return firstLine;
  final message = decoded['message']?.toString().trim() ?? '';
  if (message.isEmpty) return firstLine;
  return decoded['ok'] == false ? '失败：$message' : message;
}

class _ToolResultChip extends StatelessWidget {
  const _ToolResultChip({
    required this.summary,
    required this.textColor,
    required this.textMuted,
    required this.isDark,
  });

  final String summary;
  final Color textColor;
  final Color textMuted;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '工具调用：$summary',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
        decoration: BoxDecoration(
          color: textColor.withValues(alpha: isDark ? 0.08 : 0.045),
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.handyman_outlined, size: 14, color: textMuted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textMuted,
                  fontSize: AppTokens.fontSizeCaption,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
