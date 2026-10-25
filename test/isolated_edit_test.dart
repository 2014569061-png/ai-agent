import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/isolated_edit_service.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/infrastructure/tools/isolated_sub_agent_tool.dart';
import 'package:mobile_agent/infrastructure/tools/workspace_tools.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  Future<String> git(List<String> args) async {
    final result = await Process.run('git', args, workingDirectory: root.path);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return result.stdout as String;
  }

  Future<void> write(String path, String value) async {
    final file = File(p.join(root.path, path));
    await file.parent.create(recursive: true);
    await file.writeAsString(value);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nexus-isolated-');
    await git(['init', '-q']);
    await git(['config', 'user.name', 'Test']);
    await git(['config', 'user.email', 'test@example.invalid']);
    await write('.gitignore', '.nexus/\nignored.txt\n');
    await write('a.txt', 'committed\n');
    await write('deleted.txt', 'remove\n');
    await git(['add', '.']);
    await git(['commit', '-qm', 'fixture']);
  });
  tearDown(() => root.delete(recursive: true));

  test(
      'dirty bytes, staged bytes, untracked files and deletion seed independent proposal',
      () async {
    await write('a.txt', 'staged\n');
    await git(['add', 'a.txt']);
    await write('a.txt', 'working\n');
    await write('untracked.txt', 'untracked\n');
    await write('ignored.txt', 'private\n');
    await File(p.join(root.path, 'deleted.txt')).delete();
    final indexBefore = await git(['diff', '--cached']);
    final statusBefore = await git(['status', '--porcelain']);
    final result = await IsolatedEditService().run(
        root: root.path,
        execute: (workspace) async {
          expect(await File(p.join(workspace, 'a.txt')).readAsString(),
              'working\n');
          expect(await File(p.join(workspace, 'untracked.txt')).readAsString(),
              'untracked\n');
          expect(
              await File(p.join(workspace, 'deleted.txt')).exists(), isFalse);
          expect(
              await File(p.join(workspace, 'ignored.txt')).exists(), isFalse);
          final sandbox =
              WorkspaceSandbox(workspace, requireReadBeforeWrite: true);
          await ReadFileTool(sandbox: sandbox).execute({'path': 'a.txt'});
          expect(
              (await WriteFileTool(sandbox: sandbox)
                      .execute({'path': 'a.txt', 'content': 'proposal\n'}))
                  .ok,
              isTrue);
          await WriteFileTool(sandbox: sandbox)
              .execute({'path': 'new.txt', 'content': 'new\n'});
          return {'ok': true, 'summary': 'proposal ready'};
        });
    expect(result['status'], 'review_required');
    expect((result['changes'] as List).map((e) => e['path']),
        ['a.txt', 'new.txt']);
    expect(
        (result['changes'] as List).every((e) => e['parentUnchanged'] == true),
        isTrue);
    expect(await File(p.join(root.path, 'a.txt')).readAsString(), 'working\n');
    expect(await git(['diff', '--cached']), indexBefore);
    expect(await git(['status', '--porcelain']), statusBefore);
    final saved = jsonDecode(
        await File(p.join(root.path, result['reportPath'] as String))
            .readAsString()) as Map;
    expect(saved['baseline']['a.txt'], isNotEmpty);
    expect(saved['status'], 'review_required');
    expect(
        await git(['worktree', 'list', '--porcelain']), contains('detached'));
  });

  test('parent changes during child execution are reported as conflicts',
      () async {
    final result = await IsolatedEditService().run(
        root: root.path,
        execute: (workspace) async {
          await File(p.join(workspace, 'a.txt')).writeAsString('proposal');
          await write('a.txt', 'human');
          return {'ok': true};
        });
    expect((result['changes'] as List).single['parentUnchanged'], isFalse);
    expect(await File(p.join(root.path, 'a.txt')).readAsString(), 'human');
  });

  test(
      'failed child keeps proposal and classified outcome without changing parent',
      () async {
    final result = await IsolatedEditService().run(
        root: root.path,
        execute: (workspace) async {
          await File(p.join(workspace, 'a.txt')).writeAsString('partial');
          return {'ok': false, 'code': 'TOKEN_BUDGET_EXHAUSTED'};
        });
    expect(result['status'], 'child_incomplete');
    expect((result['outcome'] as Map)['code'], 'TOKEN_BUDGET_EXHAUSTED');
    expect(
        await File(p.join(root.path, result['workspace'] as String, 'a.txt'))
            .readAsString(),
        'partial');
    expect(
        await File(p.join(root.path, 'a.txt')).readAsString(), 'committed\n');
  });

  test('cancellation and oversized snapshot prevent model execution', () async {
    var calls = 0;
    Future<Map<String, dynamic>> execute(String _) async {
      calls++;
      return {'ok': true};
    }

    await expectLater(
        IsolatedEditService()
            .run(root: root.path, execute: execute, canContinue: () => false),
        throwsStateError);
    await File(p.join(root.path, 'large.bin'))
        .writeAsBytes(List.filled(1024 * 1024 + 1, 0));
    await expectLater(
        IsolatedEditService().run(root: root.path, execute: execute),
        throwsStateError);
    expect(calls, 0);
  });

  for (final reportBlocked in [false, true]) {
    test('failed execution reports persistence outcome: blocked=$reportBlocked',
        () async {
      final result = await IsolatedEditService().run(
          root: root.path,
          execute: (workspace) async {
            await File(p.join(workspace, 'a.txt')).writeAsString('partial');
            if (reportBlocked) {
              final reportPath = p.join(p.dirname(workspace), 'proposal.json');
              expect(p.isWithin(root.path, reportPath), isTrue);
              await File(reportPath).delete();
              await Directory(reportPath).create();
            }
            throw StateError('private child failure');
          });
      expect(result['status'], 'failed');
      expect(result['parentModified'], isFalse);
      expect(result['reportPersisted'], !reportBlocked);
      expect(jsonEncode(result), isNot(contains('private child failure')));
      if (reportBlocked) {
        // Windows may report PathAccessException for a directory at this path.
        expect(result['reportErrorType'],
            anyOf('FileSystemException', 'PathAccessException'));
      } else {
        final report = jsonDecode(
            await File(p.join(root.path, result['reportPath'] as String))
                .readAsString()) as Map;
        expect(report['status'], 'failed');
      }
      expect(
          await File(p.join(root.path, 'a.txt')).readAsString(), 'committed\n');
      expect(
          await File(p.join(root.path, result['workspace'] as String, 'a.txt'))
              .readAsString(),
          'partial');
    });
  }

  test(
      'narrow approval rejects Git metadata, escaping paths, commands and nested delegation',
      () async {
    Future<ToolApproval> approve(String name, Map<String, dynamic> args) =>
        IsolatedEditService.approve(
            root.path,
            ToolCall(id: 'c', name: name, arguments: args),
            ToolRisk.requiresConfirmation,
            false);
    for (final path in [
      '.git/config',
      './.GIT/config',
      '.nexus/x',
      '../outside',
      '.git ',
      r'.git::$DATA'
    ]) {
      expect(await approve('write_file', {'path': path}), ToolApproval.reject);
    }
    expect(
        await approve('apply_patch', {
          'files': [
            {'path': 'a.txt'},
            {'path': '.git/config'}
          ]
        }),
        ToolApproval.reject);
    expect(await approve('run_command', {'command': 'git status'}),
        ToolApproval.reject);
    expect(await approve('sub_agent_edit', {'prompt': 'nested'}),
        ToolApproval.reject);
    expect(await approve('write_file', {'path': 'lib/main.dart'}),
        ToolApproval.allowOnce);
  });

  test(
      'outer tool requires approval, validates before launch, and reports proposal side effect',
      () async {
    var calls = 0;
    final tool = IsolatedSubAgentTool(onRun: (_, budget) async {
      calls++;
      expect(budget, 4000);
      return {
        'status': 'review_required',
        'workspace': '.nexus/worktrees/x/source'
      };
    });
    expect(tool.manifest.risk, ToolRisk.requiresConfirmation);
    expect((await tool.execute({'prompt': 'x', 'maxTokens': 499})).ok, isFalse);
    expect(calls, 0);
    final result = await tool.execute({'prompt': 'edit'});
    expect(result.ok, isTrue);
    expect(result.effect, ToolEffect.applied);
    expect(tool.lastMetadata['isolatedProposal'], isTrue);
  });
}
