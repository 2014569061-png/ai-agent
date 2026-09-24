import 'dart:async';

export '../infrastructure/database/app_database.dart' show SkillPack;
export '../infrastructure/skills/skill_installer.dart'
    show GithubSkillRef, SkillInstaller, SkillPackPreview;
export '../infrastructure/skills/skill_parser.dart'
    show SkillValidationException;
export '../infrastructure/skills/skill_store.dart' show SkillStore;

import '../infrastructure/skills/builtin_skills.dart';
import '../infrastructure/skills/skill_change_notifier.dart';

/// Application-facing catalog metadata for the Skill market.
///
/// Presentation code should not depend on the infrastructure seeder or its
/// process-local notifier directly. The database remains the source of truth;
/// this facade only exposes the curated names and refresh signal.
class SkillCatalog {
  SkillCatalog._();

  static Iterable<String> get featuredNames =>
      kBuiltinSkills.map((skill) => skill.name);

  static int get featuredCount => kBuiltinSkills.length;

  static Stream<void> get changes => SkillChangeNotifier.changes;
}
