import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/desktop_worktree_service.dart';
import 'package:path/path.dart' as p;

void main() {
  const service = DesktopWorktreeService();
  late Directory directory;

  Future<void> runGit(List<String> args) async {
    final result =
        await Process.run('git', args, workingDirectory: directory.path);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nexus-wt-svc-');
    await runGit(['init', '-q', '--initial-branch=main']);
    await runGit(['config', 'user.name', 'WT Test']);
    await runGit(['config', 'user.email', 'wt-test@example.invalid']);
    await File(p.join(directory.path, 'base.txt')).writeAsString('base\n');
    await runGit(['add', '--', 'base.txt']);
    await runGit(['commit', '-qm', 'initial']);
  });

  tearDown(() async => directory.delete(recursive: true));

  test('worktreePathFor and isWorktreeWorkspace pattern matches correctly', () {
    final target = service.worktreePathFor(directory.path, 'conv-alpha-01');
    expect(target, contains(p.join('.nexus', 'worktrees', 'conv-alpha-01')));
    expect(service.isWorktreeWorkspace(target), isTrue);
    expect(service.isWorktreeWorkspace(directory.path), isFalse);
  });

  test('ensureSessionWorktree provisions dedicated directory and clean removal',
      () async {
    // 1. 创建会话专属 worktree
    final info = await service.ensureSessionWorktree(
      directory.path,
      conversationId: 'c-101',
      branchName: 'agent-thread-101',
    );
    expect(info.branch, 'agent-thread-101');
    expect(Directory(info.path).existsSync(), isTrue);

    // 2. 幂等再次调用直接返回已有实例
    final cached = await service.ensureSessionWorktree(
      directory.path,
      conversationId: 'c-101',
      branchName: 'agent-thread-101',
    );
    expect(p.normalize(cached.path), p.normalize(info.path));

    // 3. 在隔离工作区修改文件，主仓库不受干扰
    await File(p.join(info.path, 'agent_result.json'))
        .writeAsString('{"ok":true}\n');
    expect(File(p.join(directory.path, 'agent_result.json')).existsSync(),
        isFalse);

    // 4. 默认清理必须保留未提交的工作，不能将旧的强制删除语义作为成功。
    await expectLater(
      service.removeSessionWorktree(directory.path, conversationId: 'c-101'),
      throwsStateError,
    );
    expect(Directory(info.path).existsSync(), isTrue);
    final result = File(p.join(info.path, 'agent_result.json'));
    expect(await result.readAsString(), '{"ok":true}\n');
    // 仅删除本测试创建的临时文件，再验证干净工作区的正常清理。
    await result.delete();
    await service.removeSessionWorktree(directory.path,
        conversationId: 'c-101');
    expect(Directory(info.path).existsSync(), isFalse);

    final current = await service.listWorktrees(directory.path);
    expect(current, hasLength(1));
    expect(current.single.isMain, isTrue);
  });
}
