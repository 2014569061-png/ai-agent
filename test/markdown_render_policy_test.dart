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
}
