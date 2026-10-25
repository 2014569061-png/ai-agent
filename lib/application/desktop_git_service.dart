import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'desktop_workbench_service.dart';

class DesktopGitFile {
  const DesktopGitFile(this.path, this.index, this.worktree,
      {this.originalPath});
  final String path, index, worktree;
  final String? originalPath;
  bool get untracked => index == '?' && worktree == '?';
  bool get staged => !untracked && index.trim().isNotEmpty;
  bool get unstaged => untracked || worktree.trim().isNotEmpty;
  bool get conflicted =>
      index == 'U' ||
      worktree == 'U' ||
      (index == 'A' && worktree == 'A') ||
      (index == 'D' && worktree == 'D');
}

class DesktopGitSnapshot {
  const DesktopGitSnapshot(
      {required this.root, required this.branch, required this.files});
  final String root, branch;
  final List<DesktopGitFile> files;
}

/// Git worktree 信息（用于多会话 / 多 Agent 并行线程隔离）。
class DesktopWorktreeInfo {
  const DesktopWorktreeInfo({
    required this.path,
    required this.head,
    required this.branch,
    this.isBare = false,
    this.isMain = false,
    this.isDetached = false,
    this.isLocked = false,
    this.lockReason,
    this.isPrunable = false,
  });

  final String path;
  final String head;
  final String branch;
  final bool isBare;
  final bool isMain;
  final bool isDetached;
  final bool isLocked;
  final String? lockReason;
  final bool isPrunable;

  Map<String, dynamic> toJson() => {
        'path': path,
        'head': head,
        'branch': branch,
        'isBare': isBare,
        'isMain': isMain,
        'isDetached': isDetached,
        'isLocked': isLocked,
        'lockReason': lockReason,
        'isPrunable': isPrunable,
      };
}

/// Native argument vectors deliberately bypass PowerShell/cmd quoting.
/// Git paths are literal, including brackets, spaces and shell metacharacters.
class DesktopGitService {
  const DesktopGitService();
  static const outputLimit = 512 * 1024;

  Future<String> _run(String root, List<String> args, {String? input}) async {
    final process = await Process.start('git', args,
        workingDirectory: root,
        environment: {
          'GIT_LITERAL_PATHSPECS': '1',
          'GIT_TERMINAL_PROMPT': '0'
        });
    final out = <int>[], err = <int>[];
    void append(List<int> destination, List<int> chunk) {
      final remaining = outputLimit - destination.length;
      if (remaining > 0) destination.addAll(chunk.take(remaining));
    }

    final stdoutDone = process.stdout.forEach((chunk) => append(out, chunk));
    final stderrDone = process.stderr.forEach((chunk) => append(err, chunk));
    if (input != null) process.stdin.add(utf8.encode(input));
    await process.stdin.close();
    final timeout = Timer(const Duration(seconds: 20), () => process.kill());
    try {
      final code = await process.exitCode;
      await Future.wait([stdoutDone, stderrDone]);
      if (code != 0) {
        throw StateError(utf8.decode(err, allowMalformed: true).trim());
      }
      if (out.length >= outputLimit) {
        throw StateError('Git 输出超过 512 KB，请缩小查看范围或在编辑器中查看');
      }
      return utf8.decode(out, allowMalformed: true);
    } finally {
      timeout.cancel();
    }
  }

  static List<DesktopGitFile> parseStatus(String output) {
    final records = output.split('\x00');
    final files = <DesktopGitFile>[];
    for (var i = 0; i < records.length; i++) {
      final row = records[i];
      if (row.length < 4) continue;
      final index = row[0], worktree = row[1];
      String? original;
      if ((index == 'R' ||
              index == 'C' ||
              worktree == 'R' ||
              worktree == 'C') &&
          i + 1 < records.length) {
        original = records[++i];
      }
      files.add(DesktopGitFile(row.substring(3), index, worktree,
          originalPath: original));
    }
    return files;
  }

  Future<DesktopGitSnapshot> inspect(String workspace) async {
    final root =
        (await _run(workspace, ['rev-parse', '--show-toplevel'])).trim();
    final values = await Future.wait([
      _run(root, ['status', '--porcelain=v1', '-z', '--untracked-files=all']),
      _run(root, ['rev-parse', '--abbrev-ref', 'HEAD'])
          .catchError((_) => '未提交'),
    ]);
    return DesktopGitSnapshot(
        root: root, branch: values[1].trim(), files: parseStatus(values[0]));
  }

  void _validatePath(String root, String path) {
    final target = p.normalize(p.join(root, path));
    if (p.isAbsolute(path) || !p.isWithin(p.normalize(root), target)) {
      throw ArgumentError('文件不在 Git 仓库中');
    }
  }

  Future<String> diff(DesktopGitSnapshot snapshot, DesktopGitFile file,
      {bool staged = false}) async {
    _validatePath(snapshot.root, file.path);
    if (file.untracked) {
      final target = File(await const DesktopWorkspaceFiles()
          .resolve(snapshot.root, file.path));
      if (await target.length() > outputLimit ~/ 2) {
        return '新文件大于 256 KB，请在文件面板或外部编辑器查看。';
      }
      final bytes = await target.readAsBytes();
      if (bytes.contains(0)) return '新建二进制文件：${file.path}';
      final text = utf8.decode(bytes, allowMalformed: true);
      return '--- /dev/null\n+++ b/${file.path}\n'
          '@@ -0,0 +1,${'\n'.allMatches(text).length + 1} @@\n'
          '${text.split('\n').map((line) => '+$line').join('\n')}';
    }
    return _run(snapshot.root, [
      'diff',
      '--no-color',
      if (staged) '--staged',
      '--',
      file.path,
    ]);
  }

  Future<void> stage(DesktopGitSnapshot snapshot, DesktopGitFile file) async {
    _validatePath(snapshot.root, file.path);
    await _run(snapshot.root, ['add', '--', file.path]);
  }

  Future<void> revert(DesktopGitSnapshot snapshot, DesktopGitFile file) async {
    _validatePath(snapshot.root, file.path);
    if (file.untracked) {
      final target = File(await const DesktopWorkspaceFiles()
          .resolve(snapshot.root, file.path));
      if (await target.exists()) {
        await target.delete();
      }
      return;
    }
    await _run(snapshot.root, ['checkout', 'HEAD', '--', file.path]);
  }

  Future<void> unstage(DesktopGitSnapshot snapshot, DesktopGitFile file) async {
    _validatePath(snapshot.root, file.path);
    // reset works on committed repositories; rm --cached handles an unborn HEAD.
    final headExists =
        await _run(snapshot.root, ['rev-parse', '--verify', 'HEAD'])
            .then((_) => true)
            .catchError((_) => false);
    final paths = [
      file.path,
      if (file.originalPath != null) file.originalPath!
    ];
    for (final path in paths) {
      _validatePath(snapshot.root, path);
    }
    await _run(
        snapshot.root,
        headExists
            ? ['reset', 'HEAD', '--', ...paths]
            : ['rm', '--cached', '--', ...paths]);
  }

  Future<List<String>> branches(String root) async =>
      (await _run(root, ['branch', '--format=%(refname:short)']))
          .split('\n')
          .where((line) => line.isNotEmpty)
          .toList();

  Future<void> checkout(String root, String branch) async {
    await _run(root, ['check-ref-format', '--branch', branch]);
    await _run(root, ['switch', '--', branch]);
  }

  /// 解析 `git worktree list --porcelain` 输出。
  static List<DesktopWorktreeInfo> parseWorktrees(String output) {
    final lines = output.split('\n');
    final result = <DesktopWorktreeInfo>[];
    String? path, head, branch;
    var bare = false, detached = false, locked = false, prunable = false;
    String? lockReason;

    void flush() {
      if (path != null && path!.isNotEmpty) {
        final isFirst = result.isEmpty;
        var branchName = branch ?? '';
        if (branchName.startsWith('refs/heads/')) {
          branchName = branchName.substring('refs/heads/'.length);
        } else if (detached && branchName.isEmpty) {
          branchName = '(detached HEAD)';
        }
        result.add(DesktopWorktreeInfo(
          path: path!,
          head: head ?? '',
          branch: branchName,
          isBare: bare,
          isMain: isFirst,
          isDetached: detached,
          isLocked: locked,
          lockReason: lockReason,
          isPrunable: prunable,
        ));
      }
      path = null;
      head = null;
      branch = null;
      bare = false;
      detached = false;
      locked = false;
      lockReason = null;
      prunable = false;
    }

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) {
        flush();
        continue;
      }
      if (line.startsWith('worktree ')) {
        if (path != null) flush();
        path = line.substring('worktree '.length).trim();
      } else if (line.startsWith('HEAD ')) {
        head = line.substring('HEAD '.length).trim();
      } else if (line.startsWith('branch ')) {
        branch = line.substring('branch '.length).trim();
      } else if (line == 'bare') {
        bare = true;
      } else if (line == 'detached') {
        detached = true;
      } else if (line.startsWith('locked')) {
        locked = true;
        final rest = line.substring('locked'.length).trim();
        lockReason = rest.isNotEmpty ? rest : null;
      } else if (line.startsWith('prunable')) {
        prunable = true;
      }
    }
    flush();
    return result;
  }

  /// 列出当前仓库全部 worktree。
  Future<List<DesktopWorktreeInfo>> listWorktrees(String root) async {
    final topLevel =
        (await _run(root, ['rev-parse', '--show-toplevel'])).trim();
    final output = await _run(topLevel, ['worktree', 'list', '--porcelain']);
    return parseWorktrees(output);
  }

  Future<bool> _sameDirectory(String first, String second) async {
    if (p.equals(p.normalize(first), p.normalize(second))) return true;
    final firstDirectory = Directory(first);
    final secondDirectory = Directory(second);
    if (!await firstDirectory.exists() || !await secondDirectory.exists()) {
      return false;
    }
    // Git expands Windows 8.3 paths while callers may retain a short TEMP path.
    // Resolve existing aliases before deciding whether this is the main tree.
    return p.equals(await firstDirectory.resolveSymbolicLinks(),
        await secondDirectory.resolveSymbolicLinks());
  }

  /// 为多 Agent 线程在指定路径创建 worktree 隔离工作区。
  Future<DesktopWorktreeInfo> addWorktree(
    String root, {
    required String path,
    String? branch,
    bool newBranch = false,
    String? commitish,
  }) async {
    final topLevel =
        (await _run(root, ['rev-parse', '--show-toplevel'])).trim();
    final normalizedTarget =
        p.normalize(p.isAbsolute(path) ? path : p.join(topLevel, path));
    if (await _sameDirectory(topLevel, normalizedTarget)) {
      throw ArgumentError('不能在主工作区根目录上创建 worktree');
    }

    final args = <String>['worktree', 'add'];
    if (newBranch && branch != null && branch.isNotEmpty) {
      args.addAll(['-b', branch]);
    }
    args.add(normalizedTarget);
    if (!newBranch && branch != null && branch.isNotEmpty) {
      args.add(branch);
    } else if (commitish != null && commitish.isNotEmpty) {
      args.add(commitish);
    }
    await _run(topLevel, args);

    final worktrees = await listWorktrees(topLevel);
    for (final worktree in worktrees) {
      if (await _sameDirectory(worktree.path, normalizedTarget)) {
        return worktree;
      }
    }
    return DesktopWorktreeInfo(
      path: normalizedTarget,
      head: '',
      branch: branch ?? '',
    );
  }

  /// 移除 worktree 并释放文件锁。
  Future<void> removeWorktree(
    String root, {
    required String path,
    bool force = false,
  }) async {
    final topLevel =
        (await _run(root, ['rev-parse', '--show-toplevel'])).trim();
    final normalizedTarget =
        p.normalize(p.isAbsolute(path) ? path : p.join(topLevel, path));
    final worktrees = await listWorktrees(topLevel);
    DesktopWorktreeInfo? target;
    for (final worktree in worktrees) {
      if (await _sameDirectory(worktree.path, normalizedTarget)) {
        target = worktree;
        break;
      }
    }
    if (target != null && target.isMain) {
      throw StateError('不能删除主工作区');
    }
    final args = <String>['worktree', 'remove'];
    if (force) args.add('--force');
    args.add(normalizedTarget);
    await _run(topLevel, args);
  }

  /// 清理失效的 worktree 元数据。
  Future<void> applyPatch(String root, String patch,
      {bool staged = false, bool reverse = false}) async {
    if (patch.length > outputLimit) throw ArgumentError('补丁过大');
    await _run(
        root,
        [
          'apply',
          if (staged) '--cached',
          if (reverse) '--reverse',
          '--whitespace=nowarn',
          '-'
        ],
        input: patch);
  }

  Future<void> mergeBranch(String root, String branch) async {
    if (branch.isEmpty || branch.startsWith('-')) throw ArgumentError('无效分支');
    if ((await inspect(root)).files.isNotEmpty) {
      throw StateError('原工作区有未提交改动，请先保存');
    }
    // Fast-forward only: a failed merge never leaves conflict markers behind.
    await _run(root, ['merge', '--ff-only', '--', branch]);
  }

  Future<void> excludeManagedWorktrees(String root) async {
    final common = (await _run(root, ['rev-parse', '--git-common-dir'])).trim();
    final path = p.isAbsolute(common) ? common : p.join(root, common);
    final file = File(p.join(path, 'info', 'exclude'));
    await file.parent.create(recursive: true);
    final existing = await file.exists() ? await file.readAsString() : '';
    if (!existing.split('\n').contains('/.nexus/worktrees/')) {
      await file.writeAsString('\n/.nexus/worktrees/\n',
          mode: FileMode.append, flush: true);
    }
  }

  Future<void> pruneWorktrees(String root) async {
    final topLevel =
        (await _run(root, ['rev-parse', '--show-toplevel'])).trim();
    await _run(topLevel, ['worktree', 'prune']);
  }
}

final desktopGitServiceProvider = Provider((ref) => const DesktopGitService());
final desktopGitSnapshotProvider = FutureProvider.autoDispose
    .family<DesktopGitSnapshot, String>((ref, root) async {
  Timer? timer;
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    timer?.cancel();
  });
  try {
    return await ref.watch(desktopGitServiceProvider).inspect(root);
  } finally {
    if (!disposed) {
      timer = Timer(const Duration(seconds: 4), () {
        ref.invalidateSelf();
      });
    }
  }
});
