import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/data_maintenance_service.dart';
import 'package:mobile_agent/domain/runtime_data_scope.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/database/runtime_maintenance_store.dart';

Future<void> _worker((String, SendPort) args) async {
  final (path, port) = args;
  final db = AppDatabase(NativeDatabase(File(path), setup: (sqlite) {
    sqlite.execute('PRAGMA journal_mode=WAL');
    sqlite.execute('PRAGMA busy_timeout=3000');
  }));
  final cancelled = Completer<void>();
  try {
    await const DataMaintenanceService(pollInterval: Duration(milliseconds: 20))
        .run(db, () async {
      port.send('ready');
      await cancelled.future;
      try {
        await db.customStatement('DELETE FROM memories');
        port.send('unsafe-write');
      } on RuntimeDataRevoked {
        port.send('write-blocked');
      }
    }, cancel: () {
      if (!cancelled.isCompleted) cancelled.complete();
    });
    port.send('finished');
  } catch (error) {
    port.send('error:$error');
  } finally {
    await db.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('真正独立 isolate 观察持久化维护代次、取消并退出后才允许恢复', () async {
    final root =
        await Directory.systemTemp.createTemp('nexus-isolate-maintenance-');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/db.sqlite');
    final db = AppDatabase(NativeDatabase(file, setup: (sqlite) {
      sqlite.execute('PRAGMA journal_mode=WAL');
      sqlite.execute('PRAGMA busy_timeout=3000');
    }));
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    final messages = <String>[];
    final ready = Completer<void>();
    final finished = Completer<void>();
    final receive = ReceivePort();
    addTearDown(receive.close);
    receive.listen((dynamic value) {
      messages.add(value as String);
      if (value == 'ready' && !ready.isCompleted) ready.complete();
      if (value == 'finished' && !finished.isCompleted) finished.complete();
      if (value.startsWith('error:') && !ready.isCompleted) {
        ready.completeError(StateError(value));
      }
    });
    final isolate = await Isolate.spawn(_worker, (file.path, receive.sendPort));
    addTearDown(() => isolate.kill(priority: Isolate.immediate));
    await ready.future.timeout(const Duration(seconds: 10));
    await const DataMaintenanceService(
            pollInterval: Duration(milliseconds: 20),
            drainTimeout: Duration(seconds: 5))
        .maintain(db, () async {
      expect(await RuntimeMaintenanceStore(db).liveRuns(), 0);
      await db.clearAllUserData();
    });
    await finished.future.timeout(const Duration(seconds: 5));
    expect(messages, contains('write-blocked'));
    expect(messages, isNot(contains('unsafe-write')));
    expect((await RuntimeMaintenanceStore(db).state()).owner, isEmpty);
  });
}
