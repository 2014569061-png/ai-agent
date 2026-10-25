import 'dart:async';
import 'package:mobile_agent/application/mcp_service.dart';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_agent/application/data_maintenance_actions.dart';
import 'package:mobile_agent/application/data_maintenance_service.dart';
import 'package:mobile_agent/domain/runtime_data_scope.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/database/runtime_maintenance_store.dart';
import 'package:mobile_agent/infrastructure/files/vault_exporter_io.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config_store.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late ProviderConfigStore store;
  late DataMaintenanceActions actions;
  late int refreshes;
  const service = DataMaintenanceService(
      pollInterval: Duration(milliseconds: 10),
      drainTimeout: Duration(milliseconds: 200));
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final root =
        await Directory.systemTemp.createTemp('nexus-maintenance-actions-');
    addTearDown(() => root.delete(recursive: true));
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
    addTearDown(() {
      PathProviderPlatform.instance = previous;
    });
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    store = ProviderConfigStore();
    refreshes = 0;
    actions = DataMaintenanceActions(
        database: () async => db,
        providerStore: store,
        maintenance: service,
        refresh: () async {
          refreshes++;
        });
  });

  test('实际恢复等待运行取消，恢复后旧回调不能再写入', () async {
    final snapshot = await buildVaultJson(db);
    await db.customStatement(
        'INSERT INTO memories(id,content,created_at,updated_at) VALUES (?,?,?,?)',
        ['old', 'old', 1, 1]);
    final started = Completer<void>();
    final stop = Completer<void>();
    RuntimeDataScope? stale;
    final run = service.run(db, () async {
      stale = RuntimeDataScope.current;
      started.complete();
      await stop.future;
    }, cancel: stop.complete);
    await started.future;
    await actions.restore(snapshot);
    await run;
    expect(await db.allMemories(), isEmpty);
    expect(refreshes, 1);
    await expectLater(
        stale!.enter(() => db.customStatement('DELETE FROM memories')),
        throwsA(isA<RuntimeDataRevoked>()));
    expect((await RuntimeMaintenanceStore(db).state()).owner, isEmpty);
  });

  test('恢复空 MCP 配置后新服务不会重新导入旧偏好', () async {
    final snapshot = await buildVaultJson(db);
    snapshot['mcpServers'] = <dynamic>[];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mcp.servers',
        '[{"id":"old","name":"old","kind":"http","url":"https://fake.invalid","enabled":true}]');
    await actions.restore(snapshot);
    expect(await McpService(database: Future.value(db)).loadAll(), isEmpty);
    expect(prefs.containsKey('mcp.servers'), isTrue);
  });

  test('清库移除凭证与旧 MCP 来源并刷新；维护代次保留', () async {
    await store.save(const ProviderConfig(
        baseUrl: 'https://fake.invalid', model: 'fake', apiKey: 'FAKE-KEY'));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mcp.servers', '[{"id":"old"}]');
    await prefs.setBool('settings.backup.auto', true);
    await actions.clear();
    expect((await ProviderConfigStore().load()).apiKey, isEmpty);
    expect(prefs.containsKey('mcp.servers'), isFalse);
    expect(prefs.containsKey('settings.backup.auto'), isFalse);
    expect(refreshes, 1);
    expect((await RuntimeMaintenanceStore(db).state()).epoch, greaterThan(0));
  });

  test('恢复失败仍刷新并释放维护，新运行能继续写入', () async {
    await expectLater(actions.restore({'version': 999}), throwsFormatException);
    expect(refreshes, 1);
    expect((await RuntimeMaintenanceStore(db).state()).owner, isEmpty);
    await service.run(db, () => db.customStatement('DELETE FROM memories'));
  });

  test('等待审批或工具不退出时拒绝清库，不假装中止成功', () async {
    final started = Completer<void>();
    final exit = Completer<void>();
    final run = service.run(db, () async {
      started.complete();
      await exit.future;
    });
    await started.future;
    await expectLater(actions.clear(), throwsA(isA<RuntimeDataRevoked>()));
    expect(refreshes, 0);
    exit.complete();
    await run;
    await actions.clear();
    expect(refreshes, 1);
  });
}
