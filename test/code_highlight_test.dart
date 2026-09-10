import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/presentation/markdown/code_block.dart';

void main() {
  test('highlighter preserves source text and colors known tokens', () {
    const highlighter = SimpleSyntaxHighlighter();
    const source = 'final x = "hello"; // comment\nvar n = 42;';
    final span = highlighter.format(source);

    expect(span.toPlainText(), source);

    final spans = <TextSpan>[];
    void collect(InlineSpan node) {
      if (node is TextSpan) {
        spans.add(node);
        node.children?.forEach(collect);
      }
    }

    collect(span);

    final keywordSpans = spans
        .where((s) => s.style?.color == const Color(0xFFA626A4))
        .map((s) => s.text)
        .toList();
    final stringSpans = spans
        .where((s) => s.style?.color == const Color(0xFF50A14F))
        .map((s) => s.text)
        .toList();
    final commentSpans = spans
        .where((s) => s.style?.color == const Color(0xFF9DA0A6))
        .map((s) => s.text)
        .toList();
    final numberSpans = spans
        .where((s) => s.style?.color == const Color(0xFF986801))
        .map((s) => s.text)
        .toList();

    expect(keywordSpans, contains('final'));
    expect(keywordSpans, contains('var'));
    expect(stringSpans, contains('"hello"'));
    expect(commentSpans, contains('// comment'));
    expect(numberSpans, contains('42'));
  });

  test('highlighter leaves plain text uncolored', () {
    const highlighter = SimpleSyntaxHighlighter();
    final span = highlighter.format('plain text without tokens');
    expect(span.toPlainText(), 'plain text without tokens');
  });

  testWidgets('code block renders before and after deferred highlighting',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CodeBlockWidget(
            language: 'dart',
            code: 'final value = 42;',
          ),
        ),
      ),
    ));

    expect(find.byType(CodeBlockWidget), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
