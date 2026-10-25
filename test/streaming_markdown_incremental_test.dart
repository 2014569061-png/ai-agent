import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' show PointerDeviceKind;
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/widgets/message_bubble.dart';
import 'package:mobile_agent/presentation/theme/desktop_theme.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/chat/widgets/streaming_markdown.dart';
import 'package:mobile_agent/presentation/markdown/markdown_render_policy.dart';
import 'package:mobile_agent/presentation/markdown/math_block.dart';

void main() {
  testWidgets('streaming blocks retain selection and copy across appends',
      (tester) async {
    String? selected, copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    Future<void> pump(String text) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SelectionArea(
        onSelectionChanged: (content) => selected = content?.plainText,
        child: StreamingMarkdown(
            data: text,
            textColor: Colors.black,
            tailStyle: const TextStyle(fontSize: 14),
            styleSheet: MarkdownStyleSheet(p: const TextStyle(fontSize: 14))),
      ))));
      await tester.pump();
    }

    await pump('first paragraph\n\ntail');
    final blocks = find.byType(DeferredMarkdown);
    final first = tester.widgetList<DeferredMarkdown>(blocks).single;
    await pump('first paragraph\n\nsecond paragraph\n\ntail');
    expect(tester.widgetList<DeferredMarkdown>(blocks).length, 2);
    expect(tester.widgetList<DeferredMarkdown>(blocks).first, same(first));
    final region =
        tester.state<SelectableRegionState>(find.byType(SelectableRegion));
    region.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    expect(selected, contains('first paragraph'));
    expect(selected, contains('second paragraph'));
    final beforeCopy = selected;
    region.contextMenuButtonItems
        .firstWhere((item) => item.type == ContextMenuButtonType.copy)
        .onPressed!();
    await tester.pump();
    expect(copied, beforeCopy);
    region.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    await pump(
        'first paragraph\n\nsecond paragraph\n\nthird paragraph\n\ntail');
    expect(tester.widgetList<DeferredMarkdown>(blocks).first, same(first));
    expect(selected, contains('first paragraph'));
    region.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    region.contextMenuButtonItems
        .firstWhere((item) => item.type == ContextMenuButtonType.copy)
        .onPressed!();
    await tester.pump();
    for (final word in [
      'first paragraph',
      'second paragraph',
      'third paragraph',
      'tail'
    ]) {
      expect(copied, contains(word));
    }
    expect(copied!.indexOf('first'), lessThan(copied!.indexOf('second')));
    expect(copied!.indexOf('second'), lessThan(copied!.indexOf('third')));
    // Dispose an actively selected tree: delegates must detach before disposal.
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('mouse drag crosses stable paragraph boundaries', (tester) async {
    String? selected;
    Future<void> pump(String text) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SelectionArea(
        onSelectionChanged: (content) => selected = content?.plainText,
        child: StreamingMarkdown(
            data: text,
            textColor: Colors.black,
            tailStyle: const TextStyle(fontSize: 14),
            styleSheet: MarkdownStyleSheet(p: const TextStyle(fontSize: 14))),
      ))));
      await tester.pump();
    }

    await pump('first paragraph\n\ntail');
    await pump('first paragraph\n\nsecond paragraph\n\ntail');
    Finder paragraph(String text) => find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText() == text);
    final first = tester.getRect(paragraph('first paragraph'));
    final second = tester.getRect(paragraph('second paragraph'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: first.centerLeft + const Offset(1, 0));
    await mouse.down(first.centerLeft + const Offset(1, 0));
    await mouse.moveTo(second.centerRight + const Offset(1, 0));
    await mouse.up();
    await tester.pump();
    expect(selected, contains('first paragraph'));
    expect(selected, contains('second paragraph'));
    await mouse.removePointer();
  });

  testWidgets(
      'real message bubble preserves previous stable block when appending paragraphs',
      (tester) async {
    Future<void> pump(String text) => tester.pumpWidget(MaterialApp(
          theme: DesktopTheme.apply(ThemeData.light()),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: MessageBubble(
            message: ChatMessage(
                role: MessageRole.assistant, parts: [MessagePart.text(text)]),
            isLast: true,
            running: true,
            onLongPress: null,
            onRegenerate: () {},
          ))),
        ));
    await pump('first **paragraph**\n\ntail');
    await tester.pump();
    final before = tester
        .widgetList<DeferredMarkdown>(find.byType(DeferredMarkdown))
        .first;
    await pump('first **paragraph**\n\nsecond **paragraph**\n\ntail');
    await tester.pump();
    final after = tester
        .widgetList<DeferredMarkdown>(find.byType(DeferredMarkdown))
        .toList();
    expect(after.length, 2);
    expect(after.first, same(before));
  });
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
