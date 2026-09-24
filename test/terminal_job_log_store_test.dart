import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/terminal/terminal_job_log_store.dart';

void main() {
  test('retained command output is bounded and visibly marked', () {
    final output = TerminalJobLogStore.boundedOutput('${'x' * 600000}tail');
    expect(output.length, lessThan(263000));
    expect(output, startsWith('[输出已截断'));
    expect(output, endsWith('tail'));
    expect(TerminalJobLogStore.boundedOutput('small'), 'small');
  });

  test('log retention respects count, age, active handles and unrelated files',
      () async {
    final root = await Directory.systemTemp.createTemp('nexus-job-log-store-');
    addTearDown(() => root.delete(recursive: true));
    final now = DateTime.now();
    for (var i = 0; i < 4; i++) {
      final file = File('${root.path}/job-$i.log');
      await file.writeAsString('fixture');
      await file.setLastModified(now.subtract(Duration(minutes: i)));
    }
    final old = File('${root.path}/job-old.log');
    await old.writeAsString('fixture');
    await old.setLastModified(now.subtract(const Duration(days: 10)));
    final active = File('${root.path}/job-active.log');
    await active.writeAsString('fixture');
    await active.setLastModified(now.subtract(const Duration(days: 10)));
    await File('${root.path}/keep.txt').writeAsString('user-owned');
    final store = TerminalJobLogStore(root, maxFiles: 2);
    await store.prune(activePaths: () => [active.path]);
    final names = (await root.list().toList())
        .map((e) => e.uri.pathSegments.last)
        .toSet();
    expect(names, {'job-0.log', 'job-1.log', 'job-active.log', 'keep.txt'});
  });

  test(
      'both started and completed log payloads use the existing privacy policy',
      () {
    expect(TerminalJobLogStore.persistedPayload('started', 'private-command'),
        isNot(contains('private-command')));
    expect(TerminalJobLogStore.persistedPayload('completed', 'private-output'),
        isNot(contains('private-output')));
  });
}
