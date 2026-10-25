import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/files/patch_journal.dart';
import 'package:mobile_agent/infrastructure/tools/workspace_tools.dart';

void main() {
  late Directory root;
  late WorkspaceSandbox sandbox;
  const id = '0123456789abcdef0123456789abcdef';
  String backup(String path) => '$path.nexus-patch-$id.bak';
  String staged(String path) => '$path.nexus-patch-$id.tmp';
  Future<void> write(String path, String value) async {
    final file = File('${root.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString(value, flush: true);
  }

  Future<String> read(String path) => File('${root.path}/$path').readAsString();
  setUp(() async {
    root = await Directory.systemTemp.createTemp('patch-recovery-');
    sandbox = WorkspaceSandbox(root.path, requireReadBeforeWrite: true);
    await write('a', 'old');
    await write('b', 'old');
  });
  tearDown(() => root.delete(recursive: true));
  Future<void> journal({bool committed = false}) async {
    await write(
        '.nexus/patch-journal/$id.json',
        jsonEncode({
          'version': 1,
          'id': id,
          'files': [
            for (final name in ['a', 'b'])
              {
                'path': name,
                'before': PatchJournal.hash('old'),
                'after': PatchJournal.hash('new')
              }
          ]
        }));
    if (committed) await write('.nexus/patch-journal/$id.commit', 'committed');
  }

  for (final phase in [
    'staged',
    'backed_up',
    'one_installed',
    'all_installed'
  ]) {
    test(
        'restart recovers $phase without commit marker before accepting another edit',
        () async {
      await journal();
      await write(staged('a'), 'new');
      await write(staged('b'), 'new');
      if (phase != 'staged') {
        await File('${root.path}/a').rename('${root.path}/${backup('a')}');
      }
      if (phase == 'one_installed' || phase == 'all_installed') {
        await File('${root.path}/${staged('a')}').rename('${root.path}/a');
      }
      if (phase == 'all_installed') {
        await File('${root.path}/b').rename('${root.path}/${backup('b')}');
        await File('${root.path}/${staged('b')}').rename('${root.path}/b');
      }
      final result = await WriteFileTool(sandbox: sandbox)
          .execute({'path': 'unrelated', 'content': 'not yet'});
      expect(result.code, 'PATCH_RECOVERED');
      expect(await read('a'), 'old');
      expect(await read('b'), 'old');
      expect(await File('${root.path}/unrelated').exists(), isFalse);
      expect(await sandbox.prepareForWrite(), isNull);
      expect(
          (await WriteFileTool(sandbox: sandbox)
                  .execute({'path': 'a', 'content': 'edit'}))
              .code,
          'READ_REQUIRED');
    });
  }
  test(
      'durable commit keeps new versions even when backup cleanup was interrupted',
      () async {
    await journal(committed: true);
    await write('a', 'new');
    await write('b', 'new');
    await write(backup('b'), 'old'); // first backup already cleaned
    expect((await sandbox.prepareForWrite())!.code, 'PATCH_RECOVERED');
    expect(await read('a'), 'new');
    expect(await read('b'), 'new');
    expect(await File('${root.path}/${backup('b')}').exists(), isFalse);
    expect(await sandbox.prepareForWrite(), isNull);
  });
  test('damaged commit marker blocks recovery without rolling back files',
      () async {
    await journal();
    for (final name in ['a', 'b']) {
      await write(name, 'new');
      await write(backup(name), 'old');
    }
    await write('.nexus/patch-journal/$id.commit', 'committed-partial');
    expect((await sandbox.prepareForWrite())!.code, 'PATCH_RECOVERY_REQUIRED');
    for (final name in ['a', 'b']) {
      expect(await read(name), 'new');
      expect(await read(backup(name)), 'old');
    }
    expect(await sandbox.patchJournal.hasPending(), isTrue);
  });
  test('linked backup blocks the complete journal before restoring other files',
      () async {
    await journal();
    await write('a', 'new');
    await write('b', 'new');
    await write('saved-a', 'old');
    await write(backup('b'), 'old');
    final link = Link('${root.path}/${backup('a')}');
    try {
      await link.create('${root.path}/saved-a');
    } on FileSystemException {
      markTestSkipped('当前主机未允许创建符号链接');
      return;
    }
    expect((await sandbox.prepareForWrite())!.code, 'PATCH_RECOVERY_REQUIRED');
    expect(await read('a'), 'new');
    expect(await read('b'), 'new');
    expect(await read('saved-a'), 'old');
    expect(await read(backup('b')), 'old');
    expect(await link.exists(), isTrue);
  });
  test('external edit and damaged backup are retained and block further writes',
      () async {
    await journal();
    await write('a', 'external');
    await write('b', 'new');
    await write(backup('a'), 'old');
    await write(backup('b'), 'damaged');
    final result = await EditFileTool(sandbox: sandbox)
        .execute({'path': 'a', 'oldText': 'external', 'newText': 'bad'});
    expect(result.code, 'PATCH_RECOVERY_REQUIRED');
    expect(await read('a'), 'external');
    expect(await read('b'), 'new');
    expect(await read(backup('a')), 'old');
    expect(await read(backup('b')), 'damaged');
  });
  test('malformed and escaping journal blocks edits without touching targets',
      () async {
    await write(
        '.nexus/patch-journal/$id.json',
        jsonEncode({
          'version': 1,
          'id': id,
          'files': [
            {
              'path': '../escape',
              'before': PatchJournal.hash('old'),
              'after': PatchJournal.hash('new')
            }
          ]
        }));
    expect((await sandbox.prepareForWrite())!.code, 'PATCH_RECOVERY_REQUIRED');
    expect(await read('a'), 'old');
    await write('.nexus/patch-journal/$id.json', '{partial');
    expect((await sandbox.prepareForWrite())!.code, 'PATCH_RECOVERY_REQUIRED');
  });
  test('an active transaction is not mistaken for a crashed transaction',
      () async {
    final active = sandbox.patchJournal;
    await active.start(id, [
      {
        'path': 'a',
        'before': PatchJournal.hash('old'),
        'after': PatchJournal.hash('new')
      }
    ]);
    try {
      expect((await sandbox.prepareForWrite())!.code, 'PATCH_BUSY');
    } finally {
      await active.finish(clean: true);
    }
    expect(await sandbox.prepareForWrite(), isNull);
  });
}
