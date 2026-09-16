import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import '../database/app_database.dart';
import 'skill_installer.dart';
import 'skill_parser.dart';

/// 内置技能清单：随 APK 分发的 assets/skills/*，首次启动自动安装；
/// 版本或内容变化时原地更新（install 按 name upsert，保留同一 id）。
const List<BuiltinSkill> kBuiltinSkills = [
  BuiltinSkill(
    name: 'mobile-dev-basics',
    assetPath: 'assets/skills/mobile-dev-basics/SKILL.md',
  ),
  BuiltinSkill(
    name: 'android-build',
    assetPath: 'assets/skills/android-build/SKILL.md',
    resourceAssets: {
      'references/build.md': 'assets/skills/android-build/references/build.md',
      'references/toolchain.md':
          'assets/skills/android-build/references/toolchain.md',
    },
  ),
];

class BuiltinSkill {
  const BuiltinSkill({
    required this.name,
    required this.assetPath,
    this.resourceAssets = const <String, String>{},
  });

  final String name;
  final String assetPath;

  /// Installed relative path -> bundled Flutter asset path.
  final Map<String, String> resourceAssets;
}

String _hashFiles(Map<String, Uint8List> files) {
  final hashInput = <int>[];
  final paths = files.keys.toList()..sort();
  for (final path in paths) {
    hashInput.addAll(utf8.encode(path));
    hashInput.addAll(files[path]!);
  }
  return sha256.convert(hashInput).toString();
}

/// 内置技能种子安装：幂等，同版本同内容跳过，版本或内容变化更新。
/// 失败不阻断启动（下次启动重试），只影响技能可用时间。
class BuiltinSkillSeeder {
  BuiltinSkillSeeder({SkillInstaller? installer, AssetBundle? bundle})
      : _installer = installer ?? SkillInstaller(),
        _bundle = bundle ?? rootBundle;

  final SkillInstaller _installer;
  final AssetBundle _bundle;

  Future<void> ensureInstalled(AppDatabase db) async {
    for (final skill in kBuiltinSkills) {
      try {
        final text = await _bundle.loadString(skill.assetPath);
        final parsed = parseSkillMarkdown(text);
        final bytes = Uint8List.fromList(utf8.encode(text));
        final fileContents = <String, Uint8List>{'SKILL.md': bytes};
        for (final entry in skill.resourceAssets.entries) {
          final data = await _bundle.load(entry.value);
          fileContents[entry.key] = Uint8List.fromList(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
        }
        final sha256Hex = _hashFiles(fileContents);

        final existing = await db.findSkillPackByName(skill.name);
        if (existing != null &&
            existing.version == parsed.metadata.version &&
            existing.sha256 == sha256Hex) {
          continue;
        }

        await _installer.install(
          db,
          SkillPackPreview(
            source: GithubSkillRef(
              original: 'builtin:${skill.name}',
              owner: 'local',
              repo: skill.name,
              ref: 'builtin',
              subPath: null,
            ),
            metadata: parsed.metadata,
            fileContents: fileContents,
            totalBytes: fileContents.values.fold<int>(
              0,
              (sum, value) => sum + value.length,
            ),
            sha256Hex: sha256Hex,
          ),
        );
      } catch (_) {
        // 单个内置技能失败不阻断其余技能；下次启动重试。
        continue;
      }
    }
  }
}
