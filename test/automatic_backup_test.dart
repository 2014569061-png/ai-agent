import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/application/scheduled_task_runner.dart';
import 'package:mobile_agent/application/desktop_scheduler.dart';
import 'package:mobile_agent/domain/session_operation_guard.dart';
import 'package:mobile_agent/infrastructure/files/local_crypto_service.dart';
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

  test('concurrent backup publication uses unique complete files', () async {
    final root = await Directory.systemTemp.createTemp('nexus-publish-');
    addTearDown(() => root.delete(recursive: true));
    final paths = await Future.wait(
        List.generate(8, (i) => publishAutomaticBackup(root, 'encrypted-$i')));
    expect(paths.toSet(), hasLength(8));
    for (var i = 0; i < paths.length; i++) {
      expect(await File(paths[i]).readAsString(), 'encrypted-$i');
    }
    expect(root.listSync().whereType<Directory>(), isEmpty);
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

  group('desktop automatic backup scheduling', () {
    late Directory root;
    late AppDatabase db;
    late SharedPreferences prefs;

    List<File> snapshots() {
      final directory = Directory('${root.path}/backups');
      return directory.existsSync()
          ? directory
              .listSync()
              .whereType<File>()
              .where((file) => file.path.endsWith('.nexusauto'))
              .toList()
          : <File>[];
    }

    setUp(() async {
      final previousStorage = FlutterSecureStoragePlatform.instance;
      FlutterSecureStoragePlatform.instance = _InMemorySecureStorage();
      addTearDown(
          () => FlutterSecureStoragePlatform.instance = previousStorage);
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      root = await Directory.systemTemp.createTemp('nexus-desktop-backup-');
      addTearDown(() => root.delete(recursive: true));
      final previousPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TempPathProvider(root.path);
      addTearDown(() => PathProviderPlatform.instance = previousPaths);
      db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customStatement(
          'INSERT INTO memories(id,content,created_at,updated_at) VALUES (?,?,?,?)',
          ['backup-proof', 'desktop snapshot payload', 1, 1]);
    });

    test('default desktop tick publishes a decryptable snapshot once when due',
        () async {
      await prefs.setBool('settings.backup.auto', true);
      var scheduledChecks = 0;
      final scheduler =
          DesktopScheduler(() async => db, runScheduledTasks: (_) async {
        scheduledChecks++;
      });
      addTearDown(scheduler.dispose);
      await scheduler.tick();
      expect(snapshots(), hasLength(1));
      final encrypted = await snapshots().single.readAsString();
      final snapshot =
          jsonDecode(await LocalCryptoService().decryptString(encrypted))
              as Map;
      expect(snapshot['version'], 2);
      expect((snapshot['memories'] as List).single['content'],
          'desktop snapshot payload');
      final stamp = prefs.getString('settings.backup.last_time');
      expect(DateTime.tryParse(stamp!), isNotNull);
      await scheduler.tick();
      expect(snapshots(), hasLength(1));
      expect(prefs.getString('settings.backup.last_time'), stamp);
      expect(scheduledChecks, 2);
    });

    test(
        'disabled desktop backup writes nothing and observes a later switch change',
        () async {
      final scheduler =
          DesktopScheduler(() async => db, runScheduledTasks: (_) async {});
      addTearDown(scheduler.dispose);
      await scheduler.tick();
      expect(snapshots(), isEmpty);
      expect(prefs.getString('settings.backup.last_time'), isNull);
      await prefs.setBool('settings.backup.auto', true);
      await scheduler.tick();
      expect(snapshots(), hasLength(1));
    });

    test(
        'shared due check honors the exact 24h boundary and coalesces missed days',
        () async {
      final now = DateTime.utc(2026, 10, 18, 12);
      final last = now
          .subtract(const Duration(hours: 24))
          .add(const Duration(microseconds: 1));
      await prefs.setBool('settings.backup.auto', true);
      await prefs.setString(
          'settings.backup.last_time', last.toIso8601String());
      expect(await runDueAutomaticBackup(db, clock: () => now), isNull);
      expect(snapshots(), isEmpty);
      final boundary = now.add(const Duration(microseconds: 1));
      expect(await runDueAutomaticBackup(db, clock: () => boundary), isNotNull);
      expect(prefs.getString('settings.backup.last_time'),
          boundary.toIso8601String());
      expect(await runDueAutomaticBackup(db, clock: () => boundary), isNull);
      final muchLater = now.add(const Duration(days: 10));
      expect(
          await runDueAutomaticBackup(db, clock: () => muchLater), isNotNull);
      expect(snapshots(), hasLength(2),
          reason: 'missed days create one snapshot, not ten');
      expect(await runDueAutomaticBackup(db, clock: () => muchLater), isNull);
    });

    test('malformed last time is due, while a future time is not duplicated',
        () async {
      final now = DateTime.utc(2026, 10, 18);
      await prefs.setBool('settings.backup.auto', true);
      await prefs.setString('settings.backup.last_time',
          now.add(const Duration(days: 1)).toIso8601String());
      expect(await runDueAutomaticBackup(db, clock: () => now), isNull);
      expect(snapshots(), isEmpty);
      await prefs.setString('settings.backup.last_time', 'invalid');
      expect(await runDueAutomaticBackup(db, clock: () => now), isNotNull);
      expect(snapshots(), hasLength(1));
    });

    test(
        'filesystem failure preserves last time, does not block tasks, and retries',
        () async {
      final last = DateTime.utc(2026, 1, 1).toIso8601String();
      await prefs.setBool('settings.backup.auto', true);
      await prefs.setString('settings.backup.last_time', last);
      final blocked = File('${root.path}/not-a-directory');
      await blocked.writeAsString('keep');
      PathProviderPlatform.instance = _TempPathProvider(blocked.path);
      var scheduledChecks = 0;
      final scheduler =
          DesktopScheduler(() async => db, runScheduledTasks: (_) async {
        scheduledChecks++;
      });
      addTearDown(scheduler.dispose);
      await scheduler.tick();
      expect(prefs.getString('settings.backup.last_time'), last);
      expect(snapshots(), isEmpty);
      expect(scheduledChecks, 1);
      expect(await blocked.readAsString(), 'keep');
      PathProviderPlatform.instance = _TempPathProvider(root.path);
      await scheduler.tick();
      expect(snapshots(), hasLength(1));
      expect(prefs.getString('settings.backup.last_time'), isNot(last));
      expect(scheduledChecks, 2);
    });

    test('encryption failure propagates without advancing the due stamp',
        () async {
      const last = '2026-01-01T00:00:00.000Z';
      await prefs.setBool('settings.backup.auto', true);
      await prefs.setString('settings.backup.last_time', last);
      await FlutterSecureStoragePlatform.instance.write(
          key: 'sync.secret', value: 'invalid key encoding!', options: {});
      await expectLater(runDueAutomaticBackup(db), throwsFormatException);
      expect(prefs.getString('settings.backup.last_time'), last);
      expect(snapshots(), isEmpty);
    });

    test('overlapping desktop ticks do not launch duplicate backups', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var backups = 0;
      var tasks = 0;
      final scheduler =
          DesktopScheduler(() async => db, runAutomaticBackup: (_) async {
        backups++;
        entered.complete();
        await release.future;
      }, runScheduledTasks: (_) async {
        tasks++;
      });
      addTearDown(scheduler.dispose);
      final first = scheduler.tick();
      await entered.future;
      await scheduler.tick();
      expect(backups, 1);
      expect(tasks, 0);
      release.complete();
      await first;
      expect(tasks, 1);
    });

    test(
        'dispose prevents future checks and skips tasks after an in-flight backup',
        () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var opens = 0;
      var tasks = 0;
      final scheduler = DesktopScheduler(() async {
        opens++;
        return db;
      }, runAutomaticBackup: (_) async {
        entered.complete();
        await release.future;
      }, runScheduledTasks: (_) async {
        tasks++;
      });
      final first = scheduler.tick();
      await entered.future;
      scheduler.dispose();
      release.complete();
      await first;
      await scheduler.tick();
      expect(opens, 1);
      expect(tasks, 0);
    });

    test(
        'maintenance suppresses checks both before and after opening the database',
        () async {
      var backups = 0;
      var tasks = 0;
      final opening = Completer<AppDatabase>();
      final scheduler =
          DesktopScheduler(() => opening.future, runAutomaticBackup: (_) async {
        backups++;
      }, runScheduledTasks: (_) async {
        tasks++;
      });
      addTearDown(scheduler.dispose);
      await SessionOperationGuard.restore('test', () async {
        await scheduler.tick();
      });
      final pending = scheduler.tick();
      await SessionOperationGuard.restore('test', () async {
        opening.complete(db);
        await pending;
      });
      expect(backups, 0);
      expect(tasks, 0);
      await scheduler.tick();
      expect(backups, 1);
      expect(tasks, 1);
    });

    test('scheduled task failure does not stop the next backup check',
        () async {
      var backups = 0;
      var tasks = 0;
      final scheduler =
          DesktopScheduler(() async => db, runAutomaticBackup: (_) async {
        backups++;
      }, runScheduledTasks: (_) async {
        tasks++;
        throw StateError('task failure');
      });
      addTearDown(scheduler.dispose);
      await scheduler.tick();
      await scheduler.tick();
      expect(backups, 2);
      expect(tasks, 2);
    });

    testWidgets(
        'start checks immediately, repeats every 30s, and stops after dispose',
        (tester) async {
      var backups = 0;
      var tasks = 0;
      final scheduler =
          DesktopScheduler(() async => db, runAutomaticBackup: (_) async {
        backups++;
      }, runScheduledTasks: (_) async {
        tasks++;
      });
      addTearDown(scheduler.dispose);
      scheduler.start();
      scheduler.start();
      await tester.pump();
      expect(backups, 1);
      expect(tasks, 1);
      await tester.pump(const Duration(seconds: 30));
      expect(backups, 2);
      expect(tasks, 2);
      scheduler.dispose();
      await tester.pump(const Duration(seconds: 60));
      expect(backups, 2);
    });
  });
}
