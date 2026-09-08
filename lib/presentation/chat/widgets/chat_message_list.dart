import 'package:flutter/material.dart';

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
    this.trailingWidgets = const [],
    this.sessionKey,
    this.liveReply,
  });

  final List<ChatMessage> messages;
  final ScrollController controller;
  final bool running;
  final ValueChanged<int> onLongPress;
  final VoidCallback onRegenerate;
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
          message: message,
          isLast: index == widget.messages.length - 1,
          running: widget.running,
          onLongPress: () => widget.onLongPress(index),
          onRegenerate: widget.onRegenerate,
        );
      },
    );
  }
}
