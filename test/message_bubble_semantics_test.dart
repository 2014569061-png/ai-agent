import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/widgets/message_bubble.dart';
import 'package:mobile_agent/presentation/markdown/math_block.dart';
import 'package:mobile_agent/presentation/theme/desktop_theme.dart';

void main() {
  testWidgets(
      'desktop groups regenerate with reply actions without moving mobile actions',
      (tester) async {
    var regenerated = 0;
    for (final desktop in [true, false]) {
      await tester.pumpWidget(MaterialApp(
        theme:
            desktop ? DesktopTheme.apply(ThemeData.light()) : ThemeData.light(),
        home: Scaffold(
            body: SingleChildScrollView(
                child: MessageBubble(
          message: ChatMessage(
            role: MessageRole.assistant,
            modelName: 'long-model-name-for-reply-metadata-verification',
            parts: const [MessagePart.text('短回复，用于检查操作布局。')],
          ),
          isLast: true,
          running: false,
          onLongPress: null,
          onRegenerate: () => regenerated++,
          onSpeak: () {},
        ))),
      ));
      await tester.pumpAndSettle();
      final shareX = tester.getCenter(find.byTooltip('分享')).dx;
      final regenerateX = tester.getCenter(find.byTooltip('重新生成')).dx;
      expect(regenerateX - shareX,
          desktop ? lessThanOrEqualTo(60) : greaterThan(200));
      final meta =
          tester.widget<Text>(find.byKey(const ValueKey('reply-meta'))).data!;
      expect(find.byTooltip(meta), desktop ? findsOneWidget : findsNothing);
      await tester.tap(find.byTooltip('重新生成'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    expect(regenerated, 2);
  });

  testWidgets(
      'message actions do not merge an entire reply into one semantic label',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final speaking = ValueNotifier(false);
      addTearDown(speaking.dispose);
      var regenerated = 0, spoken = 0;
      final paragraphs = List.generate(
          40, (i) => 'Paragraph $i with accessible reply content.');
      await tester.pumpWidget(MaterialApp(
        theme: DesktopTheme.apply(ThemeData.light()),
        home: Scaffold(
            body: SingleChildScrollView(
                child: MessageBubble(
          message: ChatMessage(
              role: MessageRole.assistant,
              parts: [MessagePart.text(paragraphs.join('\n\n'))]),
          isLast: true,
          running: false,
          onLongPress: null,
          onRegenerate: () => regenerated++,
          onSpeak: () => spoken++,
          speakingListenable: speaking,
        ))),
      ));
      await tester.pump();
      final actionNode = find.byWidgetPredicate((w) =>
          w is Semantics &&
          (w.properties.customSemanticsActions?.keys
                  .any((a) => a.label == '复制') ??
              false));
      final node = tester.getSemantics(actionNode);
      expect(node.getSemanticsData().label, '助手回复');
      final labels = <String>[];
      void visit(SemanticsNode current) {
        labels.add(current.getSemanticsData().label);
        current.visitChildren((child) {
          visit(child);
          return true;
        });
      }

      visit(node);
      for (final paragraph in paragraphs) {
        expect(labels.join('\n'), contains(paragraph));
      }
      expect(labels.every((label) => label.length < 128), isTrue,
          reason:
              'Keep paragraph nodes readable without a multi-kilobyte merged label');
      Map<CustomSemanticsAction, VoidCallback> actions() => tester
          .widget<Semantics>(actionNode)
          .properties
          .customSemanticsActions!;
      expect(actions().keys.map((a) => a.label),
          containsAll(['复制', '重新生成', '朗读']));
      actions()
          .entries
          .firstWhere((entry) => entry.key.label == '重新生成')
          .value();
      actions().entries.firstWhere((entry) => entry.key.label == '朗读').value();
      expect(regenerated, 1);
      expect(spoken, 1);
      final markdown =
          tester.widgetList<MathMarkdown>(find.byType(MathMarkdown)).toList();
      speaking.value = true;
      await tester.pump();
      expect(actions().keys.map((a) => a.label), contains('停止朗读'));
      final after =
          tester.widgetList<MathMarkdown>(find.byType(MathMarkdown)).toList();
      expect(after.length, markdown.length);
      for (var i = 0; i < markdown.length; i++) {
        expect(after[i], same(markdown[i]));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
