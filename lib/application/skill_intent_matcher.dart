import '../infrastructure/skills/skill_parser.dart';

class SkillIntentMatch {
  const SkillIntentMatch({required this.metadata, required this.score});

  final SkillMetadata metadata;
  final double score;
}

/// Local, deterministic intent matching used to suggest skills before a run.
/// It never enables a skill or executes a tool by itself.
class SkillIntentMatcher {
  List<SkillIntentMatch> match(String input, Iterable<SkillMetadata> skills,
      {double threshold = .35, int limit = 3}) {
    final normalized = _tokens(input);
    final matches = skills
        .map((metadata) {
          final signals = [
            ...metadata.triggers,
            ...metadata.examples,
            ...metadata.tags
          ];
          final score = signals.isEmpty
              ? 0.0
              : signals
                  .map((signal) => _overlap(normalized, _tokens(signal)))
                  .reduce((a, b) => a > b ? a : b);
          return SkillIntentMatch(metadata: metadata, score: score);
        })
        .where((match) => match.score >= threshold)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return matches.take(limit).toList(growable: false);
  }

  Set<String> _tokens(String value) => value
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'))
      .where((token) => token.length >= 2)
      .toSet();

  double _overlap(Set<String> input, Set<String> signal) {
    if (signal.isEmpty) return 0;
    return input.intersection(signal).length / signal.length;
  }
}
