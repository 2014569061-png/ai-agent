import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/change_review.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/infrastructure/files/workspace_fs.dart';
import 'package:mobile_agent/infrastructure/tools/apply_patch_tool.dart';
import 'package:mobile_agent/infrastructure/tools/workspace_tools.dart';

class FaultFs extends LocalWorkspaceFs {
  int installs = 0;
  bool failStage = false;
  bool failInstall = false;
  bool failCleanup = false;
  String? externalPath;
  @override
  Future<void> writeText(String path, String content) async {
    if (failStage && path.endsWith('.tmp')) {
      await super.writeText(path, 'partial');
      throw const FileSystemException('injected');
    }
    await super.writeText(path, content);
  }

  @override
  Future<void> deleteFile(String path) async {
    if (failCleanup && path.endsWith('.bak')) {
      throw const FileSystemException('injected cleanup failure');
    }
    await super.deleteFile(path);
  }

  @override
  Future<void> rename(String from, String to) async {
    if (from.endsWith('.tmp') && ++installs == 2 && failInstall) {
      if (externalPath != null) {
        await File(externalPath!).writeAsString('external\n');
      }
      throw const FileSystemException('injected');
    }
    await super.rename(from, to);
  }
}

void main() {
  late Directory root;
  late FaultFs fs;
  late WorkspaceSandbox sandbox;
  late ApplyPatchTool tool;
  Map<String, String> patch(String name, {String old = 'old'}) => {
        'path': name,
        'patch': '--- a/$name\n+++ b/$name\n@@ -1 +1 @@\n-$old\n+new\n',
      };
  Future<String> read(String name) => File('${root.path}/$name').readAsString();
  Future<List<String>> names() async => [
        await for (final file in root.list())
          if (file.path.split(Platform.pathSeparator).last != '.nexus')
            file.path.split(Platform.pathSeparator).last
      ];
  setUp(() async {
    root = await Directory.systemTemp.createTemp('batch-patch-');
    fs = FaultFs();
    sandbox = WorkspaceSandbox(root.path, fs: fs, requireReadBeforeWrite: true);
    tool = ApplyPatchTool(sandbox: sandbox);
    for (final name in ['a.txt', 'b.txt']) {
      await File('${root.path}/$name').writeAsString('old\n');
      await ReadFileTool(sandbox: sandbox).execute({'path': name});
    }
  });
  tearDown(() => root.delete(recursive: true));

  test('commits all files and exposes both diffs to review', () async {
    final result = await tool.execute({
      'files': [patch('a.txt'), patch('b.txt')]
    });
    expect(result.ok, isTrue);
    expect(result.effect, ToolEffect.applied);
    expect(await read('a.txt'), 'new\n');
    expect(await read('b.txt'), 'new\n');
    expect(await names(), unorderedEquals(['a.txt', 'b.txt']));
    final review =
        const ChangeReviewService().fromMetadata([tool.lastMetadata]);
    expect(review.files.map((f) => f.path), ['a.txt', 'b.txt']);
    expect(review.linesAdded, 2);
    expect(review.files.every((f) => f.contentHashAfter != f.contentHashBefore),
        isTrue);
  });

  test('restart after committed cleanup failure preserves both new files',
      () async {
    fs.failCleanup = true;
    final result = await tool.execute({
      'files': [patch('a.txt'), patch('b.txt')]
    });
    expect(result.ok, isTrue);
    expect(result.data!['transactionStatus'], 'committed');
    expect(await sandbox.patchJournal.hasPending(), isTrue);
    final restarted = WorkspaceSandbox(root.path, requireReadBeforeWrite: true);
    expect((await restarted.prepareForWrite())!.code, 'PATCH_RECOVERED');
    expect(await read('a.txt'), 'new\n');
    expect(await read('b.txt'), 'new\n');
    expect(await restarted.patchJournal.hasPending(), isFalse);
    expect(await names(), unorderedEquals(['a.txt', 'b.txt']));
  });

  test('batch rejects paths that could not be safely replayed from a journal',
      () async {
    for (final path in [
      'a.txt:stream',
      '.git./config',
      '.nexus./cache',
      'dir /a.txt',
      'dir./a.txt',
    ]) {
      final result = await tool.execute({'files': [patch(path)]});
      expect(result.code, ToolCodes.invalidFormat, reason: path);
      expect(result.effect, ToolEffect.none, reason: path);
    }
    expect(await read('a.txt'), 'old\n');
    expect(await read('b.txt'), 'old\n');
    expect(await sandbox.patchJournal.hasPending(), isFalse);
  });

  test('late invalid hunk never changes earlier file', () async {
    final result = await tool.execute({
      'files': [patch('a.txt'), patch('b.txt', old: 'wrong')]
    });
    expect(result.code, ToolCodes.invalidFormat);
    expect(result.effect, ToolEffect.none);
    expect(await read('a.txt'), 'old\n');
    expect(await names(), unorderedEquals(['a.txt', 'b.txt']));
  });

  test('missing read and stale second file block entire batch', () async {
    sandbox.forgetReads();
    await ReadFileTool(sandbox: sandbox).execute({'path': 'a.txt'});
    expect(
        (await tool.execute({
          'files': [patch('a.txt'), patch('b.txt')]
        }))
            .code,
        ToolCodes.readRequired);
    await ReadFileTool(sandbox: sandbox).execute({'path': 'b.txt'});
    await File('${root.path}/b.txt').writeAsString('external\n');
    expect(
        (await tool.execute({
          'files': [patch('a.txt'), patch('b.txt')]
        }))
            .code,
        ToolCodes.revisionConflict);
    expect(await read('a.txt'), 'old\n');
    expect(await read('b.txt'), 'external\n');
  });

  test('duplicate aliases, mixed API and escape paths cannot mutate files',
      () async {
    for (final arguments in [
      {
        'files': [patch('a.txt'), patch('./a.txt')]
      },
      {
        'files': [patch('a.txt')],
        'path': 'a.txt'
      },
      {
        'files': [patch('../escape')]
      },
      {'files': List.generate(11, (_) => patch('a.txt'))},
    ]) {
      expect((await tool.execute(arguments)).ok, isFalse);
    }
    expect(await read('a.txt'), 'old\n');
    expect(await names(), unorderedEquals(['a.txt', 'b.txt']));
  });

  test(
      'partial staging write leaves originals intact and removes temporary file',
      () async {
    fs.failStage = true;
    final result = await tool.execute({
      'files': [patch('a.txt'), patch('b.txt')]
    });
    expect(result.ok, isFalse);
    expect(result.effect, ToolEffect.none);
    expect(await read('a.txt'), 'old\n');
    expect(await read('b.txt'), 'old\n');
    expect(await names(), unorderedEquals(['a.txt', 'b.txt']));
  });

  test('second installation failure restores both originals and clears reads',
      () async {
    fs.failInstall = true;
    final result = await tool.execute({
      'files': [patch('a.txt'), patch('b.txt')]
    });
    expect(result.ok, isFalse);
    expect(result.effect, ToolEffect.none);
    expect(result.data!['transactionStatus'], 'rolled_back');
    expect(await read('a.txt'), 'old\n');
    expect(await read('b.txt'), 'old\n');
    expect(await names(), unorderedEquals(['a.txt', 'b.txt']));
    expect(sandbox.checkFresh('${root.path}/a.txt', 'old\n')!.code,
        ToolCodes.readRequired);
  });

  test(
      'rollback preserves external edits and recovery backup with unknown effect',
      () async {
    fs.failInstall = true;
    fs.externalPath = '${root.path}/a.txt';
    final result = await tool.execute({
      'files': [patch('a.txt'), patch('b.txt')]
    });
    expect(result.ok, isFalse);
    expect(result.effect, ToolEffect.unknown);
    expect(result.data!['transactionStatus'], 'needs_recovery');
    expect(result.data!['unresolvedFiles'], ['a.txt']);
    expect(await read('a.txt'), 'external\n');
    expect(await read('b.txt'), 'old\n');
    final backups = result.data!['recoveryFiles'] as List;
    expect(await read(backups.single as String), 'old\n');
    expect(const ChangeReviewService().fromMetadata([tool.lastMetadata]).files,
        isEmpty);
    expect(result.encode(), isNot(contains('injected')));
  });
}
