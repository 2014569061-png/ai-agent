import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/desktop_git_service.dart';
import 'package:path/path.dart' as p;

void main() {
  const git = DesktopGitService();
  late Directory directory;
  Future<void> run(List<String> args) async {
    final result =
        await Process.run('git', args, workingDirectory: directory.path);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nexus-blue-git-');
    await run(['init', '-q', '--initial-branch=main']);
    await run(['config', 'user.name', 'UI Test']);
    await run(['config', 'user.email', 'ui-test@example.invalid']);
    await File(p.join(directory.path, 'app.txt')).writeAsString('before\n');
    await run(['add', '--', 'app.txt']);
    await run(['commit', '-qm', 'fixture']);
  });
  tearDown(() async => directory.delete(recursive: true));

  test('real unstaged and staged differences and reversible selection',
      () async {
    await File(p.join(directory.path, 'app.txt')).writeAsString('after\n');
    final snapshot = await git.inspect(directory.path);
    expect(snapshot.branch, 'main');
    final file = snapshot.files.single;
    expect(file.unstaged, isTrue);
    expect(file.staged, isFalse);
    expect(await git.diff(snapshot, file), contains('+after'));
    await git.stage(snapshot, file);
    final staged = await git.inspect(directory.path);
    expect(staged.files.single.staged, isTrue);
    expect(await git.diff(staged, staged.files.single, staged: true),
        contains('+after'));
    await git.unstage(staged, staged.files.single);
    expect((await git.inspect(directory.path)).files.single.staged, isFalse);
    expect(await File(p.join(directory.path, 'app.txt')).readAsString(),
        'after\n');
  });

  test('untracked special-character path is literal and stages only one file',
      () async {
    const path = r'notes [draft] & $cash.txt';
    await File(p.join(directory.path, path)).writeAsString('literal content\n');
    await File(p.join(directory.path, 'other.txt'))
        .writeAsString('keep unstaged\n');
    final snapshot = await git.inspect(directory.path);
    final file = snapshot.files.singleWhere((file) => file.path == path);
    expect(file.untracked, isTrue);
    expect(await git.diff(snapshot, file), contains('+literal content'));
    await git.stage(snapshot, file);
    final result = await git.inspect(directory.path);
    expect(
        result.files.singleWhere((file) => file.path == path).staged, isTrue);
    expect(
        result.files.singleWhere((file) => file.path == 'other.txt').untracked,
        isTrue);
  });

  test('rename record consumes original path and unstage retains renamed file',
      () async {
    await run(['mv', 'app.txt', 'renamed [v2].txt']);
    final snapshot = await git.inspect(directory.path);
    expect(snapshot.files.single.originalPath, 'app.txt');
    await git.unstage(snapshot, snapshot.files.single);
    expect(await File(p.join(directory.path, 'renamed [v2].txt')).exists(),
        isTrue);
  });

  test('new repository stages and unstages without HEAD', () async {
    final empty = await Directory.systemTemp.createTemp('nexus-unborn-');
    try {
      final init = await Process.run('git', ['init', '-q'],
          workingDirectory: empty.path);
      expect(init.exitCode, 0);
      await File(p.join(empty.path, 'new.txt')).writeAsString('new\n');
      final snapshot = await git.inspect(empty.path);
      await git.stage(snapshot, snapshot.files.single);
      final staged = await git.inspect(empty.path);
      await git.unstage(staged, staged.files.single);
      expect((await git.inspect(empty.path)).files.single.untracked, isTrue);
      expect(await File(p.join(empty.path, 'new.txt')).readAsString(), 'new\n');
    } finally {
      await empty.delete(recursive: true);
    }
  });

  test('branch switching and conflict-safe checkout use actual repository',
      () async {
    await run(['branch', 'feature/ui']);
    expect(await git.branches(directory.path), contains('feature/ui'));
    await git.checkout(directory.path, 'feature/ui');
    expect((await git.inspect(directory.path)).branch, 'feature/ui');
    expect(git.checkout(directory.path, '-malicious'), throwsStateError);
  });

  test('paths outside repository cannot be staged', () async {
    final snapshot = await git.inspect(directory.path);
    expect(
        git.stage(snapshot, const DesktopGitFile('../outside.txt', '?', '?')),
        throwsArgumentError);
  });

  test('parseWorktrees parses porcelain output including detached, locked, and prunable flags', () {
    const porcelain = '''worktree /home/user/project
HEAD 1111222233334444555566667777888899990000
branch refs/heads/main

worktree /home/user/project/.nexus/worktrees/feat-agent-1
HEAD aaaabbbbccccddddeeeeffff0000111122223333
branch refs/heads/feat/agent-thread-1
locked reason for locking

worktree /home/user/project/.nexus/worktrees/detached-agent
HEAD ffff000011112222333344445555666677778888
detached
prunable gitdir file points to non-existent location
''';
    final list = DesktopGitService.parseWorktrees(porcelain);
    expect(list, hasLength(3));

    // Main worktree
    expect(list[0].path, '/home/user/project');
    expect(list[0].branch, 'main');
    expect(list[0].isMain, isTrue);
    expect(list[0].isDetached, isFalse);

    // Feature worktree
    expect(list[1].branch, 'feat/agent-thread-1');
    expect(list[1].isMain, isFalse);
    expect(list[1].isLocked, isTrue);
    expect(list[1].lockReason, 'reason for locking');

    // Detached worktree
    expect(list[2].isDetached, isTrue);
    expect(list[2].branch, '(detached HEAD)');
    expect(list[2].isPrunable, isTrue);
  });

  test('real git worktree creation, file isolation, listing, and clean removal', () async {
    final tempParent = await Directory.systemTemp.createTemp('nexus-wt-container-');
    addTearDown(() => tempParent.delete(recursive: true));

    final wtPath = p.join(tempParent.path, 'agent-thread-wt');

    // 1. 初始只有主工作区
    final initialList = await git.listWorktrees(directory.path);
    expect(initialList, hasLength(1));
    expect(initialList.single.isMain, isTrue);

    // 2. 创建用于并发 Agent 线程的新分支与 worktree
    final created = await git.addWorktree(
      directory.path,
      path: wtPath,
      branch: 'thread-agent-1',
      newBranch: true,
    );
    expect(p.normalize(created.path), p.normalize(wtPath));

    // 3. 在 worktree 中写入专属文件，主仓库不受影响（强隔离）
    await File(p.join(wtPath, 'thread_output.dart')).writeAsString('void threadMain() {}\n');
    expect(await File(p.join(directory.path, 'thread_output.dart')).exists(), isFalse);

    // 4. listWorktrees 可以正确发现 2 个 worktree
    final updatedList = await git.listWorktrees(directory.path);
    expect(updatedList, hasLength(2));
    final agentWt = updatedList.firstWhere((wt) => !wt.isMain);
    expect(agentWt.branch, 'thread-agent-1');

    // 5. 任务完成后移除 worktree 并 prune
    await git.removeWorktree(directory.path, path: wtPath, force: true);
    await git.pruneWorktrees(directory.path);

    final finalList = await git.listWorktrees(directory.path);
    expect(finalList, hasLength(1));
    expect(finalList.single.isMain, isTrue);
  });

  test('cannot remove main worktree and invalid path rejected', () async {
    expect(
      git.removeWorktree(directory.path, path: directory.path),
      throwsStateError,
    );
    expect(
      git.addWorktree(directory.path, path: directory.path),
      throwsArgumentError,
    );
  });
}
