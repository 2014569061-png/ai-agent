import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:mobile_agent/application/change_set_retention.dart';

void main() {
  late Directory root;
  final now = DateTime(2030, 1, 31, 12);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nexus-retention-test');
  });
  tearDown(() => root.delete(recursive: true));

  /// Creates a task directory whose manifest was last written [age] before
  /// [now]; [baseline] writes the baseline manifest instead of the change set.
  void task(String id, Duration age, {bool baseline = false}) {
    final file = File(p.join(root.path, id,
        baseline ? 'baseline/manifest.json' : 'changeset.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('{}');
    file.setLastModifiedSync(now.subtract(age));
  }

  bool exists(String id) => Directory(p.join(root.path, id)).existsSync();

  Future<int> prune({int keep = 100, Set<String> protect = const {}}) =>
      pruneChangeSets(
        root: root,
        now: now,
        keep: keep,
        protect: protect,
        maxAge: const Duration(days: 30),
      );

  test('removes tasks inactive for longer than maxAge', () async {
    task('old', const Duration(days: 40));
    task('fresh', const Duration(days: 2));
    expect(await prune(), 1);
    expect(exists('old'), isFalse);
    expect(exists('fresh'), isTrue);
  });

  test('a recent baseline write keeps an old change set alive', () async {
    task('t', const Duration(days: 40));
    task('t', const Duration(days: 1), baseline: true);
    expect(await prune(), 0);
    expect(exists('t'), isTrue);
  });

  test('keeps only the most recently active tasks', () async {
    for (var i = 0; i < 5; i++) {
      task('t$i', Duration(days: i));
    }
    expect(await prune(keep: 2), 3);
    expect([for (var i = 0; i < 5; i++) exists('t$i')],
        [true, true, false, false, false]);
  });

  test('protected tasks survive and do not use up the quota', () async {
    task('running', const Duration(days: 90));
    task('a', const Duration(days: 1));
    task('b', const Duration(days: 2));
    expect(await prune(keep: 1, protect: {'running'}), 1);
    expect(exists('running'), isTrue);
    expect(exists('a'), isTrue);
    expect(exists('b'), isFalse);
  });

  test('missing root is a no-op', () async {
    final missing = Directory(p.join(root.path, 'nope'));
    expect(await pruneChangeSets(root: missing, now: now), 0);
  });

  test('stray files at the root are left alone', () async {
    File(p.join(root.path, 'note.txt')).writeAsStringSync('x');
    task('old', const Duration(days: 40));
    await prune();
    expect(File(p.join(root.path, 'note.txt')).existsSync(), isTrue);
  });
}
