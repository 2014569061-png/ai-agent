import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'vault_manifest.dart';

bool _isReservedDeviceName(String name) =>
    RegExp(r'^(con|prn|aux|nul|com[1-9¹²³]|lpt[1-9¹²³])(?:\..*)?$',
            caseSensitive: false)
        .hasMatch(name);

/// Names are display metadata, but reject legacy names containing path syntax.
void validateVaultName(String name) {
  if (_isReservedDeviceName(name) ||
      name.isEmpty ||
      name == '.' ||
      name == '..' ||
      name.endsWith('.') ||
      name.endsWith(' ') ||
      RegExp(r'[\\/<>:"|?*\x00-\x1f]').hasMatch(name)) {
    throw const FormatException('技能包名称含有非法路径字符');
  }
}

String validateVaultRelativePath(String path) {
  final portable = path.replaceAll('\\', '/');
  final segments = portable.split('/');
  if (p.posix.isAbsolute(portable) ||
      p.windows.isAbsolute(path) ||
      segments.any((s) =>
          _isReservedDeviceName(s) ||
          s.isEmpty ||
          s == '.' ||
          s == '..' ||
          RegExp(r'[<>:"|?*\x00-\x1f]').hasMatch(s) ||
          s.endsWith('.') ||
          s.endsWith(' '))) {
    throw const FormatException('技能文件路径越界');
  }
  return p.joinAll(segments);
}

class VaultSkillStaging {
  VaultSkillStaging._(this.temp, this.entries, this.fileCount);
  final Directory? temp;
  final List<({Directory staged, Directory target, Directory backup})> entries;
  final int fileCount;
  final List<({Directory staged, Directory target, Directory backup})>
      _published = [];

  static Future<VaultSkillStaging> prepare(Map<String, dynamic> data) async {
    final packs =
        (data['skillPacks'] as List? ?? const []).cast<Map<String, dynamic>>();
    final maps = (data['skillFiles'] as Map? ?? const {});
    var count = 0;
    var bytes = 0;
    final seen = <String>{};
    // Decode and validate every input before any filesystem operation.
    final decoded = <String, Map<String, List<int>>>{};
    for (final pack in packs) {
      validateVaultName(pack['name'] as String? ?? '');
      final id = pack['id'] as String? ?? '';
      if (id.isEmpty || !seen.add(id)) {
        throw const FormatException('技能 ID 重复或为空');
      }
      final files = <String, List<int>>{};
      final seenPaths = <String>{};
      for (final e in (maps[id] as Map? ?? const {}).entries) {
        final relative = validateVaultRelativePath(e.key as String);
        if (!seenPaths.add(relative.toLowerCase())) {
          throw const FormatException('技能路径重复');
        }
        final encoded = e.value as String;
        if (encoded.length > VaultLimits.maxFileBytes * 4 ~/ 3 + 4) {
          throw const FormatException('技能文件过大');
        }
        final content = base64Decode(encoded);
        count++;
        bytes += content.length;
        if (count > VaultLimits.maxFiles ||
            content.length > VaultLimits.maxFileBytes ||
            bytes > VaultLimits.maxSkillBytes) {
          throw const FormatException('技能文件超过容量上限');
        }
        files[relative] = content;
      }
      decoded[id] = files;
    }
    if (maps.keys.any((id) => !seen.contains(id))) {
      throw const FormatException('技能文件没有对应的技能包');
    }
    if (packs.isEmpty) return VaultSkillStaging._(null, [], 0);
    final docs = await getApplicationDocumentsDirectory();
    final canonical = await docs.resolveSymbolicLinks();
    final skills = p.join(canonical, 'skills');
    if (await FileSystemEntity.type(skills, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FormatException('技能根目录不能是符号链接');
    }
    await Directory(skills).create(recursive: true);
    final temp = await Directory(canonical).createTemp('.vault-stage-');
    final entries =
        <({Directory staged, Directory target, Directory backup})>[];
    try {
      for (final pack in packs) {
        final id = pack['id'] as String;
        final key = sha256.convert(utf8.encode(id)).toString();
        final staged = Directory(p.join(temp.path, key));
        final target = Directory(p.join(skills, key));
        if (await FileSystemEntity.type(target.path, followLinks: false) ==
            FileSystemEntityType.link) {
          throw const FormatException('技能目标目录不能是符号链接');
        }
        await staged.create();
        for (final entry in decoded[id]!.entries) {
          final path = p.normalize(p.join(staged.path, entry.key));
          if (!p.isWithin(staged.path, path)) {
            throw const FormatException('技能路径越界');
          }
          final file = File(path);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(entry.value, flush: true);
        }
        pack['installRoot'] = target.path;
        entries.add((
          staged: staged,
          target: target,
          backup: Directory(p.join(temp.path, '$key.old'))
        ));
      }
      return VaultSkillStaging._(temp, entries, count);
    } catch (_) {
      await temp.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> publish() async {
    for (final entry in entries) {
      // Recheck at mutation time; never traverse a replaced symlink.
      final parent = entry.target.parent;
      if (await FileSystemEntity.type(parent.path, followLinks: false) ==
              FileSystemEntityType.link ||
          await FileSystemEntity.type(entry.target.path, followLinks: false) ==
              FileSystemEntityType.link) {
        throw const FormatException('技能目标目录已变化');
      }
      _published.add(entry);
      if (await entry.target.exists()) {
        await entry.target.rename(entry.backup.path);
      }
      await entry.staged.rename(entry.target.path);
    }
  }

  Future<void> rollback() async {
    for (final entry in _published.reversed) {
      // staged is absent only after its rename to target succeeded.
      if (!await entry.staged.exists() && await entry.target.exists()) {
        await entry.target.delete(recursive: true);
      }
      if (await entry.backup.exists()) {
        await entry.backup.rename(entry.target.path);
      }
    }
  }

  Future<void> dispose() async {
    if (temp != null && await temp!.exists()) {
      await temp!.delete(recursive: true);
    }
  }
}
