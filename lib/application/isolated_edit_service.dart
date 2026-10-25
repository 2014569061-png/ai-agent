import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../domain/models.dart';
import '../infrastructure/tools/workspace_tools.dart';

/// A linked worktree seeded from current working bytes, never merely HEAD.
/// Child results are proposals; this service never applies them to the parent.
class IsolatedEditService {
  static const tools = [
    'read_file',
    'list_directory',
    'search_files',
    'repo_map',
    'write_file',
    'edit_file',
    'apply_patch',
  ];
  static const maxFiles = 3000;
  static const maxBytes = 32 * 1024 * 1024;

  static bool allowedPath(String path) {
    final parts = p.posix.split(path.replaceAll('\\', '/').toLowerCase());
    return !parts.any((part) =>
        part == '.git' ||
        part == '.nexus' ||
        part.contains(':') ||
        part.endsWith(' ') ||
        (part != '.' && part != '..' && part.endsWith('.')));
  }

  /// Approval of the outer delegation authorizes only this narrow capability.
  static Future<ToolApproval> approve(
      String workspace, ToolCall call, ToolRisk risk, bool sensitive) async {
    if (sensitive || !tools.contains(call.name)) return ToolApproval.reject;
    if (!['write_file', 'edit_file', 'apply_patch'].contains(call.name)) {
      return ToolApproval.allowOnce;
    }
    final args = call.arguments;
    final paths = <String>[];
    if (args['path'] is String) paths.add(args['path'] as String);
    if (args['files'] is List) {
      for (final item in args['files'] as List) {
        if (item is! Map || item['path'] is! String) return ToolApproval.reject;
        paths.add(item['path'] as String);
      }
    }
    if (paths.isEmpty) return ToolApproval.reject;
    final sandbox = WorkspaceSandbox(workspace);
    try {
      for (final path in paths) {
        final full = sandbox.resolvePath(path, allowRoot: false);
        if (!allowedPath(sandbox.toRelative(full))) return ToolApproval.reject;
      }
    } catch (_) {
      return ToolApproval.reject;
    }
    return ToolApproval.allowOnce;
  }

  Future<Map<String, dynamic>> run({
    required String root,
    required Future<Map<String, dynamic>> Function(String workspace) execute,
    bool Function()? canContinue,
  }) async {
    if (canContinue?.call() == false) throw StateError('子任务已取消');
    final parent = await Directory(root).resolveSymbolicLinks();
    final top = (await _git(parent, ['rev-parse', '--show-toplevel'])).trim();
    if (!p.equals(await Directory(top).resolveSymbolicLinks(), parent)) {
      throw StateError('请选择 Git 仓库根目录，不能从子目录建立隔离快照');
    }
    final head = (await _git(parent, ['rev-parse', '--verify', 'HEAD'])).trim();
    final paths = await _paths(parent);
    final baseline = await _read(parent, paths);
    if (canContinue?.call() == false) throw StateError('子任务已取消');
    final container = Directory(p.join(parent, '.nexus', 'worktrees'));
    WorkspaceSandbox(parent).resolvePath('.nexus/worktrees');
    await container.create(recursive: true);
    if (!p.isWithin(parent, await container.resolveSymbolicLinks())) {
      throw StateError('隔离工作区不能位于项目外');
    }
    final job = await container.createTemp('edit-');
    final workspace = p.join(job.path, 'source');
    final report = File(p.join(job.path, 'proposal.json'));
    final metadata = <String, dynamic>{
      'version': 1,
      'parent': parent,
      'workspace': workspace,
      'baseCommit': head,
      'status': 'preparing',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'baseline': {
        for (final entry in baseline.entries) entry.key: _hash(entry.value)
      },
    };
    await report.writeAsString(jsonEncode(metadata), flush: true);
    try {
      // No checkout means no filters or post-checkout hook and no stale HEAD
      // files accidentally surviving an uncommitted deletion in the parent.
      await _git(parent,
          ['worktree', 'add', '--detach', '--no-checkout', workspace, head]);
      for (final entry in baseline.entries) {
        final target = File(p.join(workspace, entry.key));
        await target.parent.create(recursive: true);
        await target.writeAsBytes(entry.value);
      }
      final again = await _read(parent, await _paths(parent));
      if (!_same(baseline, again) ||
          (await _git(parent, ['rev-parse', 'HEAD'])).trim() != head) {
        throw StateError('建立隔离快照时父工作区发生变化，请重新委派');
      }
      if (canContinue?.call() == false) throw StateError('子任务已取消');
      metadata['status'] = 'running';
      await report.writeAsString(jsonEncode(metadata), flush: true);
      final outcome = Map<String, dynamic>.of(await execute(workspace));
      if (canContinue?.call() == false) {
        outcome.addAll({'ok': false, 'code': 'CANCELLED'});
      }
      // Directory enumeration also captures ignored files created by the child.
      final after = await _read(workspace, await _workspacePaths(workspace));
      final changes = <Map<String, dynamic>>[];
      for (final path in {...baseline.keys, ...after.keys}.toList()..sort()) {
        final beforeHash =
            baseline[path] == null ? null : _hash(baseline[path]!);
        final afterHash = after[path] == null ? null : _hash(after[path]!);
        if (beforeHash == afterHash) continue;
        String? parentHash;
        var parentReadable = true;
        try {
          final full =
              WorkspaceSandbox(parent).resolvePath(path, allowRoot: false);
          if (await File(full).exists()) {
            if (await File(full).length() > 1024 * 1024) {
              throw StateError('large');
            }
            parentHash = _hash(await File(full).readAsBytes());
          }
        } catch (_) {
          parentReadable = false;
        }
        changes.add({
          'path': path,
          'beforeHash': beforeHash,
          'afterHash': afterHash,
          'operation': beforeHash == null
              ? 'create'
              : afterHash == null
                  ? 'delete'
                  : 'edit',
          'parentUnchanged': parentReadable && parentHash == beforeHash,
        });
      }
      metadata.addAll({
        'status':
            outcome['ok'] == true ? 'review_required' : 'child_incomplete',
        'outcome': outcome,
        'changes': changes,
        'finishedAt': DateTime.now().toUtc().toIso8601String(),
      });
      await report.writeAsString(jsonEncode(metadata), flush: true);
      return {
        'workspace': p.relative(workspace, from: parent).replaceAll('\\', '/'),
        'reportPath':
            p.relative(report.path, from: parent).replaceAll('\\', '/'),
        'baseCommit': head,
        'status': metadata['status'],
        'outcome': outcome,
        'changes': changes.take(100).toList(),
        'changeCount': changes.length,
        'truncated': changes.length > 100,
        'parentModified': false,
        'hint':
            '这是未验证的隔离提案，不是父工作区已完成的变更。先读取提案及父文件；存在父版本冲突时重新设计修改。应用后必须在父工作区验证。',
      };
    } catch (_) {
      metadata['status'] = 'failed';
      var reportPersisted = false;
      String? reportErrorType;
      try {
        await report.writeAsString(jsonEncode(metadata), flush: true);
        reportPersisted = true;
      } catch (error) {
        reportErrorType = error.runtimeType.toString();
      }
      return {
        'status': 'failed',
        'reportPersisted': reportPersisted,
        if (reportErrorType != null) 'reportErrorType': reportErrorType,
        'parentModified': false,
        'workspace': p.relative(workspace, from: parent).replaceAll('\\', '/'),
        'reportPath':
            p.relative(report.path, from: parent).replaceAll('\\', '/'),
        'hint': '隔离子任务未完成，已有文件已保留；父工作区源码未应用任何提案。',
      };
    }
  }

  static String _hash(List<int> value) => sha256.convert(value).toString();
  static bool _same(Map<String, List<int>> a, Map<String, List<int>> b) =>
      a.length == b.length &&
      a.entries
          .every((e) => b[e.key] != null && _hash(e.value) == _hash(b[e.key]!));

  Future<List<String>> _paths(String root) async {
    final output = await _git(
        root, ['ls-files', '-z', '--cached', '--others', '--exclude-standard']);
    final paths = output
        .split('\u0000')
        .where((e) => e.isNotEmpty && allowedPath(e))
        .toSet()
        .toList()
      ..sort();
    if (paths.length > maxFiles) throw StateError('隔离快照超过文件数量上限');
    return paths;
  }

  Future<List<String>> _workspacePaths(String root) async {
    final result = <String>[];
    final pending = <Directory>[Directory(root)];
    var visited = 0;
    while (pending.isNotEmpty) {
      await for (final entry in pending.removeLast().list(followLinks: false)) {
        if (++visited > maxFiles * 2) throw StateError('隔离结果条目过多');
        final path = p.relative(entry.path, from: root).replaceAll('\\', '/');
        if (!allowedPath(path)) continue;
        if (entry is Link) throw StateError('隔离结果不允许链接');
        if (entry is Directory) {
          pending.add(entry);
        } else {
          result.add(path);
        }
      }
    }
    return result;
  }

  Future<Map<String, List<int>>> _read(String root, List<String> paths) async {
    final result = <String, List<int>>{};
    var bytes = 0;
    final sandbox = WorkspaceSandbox(root);
    for (final path in paths) {
      final full = sandbox.resolvePath(path, allowRoot: false);
      final type = await FileSystemEntity.type(full, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        continue; // uncommitted deletion
      }
      if (type != FileSystemEntityType.file) throw StateError('隔离快照不支持链接或子模块');
      final file = File(full);
      if (await file.length() > 1024 * 1024) throw StateError('隔离快照单文件超过 1MiB');
      final value = await file
          .openRead(0, 1024 * 1024 + 1)
          .fold<List<int>>([], (all, chunk) => all..addAll(chunk));
      bytes += value.length;
      if (value.length > 1024 * 1024 ||
          bytes > maxBytes ||
          result.length >= maxFiles) {
        throw StateError('隔离快照超过大小限制');
      }
      result[path] = value;
    }
    return result;
  }

  Future<String> _git(String root, List<String> args) async {
    final process = await Process.start(
        'git', ['-c', 'core.fsmonitor=false', '-c', 'core.hooksPath=', ...args],
        workingDirectory: root, runInShell: false);
    final output = <int>[];
    var overflow = false;
    var timedOut = false;
    final timer = Timer(const Duration(seconds: 30), () {
      timedOut = true;
      process.kill();
    });
    final stdoutDone = process.stdout.forEach((chunk) {
      if (output.length + chunk.length > 2 * 1024 * 1024) {
        overflow = true;
        process.kill();
      } else {
        output.addAll(chunk);
      }
    });
    final stderrDone = process.stderr.drain<void>();
    final code = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);
    timer.cancel();
    if (code != 0 || overflow || timedOut) {
      throw StateError('Git 隔离操作失败，检查仓库和 Git 安装');
    }
    return utf8.decode(output);
  }
}
