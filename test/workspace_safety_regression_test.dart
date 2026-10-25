import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/infrastructure/tools/workspace_tools.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late WorkspaceSandbox sandbox;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('nexus-workspace-safety-');
    sandbox = WorkspaceSandbox(root.path);
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  for (final path in ['.', './', 'child/..', '   ']) {
    test('delete_file refuses workspace root alias "$path"', () async {
      final result =
          await DeleteFileTool(sandbox: sandbox).execute({'path': path});
      expect(result.ok, isFalse);
      expect(result.code, ToolCodes.sandboxViolation);
      expect(result.effect, ToolEffect.none);
      expect(await root.exists(), isTrue);
    });
  }

  test('move_file refuses the workspace root without creating a destination',
      () async {
    final result = await MoveFileTool(sandbox: sandbox)
        .execute({'path': '.', 'newPath': 'nested'});
    expect(result.code, ToolCodes.sandboxViolation);
    expect(result.effect, ToolEffect.none);
    expect(await Directory('${root.path}/nested').exists(), isFalse);
  });

  test('listing the root is still allowed', () async {
    expect(sandbox.resolvePath('.'), root.path);
    final result =
        await ListDirectoryTool(sandbox: sandbox).execute({'path': '.'});
    expect(result.ok, isTrue);
  });

  test('write_file rejects a dangling symlink that points outside workspace',
      () async {
    final outside = Directory(p.join(root.parent.path,
        'nexus-dangling-link-target-${DateTime.now().microsecondsSinceEpoch}'));
    final Link link;
    try {
      link = await Link(p.join(root.path, 'outside-link')).create(outside.path);
    } on FileSystemException {
      // Windows may not grant symlink creation; Linux/macOS and enabled Windows
      // hosts exercise the actual dangling-link write path below.
      return;
    }
    addTearDown(link.delete);

    final result = await WriteFileTool(sandbox: sandbox).execute({
      'path': 'outside-link/created.txt',
      'content': 'must stay inside workspace',
    });
    expect(result.ok, isFalse);
    expect(result.code, ToolCodes.sandboxViolation);
    expect(await outside.exists(), isFalse);
  });

  for (final pair in [('same\nsame', 'same'), ('aaa', 'aa'), ('text', '')]) {
    test('edit_file rejects empty or ambiguous target ${pair.$2}', () async {
      final file = File('${root.path}/source.txt');
      await file.writeAsString(pair.$1);
      final result = await EditFileTool(sandbox: sandbox).execute({
        'path': 'source.txt',
        'targetContent': pair.$2,
        'replacementContent': 'changed',
      });
      expect(result.ok, isFalse);
      expect(result.code, ToolCodes.invalidArguments);
      expect(result.effect, ToolEffect.none);
      expect(await file.readAsString(), pair.$1);
    });
  }

  test('read_file rejects an oversized file even for a small requested range',
      () async {
    final handle =
        await File('${root.path}/large.txt').open(mode: FileMode.write);
    await handle.truncate(3 * 1024 * 1024);
    await handle.close();
    final result = await ReadFileTool(sandbox: sandbox).execute({
      'path': 'large.txt',
      'startLine': 1,
      'endLine': 1,
    });
    expect(result.ok, isFalse);
    expect(result.code, ToolCodes.tooLarge);
  });

  test('search skips private job logs, generated folders and oversized files',
      () async {
    for (final dir in [
      '.nexus/jobs',
      '.gradle',
      '.venv',
      '__pycache__',
      'target'
    ]) {
      final file = File('${root.path}/$dir/internal.txt');
      await file.parent.create(recursive: true);
      await file.writeAsString('needle-private');
    }
    await File('${root.path}/image.png').writeAsString('needle-private');
    final large =
        await File('${root.path}/large.txt').open(mode: FileMode.write);
    await large.writeString('needle-private\n');
    await large.truncate(2 * 1024 * 1024);
    await large.close();
    await File('${root.path}/public.txt').writeAsString('needle-public');
    final result =
        await SearchFilesTool(sandbox: sandbox).execute({'query': 'needle'});
    expect(result.ok, isTrue);
    expect(result.data?['matchCount'], 1);
    expect(result.data?['text'], contains('public.txt'));
    expect(result.data?['text'], isNot(contains('needle-private')));
  });
}
