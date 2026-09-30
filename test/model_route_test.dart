// 阶段 5b：模型路由能力 seam。
import 'package:dio/dio.dart' show CancelToken;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/headless_executor.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/providers/llm_provider.dart';
import 'package:mobile_agent/infrastructure/providers/model_route.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';

const _unconfigured = ProviderConfig(
    baseUrl: 'https://unused.invalid/v1', model: 'remote-model', apiKey: '');
const _configured = ProviderConfig(
    baseUrl: 'https://api.example.invalid/v1', model: 'm', apiKey: 'sk-test');

class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.reply);
  final String reply;
  final requests = <UnifiedRequest>[];

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    requests.add(request);
    yield TextDeltaEvent(reply);
    yield const CompletedEvent();
  }
}

/// 模拟将来的远端路由：不看 Key，总能服务。
class _RemoteRoute implements ModelRoute {
  _RemoteRoute(this.provider);
  final LlmProvider provider;

  @override
  String get id => 'remote';

  @override
  LlmProvider? providerFor(ProviderConfig config) => provider;
}

class _NeverRoute implements ModelRoute {
  const _NeverRoute();
  @override
  String get id => 'never';
  @override
  LlmProvider? providerFor(ProviderConfig config) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('standard router connects directly when configured', () {
    expect(_configured.isConfigured, isTrue);
    final route = ModelRouter.standard.resolve(_configured);
    expect(route.routeId, 'direct');
    expect(route.model, 'm');
    expect(route.isDemo, isFalse);
  });

  test('falls back to the demo provider when no route can serve', () {
    final route = ModelRouter.standard.resolve(_unconfigured);
    expect(route.isDemo, isTrue);
    expect(route.provider, isA<DemoProvider>());
    expect(route.model, ModelRouter.demoModel);
    expect(ModelRouter.standard.tryResolve(_unconfigured), isNull);
  });

  test('routes are tried in order', () {
    final remote = _ScriptedProvider('x');
    final router = ModelRouter([const _NeverRoute(), _RemoteRoute(remote)]);
    final route = router.resolve(_unconfigured);
    expect(route.routeId, 'remote');
    expect(route.provider, same(remote));
    expect(route.model, 'remote-model');
  });

  test('headless runs use the injected router', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final remote = _ScriptedProvider('来自远端路由');
    final result = await HeadlessExecutor.runDetailed(
      db: db,
      config: _unconfigured,
      prompt: '你好',
      modelRouter: ModelRouter([_RemoteRoute(remote)]),
    );
    expect(result.succeeded, isTrue, reason: '${result.error}');
    expect(result.text.trim(), '来自远端路由');
    expect(remote.requests.single.model, 'remote-model');
  });
}
