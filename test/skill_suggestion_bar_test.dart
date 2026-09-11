import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/chat/widgets/skill_suggestion_bar.dart';

void main() {
  testWidgets('selects a suggested skill and supports dismissal',
      (tester) async {
    SkillSuggestionItem? selected;
    var dismissed = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SkillSuggestionBar(
          suggestions: const [
            SkillSuggestionItem(
              id: 'build',
              name: 'build',
              description: 'Build a project',
            ),
          ],
          onSelect: (item) => selected = item,
          onDismiss: () => dismissed = true,
        ),
      ),
    ));

    await tester.tap(find.text('build'));
    expect(selected?.id, 'build');

    await tester.tap(find.byTooltip('关闭技能建议'));
    expect(dismissed, isTrue);
  });

  testWidgets('removes a loaded session skill', (tester) async {
    String? removedId;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LoadedSkillBar(
          skills: const [
            SkillSuggestionItem(
              id: 'build',
              name: 'build',
              description: 'Build a project',
            ),
          ],
          onRemove: (id) => removedId = id,
        ),
      ),
    ));

    await tester.tap(find.text('build'));
    expect(removedId, 'build');
  });

  testWidgets('selects a slash skill reference', (tester) async {
    SkillSuggestionItem? selected;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SlashSkillReferenceBar(
          skills: const [
            SkillSuggestionItem(
              id: 'build',
              name: 'build',
              description: 'Build a project',
            ),
          ],
          onSelect: (item) => selected = item,
        ),
      ),
    ));

    await tester.tap(find.text('build'));
    expect(selected?.name, 'build');
  });
}
