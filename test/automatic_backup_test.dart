import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/application/scheduled_task_runner.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';

class _InMemorySecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> _store = {};
  @override
  Future<void> write(
          {required String key,
          required String value,
          required Map<String, String> options}) async =>
      _store[key] = value;
  @override
  Future<String?> read(
          {required String key, required Map<String, String> options}) async =>
      _store[key];
  @override
  Future<void> delete(
          {required String key, required Map<String, String> options}) async =>
      _store.remove(key);
  @override
  Future<bool> containsKey(
          {required String key, required Map<String, String> options}) async =>
      _store.containsKey(key);
  @override
  Future<Map<String, String>> readAll(
          {required Map<String, String> options}) async =>
      Map.of(_store);
  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      _store.clear();
}

class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('手动立即备份写出真实加密快照后才更新时间戳', () async {
    FlutterSecureStoragePlatform.instance = _InMemorySecureStorage();
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('nexus-manual-backup-');
    addTearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });
    PathProviderPlatform.instance = _TempPathProvider(root.path);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings.backup.last_time'), isNull);

    final path = await createAutomaticBackupNow(db);

    expect(path, isNotNull);
    final file = File(path!);
    expect(path.endsWith('.nexusauto'), isTrue);
    expect(file.existsSync(), isTrue, reason: '「立即备份」必须真的落盘');
    expect(file.lengthSync(), greaterThan(0), reason: '快照必须是加密后的非空内容');

    // 时间戳只在文件写盘成功之后更新。历史缺陷是只更新时间戳不写文件，
    // 而后台又用同一时间戳判断是否满 24 小时，会直接把真实备份跳过。
    final stamp = prefs.getString('settings.backup.last_time');
    expect(stamp, isNotNull);
    expect(DateTime.tryParse(stamp!), isNotNull);
  });

  test('备份保留上限只保留最近的若干份快照', () async {
    final dir = await Directory.systemTemp.createTemp('nexus-backup-prune-');
    addTearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    for (var i = 0; i < automaticBackupRetention + 3; i++) {
      final file = File('${dir.path}/nexus-auto-$i.nexusauto');
      await file.writeAsString('snapshot-$i');
      // 让 lastModified 有确定的先后顺序。
      await file.setLastModified(DateTime(2026, 1, 1).add(Duration(days: i)));
    }
    await File('${dir.path}/not-a-backup.txt').writeAsString('keep me');

    await pruneAutomaticBackups(dir);

    final remaining = dir
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .toList()
      ..sort();
    expect(remaining.where((name) => name.endsWith('.nexusauto')).length,
        automaticBackupRetention);
    // 非备份文件不参与清理。
    expect(remaining, contains('not-a-backup.txt'));
    // 保留的是最新的那些（编号最大的）。
    expect(remaining, contains('nexus-auto-10.nexusauto'));
    expect(remaining, isNot(contains('nexus-auto-0.nexusauto')));
  });
}
