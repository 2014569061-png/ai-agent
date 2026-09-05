import '../../domain/models.dart';

enum ProviderType { openaiCompatible, anthropic, gemini, proxy }

class ProviderConfig {
  /// 发送给模型的上下文 token 预算：超出时自动裁剪较早历史（见 ContextWindow）。
  static const defaultContextTokens = 32000;

  const ProviderConfig({
    this.id = 'default',
    this.name = 'OpenAI',
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    this.type = ProviderType.openaiCompatible,
    this.reasoningEffort = ReasoningEffort.medium,
    this.contextTokens = defaultContextTokens,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String model;
  final String apiKey;
  final ProviderType type;
  final ReasoningEffort reasoningEffort;
  final int contextTokens;

  ProviderConfig copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? model,
    String? apiKey,
    ProviderType? type,
    ReasoningEffort? reasoningEffort,
    int? contextTokens,
  }) =>
      ProviderConfig(
        id: id ?? this.id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        apiKey: apiKey ?? this.apiKey,
        type: type ?? this.type,
        reasoningEffort: reasoningEffort ?? this.reasoningEffort,
        contextTokens: contextTokens ?? this.contextTokens,
      );

  bool get isConfigured {
    if (model.trim().isEmpty) return false;
    // 云端服务必须携带 API Key。
    if (apiKey.trim().isNotEmpty) return true;
    // 本地模型（Ollama / LM Studio 等）无需 API Key。
    return isLocalBaseUrl(baseUrl);
  }

  /// 是否为本地地址（localhost / 127.0.0.1 / 内网保留段）。
  static bool isLocalBaseUrl(String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasAuthority) return false;
    final host = uri.host.toLowerCase().replaceAll('[', '').replaceAll(']', '');
    if (host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host == '0.0.0.0') {
      return true;
    }
    return host.startsWith('10.') ||
        host.startsWith('192.168.') ||
        host.startsWith('172.') ||
        host.startsWith('169.254.');
  }
}

class ModelInfo {
  const ModelInfo(
      {required this.id,
      this.ownedBy,
      this.capabilities = const ModelCapabilities()});
  final String id;
  final String? ownedBy;
  final ModelCapabilities capabilities;
}

class ModelCapabilities {
  const ModelCapabilities(
      {this.streaming = true,
      this.tools = true,
      this.vision = false,
      this.jsonMode = true});
  final bool streaming;
  final bool tools;
  final bool vision;
  final bool jsonMode;

  static ModelCapabilities infer(String modelId) {
    final lower = modelId.toLowerCase();
    return ModelCapabilities(
      vision: lower.contains('vision') ||
          lower.contains('4o') ||
          lower.contains('gemini') ||
          lower.contains('claude-3'),
      tools: !lower.contains('embedding') &&
          !lower.contains('tts') &&
          !lower.contains('whisper'),
    );
  }
}
