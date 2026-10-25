import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mobile_agent/application/change_review.dart';
import 'package:mobile_agent/application/change_set_service.dart';
import 'package:mobile_agent/application/file_baseline_store.dart';
import 'package:mobile_agent/application/tool_pipeline/file_baseline_interceptor.dart';
import 'package:mobile_agent/application/tool_pipeline/tool_invocation.dart';
import 'package:mobile_agent/application/tool_pipeline/tool_run_context.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_result.dart';

const _reviews = ChangeReviewService();
const _service = ChangeSetService();

void main() {
  late Directory root;
  late Directory workspace;
  late FileBaselineStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nexus-baseline-test');
    workspace = Directory(p.join(root.path, 'ws'))..createSync();
    PathProviderPlatform.instance =
        _TempPathProvider(p.join(root.path, 'docs'));
    store = FileBaselineStore(taskId: 't1', workspacePath: workspace.path);
  });
  tearDown(() => root.delete(recursive: true));

  File file(String name) => File(p.join(workspace.path, name));

  Future<ChangeSet> capture(List<FileChangeSummary> changes) =>
      _service.capture(
        projectId: 'p1',
        taskId: 't1',
        workspacePath: workspace.path,
        review:
            ChangeReview(files: changes, mark: ChangeVerificationMark.passed),
      );

  Future<List<RollbackConflict>> rollback(ChangeSet set) =>
      _service.rollback(workspacePath: workspace.path, changeSet: set);

  group('FileBaselineStore', () {
    test('rejects path-like task IDs before creating snapshot directories',
        () async {
      for (final taskId in ['../escape', r'..\escape', 'C:escape', '']) {
        await expectLater(
            FileBaselineStore.directoryFor(taskId), throwsArgumentError);
      }

      final unsafe =
          FileBaselineStore(taskId: '../escape', workspacePath: workspace.path);
      await expectLater(unsafe.preserve(['a.txt']), throwsArgumentError);
      expect(
          Directory(p.join(root.path, 'docs', 'escape')).existsSync(), isFalse);
    });

    test('keeps the first version of a file', () async {
      file('a.txt').writeAsStringSync('v1');
      await store.preserve(['a.txt']);
      file('a.txt').writeAsStringSync('v2');
      await store.preserve(['./a.txt']);

      final entry = (await FileBaselineStore.read('t1'))['a.txt']!;
      expect(entry.existed, isTrue);
      expect(entry.captured, isTrue);
      expect(File(entry.ref!).readAsStringSync(), 'v1');
    });

    test('records missing files, skips directories and oversized files',
        () async {
      Directory(p.join(workspace.path, 'dir')).createSync();
      file('big.bin').writeAsBytesSync(List.filled(32, 1));
      final small = FileBaselineStore(
          taskId: 't1', workspacePath: workspace.path, maxBytes: 16);
      await small.preserve(['missing.txt', 'dir', 'big.bin']);

      final entries = await FileBaselineStore.read('t1');
      expect(entries['missing.txt']!.existed, isFalse);
      expect(entries['missing.txt']!.captured, isTrue);
      expect(entries['dir']!.captured, isFalse);
      expect(entries['big.bin']!.captured, isFalse);
    });

    test('concurrent preserves do not lose entries', () async {
      file('a.txt').writeAsStringSync('a');
      file('b.txt').writeAsStringSync('b');
      await Future.wait([
        store.preserve(['a.txt']),
        store.preserve(['b.txt'])
      ]);
      expect((await FileBaselineStore.read('t1')).keys,
          containsAll(['a.txt', 'b.txt']));
    });
  });

  group('FileBaselineInterceptor', () {
    ToolInvocation call(String name, Map<String, dynamic> arguments) =>
        ToolInvocation(
          call: ToolCall(id: 'c1', name: name, arguments: arguments),
          registration: null,
          context: ToolRunContext.detached(),
        );

    test('saves the original before the tool runs', () async {
      file('a.txt').writeAsStringSync('original');
      final result = await FileBaselineInterceptor(store).intercept(
        call('edit_file', {'path': 'a.txt'}),
        (_) async {
          file('a.txt').writeAsStringSync('changed');
          return ToolResult.text('ok');
        },
      );
      expect(result, isA<ToolResult>());
      final entry = (await FileBaselineStore.read('t1'))['a.txt']!;
      expect(File(entry.ref!).readAsStringSync(), 'original');
    });

    test('move preserves source and destination', () async {
      file('a.txt').writeAsStringSync('a');
      await FileBaselineInterceptor(store).intercept(
        call('move_file', {'path': 'a.txt', 'newPath': 'b.txt'}),
        (_) async => ToolResult.text('ok'),
      );
      final entries = await FileBaselineStore.read('t1');
      expect(entries['a.txt']!.existed, isTrue);
      expect(entries['b.txt']!.existed, isFalse);
    });

    test('batch patch preserves every original before execution', () async {
      file('a.txt').writeAsStringSync('a-original');
      file('b.txt').writeAsStringSync('b-original');
      await FileBaselineInterceptor(store).intercept(
        call('apply_patch', {
          'files': [
            {'path': 'a.txt', 'patch': 'a'},
            {'path': 'b.txt', 'patch': 'b'},
          ]
        }),
        (_) async {
          final entries = await FileBaselineStore.read('t1');
          expect(File(entries['a.txt']!.ref!).readAsStringSync(), 'a-original');
          expect(File(entries['b.txt']!.ref!).readAsStringSync(), 'b-original');
          return ToolResult.text('ok');
        },
      );
    });

    test('ignores non-mutating tools', () async {
      file('a.txt').writeAsStringSync('a');
      await FileBaselineInterceptor(store).intercept(
        call('read_file', {'path': 'a.txt'}),
        (_) async => ToolResult.text('ok'),
      );
      expect(await FileBaselineStore.read('t1'), isEmpty);
    });

    test('a failing store never blocks the tool', () async {
      Object? reported;
      var executed = false;
      await FileBaselineInterceptor(
        _ThrowingStore(workspace.path),
        onError: (error, _) => reported = error,
      ).intercept(
        call('write_file', {'path': 'a.txt'}),
        (_) async {
          executed = true;
          return ToolResult.text('ok');
        },
      );
      expect(executed, isTrue);
      expect(reported, isA<StateError>());
    });

    test('fileBaselinePipeline requires a task and a workspace', () {
      expect(fileBaselinePipeline(taskId: null, workspacePath: 'w'), isNull);
      expect(fileBaselinePipeline(taskId: 't', workspacePath: ' '), isNull);
      final pipeline = fileBaselinePipeline(taskId: 't', workspacePath: 'w')!;
      expect(pipeline.interceptors.last.id, 'file-baseline');
    });
  });

  group('ChangeSetService with stored baseline', () {
    test('restores a deleted file', () async {
      file('a.txt').writeAsStringSync('keep me');
      await store.preserve(['a.txt']);
      file('a.txt').deleteSync();

      final set = await capture([
        const FileChangeSummary(
            path: 'a.txt', operation: 'delete', linesAdded: 0, linesRemoved: 1),
      ]);
      expect(set.files.single.reversible, isTrue);
      expect(await rollback(set), isEmpty);
      expect(file('a.txt').readAsStringSync(), 'keep me');
    });

    test('undoes a move: source restored, destination removed', () async {
      file('a.txt').writeAsStringSync('content');
      await store.preserve(['a.txt', 'sub/b.txt']);
      Directory(p.join(workspace.path, 'sub')).createSync();
      file('a.txt').renameSync(file('sub/b.txt').path);

      final set = await capture([
        const FileChangeSummary(
            path: 'sub/b.txt',
            operation: 'move',
            linesAdded: 0,
            linesRemoved: 0),
      ]);
      expect(set.files.map((f) => f.relativePath),
          containsAll(['a.txt', 'sub/b.txt']));
      expect(await rollback(set), isEmpty);
      expect(file('a.txt').readAsStringSync(), 'content');
      expect(file('sub/b.txt').existsSync(), isFalse);
    });

    test('restores edits whose diff was redacted', () async {
      const before = 'token=old-value\n';
      const after = 'token=new-value\n';
      file('env.txt').writeAsStringSync(before);
      await store.preserve(['env.txt']);
      file('env.txt').writeAsStringSync(after);

      final set = await capture([
        _reviews.summarizeEdit(path: 'env.txt', before: before, after: after),
      ]);
      expect(set.files.single.reversible, isTrue);
      expect(await rollback(set), isEmpty);
      expect(file('env.txt').readAsStringSync(), before);
    });

    test('restores binary content', () async {
      file('img.bin').writeAsBytesSync([0, 255, 1, 254]);
      await store.preserve(['img.bin']);
      file('img.bin').writeAsBytesSync([9, 9]);

      final set = await capture([
        const FileChangeSummary(
            path: 'img.bin',
            operation: 'binary',
            linesAdded: 0,
            linesRemoved: 0),
      ]);
      expect(await rollback(set), isEmpty);
      expect(file('img.bin').readAsBytesSync(), [0, 255, 1, 254]);
    });

    test('existing empty file labelled create is restored, not deleted',
        () async {
      file('empty.txt').writeAsStringSync('');
      await store.preserve(['empty.txt']);
      file('empty.txt').writeAsStringSync('filled\n');

      final set = await capture([
        _reviews.summarizeEdit(
            path: 'empty.txt',
            before: '',
            after: 'filled\n',
            operation: 'create'),
      ]);
      expect(set.files.single.operation, 'write');
      expect(await rollback(set), isEmpty);
      expect(file('empty.txt').existsSync(), isTrue);
      expect(file('empty.txt').readAsStringSync(), isEmpty);
    });

    test('files touched by failed calls are omitted', () async {
      file('same.txt').writeAsStringSync('same');
      await store.preserve(['same.txt', 'never.txt']);
      final set = await capture(const []);
      expect(set.files, isEmpty);
    });

    test('loadOrCapture reuses the set until the task changes more files',
        () async {
      file('a.txt').writeAsStringSync('a0');
      await store.preserve(['a.txt']);
      file('a.txt').writeAsStringSync('a1');
      final review = ChangeReview(
        files: [
          _reviews.summarizeEdit(path: 'a.txt', before: 'a0', after: 'a1')
        ],
        mark: ChangeVerificationMark.passed,
      );
      Future<ChangeSet> open(ChangeReview r) => _service.loadOrCapture(
          projectId: 'p1',
          taskId: 't1',
          workspacePath: workspace.path,
          review: r);

      final first = await open(review);
      file('a.txt').writeAsStringSync('human');
      final again = await open(review);
      expect(again.id, first.id);
      expect(again.files.single.afterHash, first.files.single.afterHash);

      final grown = ChangeReview(
        files: [
          ...review.files,
          _reviews.summarizeEdit(
              path: 'b.txt', before: '', after: 'b', operation: 'create'),
        ],
        mark: ChangeVerificationMark.passed,
      );
      expect((await open(grown)).id, isNot(first.id));
    });
  });
}

class _ThrowingStore extends FileBaselineStore {
  _ThrowingStore(String workspacePath)
      : super(taskId: 'x', workspacePath: workspacePath);

  @override
  Future<void> preserve(Iterable<String> paths) async =>
      throw StateError('disk full');
}

class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}
