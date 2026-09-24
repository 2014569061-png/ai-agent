import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/files/vault_exporter_io.dart';
import 'package:mobile_agent/infrastructure/files/vault_manifest.dart';
import 'package:mobile_agent/infrastructure/files/vault_skill_staging.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config_store.dart';

class _Store extends ProviderConfigStore {
  @override
  Future<List<ProviderConfig>> loadAll() async => [];
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

Map<String, dynamic> _pack(String name) => SkillPack(
        id: 'skill-1',
        name: name,
        description: '',
        author: null,
        version: '1',
        source: 'test',
        repo: '',
        ref: '',
        subPath: null,
        installRoot: '',
        fileListJson: '[]',
        enabled: true,
        installedAt: DateTime(2026),
        updatedAt: DateTime(2026),
        sha256: '')
    .toJson();

class _FailingSecrets extends ProviderConfigStore {
  final original = const [
    ProviderConfig(
        id: 'first',
        baseUrl: 'https://example.test',
        model: 'm',
        apiKey: 'one'),
    ProviderConfig(
        id: 'active',
        baseUrl: 'https://example.test',
        model: 'm',
        apiKey: 'two'),
  ];
  int calls = 0;
  String? active;
  List<ProviderConfig>? restored;
  @override
  Future<List<ProviderConfig>> loadAll() async => original;
  @override
  Future<ProviderConfig> load() async => original.last;
  @override
  Future<void> restoreProfiles(List<ProviderConfig> configs,
      {String? activeId}) async {
    restored = configs;
    active = activeId;
    if (++calls == 1) throw StateError('injected secure storage failure');
  }
}

class _FailOnceDatabase extends AppDatabase {
  _FailOnceDatabase() : super(NativeDatabase.memory());
  bool failNext = false;
  final requested = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> clearAllUserData() async {
    if (failNext) {
      failNext = false;
      requested.complete();
      await release.future;
      throw StateError('injected database failure');
    }
    await super.clearAllUserData();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'portable relative paths and package names reject traversal and absolute paths',
      () {
    for (final path in [
      '../file',
      '/root',
      r'C:\root',
      r'..\file',
      'a/../b',
      'a//b',
      'NUL',
      'docs/CON.txt',
      'com1.log',
      'LPT²'
    ]) {
      expect(() => validateVaultRelativePath(path), throwsFormatException);
    }
    for (final name in [
      '..',
      '../escape',
      r'..\escape',
      'a/b',
      'a:',
      'CON',
      'nul.txt'
    ]) {
      expect(() => validateVaultName(name), throwsFormatException);
    }
    expect(validateVaultRelativePath('docs/中文.md'), p.join('docs', '中文.md'));
    expect(() => validateVaultName('正常技能'), returnsNormally);
  });

  test('orphaned skill files cannot be silently omitted', () async {
    await expectLater(
        VaultSkillStaging.prepare({
          'skillFiles': {
            'missing': {'file.txt': 'YQ=='}
          }
        }),
        throwsFormatException);
  });

  test('secret compensation restores the original active profile', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = _FailingSecrets();
    await expectLater(
        restoreVault(
            db,
            {
              'version': 2,
              'providerProfiles': [
                {'id': 'new', 'model': 'm', 'apiKey': 'new-key'}
              ],
            },
            providerStore: store),
        throwsStateError);
    expect(store.calls, 2);
    expect(store.active, 'active');
    expect(store.restored!.map((p) => p.apiKey), ['one', 'two']);
  });

  test('manifest rejects missing, changed and future-version data', () async {
    final data =
        await sealVault({'version': 2, 'messages': <Map<String, dynamic>>[]});
    await validateVault(data);
    data['messages'] = [
      {'id': 'unexpected'}
    ];
    await expectLater(validateVault(data), throwsFormatException);
    await expectLater(validateVault({'version': 99}), throwsFormatException);
    await expectLater(validateVault({'version': 2, 'tasks': 'not-a-list'}),
        throwsFormatException);
    await expectLater(
        validateVault({
          'version': 2,
          'toolKeys': {'tavily': 123}
        }),
        throwsFormatException);
  });

  test(
      'failed database restore rolls back published files and original database',
      () async {
    final root = await Directory.systemTemp.createTemp('vault-safe-');
    final old = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async {
      PathProviderPlatform.instance = old;
      await db.close();
      await root.delete(recursive: true);
    });
    Map<String, dynamic> payload(String content) => {
          'version': 2,
          'skillPacks': [_pack('测试')],
          'skillFiles': {
            'skill-1': {'marker.txt': base64Encode(utf8.encode(content))}
          },
        };
    final report =
        await restoreVault(db, payload('old'), providerStore: _Store());
    expect(report.files, 1);
    final installed = (await db.allSkillPacks()).single;
    final file = File(p.join(installed.installRoot, 'marker.txt'));
    expect(await file.readAsString(), 'old');
    final broken = payload('new')
      ..['messages'] = [
        {'bad': true}
      ];
    await expectLater(
        restoreVault(db, broken, providerStore: _Store()), throwsA(anything));
    expect(await file.readAsString(), 'old');
    expect(await db.allSkillPacks(), hasLength(1));
    expect(
        root
            .listSync()
            .where((e) => p.basename(e.path).startsWith('.vault-stage-')),
        isEmpty);
  });

  test('a failed restore cannot roll back a concurrent successful restore',
      () async {
    final root = await Directory.systemTemp.createTemp('vault-concurrent-');
    final old = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
    final db = _FailOnceDatabase();
    addTearDown(() async {
      PathProviderPlatform.instance = old;
      await db.close();
      await root.delete(recursive: true);
    });
    Map<String, dynamic> payload(String content) => {
          'version': 2,
          'skillPacks': [_pack('测试')],
          'skillFiles': {
            'skill-1': {'marker.txt': base64Encode(utf8.encode(content))}
          },
        };
    await restoreVault(db, payload('original'), providerStore: _Store());
    final installed = (await db.allSkillPacks()).single;
    final file = File(p.join(installed.installRoot, 'marker.txt'));
    db.failNext = true;
    final failed = expectLater(
        restoreVault(db, payload('failed'), providerStore: _Store()),
        throwsStateError);
    await db.requested.future;
    final successful =
        restoreVault(db, payload('success'), providerStore: _Store());
    await pumpEventQueue();
    expect(await file.readAsString(), 'failed');
    db.release.complete();
    await failed;
    expect((await successful).files, 1);
    expect(await file.readAsString(), 'success');
  });

  test('export pages all rows beyond the old 2000 item cap', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.transaction(() async {
      for (var i = 0; i < 2005; i++) {
        await db.saveAuditLog(AuditLog(
            id: 'audit-$i',
            type: 'test',
            conversationId: null,
            detail: 'entry',
            decision: null,
            risk: null,
            createdAt: DateTime(2026)));
      }
    });
    final data = await buildVaultJson(db, providerStore: _Store());
    expect(data['auditLogs'] as List, hasLength(2005));
    expect((data['manifest'] as Map)['complete'], isTrue);
    await validateVault(data);
  });
}
