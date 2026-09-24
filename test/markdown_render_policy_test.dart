import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/markdown/markdown_render_policy.dart';

void main() {
  setUp(MarkdownRenderPolicy.clearCache);

  test('adapts the defer threshold to viewport width', () {
    expect(MarkdownRenderPolicy.thresholdFor(360), 3000);
    expect(MarkdownRenderPolicy.thresholdFor(480), 4000);
    expect(MarkdownRenderPolicy.thresholdFor(800), 5000);
  });

  test('caches the rendering decision for repeated content', () {
    const shortReply = 'short reply';
    final longReply = 'x' * 4500;

    expect(MarkdownRenderPolicy.shouldDefer(shortReply, 480), isFalse);
    expect(MarkdownRenderPolicy.shouldDefer(longReply, 480), isTrue);
    expect(MarkdownRenderPolicy.shouldDefer(longReply, 480), isTrue);
  });

  test('keeps the growing paragraph outside the Markdown prefix', () {
    const response = '## 第一部分\n\n这段内容还在持续输出';

    final segments = MarkdownRenderPolicy.splitForStreaming(response);

    expect(segments.stable, '## 第一部分\n\n');
    expect(segments.tail, '这段内容还在持续输出');
  });

  test('keeps an unclosed fenced code block in the plain-text tail', () {
    const response = '已完成说明。\n\n```dart\nvoid main() {';

    final segments = MarkdownRenderPolicy.splitForStreaming(response);

    expect(segments.stable, '已完成说明。\n\n');
    expect(segments.tail, '```dart\nvoid main() {');
  });
}
