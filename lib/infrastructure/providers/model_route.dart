import 'llm_provider.dart';
import 'provider_config.dart';
import 'provider_factory.dart';

/// 模型路由的能力 seam：决定一次运行用哪个 [LlmProvider]。
///
/// 目前只有直连厂商一条路由；将来的远端路由（例如经配对的桌面端转发）实现同一接口，
/// 排在 [ModelRouter.routes] 中即可，调用方不用改。
abstract interface class ModelRoute {
  /// 路由标识，写入诊断信息，例如 `direct`。
  String get id;

  /// 该路由能服务此配置时返回 Provider，否则返回 null，交给下一条路由。
  LlmProvider? providerFor(ProviderConfig config);
}

/// 按配置直连厂商 API。
class DirectModelRoute implements ModelRoute {
  const DirectModelRoute();

  @override
  String get id => 'direct';

  @override
  LlmProvider? providerFor(ProviderConfig config) =>
      config.isConfigured ? createLlmProvider(config) : null;
}

/// 路由结果。
class ResolvedModel {
  const ResolvedModel({
    required this.provider,
    required this.model,
    required this.routeId,
  });

  final LlmProvider provider;
  final String model;
  final String routeId;

  bool get isDemo => routeId == ModelRouter.demoRouteId;
}

/// 按顺序尝试路由；都不能服务时退回演示 Provider。
class ModelRouter {
  const ModelRouter(this.routes);

  static const standard = ModelRouter([DirectModelRoute()]);
  static const demoRouteId = 'demo';
  static const demoModel = 'demo-model';

  final List<ModelRoute> routes;

  /// 第一条能服务的路由；都不能时返回 null（调用方自行决定如何降级）。
  ResolvedModel? tryResolve(ProviderConfig config) {
    for (final route in routes) {
      final provider = route.providerFor(config);
      if (provider != null) {
        return ResolvedModel(
            provider: provider, model: config.model, routeId: route.id);
      }
    }
    return null;
  }

  /// 同 [tryResolve]，但没有可用路由时退回 [DemoProvider]。
  ResolvedModel resolve(ProviderConfig config) =>
      tryResolve(config) ??
      ResolvedModel(
          provider: DemoProvider(), model: demoModel, routeId: demoRouteId);
}
