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
    this.trailingWidgets = const [],
    this.sessionKey,
    this.liveReply,
  });

  final List<ChatMessage> messages;
  final ScrollController controller;
  final bool running;
  final ValueChanged<int> onLongPress;
  final VoidCallback onRegenerate;
  final VoidCallback? onEditPrompt;
  final VoidCallback? onSwitchModel;
  final List<Widget> trailingWidgets;
  final String? sessionKey;
  final LiveReply? liveReply;

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
    if (sessionChanged || countDecreased) {
      _resetWindow();
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

  void _onScroll() {
    if (!widget.controller.hasClients ||
        widget.controller.position.pixels > 80 ||
        _start == 0 ||
        _loadingOlder) {
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
        );
      },
    );
  }
}
