/// Skill 管理接口：读写 SkillPacks 表，并把已启用的 skill 注入系统提示词。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../database/app_database.dart';
import 'skill_parser.dart';

class SkillStore {
  static const int _defaultInjectionBudget = 2000;
  // 闄愬埗鍖呭惈鎴柇鏍囪鍚庣殑鎬婚暱搴︼紝閬垮厤绱㈠紩琛屾湇缁嗛檺銆?
  static const int _maxDescriptionChars = 79;

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

  bool isFrozen(SkillPack pack) =>
      File(p.join(pack.installRoot, '.nexus-frozen')).existsSync();

  /// Reads install-time metadata again so callers can safely use fields that
  /// are intentionally not duplicated in the database, such as triggers.
  SkillMetadata? readMetadata(SkillPack pack) {
    try {
      if (isFrozen(pack)) return null;
      final file = File(p.join(pack.installRoot, 'SKILL.md'));
      if (!file.existsSync()) return null;
      return parseSkillMarkdown(file.readAsStringSync()).metadata;
    } catch (_) {
      return null;
    }
  }

  /// 构建待注入到系统提示词的 Skill 索引：正文通过 skills_read 按需读取。
  Future<String> buildInjectionBlock(AppDatabase db,
      {int budget = _defaultInjectionBudget}) async {
    final packs = await db.enabledSkillPacks();
    if (packs.isEmpty) return '';
    final effectiveBudget = budget.clamp(256, 32000).toInt();
    // 行首就是 skills_read 的 skill 参数值。曾经把内部 id 放在名称前面，
    // 模型会把 “<id> | <name>” 整串当参数传回来导致 notFound。
    final buffer = StringBuffer(
        '## 可用 Skill（行格式：名称 | 能力 | 描述；用 skills_read 的 skill 参数传名称读取正文；本轮安装的 Skill 下一轮才可用）\n');
    var used = buffer.length;
    var omitted = false;
    for (final pack in packs) {
      if (isFrozen(pack)) continue;
      final description =
          pack.description.replaceAll(RegExp(r'\s+'), ' ').trim();
      final shortDescription = description.length > _maxDescriptionChars
          ? '${description.substring(0, _maxDescriptionChars)}…'
          : description;
      final capabilities = _capabilities(pack);
      final line = '- ${pack.name} | $capabilities | $shortDescription\n';
      if (used + line.length > effectiveBudget) {
        omitted = true;
        break;
      }
      buffer.write(line);
      used += line.length;
    }
    if (omitted) {
      buffer.write('- 其余 Skill 未注入，请按需调用 skills_read 读取索引之外的内容\n');
    }
    return buffer.toString();
  }

  String _capabilities(SkillPack pack) {
    try {
      final raw = jsonDecode(pack.fileListJson);
      if (raw is List) {
        final resources = raw
            .map((item) => item.toString())
            .where((item) => item != 'SKILL.md')
            .take(4)
            .toList(growable: false);
        if (resources.isNotEmpty) {
          return 'skills_read, resources:${resources.join(',')}';
        }
      }
    } catch (_) {
      // 旧版本 fileListJson 损坏时仍保留最小可用能力声明。
    }
    return 'skills_read';
  }

  String? readBody(SkillPack pack, {int maxChars = 16000}) {
    try {
      maxChars = maxChars.clamp(1, 64000).toInt();
      if (isFrozen(pack)) {
        return null;
      }
      final file = File(p.join(pack.installRoot, 'SKILL.md'));
      if (!file.existsSync()) return null;
      final body = parseSkillMarkdown(file.readAsStringSync()).body;
      return body.length <= maxChars
          ? body
          : '${body.substring(0, maxChars)}\n[内容已截断]';
    } catch (_) {
      return null;
    }
  }

  String? readResource(SkillPack pack, String relativePath,
      {int maxChars = 16000}) {
    maxChars = maxChars.clamp(1, 64000).toInt();
    final normalized = p.normalize(relativePath);
    if (normalized == '.' ||
        p.isAbsolute(normalized) ||
        normalized.split(p.separator).contains('..')) {
      return null;
    }
    try {
      if (isFrozen(pack)) return null;
      final root = p.normalize(pack.installRoot);
      final path = p.normalize(p.join(root, normalized));
      if (!path.startsWith('$root${p.separator}')) return null;
      final file = File(path);
      if (!file.existsSync()) return null;
      final text = file.readAsStringSync();
      return text.length <= maxChars
          ? text
          : '${text.substring(0, maxChars)}\n[资源已截断]';
    } catch (_) {
      return null;
    }
  }
}

final skillStoreProvider = Provider<SkillStore>((ref) => SkillStore());
