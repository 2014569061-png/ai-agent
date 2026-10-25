import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/data_maintenance_service.dart';
import 'package:mobile_agent/domain/runtime_data_scope.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/database/runtime_maintenance_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  const service = DataMaintenanceService(
      pollInterval: Duration(milliseconds: 10),
      drainTimeout: Duration(milliseconds: 100));
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
  });
  tearDown(() => db.close());
  Future<void> put(String value) => db.customStatement(
      'INSERT INTO memories(id, content, created_at, updated_at) VALUES (?, ?, ?, ?)',
      [value, value, 1, 1]);

  test('normal CRUD, explicit transaction and batch still work', () async {
    await put('normal');
    await db.transaction(() => put('transaction'));
    await db.batch((b) => b.customStatement(
        'INSERT INTO memories(id, content, created_at, updated_at) VALUES (?, ?, ?, ?)',
        ['batch', 'batch', 1, 1]));
    expect(
        await db.customSelect('SELECT id FROM memories').get(), hasLength(3));
  });
  test('maintenance admits no new runs or unscoped writes', () async {
    await service.maintain(db, () async {
      await put('maintenance');
      await expectLater(service.run(db, () => put('nested-run')),
          throwsA(isA<RuntimeDataRevoked>()));
    });
    await service.run(db, () => put('after'));
  });
  test(
      'cancel then drain before destructive action; revoke late callbacks permanently',
      () async {
    final started = Completer<void>();
    final exit = Completer<void>();
    RuntimeDataScope? old;
    final running = service.run(db, () async {
      old = RuntimeDataScope.current;
      started.complete();
      await exit.future;
    }, cancel: exit.complete);
    await started.future;
    var refreshed = false;
    await service.maintain(db, () async {
      await running;
      await db.clearAllUserData();
      await put('restored');
    }, refresh: () async {
      refreshed = true;
    });
    expect(refreshed, isTrue);
    await expectLater(
        old!.enter(() => put('late')), throwsA(isA<RuntimeDataRevoked>()));
    expect(
        await db.customSelect('SELECT id FROM memories').get(), hasLength(1));
  });
  test(
      'unresponsive task prevents overwrite; failed maintenance unlocks without reviving old epoch',
      () async {
    final started = Completer<void>();
    final exit = Completer<void>();
    RuntimeDataScope? old;
    final running = service.run(db, () async {
      old = RuntimeDataScope.current;
      started.complete();
      await exit.future;
    });
    await started.future;
    var overwritten = false;
    await expectLater(
        service.maintain(db, () async {
          overwritten = true;
        }),
        throwsA(isA<RuntimeDataRevoked>()));
    expect(overwritten, isFalse);
    expect((await RuntimeMaintenanceStore(db).state()).owner, isEmpty);
    await service.run(db, () => put('new-run'));
    await expectLater(
        old!.enter(() => put('late')), throwsA(isA<RuntimeDataRevoked>()));
    exit.complete();
    await running;
  });
  test('action failure releases maintenance and leaves old epoch invalid',
      () async {
    await expectLater(
        service.maintain(db, () async {
          throw StateError('fake');
        }),
        throwsStateError);
    await service.run(db, () => put('after-failure'));
  });
  test('nested unresponsive executor retains lease after parent timeout',
      () async {
    const short = DataMaintenanceService(
        pollInterval: Duration(milliseconds: 5),
        runLease: Duration(milliseconds: 40),
        drainTimeout: Duration(milliseconds: 120));
    final started = Completer<void>();
    final exit = Completer<void>();
    late Future<void> child;
    await short.run(db, () async {
      child = short.run(db, () async {
        started.complete();
        await exit.future;
      });
      await started.future;
    });
    expect(await RuntimeMaintenanceStore(db).liveRuns(), 1);
    var overwritten = false;
    try {
      await expectLater(
          short.maintain(db, () async {
            overwritten = true;
          }),
          throwsA(isA<RuntimeDataRevoked>()));
      expect(overwritten, isFalse);
      expect(await RuntimeMaintenanceStore(db).liveRuns(), 1);
    } finally {
      exit.complete();
      await child;
    }
    expect(await RuntimeMaintenanceStore(db).liveRuns(), 0);
  });

  test('refresh failure does not hide the primary operation failure', () async {
    final primary = StateError('primary restore failure');
    await expectLater(
        service.maintain(db, () async {
          throw primary;
        }, refresh: () async {
          throw StateError('secondary refresh failure');
        }),
        throwsA(same(primary)));
    expect((await RuntimeMaintenanceStore(db).state()).owner, isEmpty);
    await expectLater(
        service.maintain(db, () async {}, refresh: () async {
          throw StateError('refresh failure');
        }),
        throwsA(isA<DataMaintenanceRefreshFailure>()));
    expect((await RuntimeMaintenanceStore(db).state()).owner, isEmpty);
  });

  test('expired heartbeat is not proof that an executor has stopped', () async {
    final store = RuntimeMaintenanceStore(db);
    await store.register('suspended-isolate', Duration.zero);
    var overwritten = false;
    await expectLater(
        service.maintain(db, () async {
          overwritten = true;
        }),
        throwsA(isA<RuntimeDataRevoked>()));
    expect(overwritten, isFalse);
    expect(await store.liveRuns(), 1);
    await store.release('suspended-isolate');
    await service.maintain(db, () async {
      overwritten = true;
    });
    expect(overwritten, isTrue);
  });

  test('persistent state fences a second SQLite connection', () async {
    final root = await Directory.systemTemp.createTemp('nexus-maintenance-');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/db.sqlite');
    final a = AppDatabase(NativeDatabase(file));
    final b = AppDatabase(NativeDatabase(file));
    addTearDown(a.close);
    addTearDown(b.close);
    await a.customSelect('SELECT 1').get();
    await b.customSelect('SELECT 1').get();
    final first = RuntimeMaintenanceStore(a);
    final epoch = await first.register('test-old', const Duration(minutes: 1));
    final stale = RuntimeDataScope.run(epoch);
    final next = await first.begin('owner');
    final independent = RuntimeMaintenanceStore(b);
    expect((await independent.state()).owner, 'owner');
    await expectLater(
        independent.register('test-new', const Duration(minutes: 1)),
        throwsA(isA<RuntimeDataRevoked>()));
    await expectLater(b.customStatement('DELETE FROM memories'),
        throwsA(isA<RuntimeDataRevoked>()));
    await first.finish('owner', next);
    await expectLater(
        stale.enter(() => b.customStatement('DELETE FROM memories')),
        throwsA(isA<RuntimeDataRevoked>()));
    await b.customStatement('DELETE FROM memories');
  });
}
