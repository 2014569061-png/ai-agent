import 'dart:async';
import 'package:flutter/material.dart';
import 'assistant_entry_surface.dart';
import '../../domain/assistant_input_decision.dart';
export '../../domain/assistant_input_decision.dart';

/// External input becomes a draft only after this visible, editable review.
/// Dismissal pauses this entry; it must not reopen itself on the next frame.
class AssistantInputReviewSheet extends StatefulWidget {
  const AssistantInputReviewSheet(
      {super.key,
      required this.title,
      required this.initialText,
      this.source,
      this.expiresAt,
      this.validFor,
      this.attachmentCount = 0,
      this.warning});
  final String title, initialText;
  final String? source, warning;
  final DateTime? expiresAt;
  final Duration? validFor;
  final int attachmentCount;
  @override
  State<AssistantInputReviewSheet> createState() =>
      _AssistantInputReviewSheetState();
}

class _AssistantInputReviewSheetState extends State<AssistantInputReviewSheet>
    with WidgetsBindingObserver {
  late final _text = TextEditingController(text: widget.initialText);
  Timer? _timer;
  bool _expired = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final expires = widget.expiresAt;
    if (expires != null) {
      final wallDelay = expires.difference(DateTime.now());
      final delay = widget.validFor != null && widget.validFor! < wallDelay
          ? widget.validFor!
          : wallDelay;
      _timer = Timer(delay.isNegative ? Duration.zero : delay, _expire);
    }
  }

  void _expire() {
    if (!mounted) return;
    _text.clear();
    setState(() => _expired = true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.expiresAt != null && state == AppLifecycleState.paused) {
      _expire();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _text.dispose();
    super.dispose();
  }

  void _use() {
    if (_expired || !AssistantEntrySurface.canConsume(context)) return;
    if (_text.text.length > (widget.expiresAt == null ? 16000 : 8000)) return;
    if (widget.expiresAt != null &&
        !DateTime.now().isBefore(widget.expiresAt!)) {
      _expire();
      return;
    }
    if (_text.text.trim().isEmpty && widget.attachmentCount == 0) return;
    Navigator.of(context).pop(AssistantInputDecision.use(_text.text));
  }

  @override
  Widget build(BuildContext context) => SafeArea(
          child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              if (widget.source != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(widget.source!)),
              const SizedBox(height: 8),
              const Text('请检查并删除敏感信息。加入草稿后仍需手动发送；页面和分享内容不代表操作授权。'),
              if (widget.warning != null) Text(widget.warning!),
              if (widget.attachmentCount > 0)
                Text('附带 ${widget.attachmentCount} 张图片，将与现有附件保留在同一草稿。'),
              const SizedBox(height: 12),
              TextField(
                  key: const ValueKey('assistant-entry-review-text'),
                  controller: _text,
                  enabled: !_expired,
                  minLines: 3,
                  maxLines: 7,
                  maxLength: widget.expiresAt == null ? 16000 : 8000,
                  decoration: const InputDecoration(
                      labelText: '核对内容', border: OutlineInputBorder())),
              if (_expired) const Text('页面文字已过期或离开前台，请重新读取。'),
              const SizedBox(height: 12),
              FilledButton(
                  key: const ValueKey('assistant-entry-review-use'),
                  onPressed: _expired ? null : _use,
                  child: const Text('加入当前草稿')),
              Wrap(spacing: 12, children: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('稍后处理')),
                TextButton(
                    onPressed: () => Navigator.of(context)
                        .pop(const AssistantInputDecision.discard()),
                    child: const Text('丢弃此输入')),
              ]),
            ])),
      ));
}
