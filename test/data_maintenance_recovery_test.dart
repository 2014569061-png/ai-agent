import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mobile_agent/application/data_maintenance_actions.dart';
import 'package:mobile_agent/application/data_maintenance_service.dart';
import 'package:mobile_agent/domain/runtime_data_scope.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/database/runtime_maintenance_store.dart';
import 'package:mobile_agent/infrastructure/database/runtime_process_probe.dart';

class _Probe implements RuntimeProcessProbe {
  _Probe(this.identity);
  RuntimeProcessIdentity? identity;
  bool unknown = false;
  @override
  RuntimeProcessIdentity? get current => identity;
  @override
  bool? isAlive(RuntimeProcessIdentity id) =>
      unknown ? null : id.birth != 'dead';
}

/// Metadata is written on behalf of the owned child; liveness still comes from
/// the REAL OS probe, never a mocked PID/timeout. No business data is in child RAM.
class _ChildCurrent implements RuntimeProcessProbe {
  _ChildCurrent(this.current);
  @override
  final RuntimeProcessIdentity current;
  @override
  bool? isAlive(RuntimeProcessIdentity id) => runtimeProcessProbe.isAlive(id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  test(
      'real process identity includes birth; same PID with another birth is not alive',
      () {
    final self = runtimeProcessProbe.current;
    expect(self, isNotNull);
    expect(runtimeProcessProbe.isAlive(self!), isTrue);
    expect(
        runtimeProcessProbe.isAlive(RuntimeProcessIdentity(
            self.platform, self.pid, '${self.birth}-another-incarnation')),
        isFalse);
    expect(
        runtimeProcessProbe.isAlive(
            RuntimeProcessIdentity('unsupported', self.pid, self.birth)),
        isNull);
  }, skip: !(Platform.isWindows || Platform.isLinux || Platform.isAndroid));

  test(
      'live or unprovable owner cannot be force-unlocked, even without run rows',
      () async {
    final probe = _Probe(const RuntimeProcessIdentity('unit', 42, 'alive'));
    final store = RuntimeMaintenanceStore(db, processProbe: probe);
    final epoch = await store.begin('live-owner');
    expect((await store.inspectRecovery()).canRecover, isFalse);
    await expectLater(
        store.recoverAndBegin('new'), throwsA(isA<RuntimeDataRevoked>()));
    probe.unknown = true;
    expect((await store.inspectRecovery()).canRecover, isFalse);
    await expectLater(
        store.recoverAndBegin('new'), throwsA(isA<RuntimeDataRevoked>()));
    expect((await store.state()).owner, 'live-owner');
    await store.finish('live-owner', epoch);
  });

  test(
      'confirmed-dead recovery advances epoch, preserves business data and takes refresh lock',
      () async {
    await db.customStatement(
        "INSERT INTO memories(id, content, created_at, updated_at) VALUES ('kept', 'kept', 1, 1)");
    final probe = _Probe(const RuntimeProcessIdentity('unit', 42, 'dead'));
    final store = RuntimeMaintenanceStore(db, processProbe: probe);
    final oldEpoch = await store.register('orphan', Duration.zero);
    await store.begin('dead-owner');
    expect((await store.inspectRecovery()).canRecover, isTrue);
    final next = await store.recoverAndBegin('new-owner');
    expect(next, greaterThan(oldEpoch));
    expect((await store.state()).owner, 'new-owner');
    expect(await store.liveRuns(), 0);
    await expectLater(store.register('blocked', const Duration(seconds: 1)),
        throwsA(isA<RuntimeDataRevoked>()));
    await store.finish('new-owner', next);
    await expectLater(
        RuntimeDataScope.run(oldEpoch)
            .enter(() => db.customStatement('DELETE FROM memories')),
        throwsA(isA<RuntimeDataRevoked>()));
    expect(await db.allMemories(), hasLength(1));
  });

  test(
      'an old inspection is not permission: newly admitted live work blocks recovery',
      () async {
    final probe = _Probe(const RuntimeProcessIdentity('unit', 42, 'dead'));
    final store = RuntimeMaintenanceStore(db, processProbe: probe);
    await store.register('orphan', Duration.zero);
    expect((await store.inspectRecovery()).canRecover, isTrue);
    probe.identity = const RuntimeProcessIdentity('unit', 43, 'alive');
    await store.register('new-live', const Duration(minutes: 1));
    await expectLater(
        store.recoverAndBegin('new'), throwsA(isA<RuntimeDataRevoked>()));
    expect(await store.liveRuns(), 2);
    expect((await store.state()).epoch, 0);
  });

  test(
      'legacy records lacking identity stay fail-closed; no blind expiry cleanup',
      () async {
    final store = RuntimeMaintenanceStore(db, processProbe: _Probe(null));
    await store.register('unknown', Duration.zero);
    expect((await store.inspectRecovery()).canRecover, isFalse);
    await expectLater(
        store.recoverAndBegin('new'), throwsA(isA<RuntimeDataRevoked>()));
    expect(await store.liveRuns(), 1);
  });

  test(
      'real killed child + reopened file database: recover via application action, preserve rows and fence stale writes',
      () async {
    final root =
        await Directory.systemTemp.createTemp('nexus-process-recovery-');
    addTearDown(() => root.delete(recursive: true));
    final configFile = File(
        p.join(Directory.current.path, '.dart_tool', 'package_config.json'));
    final config =
        jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    final flutterPackage = (config['packages'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((item) => item['name'] == 'flutter_test');
    final flutterRoot = Directory.fromUri(
            configFile.uri.resolve(flutterPackage['rootUri'] as String))
        .parent
        .parent
        .path;
    final dart = p.join(flutterRoot, 'bin', 'cache', 'dart-sdk', 'bin',
        Platform.isWindows ? 'dart.exe' : 'dart');
    final child = await Process.start(dart, [
      p.join(Directory.current.path, 'test', 'fixtures',
          'runtime_process_identity_worker.dart')
    ]);
    final stderr = StringBuffer();
    final errors = child.stderr.transform(utf8.decoder).listen(stderr.write);
    RuntimeProcessIdentity? ownedIdentity;
    addTearDown(() async {
      if (ownedIdentity != null &&
          runtimeProcessProbe.isAlive(ownedIdentity) == true) {
        Process.killPid(ownedIdentity.pid, ProcessSignal.sigkill);
      }
      await child.stdin.close();
      child.kill();
      await child.exitCode.timeout(const Duration(seconds: 5));
      await errors.cancel();
    });
    final line = await child.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 8),
            onTimeout: () =>
                throw StateError('child handshake failed: $stderr'));
    final identity = RuntimeProcessIdentity.fromJson(jsonDecode(line))!;
    ownedIdentity = identity;
    // Windows dart.exe may be a launcher for a different dartvm.exe PID.
    // The fixture reports its own OS identity; never substitute the wrapper PID.
    expect(identity.pid, greaterThan(0));
    expect(runtimeProcessProbe.isAlive(identity), isTrue);
    final file = File(p.join(root.path, 'acceptance.sqlite'));
    var disk = AppDatabase(NativeDatabase(file));
    addTearDown(() => disk.close());
    await disk.customStatement(
        "INSERT INTO memories(id, content, created_at, updated_at) VALUES ('kept', 'kept', 1, 1)");
    final writer =
        RuntimeMaintenanceStore(disk, processProbe: _ChildCurrent(identity));
    final oldEpoch =
        await writer.register('owned-child-run', const Duration(minutes: 1));
    await writer.begin('owned-child-owner');
    await disk.close();
    disk = AppDatabase(NativeDatabase(file));
    final reader = RuntimeMaintenanceStore(disk);
    expect((await reader.inspectRecovery()).canRecover, isFalse);
    expect(Process.killPid(identity.pid, ProcessSignal.sigkill), isTrue);
    await child.exitCode.timeout(const Duration(seconds: 5));
    expect(runtimeProcessProbe.isAlive(identity), isFalse);
    expect((await reader.inspectRecovery()).canRecover, isTrue);
    var refreshed = false;
    final actions = DataMaintenanceActions(
        database: () async => disk,
        refresh: () async {
          refreshed = true;
          expect((await reader.state()).owner, isNotEmpty);
          expect(await disk.allMemories(), hasLength(1));
          await expectLater(
              const DataMaintenanceService().run(disk, () async {}),
              throwsA(isA<RuntimeDataRevoked>()));
        });
    await actions.recoverInterrupted();
    expect(refreshed, isTrue);
    expect((await reader.state()).owner, isEmpty);
    expect(await reader.liveRuns(), 0);
    await expectLater(
        RuntimeDataScope.run(oldEpoch)
            .enter(() => disk.customStatement('DELETE FROM memories')),
        throwsA(isA<RuntimeDataRevoked>()));
    expect(await disk.allMemories(), hasLength(1));
    expect((await reader.inspectRecovery()).hasWork, isFalse);
  }, skip: !(Platform.isWindows || Platform.isLinux));
}
