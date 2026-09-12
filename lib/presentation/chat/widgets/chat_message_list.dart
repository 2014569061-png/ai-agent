import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../../domain/models.dart';
import 'message_bubble.dart';

/// 长会话消息列表：完整消息仍由上层持有，列表只按窗口构建可见消息。
class ChatMessageList extends StatefulWidget {
  const ChatMessageList({
    super.key,
    required this.messages,
    required this.controller,
    required this.running,
    required this.onLongPress,
    required this.onRegenerate,
    this.onEditPrompt,
    this.onSwitchModel,
    this.onSpeak,
    this.speakingListenable,
    this.trailingWidgets = const [],
    this.sessionKey,
    this.liveReply,
    this.onLoadOlder,
  });

  final List<ChatMessage> messages;
  final ScrollController controller;
  final bool running;
  final ValueChanged<int> onLongPress;
  final VoidCallback onRegenerate;
  final VoidCallback? onEditPrompt;
  final VoidCallback? onSwitchModel;

  /// 长按朗读（G1）：仅助手消息、且平台支持 TTS 时非空。
  final ValueChanged<int>? onSpeak;
  final ValueListenable<bool>? speakingListenable;
  final List<Widget> trailingWidgets;
  final String? sessionKey;
  final LiveReply? liveReply;

  /// 内存窗口耗尽（_start 到 0）后向 DB 拉更早一页的回调（B-2 键集分页）。
  /// 返回 true 表示有新页已前插进 [messages]；null/false 表示无更早或未接线。
  final Future<bool> Function()? onLoadOlder;

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  static const _initialWindow = 40;
  static const _pageSize = 20;
  late int _start;
  bool _loadingOlder = false;

  @override
  void initState() {
    super.initState();
    _resetWindow();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sessionChanged =
        widget.sessionKey != null && widget.sessionKey != oldWidget.sessionKey;
    final countDecreased = widget.messages.length < oldWidget.messages.length;
    // DB「加载更早」会把新页前插：窗口起点同步前移，才能保持同一条消息的
    // 全局索引（= ValueKey）恒定、Element 继续复用。用 identical 识别前插，
    // 与「运行中向尾部追加新消息」区分开。
    final delta = widget.messages.length - oldWidget.messages.length;
    final prepended = delta > 0 &&
        oldWidget.messages.isNotEmpty &&
        widget.messages.length > delta &&
        identical(widget.messages[delta], oldWidget.messages[0]);
    if (sessionChanged || countDecreased) {
      _resetWindow();
    } else if (prepended) {
      _start += delta;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _resetWindow() {
    _start = (widget.messages.length - _initialWindow)
        .clamp(0, widget.messages.length);
  }

  bool _dbExhausted = false;

  void _onScroll() {
    if (!widget.controller.hasClients ||
        widget.controller.position.pixels > 80 ||
        _loadingOlder) {
      return;
    }
    if (_start == 0) {
      // 内存窗口已全部展示：转 DB 键集翻页（未接线或已到底则静默停止）。
      if (widget.onLoadOlder == null || _dbExhausted) return;
      _fetchOlderFromDb();
      return;
    }
    _loadingOlder = true;
    final oldStart = _start;
    final oldExtent = widget.controller.position.maxScrollExtent;
    final oldPixels = widget.controller.position.pixels;
    setState(() {
      _start = (oldStart - _pageSize).clamp(0, oldStart);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.controller.hasClients) {
        final newExtent = widget.controller.position.maxScrollExtent;
        final delta = newExtent - oldExtent;
        if (delta > 0) {
          widget.controller.jumpTo((oldPixels + delta)
              .clamp(0.0, widget.controller.position.maxScrollExtent));
        }
      }
      if (mounted) _loadingOlder = false;
    });
  }

  Future<void> _fetchOlderFromDb() async {
    _loadingOlder = true;
    final oldExtent = widget.controller.hasClients
        ? widget.controller.position.maxScrollExtent
        : 0.0;
    final oldPixels = widget.controller.hasClients
        ? widget.controller.position.pixels
        : 0.0;
    bool hadMore;
    try {
      hadMore = await widget.onLoadOlder!();
    } catch (_) {
      hadMore = false;
    }
    if (!mounted) return;
    if (!hadMore) {
      setState(() => _dbExhausted = true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.controller.hasClients) return;
      final delta = widget.controller.position.maxScrollExtent - oldExtent;
      if (delta > 0) {
        widget.controller.jumpTo((oldPixels + delta)
            .clamp(0.0, widget.controller.position.maxScrollExtent));
      }
      if (mounted) _loadingOlder = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.messages.length - _start;
    final totalCount = count + widget.trailingWidgets.length;
    return ListView.builder(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      itemCount: totalCount,
      // F-4：预渲染视口外 400px，快速滚动时不露白；消息气泡自带独立状态，
      // 关闭自动 KeepAlive 省下不可见子树的存活开销。
      scrollCacheExtent: const ScrollCacheExtent.pixels(400),
      addAutomaticKeepAlives: false,
      itemBuilder: (context, localIndex) {
        if (localIndex >= count) {
          return widget.trailingWidgets[localIndex - count];
        }
        final index = _start + localIndex;
        final storedMessage = widget.messages[index];
        final live = widget.liveReply;
        final message = live != null && live.messageIndex == index
            ? ChatMessage(
                role: storedMessage.role,
                parts: [MessagePart.text(live.text)],
                toolCallId: storedMessage.toolCallId,
                toolCalls: storedMessage.toolCalls,
                modelName: storedMessage.modelName,
                usage: storedMessage.usage,
                elapsed: storedMessage.elapsed,
                ttft: storedMessage.ttft,
                reasoning: live.reasoning,
              )
            : storedMessage;
        return MessageBubble(
          // 用全局索引（= _start + localIndex）作 key：窗口只会改变 localIndex
          // （加载更早消息时 _start 前移），同一条消息的全局索引恒定，因此该 key
          // 跨重建稳定，可让 Element 复用、避免整屏气泡重建。
          key: ValueKey<int>(index),
          message: message,
          isLast: index == widget.messages.length - 1,
          running: widget.running,
          onLongPress: () => widget.onLongPress(index),
          onRegenerate: widget.onRegenerate,
          onEditPrompt: widget.onEditPrompt,
          onSwitchModel: widget.onSwitchModel,
          // 朗读只对助手正文开放（工具气泡与用户消息不提供该读屏动作）。
          onSpeak: message.role == MessageRole.assistant && widget.onSpeak != null
              ? () => widget.onSpeak!(index)
              : null,
          speakingListenable: widget.speakingListenable,
        );
      },
    );
  }
}
