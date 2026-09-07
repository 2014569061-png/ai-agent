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
  });

  final List<ChatMessage> messages;
  final ScrollController controller;
  final bool running;
  final ValueChanged<int> onLongPress;
  final VoidCallback onRegenerate;
  final List<Widget> trailingWidgets;

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  static const _initialWindow = 40;
  static const _pageSize = 20;
  late int _start;

  @override
  void initState() {
    super.initState();
    _resetWindow();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length < oldWidget.messages.length ||
        (widget.messages.isNotEmpty &&
            oldWidget.messages.isNotEmpty &&
            widget.messages.first.text != oldWidget.messages.first.text)) {
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
        _start == 0) {
      return;
    }
    final oldStart = _start;
    setState(() {
      _start = (oldStart - _pageSize).clamp(0, oldStart);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.controller.hasClients) {
        widget.controller.jumpTo((widget.controller.position.pixels + 900)
            .clamp(0.0, widget.controller.position.maxScrollExtent));
      }
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
        final message = widget.messages[index];
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
