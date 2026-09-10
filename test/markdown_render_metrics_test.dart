import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/markdown/markdown_render_metrics.dart';

void main() {
  test('tracks render counts and average durations', () {
    final metrics = MarkdownRenderMetrics.instance;
    metrics.reset();

    metrics.recordMarkdown(durationMs: 4);
    metrics.recordMarkdown(durationMs: 6);
    metrics.recordCodeBlock(
        highlighted: true, durationMs: 8, longFallback: false);
    metrics.recordCodeBlock(
        highlighted: false, durationMs: 0, longFallback: true);

    expect(metrics.markdownRenderCount, 2);
    expect(metrics.averageMarkdownMs, 5);
    expect(metrics.codeBlockCount, 2);
    expect(metrics.highlightedCodeBlockCount, 1);
    expect(metrics.averageHighlightMs, 8);
    expect(metrics.longCodeFallbackCount, 1);
  });
}
