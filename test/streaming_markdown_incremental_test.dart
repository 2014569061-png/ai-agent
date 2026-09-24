import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/chat/widgets/streaming_markdown.dart';
import 'package:mobile_agent/presentation/markdown/markdown_render_policy.dart';
import 'package:mobile_agent/presentation/markdown/math_block.dart';

void main() {
  test('incremental scanner agrees with a fresh scanner at every boundary', () {
    const text = 'Intro\r\n\r\n````dart\ncode\n```\n\nnot closed\n````\n\n'
        'paragraph\n\n~~~text\ncode\n~~~\n\ntail';
    final scanner = StreamingMarkdownScanner();
    for (var i = 0; i <= text.length; i++) {
      final input = text.substring(0, i);
      final actual = scanner.update(input);
      final expected = MarkdownRenderPolicy.splitForStreaming(input);
      expect(actual.stable, expected.stable, reason: 'prefix $i');
      expect(actual.tail, expected.tail, reason: 'prefix $i');
    }
    expect(scanner.scannedCharacters, text.length);
    expect(scanner.resets, 0);
    final rewritten = scanner.update('Different\n\ntail');
    expect(rewritten.stable, 'Different\n\n');
    expect(scanner.resets, 1);
  });

  test('shorter closing fence does not prematurely stabilize a code block', () {
    final result = MarkdownRenderPolicy.splitForStreaming(
        'intro\n\n````\ncode\n```\n\ntail');
    expect(result.stable, 'intro\n\n');
    expect(result.tail, startsWith('````'));
  });

  test('long append-only paragraph is scanned once, not once per frame', () {
    final scanner = StreamingMarkdownScanner();
    final text = 'x' * 50000;
    for (var i = 100; i <= text.length; i += 100) {
      scanner.update(text.substring(0, i));
    }
    expect(scanner.scannedCharacters, 50000);
  });

  testWidgets(
      'tail updates reuse stable math/markdown widget and theme changes invalidate',
      (tester) async {
    Future<void> pump(String tail, Brightness brightness, {double size = 14}) =>
        tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
              body: StreamingMarkdown(
            data: '**stable**\n\n$tail',
            textColor:
                brightness == Brightness.light ? Colors.black : Colors.white,
            tailStyle: const TextStyle(fontSize: 14),
            styleSheet: MarkdownStyleSheet(p: TextStyle(fontSize: size)),
          )),
        ));
    await pump('one', Brightness.light);
    await tester.pump();
    final before = tester.widget<MathMarkdown>(find.byType(MathMarkdown));
    for (var i = 0; i < 20; i++) {
      await pump('tail $i', Brightness.light);
    }
    expect(
        tester.widget<MathMarkdown>(find.byType(MathMarkdown)), same(before));
    await pump('tail 20', Brightness.light, size: 18);
    await tester.pumpAndSettle();
    expect(tester.widget<MathMarkdown>(find.byType(MathMarkdown)),
        isNot(same(before)));
    await pump('tail 20', Brightness.dark);
    await tester.pumpAndSettle();
    expect(tester.widget<MathMarkdown>(find.byType(MathMarkdown)),
        isNot(same(before)));
  });
}
