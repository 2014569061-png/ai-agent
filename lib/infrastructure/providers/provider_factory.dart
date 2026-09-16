import 'anthropic_provider.dart';
import 'gemini_provider.dart';
import 'llm_provider.dart';
import 'openai_compatible_provider.dart';
import 'provider_config.dart';
import 'proxy_provider.dart';

/// 按 [ProviderConfig.type] 构造对应的厂商适配器。
///
/// 聊天主流程、后台无头执行与「Agent 草稿生成」等一次性调用都从这里取，
/// 避免每个新调用点各维护一份 switch —— 新增厂商时漏改其中一处，表现为
/// 「某个入口静默走了错误适配器」，很难从症状定位到原因。
LlmProvider createLlmProvider(ProviderConfig config) {
  switch (config.type) {
    case ProviderType.anthropic:
      return AnthropicProvider(config: config);
    case ProviderType.gemini:
      return GeminiProvider(config: config);
    case ProviderType.openaiCompatible:
      return OpenAiCompatibleProvider(config: config);
    case ProviderType.proxy:
      return ProxyProvider(
          backendBaseUrl: config.baseUrl,
          managedKey: config.apiKey,
          model: config.model);
  }
}
