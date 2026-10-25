import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../domain/tool_result.dart';
import 'workspace_fs.dart';

/// Write-ahead description of existing-file replacement, with a commit marker.
/// Recovery is idempotent and only replaces absent or expected-output targets.
class PatchJournal {
  PatchJournal({required this.root, required this.fs, required this.resolve});
  final String root;
  final WorkspaceFs fs;
  final String Function(String path) resolve;
  static final _busy = <String>{};
  String get _key =>
      Platform.isWindows ? p.normalize(root).toLowerCase() : p.normalize(root);
  static const directory = '.nexus/patch-journal';
  String? _ownedId;
  static String hash(String content) =>
      sha256.convert(utf8.encode(content)).toString();

  /// Keep writer admission and crash replay aligned, including Windows aliases.
  static bool isSafeRelativePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    return path.isNotEmpty &&
        !p.isAbsolute(path) &&
        !normalized.startsWith('/') &&
        !RegExp(r'[\x00-\x1f]').hasMatch(path) &&
        !normalized.toLowerCase().split('/').any((part) =>
            part == '..' ||
            part == '.nexus' ||
            part == '.git' ||
            part.contains(':') ||
            part.endsWith(' ') ||
            (part != '.' && part.endsWith('.')));
  }

  /// Containment alone permits in-workspace links. Recovery must not treat a
  /// changed link (or linked parent directory) as a transaction-owned file.
  Future<void> _guardLocalPath(String path) async {
    if (fs is! LocalWorkspaceFs) return;
    var probe = p.normalize(path);
    while (!p.equals(probe, root)) {
      if (await FileSystemEntity.type(probe, followLinks: false) ==
          FileSystemEntityType.link) {
        throw StateError('linked transaction path');
      }
      final parent = p.dirname(probe);
      if (parent == probe) throw StateError('invalid transaction root');
      probe = parent;
    }
  }

  Future<void> start(String id, List<Map<String, String>> entries) async {
    if (!_busy.add(_key)) throw StateError('patch transaction busy');
    _ownedId = id;
    try {
      final journal = resolve('$directory/$id.json');
      await _guardLocalPath(journal);
      if (await fs.kindOf(journal) != WorkspaceEntryKind.notFound) {
        throw StateError('journal exists');
      }
      await fs.writeText(
          journal, jsonEncode({'version': 1, 'id': id, 'files': entries}));
    } catch (_) {
      _busy.remove(_key);
      _ownedId = null;
      rethrow;
    }
  }

  Future<void> commit() async {
    final id = _ownedId;
    if (id == null) throw StateError('no owned patch transaction');
    final marker = resolve('$directory/$id.commit');
    await _guardLocalPath(marker);
    await fs.writeText(marker, 'committed');
  }

  Future<void> finish({required bool clean}) async {
    try {
      if (clean && _ownedId != null) {
        await _delete(resolve('$directory/$_ownedId.json'));
        await _delete(resolve('$directory/$_ownedId.commit'));
      }
    } finally {
      _busy.remove(_key);
      _ownedId = null;
    }
  }

  Future<void> _delete(String path) async {
    await _guardLocalPath(path);
    if (await fs.kindOf(path) == WorkspaceEntryKind.file) {
      await fs.deleteFile(path);
    }
  }

  Future<bool> hasPending() async {
    if (_busy.contains(_key)) return true;
    try {
      final folder = resolve(directory);
      await _guardLocalPath(folder);
      if (await fs.kindOf(folder) == WorkspaceEntryKind.notFound) return false;
      var visited = 0;
      await for (final entry in fs.list(folder)) {
        if (++visited > 200 || entry.isLink || entry.path.endsWith('.json')) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return true;
    }
  }

  Future<ToolResult?> recover() async {
    if (!_busy.add(_key)) {
      return ToolResult.failure(
          code: 'PATCH_BUSY', message: '工作区正在提交或恢复补丁，请等待当前操作完成。');
    }
    final recovered = <String>{};
    final conflicts = <String>[];
    var found = false;
    try {
      final folder = resolve(directory);
      await _guardLocalPath(folder);
      if (await fs.kindOf(folder) == WorkspaceEntryKind.notFound) return null;
      final journals = <String>[];
      var visited = 0;
      await for (final entry in fs.list(folder)) {
        if (++visited > 200) throw StateError('too many journal entries');
        if (entry.isLink) {
          conflicts.add('journal_link');
          continue;
        }
        if (entry.isFile && entry.path.endsWith('.json')) {
          journals.add(entry.path);
        }
        if (journals.length > 100) throw StateError('too many journals');
      }
      for (final file in journals..sort()) {
        found = true;
        final name = p.basename(file);
        if (!RegExp(r'^[a-f0-9]{32}\.json$').hasMatch(name)) {
          conflicts.add(name);
          continue;
        }
        final id = name.substring(0, 32);
        final journalPath = resolve('$directory/$name');
        try {
          final raw =
              jsonDecode(await fs.readText(journalPath, maxBytes: 64 * 1024));
          if (raw is! Map ||
              raw['version'] != 1 ||
              raw['id'] != id ||
              raw['files'] is! List ||
              (raw['files'] as List).isEmpty ||
              (raw['files'] as List).length > 10) {
            throw const FormatException('invalid journal');
          }
          // Validate the complete record before touching any referenced file.
          final entries = <Map<String, String>>[];
          final paths = <String>{};
          for (final entry in raw['files'] as List) {
            if (entry is! Map ||
                entry['path'] is! String ||
                entry['before'] is! String ||
                entry['after'] is! String) {
              throw const FormatException('invalid entry');
            }
            final path = entry['path'] as String;
            if (!isSafeRelativePath(path) ||
                !paths.add(Platform.isWindows
                    ? resolve(path).toLowerCase()
                    : resolve(path)) ||
                !RegExp(r'^[a-f0-9]{64}$').hasMatch(entry['before']) ||
                !RegExp(r'^[a-f0-9]{64}$').hasMatch(entry['after'])) {
              throw const FormatException('unsafe entry');
            }
            for (final candidate in [
              path,
              '$path.nexus-patch-$id.bak',
              '$path.nexus-patch-$id.tmp',
            ]) {
              await _guardLocalPath(resolve(candidate));
            }
            entries.add({
              'path': path,
              'before': entry['before'],
              'after': entry['after']
            });
          }
          final marker = resolve('$directory/$id.commit');
          await _guardLocalPath(marker);
          final markerKind = await fs.kindOf(marker);
          var committed = false;
          if (markerKind != WorkspaceEntryKind.notFound) {
            if (markerKind != WorkspaceEntryKind.file ||
                await fs.readText(marker, maxBytes: 32) != 'committed') {
              throw const FormatException('invalid commit marker');
            }
            committed = true;
          }
          var complete = true;
          for (final entry in entries.reversed) {
            final path = entry['path']!;
            try {
              final target = resolve(path);
              final backup = resolve('$path.nexus-patch-$id.bak');
              final staged = resolve('$path.nexus-patch-$id.tmp');
              final current = await fs.kindOf(target) ==
                      WorkspaceEntryKind.notFound
                  ? null
                  : hash(await fs.readText(target, maxBytes: 4 * 1024 * 1024));
              if (committed) {
                if (current != entry['after']) {
                  throw StateError('committed target changed');
                }
              } else if (current != entry['before']) {
                if (current != null && current != entry['after']) {
                  throw StateError('external change');
                }
                if (hash(
                        await fs.readText(backup, maxBytes: 4 * 1024 * 1024)) !=
                    entry['before']) {
                  throw StateError('backup changed');
                }
                if (current != null) await fs.deleteFile(target);
                await fs.rename(backup, target);
                if (hash(
                        await fs.readText(target, maxBytes: 4 * 1024 * 1024)) !=
                    entry['before']) {
                  throw StateError('restore failed');
                }
              }
              // Delete only transaction-owned data whose hash is still known.
              for (final pair in [
                (backup, entry['before']),
                (staged, entry['after'])
              ]) {
                if (await fs.kindOf(pair.$1) == WorkspaceEntryKind.file) {
                  if (hash(await fs.readText(pair.$1,
                          maxBytes: 4 * 1024 * 1024)) !=
                      pair.$2) {
                    throw StateError('temporary file changed');
                  }
                  await fs.deleteFile(pair.$1);
                }
              }
              recovered.add(path);
            } catch (_) {
              complete = false;
              conflicts.add(path);
            }
          }
          if (complete) {
            await _delete(journalPath);
            await _delete(marker);
          }
        } catch (_) {
          conflicts.add(name);
        }
      }
    } catch (_) {
      conflicts.add('journal_unreadable');
    } finally {
      _busy.remove(_key);
    }
    if (!found && conflicts.isEmpty) return null;
    return ToolResult.failure(
      code: conflicts.isEmpty ? 'PATCH_RECOVERED' : 'PATCH_RECOVERY_REQUIRED',
      message: conflicts.isEmpty
          ? '已恢复中断补丁或清理已提交补丁。本次新编辑未执行，请重新读取文件后再编辑。'
          : '中断补丁存在恢复冲突，新编辑已阻止。请检查文件与 .nexus/patch-journal；不会覆盖未知外部内容。',
      effect: conflicts.isEmpty ? ToolEffect.applied : ToolEffect.unknown,
      data: {
        'recoveredFiles': recovered.toList(),
        'conflicts': conflicts,
        'transactionStatus': conflicts.isEmpty ? 'recovered' : 'needs_recovery'
      },
    );
  }
}
