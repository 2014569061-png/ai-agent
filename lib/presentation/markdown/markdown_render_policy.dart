/// Chooses when a completed reply should defer rich-text parsing.
///
/// The decision uses only string length and viewport width; no hashing is needed.
class MarkdownRenderPolicy {
  MarkdownRenderPolicy._();

  static const baseThreshold = 4000;
  static bool shouldDefer(String data, double viewportWidth) =>
      data.length > thresholdFor(viewportWidth);

  static int thresholdFor(double viewportWidth) {
    if (viewportWidth < 380) return 3000;
    if (viewportWidth >= 600) return 5000;
    return baseThreshold;
  }

  static void
      clearCache() {} // Compatibility: the O(1) decision needs no cache.

  /// Splits a response into a rich-text-safe prefix and a plain-text tail while
  /// it is still streaming. Only completed paragraphs are parsed as Markdown;
  /// the growing paragraph and an unclosed fenced code block stay plain text.
  static StreamingMarkdownSegments splitForStreaming(String data) =>
      StreamingMarkdownScanner().update(data);
}

/// Stateful line scanner. Only newly appended text is scanned for newlines;
/// complete lines are inspected once. Prefix validation still protects rewrites.
class StreamingMarkdownScanner {
  String _previous = '';
  int _offset = 0;
  int _lineStart = 0;
  int _stableEnd = 0;
  String _stable = '';
  String? _fence;
  int _fenceLength = 0;
  int scannedCharacters = 0;
  int resets = 0;

  StreamingMarkdownSegments update(String data) {
    if (!data.startsWith(_previous)) {
      _offset = _lineStart = _stableEnd = _fenceLength = 0;
      _stable = '';
      _fence = null;
      resets++;
    }
    final oldStableEnd = _stableEnd;
    scannedCharacters += data.length - _offset;
    var newline = data.indexOf('\n', _offset);
    while (newline >= 0) {
      final line = data.substring(_lineStart, newline).replaceAll('\r', '');
      final marker = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$').firstMatch(line);
      if (marker != null) {
        final fence = marker.group(1)!;
        final suffix = marker.group(2)!;
        if (_fence == null) {
          if (fence[0] != '`' || !suffix.contains('`')) {
            _fence = fence[0];
            _fenceLength = fence.length;
          }
        } else if (fence[0] == _fence &&
            fence.length >= _fenceLength &&
            suffix.trim().isEmpty) {
          _fence = null;
        }
      }
      if (_fence == null && _lineStart > 0 && line.trim().isEmpty) {
        _stableEnd = newline + 1;
      }
      _lineStart = newline + 1;
      newline = data.indexOf('\n', _lineStart);
    }
    _offset = data.length;
    _previous = data;
    if (oldStableEnd != _stableEnd || (_stable.isEmpty && _stableEnd > 0)) {
      _stable = data.substring(0, _stableEnd);
    }
    return StreamingMarkdownSegments(
        stable: _stable, tail: data.substring(_stableEnd));
  }
}

/// The stable portion can be parsed as Markdown without reflowing the tail.
class StreamingMarkdownSegments {
  const StreamingMarkdownSegments({required this.stable, required this.tail});
  const StreamingMarkdownSegments.empty()
      : stable = '',
        tail = '';

  final String stable;
  final String tail;

  bool get hasStableContent => stable.isNotEmpty;
}
