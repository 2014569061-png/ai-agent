/// Skill 管理接口：读写 SkillPacks 表，并把已启用的 skill 注入系统提示词。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../database/app_database.dart';
import 'skill_parser.dart';

class SkillStore {
  static const int _defaultInjectionBudget = 2000;

  Future<List<SkillPack>> all(AppDatabase db) => db.allSkillPacks();

  Future<SkillPack?> findByName(AppDatabase db, String name) =>
      db.findSkillPackByName(name);

  Future<void> setEnabled(AppDatabase db, SkillPack pack, bool enabled) =>
      db.saveSkillPack(
          pack.copyWith(enabled: enabled, updatedAt: DateTime.now()));

  Future<void> delete(AppDatabase db, SkillPack pack) async {
    try {
      final dir = Directory(pack.installRoot);
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // 文件缺失不影响记录删除。
    }
    await db.deleteSkillPack(pack.id);
  }

  /// 构建待注入到系统提示词的 Skill 块：只注入已启用 skill。
  Future<String> buildInjectionBlock(AppDatabase db,
      {int budget = _defaultInjectionBudget}) async {
    final packs = await db.enabledSkillPacks();
    if (packs.isEmpty) return '';
    final buffer = StringBuffer('## 可用 Skill（按需遵循以下指令）\n');
    var used = 0;
    for (final pack in packs) {
      final body = _readSkillBody(pack);
      if (body == null) continue;
      final header = '- [Skill] ${pack.name} v${pack.version}\n';
      var block = '$header$body\n';
      if (used + block.length > budget) break;
      buffer.write(block);
      used += block.length;
    }
    return buffer.toString();
  }

  String? _readSkillBody(SkillPack pack) {
    try {
      final file = File(p.join(pack.installRoot, 'SKILL.md'));
      if (!file.existsSync()) return null;
      return parseSkillMarkdown(file.readAsStringSync()).body;
    } catch (_) {
      return null;
    }
  }
}

final skillStoreProvider = Provider<SkillStore>((ref) => SkillStore());
