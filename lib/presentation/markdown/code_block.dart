import '../widgets/floating_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import 'markdown_render_metrics.dart';

/// 轻量级正则语法高亮器，用于代码块内的关键字/字符串/注释/数字着色。
///
/// 基于单次正则扫描 + 分组判断，覆盖 Dart/JS/Python/Java 等常见语言的
/// 基础高亮，无需引入重量级高亮库。
class SimpleSyntaxHighlighter implements SyntaxHighlighter {
  const SimpleSyntaxHighlighter({
    this.keywordColor = const Color(0xFFA626A4),
    this.stringColor = const Color(0xFF50A14F),
    this.commentColor = const Color(0xFF9DA0A6),
    this.numberColor = const Color(0xFF986801),
  });

  final Color keywordColor;
  final Color stringColor;
  final Color commentColor;
  final Color numberColor;

  static const Set<String> _keywords = {
    'abstract',
    'as',
    'assert',
    'async',
    'await',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'default',
    'do',
    'else',
    'enum',
    'export',
    'extends',
    'extension',
    'final',
    'finally',
    'for',
    'func',
    'function',
    'get',
    'if',
    'implements',
    'import',
    'in',
    'interface',
    'is',
    'late',
    'let',
    'mixin',
    'new',
    'null',
    'on',
    'operator',
    'package',
    'private',
    'protected',
    'public',
    'return',
    'sealed',
    'set',
    'static',
    'super',
    'switch',
    'this',
    'throw',
    'try',
    'type',
    'typedef',
    'var',
    'void',
    'while',
    'with',
    'yield',
    'true',
    'false',
    'int',
    'double',
    'String',
    'bool',
    'num',
    'dynamic',
    'Object',
    'List',
    'Map',
    'Set',
    'Future',
    'Stream',
    'unknown',
  };

  // 分组顺序：1 行注释 / 2 块注释 / 3 字符串 / 4 数字 / 5 标识符
  static final RegExp _tokenRegex = RegExp(
    r'(//[^\n]*|#[^\n]*)' // 1 行注释
    r'|(/\*[\s\S]*?\*/)' // 2 块注释
    r'''|("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`)''' // 3 字符串
    r'|(\b\d+(?:\.\d+)?\b)' // 4 数字
    r'|(\b[A-Za-z_][A-Za-z0-9_]*\b)', // 5 标识符
  );

  @override
  TextSpan format(String source) {
    final spans = <TextSpan>[];
    var lastEnd = 0;
    for (final match in _tokenRegex.allMatches(source)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: source.substring(lastEnd, match.start)));
      }
      final token = match.group(0)!;
      Color? color;
      if (match.group(1) != null || match.group(2) != null) {
        color = commentColor;
      } else if (match.group(3) != null) {
        color = stringColor;
      } else if (match.group(4) != null) {
        color = numberColor;
      } else if (match.group(5) != null && _keywords.contains(token)) {
        color = keywordColor;
      }
      spans.add(TextSpan(
        text: token,
        style: color == null ? null : TextStyle(color: color),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < source.length) {
      spans.add(TextSpan(text: source.substring(lastEnd)));
    }
    return TextSpan(children: spans);
  }
}

/// 自定义 `<pre>` 代码块渲染器：顶部语言标签 + 一键复制 + 语法高亮。
class CodeBlockBuilder extends MarkdownElementBuilder {
  CodeBlockBuilder();

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) => null;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = element.textContent;
    final language = _extractLanguage(element);
    return CodeBlockWidget(language: language, code: code);
  }

  String? _extractLanguage(md.Element element) {
    for (final child in element.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'code') {
        final classAttr = child.attributes['class'];
        if (classAttr == null) return null;
        final match = RegExp(r'language-([\w+#.-]+)').firstMatch(classAttr);
        return match?.group(1);
      }
    }
    return null;
  }
}

/// 代码块卡片：标题栏（语言名 + 复制）+ 横向滚动的高亮代码。
class CodeBlockWidget extends StatefulWidget {
  const CodeBlockWidget(
      {super.key, required this.language, required this.code});

  final String? language;
  final String code;

  @override
  State<CodeBlockWidget> createState() => _CodeBlockWidgetState();
}

class _CodeBlockWidgetState extends State<CodeBlockWidget> {
  static const _maxHighlightChars = 12000;
  bool _highlighted = false;
  bool _codeMetricRecorded = false;
  TextSpan? _highlightedSpan;
  ScrollPosition? _scrollPosition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _watchViewport());
  }

  @override
  void didUpdateWidget(covariant CodeBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code ||
        oldWidget.language != widget.language) {
      _highlighted = false;
      _codeMetricRecorded = false;
      _highlightedSpan = null;
      _detachScrollListener();
      WidgetsBinding.instance.addPostFrameCallback((_) => _watchViewport());
    }
  }

  void _watchViewport() {
    if (!mounted) return;
    if (widget.code.length > _maxHighlightChars) {
      _detachScrollListener();
      return;
    }
    final position = Scrollable.maybeOf(context)?.position;
    if (position == null) {
      _highlightIfVisible();
      return;
    }
    _scrollPosition = position;
    position.addListener(_onScroll);
    _highlightIfVisible();
  }

  void _onScroll() => _highlightIfVisible();

  void _highlightIfVisible() {
    if (!mounted || _highlighted) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final bottom = topLeft.dy + renderObject.size.height;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    if (bottom < -200 || topLeft.dy > viewportHeight + 200) return;
    setState(() => _highlighted = true);
    _detachScrollListener();
  }

  void _detachScrollListener() {
    _scrollPosition?.removeListener(_onScroll);
    _scrollPosition = null;
  }

  @override
  void dispose() {
    _detachScrollListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final background = dark ? const Color(0xFF1B2230) : const Color(0xFFF6F8FA);
    final headerBackground =
        dark ? const Color(0xFF222A3A) : const Color(0xFFEEF1F4);
    final border = dark ? const Color(0xFF2C3547) : const Color(0xFFE2E8F0);
    final headerText = dark ? const Color(0xFFA6B2C6) : const Color(0xFF64748B);
    final codeColor = dark ? const Color(0xFFE6EDF3) : const Color(0xFF24292F);
    final trimmed = widget.code.trimRight();
    final longFallback = widget.code.length > _maxHighlightChars;

    final highlighter = SimpleSyntaxHighlighter(
      keywordColor: dark ? const Color(0xFFC678DD) : const Color(0xFFA626A4),
      stringColor: dark ? const Color(0xFF98C379) : const Color(0xFF50A14F),
      commentColor: dark ? const Color(0xFF5C6773) : const Color(0xFF9DA0A6),
      numberColor: dark ? const Color(0xFFD19A66) : const Color(0xFF986801),
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: headerBackground,
            child: Row(
              children: [
                Icon(Icons.code, size: 14, color: headerText),
                const SizedBox(width: 6),
                Text(
                  widget.language ?? '代码',
                  style: TextStyle(
                    fontSize: 12,
                    color: headerText,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Clipboard.setData(ClipboardData(text: trimmed));
                      FloatingToast.show(context, '代码已复制');
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy, size: 14, color: headerText),
                          const SizedBox(width: 4),
                          Text('复制',
                              style:
                                  TextStyle(fontSize: 12, color: headerText)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Scrollbar(
            thumbVisibility: false,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: _highlighted
                  ? _buildHighlighted(
                      highlighter, trimmed, codeColor, longFallback)
                  : _buildPlain(trimmed, codeColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlain(String code, Color color) {
    _recordCodeMetric(
      highlighted: false,
      durationMs: 0,
      longFallback: code.length > _maxHighlightChars,
    );
    return SelectableText(
      code,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        color: color,
        height: 1.5,
      ),
    );
  }

  Widget _buildHighlighted(SimpleSyntaxHighlighter highlighter, String code,
      Color color, bool longFallback) {
    final stopwatch = Stopwatch();
    if (_highlightedSpan == null) {
      stopwatch.start();
      _highlightedSpan = highlighter.format(code);
      stopwatch.stop();
    }
    _recordCodeMetric(
      highlighted: true,
      durationMs: stopwatch.elapsedMilliseconds,
      longFallback: longFallback,
    );
    return SelectableText.rich(
      _highlightedSpan!,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        color: color,
        height: 1.5,
      ),
    );
  }

  void _recordCodeMetric({
    required bool highlighted,
    required int durationMs,
    required bool longFallback,
  }) {
    if (_codeMetricRecorded) return;
    _codeMetricRecorded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MarkdownRenderMetrics.instance.recordCodeBlock(
        highlighted: highlighted,
        durationMs: durationMs,
        longFallback: longFallback,
      );
    });
  }
}
