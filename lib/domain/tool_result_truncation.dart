import 'dart:math' as math;

/// Pure text framing shared by context budgeting and tool summaries.
class ToolResultTruncation {
  static const marker = '…[工具结果过长，已截断]';

  /// Keep command context and final diagnostics without splitting UTF-16 pairs.
  /// The marker is additional framing, not included in the retained text limit.
  static String truncate(String text, int limit) {
    if (text.length <= limit) return text;
    final keep = math.max(0, limit);
    var head = (keep + 1) ~/ 2;
    var tail = text.length - keep ~/ 2;
    if (head > 0 && _highSurrogate(text.codeUnitAt(head - 1))) head--;
    if (tail < text.length && _lowSurrogate(text.codeUnitAt(tail))) tail++;
    return '${text.substring(0, head)}\n$marker'
        '（中间省略 ${tail - head} 字符）\n${text.substring(tail)}';
  }

  static bool _highSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
  static bool _lowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
}
