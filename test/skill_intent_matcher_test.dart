import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/skill_intent_matcher.dart';
import 'package:mobile_agent/infrastructure/skills/skill_parser.dart';

void main() {
  test('matches trigger and example text deterministically', () {
    const build = SkillMetadata(
      name: 'build',
      description: 'Build projects',
      triggers: ['交叉编译', '构建'],
      examples: ['帮我构建 ARM64 版本'],
    );
    const docs = SkillMetadata(
      name: 'docs',
      description: 'Write docs',
      triggers: ['文档'],
    );
    final matched = SkillIntentMatcher().match('请帮我做 ARM64 构建', [build, docs]);
    expect(matched.single.metadata.name, 'build');
  });
}
