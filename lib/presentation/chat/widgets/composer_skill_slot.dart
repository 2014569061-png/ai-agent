import 'package:flutter/material.dart';

import '../../../application/chat_controller.dart';
import '../composer_skill_slot.dart';
import 'skill_suggestion_bar.dart';

class ComposerSkillPromptSlot extends StatelessWidget {
  const ComposerSkillPromptSlot({
    super.key,
    required this.running,
    required this.slashSkills,
    required this.suggestions,
    required this.sessionSkills,
    required this.onSlashSelect,
    required this.onSuggestionSelect,
    required this.onSuggestionDismiss,
    required this.onRemove,
  });

  final bool running;
  final List<SkillSuggestionItem> slashSkills;
  final List<SkillSuggestionItem> suggestions;
  final List<SessionSkillInstruction> sessionSkills;
  final ValueChanged<SkillSuggestionItem> onSlashSelect;
  final ValueChanged<SkillSuggestionItem> onSuggestionSelect;
  final VoidCallback onSuggestionDismiss;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final slot = resolveComposerSkillSlot(
      running: running,
      hasSlashMatches: slashSkills.isNotEmpty,
      hasSuggestions: suggestions.isNotEmpty,
      hasLoadedSkills: sessionSkills.isNotEmpty,
    );
    return switch (slot) {
      ComposerSkillSlot.slash => SlashSkillReferenceBar(
          skills: slashSkills,
          onSelect: onSlashSelect,
        ),
      ComposerSkillSlot.suggestion => SkillSuggestionBar(
          suggestions: suggestions,
          onSelect: onSuggestionSelect,
          onDismiss: onSuggestionDismiss,
        ),
      ComposerSkillSlot.loaded => LoadedSkillBar(
          skills: sessionSkills
              .map((skill) => SkillSuggestionItem(
                    id: skill.id,
                    name: skill.name,
                    description: '',
                  ))
              .toList(growable: false),
          onRemove: onRemove,
        ),
      ComposerSkillSlot.none => const SizedBox.shrink(),
    };
  }
}
