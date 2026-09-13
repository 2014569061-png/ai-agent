import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/skills/builtin_skills.dart';
import 'package:mobile_agent/infrastructure/skills/skill_installer.dart';
import 'package:mobile_agent/infrastructure/skills/skill_parser.dart';

class _FakePathProvider extends PathProviderPlatform {
  final Directory root;
  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('builtin-skills-test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('内置技能 frontmatter 均可解析且名称合法', () async {
    expect(kBuiltinSkills, isNotEmpty);
    for (final skill in kBuiltinSkills) {
      final text = await rootBundle.loadString(skill.assetPath);
      final parsed = parseSkillMarkdown(text);
      expect(parsed.metadata.name, skill.name);
      expect(parsed.metadata.version, matches(RegExp(r'^\d+\.\d+\.\d+$')));
      expect(parsed.metadata.description, isNotEmpty);
      expect(parsed.body, contains('## '));
    }
  });

  test('ensureInstalled 幂等：同版本重复安装只保留一条记录', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final seeder = BuiltinSkillSeeder();
    await seeder.ensureInstalled(db);
    await seeder.ensureInstalled(db);

    final packs = await db.allSkillPacks();
    expect(packs.map((s) => s.name),
        containsAll(kBuiltinSkills.map((s) => s.name)));
    for (final builtin in kBuiltinSkills) {
      expect(
        packs.where((s) => s.name == builtin.name).length,
        1,
        reason: '${builtin.name} 不应重复安装',
      );
    }
    for (final pack in packs) {
      expect(pack.source, startsWith('builtin:'));
      final skillFile = File('${pack.installRoot}/SKILL.md');
      expect(skillFile.existsSync(), isTrue, reason: pack.installRoot);
    }
  });

  test('版本或内容变化时原地更新并保留同一 id', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final seeder = BuiltinSkillSeeder();
    await seeder.ensureInstalled(db);
    final first = await db.findSkillPackByName('mobile-dev-basics');
    expect(first, isNotNull);

    final text =
        await rootBundle.loadString('assets/skills/mobile-dev-basics/SKILL.md');
    final bytes = Uint8List.fromList(text.codeUnits);
    final updated = SkillPackPreview(
      source: GithubSkillRef(
        original: 'builtin:mobile-dev-basics',
        owner: 'local',
        repo: 'mobile-dev-basics',
        ref: 'builtin',
        subPath: null,
      ),
      metadata: const SkillMetadata(
        name: 'mobile-dev-basics',
        description: 'updated description',
        version: '1.1.0',
      ),
      fileContents: {'SKILL.md': bytes},
      totalBytes: bytes.length,
      sha256Hex: 'changed',
    );
    await SkillInstaller().install(db, updated);

    final second = await db.findSkillPackByName('mobile-dev-basics');
    expect(second!.id, first!.id, reason: '更新必须保留同一 id');
    expect(second.version, '1.1.0');
  });
}
