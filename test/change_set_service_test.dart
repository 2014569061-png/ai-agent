import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mobile_agent/application/change_review.dart';
import 'package:mobile_agent/application/change_set_service.dart';

const _reviews = ChangeReviewService();
const _service = ChangeSetService();

void main() {
  late Directory root;
  late Directory workspace;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nexus-cs-test');
    workspace = Directory(p.join(root.path, 'ws'))..createSync();
    PathProviderPlatform.instance =
        _TempPathProvider(p.join(root.path, 'docs'));
  });
  tearDown(() => root.delete(recursive: true));

  File file(String name) => File(p.join(workspace.path, name));

  Future<ChangeSet> capture(List<FileChangeSummary> changes,
          {String taskId = 't1'}) =>
      _service.capture(
        projectId: 'p1',
        taskId: taskId,
        workspacePath: workspace.path,
        review:
            ChangeReview(files: changes, mark: ChangeVerificationMark.passed),
      );

  FileChangeSummary edit(String path, String before, String after,
          {String operation = 'edit'}) =>
      _reviews.summarizeEdit(
          path: path, before: before, after: after, operation: operation);

  test('edit is restored to the pre-task content', () async {
    const before = 'a\nb\nc\n';
    file('x.txt').writeAsStringSync('a\nB\nc\n');
    final set = await capture([edit('x.txt', before, 'a\nB\nc\n')]);

    final f = set.files.single;
    expect(f.reversible, isTrue);
    expect(f.beforeHash, sha256.convert(utf8.encode(before)).toString());

    final conflicts =
        await _service.rollback(workspacePath: workspace.path, changeSet: set);
    expect(conflicts, isEmpty);
    expect(file('x.txt').readAsStringSync(), before);
  });

  test('nested and underscore paths keep independent snapshots after reload',
      () async {
    file('a/b.txt').parent.createSync(recursive: true);
    file('a/b.txt').writeAsStringSync('nested after\n');
    file('a_b.txt').writeAsStringSync('flat after\n');
    final set = await capture([
      edit('a/b.txt', 'nested before\n', 'nested after\n'),
      edit('a_b.txt', 'flat before\n', 'flat after\n'),
    ]);
    expect(set.files.map((f) => f.beforeRef).toSet(), hasLength(2));
    expect(set.files.map((f) => f.afterRef).toSet(), hasLength(2));
    for (final entry in set.files) {
      expect(sha256.convert(File(entry.afterRef!).readAsBytesSync()).toString(),
          entry.afterHash);
    }
    final loaded = await _service.load(taskId: 't1');
    final conflicts = await _service.rollback(
        workspacePath: workspace.path, changeSet: loaded!);
    expect(conflicts, isEmpty);
    expect(file('a/b.txt').readAsStringSync(), 'nested before\n');
    expect(file('a_b.txt').readAsStringSync(), 'flat before\n');
  });

  test('corrupted backup is rejected before overwriting the workspace',
      () async {
    file('x.txt').writeAsStringSync('after\n');
    final set = await capture([edit('x.txt', 'before\n', 'after\n')]);
    File(set.files.single.beforeRef!).writeAsStringSync('another file\n');
    final conflicts =
        await _service.rollback(workspacePath: workspace.path, changeSet: set);
    expect(conflicts.single.reason, contains('备份校验失败'));
    expect(file('x.txt').readAsStringSync(), 'after\n');
  });

  test('legacy aliased snapshots cannot restore another files content',
      () async {
    file('a/b.txt').parent.createSync(recursive: true);
    file('a/b.txt').writeAsStringSync('nested after\n');
    file('a_b.txt').writeAsStringSync('flat after\n');
    final shared = File(p.join(root.path, 'legacy.before'))
      ..writeAsStringSync('flat before\n');
    final set = ChangeSet(
        id: 'legacy',
        taskId: 't1',
        projectId: 'p1',
        createdAt: DateTime.now(),
        files: [
          for (final path in ['a/b.txt', 'a_b.txt'])
            ChangeSetFile(
                relativePath: path,
                operation: 'edit',
                beforeHash: sha256
                    .convert(utf8.encode(path == 'a/b.txt'
                        ? 'nested before\n'
                        : 'flat before\n'))
                    .toString(),
                afterHash:
                    sha256.convert(file(path).readAsBytesSync()).toString(),
                beforeRef: shared.path),
        ]);
    final conflicts =
        await _service.rollback(workspacePath: workspace.path, changeSet: set);
    expect(conflicts.single.path, 'a/b.txt');
    expect(file('a/b.txt').readAsStringSync(), 'nested after\n');
    expect(file('a_b.txt').readAsStringSync(), 'flat before\n');
  });

  test('overwriting write restores the original instead of deleting it',
      () async {
    file('keep.txt').writeAsStringSync('new\n');
    final set = await capture(
        [edit('keep.txt', 'original\n', 'new\n', operation: 'write')]);

    final conflicts =
        await _service.rollback(workspacePath: workspace.path, changeSet: set);
    expect(conflicts, isEmpty);
    expect(file('keep.txt').existsSync(), isTrue);
    expect(file('keep.txt').readAsStringSync(), 'original\n');
  });

  test('created file is deleted on rollback', () async {
    file('new.txt').writeAsStringSync('hello\n');
    final set =
        await capture([edit('new.txt', '', 'hello\n', operation: 'create')]);

    expect(set.files.single.operation, 'create');
    final conflicts =
        await _service.rollback(workspacePath: workspace.path, changeSet: set);
    expect(conflicts, isEmpty);
    expect(file('new.txt').existsSync(), isFalse);
  });

  test('several edits of one file unwind newest first', () async {
    const v0 = 'one\ntwo\nthree\n';
    const v1 = 'one\nTWO\nthree\n';
    const v2 = 'one\nTWO\nthree\nfour\n';
    file('m.txt').writeAsStringSync(v2);
    final set = await capture([edit('m.txt', v0, v1), edit('m.txt', v1, v2)]);

    expect(set.files, hasLength(1));
    await _service.rollback(workspacePath: workspace.path, changeSet: set);
    expect(file('m.txt').readAsStringSync(), v0);
  });

  test('human edit after capture is a conflict and is not overwritten',
      () async {
    file('x.txt').writeAsStringSync('after\n');
    final set = await capture([edit('x.txt', 'before\n', 'after\n')]);
    file('x.txt').writeAsStringSync('human\n');

    final conflicts =
        await _service.rollback(workspacePath: workspace.path, changeSet: set);
    expect(conflicts.single.reason, contains('人工后续修改'));
    expect(file('x.txt').readAsStringSync(), 'human\n');
  });

  test('human edit before capture makes the file irreversible', () async {
    file('x.txt').writeAsStringSync('human\n');
    final set = await capture([edit('x.txt', 'before\n', 'after\n')]);

    expect(set.files.single.reversible, isFalse);
    expect(set.files.single.note, contains('人工修改'));
  });

  test('missing diff is reported instead of a silent no-op success', () async {
    file('x.txt').writeAsStringSync('after\n');
    final set = await capture([
      const FileChangeSummary(
          path: 'x.txt', operation: 'edit', linesAdded: 1, linesRemoved: 1),
    ]);

    expect(set.files.single.reversible, isFalse);
    final conflicts =
        await _service.rollback(workspacePath: workspace.path, changeSet: set);
    expect(conflicts.single.reason, contains('diff'));
    expect(file('x.txt').readAsStringSync(), 'after\n');
  });

  test('truncated diff is irreversible', () async {
    file('x.txt').writeAsStringSync('after\n');
    final base = edit('x.txt', 'before\n', 'after\n');
    final set = await capture([
      FileChangeSummary(
        path: base.path,
        operation: base.operation,
        linesAdded: base.linesAdded,
        linesRemoved: base.linesRemoved,
        diff: base.diff,
        truncated: true,
      ),
    ]);
    expect(set.files.single.reversible, isFalse);
  });

  test('task IDs cannot escape the change-set storage directory', () async {
    await expectLater(_service.load(taskId: '../escape'), throwsArgumentError);
    await expectLater(capture([], taskId: '../escape'), throwsArgumentError);
    expect(
        Directory(p.join(root.path, 'docs', 'escape')).existsSync(), isFalse);
  });

  test('redacted secrets never produce a fake baseline', () async {
    const before = 'token=old-value\n';
    const after = 'token=new-value\n';
    file('env.txt').writeAsStringSync(after);
    final set = await capture([edit('env.txt', before, after)]);
    expect(set.files.single.reversible, isFalse);
  });

  test('delete and move are not auto-reversible', () async {
    final set = await capture([
      const FileChangeSummary(
          path: 'gone.txt',
          operation: 'delete',
          linesAdded: 0,
          linesRemoved: 3),
    ]);
    expect(set.files.single.reversible, isFalse);
  });

  test('load returns the persisted set and ignores v1 manifests', () async {
    file('x.txt').writeAsStringSync('after\n');
    final set = await capture([edit('x.txt', 'before\n', 'after\n')]);
    final loaded = await _service.load(taskId: 't1');
    expect(loaded?.id, set.id);
    expect(loaded?.files.single.beforeRef, set.files.single.beforeRef);

    final legacy =
        File(p.join(root.path, 'docs', 'changesets', 't2', 'changeset.json'))
          ..createSync(recursive: true)
          ..writeAsStringSync(jsonEncode({
            'id': 'old',
            'taskId': 't2',
            'projectId': 'p1',
            'files': [],
            'createdAt': DateTime(2026).toIso8601String(),
          }));
    expect(legacy.existsSync(), isTrue);
    expect(await _service.load(taskId: 't2'), isNull);
    expect(await _service.load(taskId: 'missing'), isNull);
  });
}

class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}
