import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/workspace_snapshot.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('snapshot-sources-');
  });
  tearDown(() => root.delete(recursive: true));

  Future<void> write(String path, String text) async {
    final file = File(p.join(root.path, path));
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }

  test('non-Git snapshots exclude dependency caches and preserve source files',
      () async {
    await write('.dart_tool/cache/a.txt', 'generated');
    await write('node_modules/package/index.js', 'generated');
    await write('.nexus/checkpoints/old.txt', 'runtime state');
    await write('src/main.dart', 'source');
    final snapshot =
        await const WorkspaceSnapshotService(maxFiles: 1).capture(root.path);
    expect(snapshot.files.keys, ['src/main.dart']);
  });

  test('Git snapshots honor nested ignores, negation and tracked files',
      () async {
    final initialized = await Process.run('git', ['init', '--quiet'],
        workingDirectory: root.path);
    expect(initialized.exitCode, 0);
    await write('.gitignore', '/local/\n*.generated\n!keep.generated\n');
    await write('local/sdk/config.txt', 'SDK configuration');
    await write('ignored.generated', 'not project source');
    await write('keep.generated', 'explicitly included');
    await write('tracked.generated', 'tracked source');
    await write('src/.gitignore', 'secret.txt\n');
    await write('src/secret.txt', 'private');
    await write('src/main.dart', 'untracked source');
    final added = await Process.run('git', ['add', '-f', 'tracked.generated'],
        workingDirectory: root.path);
    expect(added.exitCode, 0);

    final snapshot = await const WorkspaceSnapshotService().capture(root.path);
    expect(
        snapshot.files.keys,
        containsAll([
          'keep.generated',
          'tracked.generated',
          'src/main.dart',
        ]));
    expect(
        snapshot.files.keys,
        isNot(contains(anyOf(
            'ignored.generated', 'local/sdk/config.txt', 'src/secret.txt'))));
  });

  test('snapshots detect actual source changes without cache noise', () async {
    await write('src/main.dart', 'before');
    const service = WorkspaceSnapshotService();
    final before = await service.capture(root.path);
    await write('src/main.dart', 'after');
    await write('build/output.txt', 'build artifact');
    final review = await service.reviewFromSnapshot(
        workspacePath: root.path, snapshot: before);
    expect(review.files, hasLength(1));
    expect(review.files.single.path, 'src/main.dart');
    expect(review.files.single.operation, 'edit');
  });
}
