import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/infrastructure/skills/skill_installer.dart';
import 'package:mobile_agent/infrastructure/skills/skill_parser.dart';

void main() {
  group('Skill parser', () {
    test('parses the trimmed Codex SKILL.md format', () {
      final result = parseSkillMarkdown('''
---
name: writing_helper
description: Helps improve writing quality
author: nexus
version: 1.2.0
tags: [writing, polish]
---

Follow the user's language and preserve their intent.
''');

      expect(result.metadata.name, 'writing_helper');
      expect(result.metadata.description, 'Helps improve writing quality');
      expect(result.metadata.author, 'nexus');
      expect(result.metadata.version, '1.2.0');
      expect(result.metadata.tags, ['writing', 'polish']);
      expect(result.body, contains('preserve their intent'));
    });

    test('rejects an invalid skill name', () {
      expect(
        () => parseSkillMarkdown('''
---
name: Unsafe Skill
description: invalid
---
body
'''),
        throwsA(isA<SkillValidationException>()),
      );
    });

    test('requires a description', () {
      expect(
        () => parseSkillMarkdown('''
---
name: valid_skill
---
body
'''),
        throwsA(isA<SkillValidationException>()),
      );
    });
  });

  group('GitHub skill source', () {
    final installer = SkillInstaller();

    test('parses repository shorthand', () {
      final ref = installer.parseInput('openai/example-skill');
      expect(ref.owner, 'openai');
      expect(ref.repo, 'example-skill');
      expect(ref.ref, 'HEAD');
      expect(ref.subPath, isNull);
    });

    test('parses a repository subdirectory', () {
      final ref = installer.parseInput(
        'https://github.com/acme/skills/tree/main/writing/helper',
      );
      expect(ref.fullRepo, 'acme/skills');
      expect(ref.ref, 'main');
      expect(ref.subPath, 'writing/helper');
    });

    test('rejects non-GitHub URLs', () {
      expect(
        () => installer.parseInput('https://example.com/skill.tar.gz'),
        throwsA(isA<SkillValidationException>()),
      );
    });
  });
}
