/// Skill 管理接口：读写 SkillPacks 表，并把已启用的 skill 注入系统提示词。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../database/app_database.dart';
import 'skill_change_notifier.dart';
import 'skill_parser.dart';

class SkillStore {
  static const int _defaultInjectionBudget = 2000;
  // 限制包含截断标记后的总长度，避免索引行超出预算。
  static const int _maxDescriptionChars = 79;

  Future<List<SkillPack>> all(AppDatabase db) => db.allSkillPacks();

  Future<SkillPack?> findByName(AppDatabase db, String name) =>
      db.findSkillPackByName(name);

  Future<void> setEnabled(AppDatabase db, SkillPack pack, bool enabled) async {
    await db.saveSkillPack(
        pack.copyWith(enabled: enabled, updatedAt: DateTime.now()));
    SkillChangeNotifier.notify();
  }

  Future<void> delete(AppDatabase db, SkillPack pack) async {
    try {
      final dir = Directory(p.normalize(pack.installRoot));
      if (p.isAbsolute(dir.path) &&
          !_hasSymlinkAncestor(dir.path) &&
          FileSystemEntity.typeSync(dir.path, followLinks: false) ==
              FileSystemEntityType.directory) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // 文件缺失不影响记录删除。
    }
    await db.deleteSkillPack(pack.id);
    SkillChangeNotifier.notify();
  }

  bool isFrozen(SkillPack pack) {
    final type = FileSystemEntity.typeSync(
      p.join(pack.installRoot, '.nexus-frozen'),
      followLinks: false,
    );
    // A marker symlink/directory is also treated as frozen; it must never be
    // followed or overwritten by a runtime read.
    return type != FileSystemEntityType.notFound;
  }

  /// Verifies the install manifest before exposing a Skill to runtime code.
  ///
  /// Older database rows did not have a canonical checksum, so a non-SHA-256
  /// value is treated as legacy and remains readable. New installs always
  /// contain a 64-character SHA-256; a changed or missing declared file freezes
  /// the pack until the user explicitly updates/reinstalls it.
  bool verifyIntegrity(SkillPack pack) {
    if (isFrozen(pack)) return false;
    final expected = pack.sha256.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) return true;
    try {
      final declared = _strictDeclaredFiles(pack);
      if (declared == null ||
          declared.isEmpty ||
          !declared.contains('SKILL.md')) {
        return _freeze(pack);
      }
      final root = p.normalize(pack.installRoot);
      if (FileSystemEntity.typeSync(root, followLinks: false) !=
          FileSystemEntityType.directory) {
        return _freeze(pack);
      }
      final hashInput = <int>[];
      final paths = declared.toList()..sort();
      for (final relativePath in paths) {
        final path = p.normalize(p.join(root, relativePath));
        if (!_isWithinRoot(path, root) ||
            !_isRegularFile(path) ||
            _hasSymlinkComponent(root, relativePath)) {
          return _freeze(pack);
        }
        hashInput
            .addAll(utf8.encode(relativePath.replaceAll(p.separator, '/')));
        hashInput.addAll(File(path).readAsBytesSync());
      }
      final actual = sha256.convert(hashInput).toString();
      return actual == expected ? true : _freeze(pack);
    } catch (_) {
      return _freeze(pack);
    }
  }

  bool _freeze(SkillPack pack) {
    try {
      final root = Directory(p.normalize(pack.installRoot));
      final existingType =
          FileSystemEntity.typeSync(root.path, followLinks: false);
      if (existingType != FileSystemEntityType.directory) {
        // Never create or follow a path supplied by a tampered database row.
        return false;
      }
      final marker = p.join(root.path, '.nexus-frozen');
      final markerType = FileSystemEntity.typeSync(marker, followLinks: false);
      if (markerType != FileSystemEntityType.notFound &&
          markerType != FileSystemEntityType.file) {
        return false;
      }
      File(marker).writeAsStringSync(
        'code=NEXT_TURN_REQUIRED\nreason=integrity-check-failed\n',
        flush: true,
      );
    } catch (_) {
      // 冻结标记写失败时仍返回 false；调用方不会把完整性检查当成成功，最多是
      // 少了供下一轮读取的持久化原因。
    }
    return false;
  }

  Set<String>? _strictDeclaredFiles(SkillPack pack) {
    try {
      final raw = jsonDecode(pack.fileListJson);
      if (raw is! List || raw.isEmpty) return null;
      final result = <String>{};
      for (final item in raw) {
        if (item is! String) return null;
        final normalized = _normalizeRelativePath(item);
        if (normalized == null || !result.add(normalized)) return null;
      }
      return result.length == raw.length ? result : null;
    } catch (_) {
      return null;
    }
  }

  bool _hasSymlinkAncestor(String path) {
    var current = p.normalize(path);
    while (true) {
      if (FileSystemEntity.typeSync(current, followLinks: false) ==
          FileSystemEntityType.link) {
        return true;
      }
      final parent = p.dirname(current);
      if (parent == current) return false;
      current = parent;
    }
  }

  bool _hasSymlinkComponent(String root, String relativePath) {
    if (_hasSymlinkAncestor(root)) return true;
    var current = p.normalize(root);
    for (final part in relativePath.split(p.separator)) {
      current = p.join(current, part);
      if (FileSystemEntity.typeSync(current, followLinks: false) ==
          FileSystemEntityType.link) {
        return true;
      }
    }
    return false;
  }

  /// Reads install-time metadata again so callers can safely use fields that
  /// are intentionally not duplicated in the database, such as triggers.
  ///
  /// Metadata is also used by the market page for disabled packs, so this
  /// method deliberately does not require [pack.enabled]. Runtime body and
  /// resource reads do enforce the enabled flag below.
  SkillMetadata? readMetadata(SkillPack pack) {
    try {
      if (isFrozen(pack) || !verifyIntegrity(pack)) return null;
      final root = p.normalize(pack.installRoot);
      final file = File(p.join(root, 'SKILL.md'));
      if (!_isRegularFile(file.path) ||
          _hasSymlinkComponent(root, 'SKILL.md')) {
        return null;
      }
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
    var included = 0;
    var omitted = false;
    for (final pack in packs) {
      if (!verifyIntegrity(pack)) continue;
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
      included++;
    }
    if (included == 0) return '';
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
    if (!pack.enabled) return null;
    try {
      maxChars = maxChars.clamp(1, 64000).toInt();
      if (isFrozen(pack) || !verifyIntegrity(pack)) {
        return null;
      }
      final file = File(p.join(pack.installRoot, 'SKILL.md'));
      if (!_isReadableTextFile(pack, file.path, 'SKILL.md')) return null;
      final body = parseSkillMarkdown(file.readAsStringSync()).body;
      return body.length <= maxChars
          ? body
          : '${body.substring(0, maxChars)}\n[内容已截断]';
    } catch (_) {
      return null;
    }
  }

  /// Reads an image resource as raw bytes for multimodal/tool callers. Text
  /// resources continue through [readResource] so binary data is never decoded
  /// as corrupted UTF-8.
  List<int>? readResourceBytes(SkillPack pack, String relativePath,
      {int maxBytes = kSkillMaxBytes}) {
    if (!pack.enabled) return null;
    final normalized = _normalizeRelativePath(relativePath);
    if (normalized == null) return null;
    final extension = p.extension(normalized).toLowerCase();
    if (!const {'.png', '.jpg', '.jpeg', '.webp'}.contains(extension)) {
      return null;
    }
    try {
      if (isFrozen(pack) || !verifyIntegrity(pack)) return null;
      final root = p.normalize(pack.installRoot);
      final path = p.normalize(p.join(root, normalized));
      if (!_isWithinRoot(path, root) ||
          !_isReadableTextFile(pack, path, normalized)) {
        return null;
      }
      final bytes = File(path).readAsBytesSync();
      if (bytes.length > maxBytes.clamp(1, kSkillMaxBytes).toInt()) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  String? readResource(SkillPack pack, String relativePath,
      {int maxChars = 16000}) {
    if (!pack.enabled) return null;
    maxChars = maxChars.clamp(1, 64000).toInt();
    final normalized = _normalizeRelativePath(relativePath);
    if (normalized == null) return null;
    // Skill resources are currently text-only at the tool boundary. Images
    // may remain in a package for future multimodal support, but must not be
    // decoded as UTF-8 and returned as corrupted prompt text.
    final extension = p.extension(normalized).toLowerCase();
    if (!const {'.md', '.txt', '.template'}.contains(extension)) return null;
    try {
      if (isFrozen(pack) || !verifyIntegrity(pack)) return null;
      final root = p.normalize(pack.installRoot);
      final path = p.normalize(p.join(root, normalized));
      if (!_isWithinRoot(path, root) ||
          !_isReadableTextFile(pack, path, normalized)) {
        return null;
      }
      final text = File(path).readAsStringSync();
      return text.length <= maxChars
          ? text
          : '${text.substring(0, maxChars)}\n[资源已截断]';
    } catch (_) {
      return null;
    }
  }

  bool _isReadableTextFile(SkillPack pack, String path, String relativePath) {
    if (!_isRegularFile(path) ||
        _hasSymlinkComponent(p.normalize(pack.installRoot), relativePath)) {
      return false;
    }
    final declared = _declaredFiles(pack);
    // A malformed/legacy empty list should not make an otherwise valid old
    // installation unreadable. Once a manifest declares files, enforce it so
    // files added behind the database record cannot become Skill resources.
    if (declared.isNotEmpty && !declared.contains(relativePath)) return false;
    return true;
  }

  Set<String> _declaredFiles(SkillPack pack) {
    try {
      final raw = jsonDecode(pack.fileListJson);
      if (raw is! List) return const <String>{};
      final result = <String>{};
      for (final item in raw) {
        final normalized = _normalizeRelativePath(item.toString());
        if (normalized != null) result.add(normalized);
      }
      return result;
    } catch (_) {
      return const <String>{};
    }
  }

  String? _normalizeRelativePath(String value) {
    final raw = value.replaceAll('\\', '/');
    if (raw.isEmpty ||
        raw.startsWith('/') ||
        raw.startsWith('\\') ||
        (raw.length >= 2 && raw.codeUnitAt(1) == 0x3a) ||
        raw.contains('\u0000')) {
      return null;
    }
    final parts = <String>[];
    for (final part in raw.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..' || part.contains(':')) return null;
      parts.add(part);
    }
    if (parts.isEmpty) return null;
    final normalized = p.normalize(parts.join(p.separator));
    if (normalized == '.' || p.isAbsolute(normalized)) return null;
    return normalized;
  }

  bool _isWithinRoot(String path, String root) {
    final normalizedPath = p.normalize(path);
    final normalizedRoot = p.normalize(root);
    return normalizedPath == normalizedRoot ||
        normalizedPath.startsWith('$normalizedRoot${p.separator}');
  }

  bool _isRegularFile(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.file;
}

final skillStoreProvider = Provider<SkillStore>((ref) => SkillStore());
