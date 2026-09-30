// 阶段 5a：文件工具只经由 WorkspaceFs 访问文件。
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/infrastructure/files/bounded_text_reader.dart';
import 'package:mobile_agent/infrastructure/files/workspace_fs.dart';
import 'package:mobile_agent/infrastructure/tools/workspace_tools.dart';
import 'package:path/path.dart' as p;

/// 纯内存实现：证明工具不再直接碰 dart:io。
class InMemoryWorkspaceFs implements WorkspaceFs {
  final files = <String, String>{};
  final dirs = <String>{};
  final ops = <String>[];

  @override
  String get id => 'memory';

  @override
  Future<WorkspaceEntryKind> kindOf(String path) async {
    if (files.containsKey(path)) return WorkspaceEntryKind.file;
    if (dirs.contains(path)) return WorkspaceEntryKind.directory;
    return WorkspaceEntryKind.notFound;
  }

  @override
  Future<String> readText(String path,
      {int maxBytes = BoundedTextReader.maxReadBytes}) async {
    ops.add('read $path');
    final text = files[path];
    if (text == null) throw const FileSystemException('missing');
    return text;
  }

  @override
  Future<void> writeText(String path, String content) async {
    ops.add('write $path');
    await ensureDirectory(p.dirname(path));
    files[path] = content;
  }

  @override
  Stream<WorkspaceEntry> list(String directory, {bool recursive = false}) {
    bool under(String path) => recursive
        ? p.isWithin(directory, path)
        : p.dirname(path) == directory;
    return Stream.fromIterable([
      for (final d in dirs)
        if (under(d)) WorkspaceEntry(d, isDirectory: true),
      for (final f in files.keys)
        if (under(f)) WorkspaceEntry(f, isDirectory: false),
    ]);
  }

  @override
  Future<void> ensureDirectory(String path) async {
    var current = path;
    while (!dirs.contains(current) && p.dirname(current) != current) {
      dirs.add(current);
      current = p.dirname(current);
    }
  }

  @override
  Future<void> deleteFile(String path) async {
    ops.add('delete $path');
    files.remove(path);
  }

  @override
  Future<void> deleteEmptyDirectory(String path) async {
    if (files.keys.any((f) => p.isWithin(path, f)) ||
        dirs.any((d) => p.isWithin(path, d))) {
      throw const FileSystemException('not empty');
    }
    ops.add('rmdir $path');
    dirs.remove(path);
  }

  @override
  Future<void> rename(String from, String to) async {
    ops.add('rename $from -> $to');
    if (files.containsKey(from)) {
      files[to] = files.remove(from)!;
      return;
    }
    dirs
      ..remove(from)
      ..add(to);
    for (final f in files.keys.where((f) => p.isWithin(from, f)).toList()) {
      files[p.join(to, p.relative(f, from: from))] = files.remove(f)!;
    }
  }
}

void main() {
  late Directory root;
  late InMemoryWorkspaceFs fs;
  late WorkspaceSandbox sandbox;

  setUp(() async {
    // 沙盒的路径校验仍在本地进行，所以根目录要真实存在；文件本身全在内存里。
    root = await Directory.systemTemp.createTemp('ws_fs_');
    fs = InMemoryWorkspaceFs()..dirs.add(root.path);
    sandbox = WorkspaceSandbox(root.path, fs: fs);
  });
  tearDown(() => root.delete(recursive: true));

  String abs(String rel) => p.normalize(p.join(root.path, rel));

  test('sandbox defaults to the local implementation', () {
    expect(WorkspaceSandbox(root.path).fs, isA<LocalWorkspaceFs>());
    expect(sandbox.fs.id, 'memory');
  });

  test('write, read and edit go through the capability', () async {
    final write = await WriteFileTool(sandbox: sandbox)
        .execute({'path': 'src/a.txt', 'content': 'hello world'});
    expect(write.ok, isTrue);
    expect(fs.files[abs('src/a.txt')], 'hello world');

    final edit = await EditFileTool(sandbox: sandbox).execute({
      'path': 'src/a.txt',
      'targetContent': 'world',
      'replacementContent': 'nexus',
    });
    expect(edit.ok, isTrue);

    final read =
        await ReadFileTool(sandbox: sandbox).execute({'path': 'src/a.txt'});
    expect(read.data!['text'], 'hello nexus');
    expect(await root.list().toList(), isEmpty, reason: '真实磁盘未被触碰');
  });

  test('list and search walk the capability tree', () async {
    fs.files[abs('lib/a.dart')] = 'void main() {}\n// TODO: x';
    fs.files[abs('lib/b.dart')] = 'nothing here';
    fs.files[abs('node_modules/c.dart')] = 'TODO: skipped';
    await fs.ensureDirectory(abs('lib'));
    await fs.ensureDirectory(abs('node_modules'));

    final list = await ListDirectoryTool(sandbox: sandbox)
        .execute({'path': '', 'recursive': true});
    expect(list.data!['text'], contains('📄 [文件] lib/a.dart'));
    expect(list.data!['text'], contains('📁 [目录] lib'));

    final search =
        await SearchFilesTool(sandbox: sandbox).execute({'query': 'TODO'});
    expect(search.data!['text'], 'lib/a.dart:2: // TODO: x');
  });

  test('delete and move use capability operations', () async {
    fs.files[abs('a.txt')] = 'A';
    final move = await MoveFileTool(sandbox: sandbox)
        .execute({'path': 'a.txt', 'newPath': 'docs/b.txt'});
    expect(move.ok, isTrue);
    expect(fs.files.keys, [abs('docs/b.txt')]);

    final blocked = await MoveFileTool(sandbox: sandbox)
        .execute({'path': 'docs/b.txt', 'newPath': 'docs/b.txt'});
    expect(blocked.ok, isFalse);

    final delete =
        await DeleteFileTool(sandbox: sandbox).execute({'path': 'docs/b.txt'});
    expect(delete.ok, isTrue);
    final rmdir =
        await DeleteFileTool(sandbox: sandbox).execute({'path': 'docs'});
    expect(rmdir.ok, isTrue);
    expect(fs.ops, containsAllInOrder([
      'rename ${abs('a.txt')} -> ${abs('docs/b.txt')}',
      'delete ${abs('docs/b.txt')}',
      'rmdir ${abs('docs')}',
    ]));
  });

  test('missing targets are reported without touching the capability',
      () async {
    final read =
        await ReadFileTool(sandbox: sandbox).execute({'path': 'nope.txt'});
    expect(read.code, ToolCodes.notFound);
    final move = await MoveFileTool(sandbox: sandbox)
        .execute({'path': 'nope.txt', 'newPath': 'x.txt'});
    expect(move.code, ToolCodes.notFound);
    expect(fs.ops, isEmpty);
  });

  test('sandbox path policy still applies before the capability', () async {
    final escape = await ReadFileTool(sandbox: sandbox)
        .execute({'path': '../outside.txt'});
    expect(escape.code, ToolCodes.sandboxViolation);
    expect(fs.ops, isEmpty);
  });

  group('LocalWorkspaceFs', () {
    const local = LocalWorkspaceFs();

    test('reports kinds, lists without following links and renames',
        () async {
      await local.writeText(abs('deep/x.txt'), 'x');
      expect(await local.kindOf(abs('deep/x.txt')), WorkspaceEntryKind.file);
      expect(await local.kindOf(abs('deep')), WorkspaceEntryKind.directory);
      expect(await local.kindOf(abs('none')), WorkspaceEntryKind.notFound);

      if (!Platform.isWindows) {
        await Link(abs('link')).create(abs('deep'));
        final entries = await local.list(root.path).toList();
        final link = entries.firstWhere((e) => e.path == abs('link'));
        expect(link.isLink, isTrue);
        expect(link.isFile, isFalse);
      }

      await local.rename(abs('deep'), abs('moved'));
      expect(await local.readText(abs('moved/x.txt')), 'x');
      await local.deleteFile(abs('moved/x.txt'));
      await local.deleteEmptyDirectory(abs('moved'));
      expect(await local.kindOf(abs('moved')), WorkspaceEntryKind.notFound);
    });
  });
}
