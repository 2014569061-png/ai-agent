import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';

class SkillSuggestionItem {
  const SkillSuggestionItem({
    required this.id,
    required this.name,
    required this.description,
  });

  final String id;
  final String name;
  final String description;
}

/// A compact, explicit entry point for locally matched skills.
/// It does not imply a skill is enabled until the user taps it.
class SkillSuggestionBar extends StatelessWidget {
  const SkillSuggestionBar({
    super.key,
    required this.suggestions,
    required this.onSelect,
    required this.onDismiss,
  });

  final List<SkillSuggestionItem> suggestions;
  final ValueChanged<SkillSuggestionItem> onSelect;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? AppPalette.darkSurface : AppPalette.lightSurface;
    final hairline = dark ? AppPalette.darkHairline : AppPalette.lightHairline;
    final muted = dark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final brandSoft =
        dark ? AppPalette.darkBrandSoft : AppPalette.lightBrandSoft;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          border: Border.all(color: hairline),
        ),
        child: Row(
          children: [
            const SizedBox(width: 10),
            const Icon(Icons.auto_awesome_outlined,
                size: 15, color: AppPalette.brand),
            const SizedBox(width: 6),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: suggestions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final item = suggestions[index];
                  return Tooltip(
                    message: item.description,
                    child: Material(
                      color: brandSoft,
                      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                      child: InkWell(
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusPill),
                        onTap: () => onSelect(item),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 9),
                          child: Center(
                            child: Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppPalette.brandOnSoft,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            IconButton(
              iconSize: 16,
              tooltip: '关闭技能建议',
              color: muted,
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

/// Makes session-only context visible and reversible before a run begins.
class LoadedSkillBar extends StatelessWidget {
  const LoadedSkillBar({
    super.key,
    required this.skills,
    required this.onRemove,
  });

  final List<SkillSuggestionItem> skills;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    if (skills.isEmpty) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? AppPalette.darkSurface : AppPalette.lightSurface;
    final hairline = dark ? AppPalette.darkHairline : AppPalette.lightHairline;
    final muted = dark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          border: Border.all(color: hairline),
        ),
        child: Row(
          children: [
            const SizedBox(width: 10),
            const Icon(Icons.extension_rounded,
                size: 15, color: AppPalette.success),
            const SizedBox(width: 6),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: skills.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final skill = skills[index];
                  return Tooltip(
                    message: '从当前会话移除 ${skill.name}',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusPill),
                        onTap: () => onRemove(skill.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                skill.name,
                                style: TextStyle(
                                  color: muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 3),
                              Icon(Icons.close_rounded, size: 14, color: muted),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows name completion after the user types `/` in the composer.
class SlashSkillReferenceBar extends StatelessWidget {
  const SlashSkillReferenceBar({
    super.key,
    required this.skills,
    required this.onSelect,
  });

  final List<SkillSuggestionItem> skills;
  final ValueChanged<SkillSuggestionItem> onSelect;

  @override
  Widget build(BuildContext context) {
    if (skills.isEmpty) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? AppPalette.darkSurface : AppPalette.lightSurface;
    final hairline = dark ? AppPalette.darkHairline : AppPalette.lightHairline;
    final muted = dark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          border: Border.all(color: hairline),
        ),
        child: Row(
          children: [
            const SizedBox(width: 10),
            Text('/', style: TextStyle(color: muted, fontSize: 15)),
            const SizedBox(width: 6),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: skills.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final skill = skills[index];
                  return Tooltip(
                    message: skill.description,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusPill),
                        onTap: () => onSelect(skill),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Center(
                            child: Text(
                              skill.name,
                              style: TextStyle(
                                color: muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
