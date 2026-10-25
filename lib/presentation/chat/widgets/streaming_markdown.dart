import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../../markdown/code_block.dart';
import '../../markdown/math_block.dart';
import '../../markdown/markdown_render_policy.dart';
import '../../markdown/markdown_render_metrics.dart';
import '../../theme/app_tokens.dart';

/// Renders stable Markdown without re-parsing the still-growing tail.
class StreamingMarkdown extends StatefulWidget {
  const StreamingMarkdown({
    super.key,
    required this.data,
    required this.textColor,
    required this.tailStyle,
    required this.styleSheet,
  });

  final String data;
  final Color textColor;
  final TextStyle tailStyle;
  final MarkdownStyleSheet styleSheet;

  @override
  State<StreamingMarkdown> createState() => _StreamingMarkdownState();
}

class _StreamingMarkdownState extends State<StreamingMarkdown> {
  final _scanner = StreamingMarkdownScanner();
  final List<Widget> _stableChildren = [];
  String _renderedStable = '';
  Object? _signature;

  @override
  Widget build(BuildContext context) {
    final segments = _scanner.update(widget.data);
    final signature = (
      widget.textColor,
      widget.tailStyle,
      widget.styleSheet,
      Theme.of(context),
      MediaQuery.textScalerOf(context)
    );
    // Reference definitions and lists can change earlier blocks. Keep their
    // complete Markdown semantics; ordinary completed paragraphs are immutable.
    final coupled = RegExp(r'^ {0,3}(?:\[[^\]]+\]:|[-*+] |[0-9]+[.)] |> |\$\$)',
            multiLine: true)
        .hasMatch(segments.stable);
    if (signature != _signature ||
        !segments.stable.startsWith(_renderedStable) ||
        coupled) {
      _stableChildren.clear();
      _renderedStable = '';
      _signature = signature;
    }
    if (segments.stable.length > _renderedStable.length) {
      final delta = segments.stable.substring(_renderedStable.length);
      _stableChildren.add(RepaintBoundary(
          child: DeferredMarkdown(
        data: delta,
        selectable: false,
        builders: {'pre': CodeBlockBuilder()},
        textColor: widget.textColor,
        styleSheet: widget.styleSheet,
      )));
      _renderedStable = segments.stable;
    }
    if (_stableChildren.isEmpty) {
      return Text(segments.tail, style: widget.tailStyle);
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ..._stableChildren,
          if (segments.tail.isNotEmpty)
            Text(segments.tail, style: widget.tailStyle)
        ]);
  }
}

/// Delays expensive Markdown and math parsing for long completed replies.
class DeferredMarkdown extends StatefulWidget {
  const DeferredMarkdown({
    super.key,
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
  State<DeferredMarkdown> createState() => DeferredMarkdownState();
}

class DeferredMarkdownState extends State<DeferredMarkdown> {
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
  void didUpdateWidget(covariant DeferredMarkdown oldWidget) {
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
      // 占位渲染也必须跟随 selectable：占位阶段若用 SelectableText，长按依旧会被
      // 文本选择器截走 —— 那会让"长消息"这一整类气泡的菜单时灵时不灵。
      final placeholderStyle = TextStyle(
        color: widget.textColor,
        height: 1.6,
        fontSize: AppTokens.fontSizeBody,
        fontWeight: FontWeight.w400,
      );
      return widget.selectable
          ? SelectableText(widget.data, style: placeholderStyle)
          : Text(widget.data, style: placeholderStyle);
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
