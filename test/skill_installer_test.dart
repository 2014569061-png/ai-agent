import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/skills/skill_installer.dart';
import 'package:mobile_agent/infrastructure/skills/skill_parser.dart';

const _skillMd = '''
---
name: demo-skill
description: 演示技能
version: 0.0.1
---

按步骤执行任务。
''';

Archive _archive() {
  final archive = Archive();
  archive
      .addFile(ArchiveFile.bytes('repo-main/SKILL.md', utf8.encode(_skillMd)));
  return archive;
}

Uint8List _tarGz(Archive archive) {
  final tar = TarEncoder().encode(archive);
  return Uint8List.fromList(const GZipEncoder().encode(tar));
}

Uint8List _zip(Archive archive) =>
    Uint8List.fromList(ZipEncoder().encode(archive));

GithubSkillRef _ref() => GithubSkillRef(
    original: 'o/r', owner: 'o', repo: 'r', ref: 'main', subPath: null);

void main() {
  late SkillInstaller installer;
  setUp(() => installer = SkillInstaller());

  test('installs a well-formed archive', () async {
    final archive = _archive()
      ..addFile(
          ArchiveFile.bytes('repo-main/assets/guide.txt', utf8.encode('说明')));
    final preview =
        await installer.previewFromArchiveBytes(_tarGz(archive), _ref());

    expect(preview.metadata.name, 'demo-skill');
    expect(preview.fileList, ['SKILL.md', 'assets/guide.txt']);
    expect(preview.totalBytes, greaterThan(0));
    expect(preview.sha256Hex, isNotEmpty);
  });

  test('accepts a ZIP archive with SKILL.md at its root', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('SKILL.md', utf8.encode(_skillMd)))
      ..addFile(ArchiveFile.bytes('assets/guide.txt', utf8.encode('guide')));

    final preview = await installer.previewFromArchiveBytes(
      _zip(archive),
      GithubSkillRef.localArchive('demo-skill.zip'),
    );

    expect(preview.source.isLocalArchive, isTrue);
    expect(preview.fileList, ['SKILL.md', 'assets/guide.txt']);
  });

  test('rejects path traversal entries', () async {
    final archive = _archive()
      ..addFile(ArchiveFile.bytes('repo-main/../../evil.md', utf8.encode('x')));
    expect(
      () => installer.previewFromArchiveBytes(_tarGz(archive), _ref()),
      throwsA(predicate(
          (e) => e is SkillValidationException && e.message.contains('路径穿越'))),
    );
  });

  test('rejects symbolic links', () async {
    final archive = _archive()
      ..addFile(ArchiveFile.symlink('repo-main/link.md', '/etc/passwd'));
    expect(
      () => installer.previewFromArchiveBytes(_tarGz(archive), _ref()),
      throwsA(predicate(
          (e) => e is SkillValidationException && e.message.contains('符号链接'))),
    );
  });

  test('rejects files outside the extension whitelist', () async {
    final archive = _archive()
      ..addFile(
          ArchiveFile.bytes('repo-main/evil.sh', utf8.encode('rm -rf /')));
    expect(
      () => installer.previewFromArchiveBytes(_tarGz(archive), _ref()),
      throwsA(predicate((e) =>
          e is SkillValidationException && e.message.contains('不允许的文件'))),
    );
  });

  test('rejects archives without SKILL.md', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('repo-main/README.md', utf8.encode('x')));
    expect(
      () => installer.previewFromArchiveBytes(_tarGz(archive), _ref()),
      throwsA(predicate((e) =>
          e is SkillValidationException && e.message.contains('SKILL.md'))),
    );
  });
}
