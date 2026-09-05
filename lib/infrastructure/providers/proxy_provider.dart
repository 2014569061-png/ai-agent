import 'package:dio/dio.dart';

import '../../domain/models.dart';
import 'llm_provider.dart';
import 'openai_compatible_provider.dart';
import 'provider_config.dart';

/// 托管 Key 代理 Provider（§4.2）。
///
/// 复用 [OpenAiCompatibleProvider] 的 SSE 透传 / 工具调用 / 用量解析逻辑，
/// 仅把 baseUrl 指向后端 `/v1`、apiKey 换成用户托管 Key。后端负责路由、缓存、
/// 审核与计费（返回 `X-Balance-Low` 预警头）。
class ProxyProvider implements LlmProvider {
  ProxyProvider({
    required this.backendBaseUrl,
    required this.managedKey,
    String? model,
  }) : _inner = OpenAiCompatibleProvider(
          config: ProviderConfig(
            baseUrl: backendBaseUrl,
            model: model ?? 'gpt-4o',
            apiKey: managedKey,
            type: ProviderType.proxy,
          ),
        );

  final String backendBaseUrl;
  final String managedKey;
  final OpenAiCompatibleProvider _inner;

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
          {CancelToken? cancelToken}) =>
      _inner.stream(request, cancelToken: cancelToken);

  /// 测试到后端（含托管 Key 鉴权）的连接。
  Future<String?> testConnection() => _inner.testConnection();
}
