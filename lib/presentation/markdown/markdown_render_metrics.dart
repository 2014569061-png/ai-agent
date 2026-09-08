import 'package:flutter/foundation.dart';

class MarkdownRenderMetrics extends ChangeNotifier {
  MarkdownRenderMetrics._();

  static final instance = MarkdownRenderMetrics._();

  int markdownRenderCount = 0;
  int markdownRenderTotalMs = 0;
  int codeBlockCount = 0;
  int highlightedCodeBlockCount = 0;
  int highlightTotalMs = 0;
  int longCodeFallbackCount = 0;

  void recordMarkdown({required int durationMs}) {
    markdownRenderCount++;
    markdownRenderTotalMs += durationMs;
    notifyListeners();
  }

  void recordCodeBlock({
    required bool highlighted,
    required int durationMs,
    required bool longFallback,
  }) {
    codeBlockCount++;
    if (highlighted) {
      highlightedCodeBlockCount++;
      highlightTotalMs += durationMs;
    }
    if (longFallback) longCodeFallbackCount++;
    notifyListeners();
  }

  double get averageMarkdownMs => markdownRenderCount == 0
      ? 0
      : markdownRenderTotalMs / markdownRenderCount;

  double get averageHighlightMs => highlightedCodeBlockCount == 0
      ? 0
      : highlightTotalMs / highlightedCodeBlockCount;

  void reset() {
    markdownRenderCount = 0;
    markdownRenderTotalMs = 0;
    codeBlockCount = 0;
    highlightedCodeBlockCount = 0;
    highlightTotalMs = 0;
    longCodeFallbackCount = 0;
    notifyListeners();
  }
}
