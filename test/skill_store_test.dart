import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/skills/skill_store.dart';

void main() {
  late AppDatabase db;
  late Directory root;
  final store = SkillStore();

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    root = await Directory.systemTemp.createTemp('nexus-skill-store-');
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<SkillPack> installPack({
    String id = 'demo',
    String name = 'demo-skill',
    String description = 'short description',
    bool enabled = true,
    bool frozen = false,
  }) async {
    final directory = Directory('${root.path}${Platform.pathSeparator}$id')
      ..createSync(recursive: true);
    final body = '''---
name: $name
description: valid skill
---

${'body line\n' * 40}''';
    File('${directory.path}${Platform.pathSeparator}SKILL.md')
        .writeAsStringSync(body);
    File('${directory.path}${Platform.pathSeparator}guide.txt')
        .writeAsStringSync('resource\n' * 40);
    if (frozen) {
      File('${directory.path}${Platform.pathSeparator}.nexus-frozen')
          .writeAsStringSync('frozen');
    }
    final pack = SkillPack(
      id: id,
      name: name,
      description: description,
      version: '1.0.0',
      source: 'github.com/example/repo',
      repo: 'example/repo',
      ref: 'main',
      installRoot: directory.path,
      fileListJson: jsonEncode(['SKILL.md', 'guide.txt']),
      enabled: enabled,
      installedAt: DateTime.now(),
      updatedAt: DateTime.now(),
      sha256: 'hash',
    );
    await db.saveSkillPack(pack);
    return pack;
  }

  test(
      'injects one-line indexes, truncates descriptions, and skips frozen packs',
      () async {
    await installPack(
      id: 'long',
      description: 'x' * 200,
    );
    await installPack(id: 'frozen', name: 'frozen-skill', frozen: true);
    await installPack(id: 'disabled', name: 'disabled-skill', enabled: false);

    final block = await store.buildInjectionBlock(db, budget: 2000);
    final longLine =
        block.split('\n').firstWhere((line) => line.contains('- demo-skill |'));
    // 索引行不再暴露内部 id：行首就是 skills_read 要传的名称。
    expect(longLine, isNot(contains('long |')));
    final description = longLine.split(' | ').last;
    expect(description.length, lessThanOrEqualTo(80));
    expect(block, contains('skills_read, resources:guide.txt'));
    expect(block, isNot(contains('frozen-skill')));
    expect(block, isNot(contains('disabled-skill')));
  });

  test('respects the index budget and reports omitted skills', () async {
    await installPack(id: 'one', name: 'one-skill');
    await installPack(id: 'two', name: 'two-skill');
    await installPack(id: 'three', name: 'three-skill', description: 'x' * 200);

    final block = await store.buildInjectionBlock(db, budget: 256);
    expect(block, contains('其余 Skill'));
    expect(block, isNot(contains('three-skill')));
    expect(block.length, lessThanOrEqualTo(32000));
  });

  test('frozen skills cannot expose body or resources', () async {
    final pack = await installPack(frozen: true);
    expect(store.readBody(pack), isNull);
    expect(store.readResource(pack, 'guide.txt'), isNull);
  });

  test('body and resource reads are truncated without escaping the root',
      () async {
    final pack = await installPack();
    final body = store.readBody(pack, maxChars: 20)!;
    final resource = store.readResource(pack, 'guide.txt', maxChars: 12)!;
    expect(body, contains('[内容已截断]'));
    expect(resource, contains('[资源已截断]'));
    expect(store.readResource(pack, '../SKILL.md'), isNull);
    expect(store.readResource(pack, '/etc/passwd'), isNull);
  });
}
