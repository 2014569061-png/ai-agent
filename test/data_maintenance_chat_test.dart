import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/application/data_maintenance_actions.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/domain/models.dart';
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

class _Config extends ProviderConfigStore {
  _Config(this.port);
  final int port;
  bool failLoad = false;
  @override
  Future<ProviderConfig> load() async {
    if (failLoad) throw StateError('injected refresh failure');
    return ProviderConfig(
        id: 'fake',
        name: 'Fake local SSE',
        baseUrl: 'http://127.0.0.1:$port/v1',
        model: 'fake',
        apiKey: 'FAKE-KEY',
        inputPricePerMillionCents: 0,
        outputPricePerMillionCents: 0);
  }

  @override
  Future<List<ProviderConfig>> loadAll() async => [await load()];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    // Plain integration tests use only this loopback server, never the network.
    final previousHttp = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() {
      HttpOverrides.global = previousHttp;
    });
  });
  for (final mode in ['restore', 'clear', 'refreshFailure']) {
    test('real ChatController SSE cancellation and $mode refresh', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final root =
          await Directory.systemTemp.createTemp('nexus-chat-maintenance-');
      addTearDown(() => root.delete(recursive: true));
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(root.path);
      addTearDown(() {
        PathProviderPlatform.instance = previous;
      });
      final server = await HttpServer.bind('127.0.0.1', 0);
      addTearDown(() => server.close(force: true));
      final arrived = Completer<void>();
      HttpResponse? response;
      server.listen((request) async {
        await request.drain<void>();
        response = request.response;
        response!.headers.contentType =
            ContentType('text', 'event-stream', charset: 'utf-8');
        response!.write(
            'data: {"choices":[{"delta":{"content":"old streamed token"}}]}\n\n');
        try {
          await response!.flush();
          if (!arrived.isCompleted) arrived.complete();
        } catch (error, stack) {
          if (!arrived.isCompleted) arrived.completeError(error, stack);
        }
        // Deliberately leave the stream open. Only the real Dio cancellation
        // token can terminate the client without the server completing it.
      });
      final db = AppDatabase(NativeDatabase.memory());
      final config = _Config(server.port);
      final container = ProviderContainer(overrides: [
        databaseProvider.overrideWith((ref) async => db),
        providerConfigStoreProvider.overrideWith((ref) => config),
        agentRetrySettingsProvider
            .overrideWithValue(const AgentRetrySettings(maxRetries: 0)),
      ]);
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      final controller = container.read(chatControllerProvider.notifier);
      await controller.initialized;
      expect(container.read(chatControllerProvider).loading, isFalse);
      final snapshot = await buildVaultJson(db);
      final sending = controller.send(
          text: 'fake local stream',
          attachments: const [],
          approveTool: (call, risk, sensitive) async => ToolApproval.allowOnce);
      await arrived.future.timeout(const Duration(seconds: 5));
      expect(container.read(chatControllerProvider).running, isTrue);
      final actions = container.read(dataMaintenanceActionsProvider);
      if (mode == 'restore') {
        await actions.restore(snapshot).timeout(const Duration(seconds: 5));
      } else if (mode == 'refreshFailure') {
        config.failLoad = true;
        await expectLater(
            actions.restore(snapshot).timeout(const Duration(seconds: 5)),
            throwsA(isA<DataMaintenanceRefreshFailure>()));
      } else {
        await actions.clear().timeout(const Duration(seconds: 5));
      }
      await sending.timeout(const Duration(seconds: 2));
      final state = container.read(chatControllerProvider);
      expect(state.running, isFalse);
      expect(state.loading, isFalse);
      expect(state.messages, isEmpty);
      expect(await db.recentRuns(), isEmpty);
      expect(await RuntimeMaintenanceStore(db).liveRuns(), 0);
      expect((await RuntimeMaintenanceStore(db).state()).owner, isEmpty);
      // An attempted late server chunk must neither revive the old response nor
      // create records in the restored/cleared database.
      try {
        response?.write('data: {"choices":[{"delta":{"content":"LATE"}}]}\n\n');
        await response?.close();
      } catch (_) {/* disconnected by cancellation */}
      await pumpEventQueue();
      expect(container.read(chatControllerProvider).messages, isEmpty);
      // Provider calls must use the injected database, including cost records.
      expect(File('${root.path}/mobile_agent.sqlite').existsSync(), isFalse);
    });
  }
}
