import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// 数学公式渲染（H2）：把 `$$...$$`（块级）与 `$...$`（行内）渲染为 LaTeX 公式，
/// 其余文本走 MarkdownBody。渲染失败回退原文。
class MathMarkdown extends StatelessWidget {
  const MathMarkdown({
    super.key,
    required this.data,
    this.selectable = true,
    this.styleSheet,
    this.builders = const {},
    this.textColor,
  });

  final String data;
  final bool selectable;
  final MarkdownStyleSheet? styleSheet;
  final Map<String, MarkdownElementBuilder> builders;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final color = textColor ?? Theme.of(context).colorScheme.onSurface;
    final segments = _split(data);
    if (segments.every((s) => !s.isMath)) {
      return MarkdownBody(
          data: data,
          selectable: selectable,
          shrinkWrap: true,
          builders: builders,
          styleSheet: styleSheet);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final seg in segments)
          seg.isMath
              ? _mathBlock(seg.text, color)
              : (seg.text.trim().isEmpty
                  ? const SizedBox.shrink()
                  : MarkdownBody(
                      data: seg.text,
                      selectable: selectable,
                      shrinkWrap: true,
                      builders: builders,
                      styleSheet: styleSheet)),
      ],
    );
  }

  Widget _mathBlock(String tex, Color color) {
    final isBlock = tex.contains('\n') || tex.trim().length > 24;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Math.tex(
        tex.trim(),
        textStyle: TextStyle(color: color, fontSize: 15),
        mathStyle: isBlock ? MathStyle.display : MathStyle.text,
        onErrorFallback: (error) =>
            Text(tex, style: TextStyle(color: color, fontFamily: 'monospace')),
      ),
    );
  }

  List<_MathSegment> _split(String text) {
    final segments = <_MathSegment>[];
    final pattern = RegExp(
      r'\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\]|\\\(([^\\\n]+?)\\\)|\$([^\$\n]+?)\$',
    );
    var last = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > last) {
        segments.add(_MathSegment(text.substring(last, match.start), false));
      }
      segments.add(_MathSegment(
        match.group(1) ??
            match.group(2) ??
            match.group(3) ??
            match.group(4) ??
            '',
        true,
      ));
      last = match.end;
    }
    if (last < text.length) {
      segments.add(_MathSegment(text.substring(last), false));
    }
    return segments;
  }
}

class _MathSegment {
  const _MathSegment(this.text, this.isMath);
  final String text;
  final bool isMath;
}
