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
          // Explicit triggers are strongest. Name/description are fallbacks
          // for older Skill packages that do not declare triggers yet.
          final signals = <String, double>{
            for (final signal in metadata.triggers) signal: 1.0,
            for (final signal in metadata.examples) signal: .85,
            for (final signal in metadata.tags) signal: .75,
            metadata.name.replaceAll(RegExp(r'[-_]'), ' '): .65,
            metadata.description: .45,
          };
          var score = 0.0;
          for (final entry in signals.entries) {
            final weighted =
                _overlap(normalized, _tokens(entry.key)) * entry.value;
            if (weighted > score) score = weighted;
          }
          return SkillIntentMatch(metadata: metadata, score: score);
        })
        .where((match) => match.score >= threshold)
        .toList()
      ..sort((a, b) {
        final score = b.score.compareTo(a.score);
        return score == 0 ? a.metadata.name.compareTo(b.metadata.name) : score;
      });
    return matches.take(limit).toList(growable: false);
  }

  Set<String> _tokens(String value) {
    final tokens = <String>{};
    final chunks = value
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'))
        .where((token) => token.length >= 2);
    for (final chunk in chunks) {
      tokens.add(chunk);
      // Chinese requests are commonly written without spaces. Add short
      // n-grams so “构建安卓应用” can match “构建” and “安卓应用”.
      if (!RegExp(r'[\u4e00-\u9fff]').hasMatch(chunk)) continue;
      for (var size = 2; size <= 3; size++) {
        if (chunk.length < size) continue;
        for (var i = 0; i <= chunk.length - size; i++) {
          tokens.add(chunk.substring(i, i + size));
        }
      }
    }
    return tokens;
  }

  double _overlap(Set<String> input, Set<String> signal) {
    if (signal.isEmpty) return 0;
    return input.intersection(signal).length / signal.length;
  }
}
