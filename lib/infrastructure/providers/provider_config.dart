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
    this.reasoningEffort = ReasoningEffort.auto,
    this.contextTokens = defaultContextTokens,
    this.inputPricePerMillionCents,
    this.outputPricePerMillionCents,
    this.cachedPricePerMillionCents,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String model;
  final String apiKey;
  final ProviderType type;
  final ReasoningEffort reasoningEffort;
  final int contextTokens;

  /// 可选的每百万 Token 价格（单位：分）。为空时使用本地模型价目表，
  /// 这样新增模型不会静默显示 0 成本，同时允许服务商自定义价格。
  final int? inputPricePerMillionCents;
  final int? outputPricePerMillionCents;
  final int? cachedPricePerMillionCents;

  ProviderConfig copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? model,
    String? apiKey,
    ProviderType? type,
    ReasoningEffort? reasoningEffort,
    int? contextTokens,
    int? inputPricePerMillionCents,
    int? outputPricePerMillionCents,
    int? cachedPricePerMillionCents,
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
        inputPricePerMillionCents:
            inputPricePerMillionCents ?? this.inputPricePerMillionCents,
        outputPricePerMillionCents:
            outputPricePerMillionCents ?? this.outputPricePerMillionCents,
        cachedPricePerMillionCents:
            cachedPricePerMillionCents ?? this.cachedPricePerMillionCents,
      );

  /// 本次运行实际使用的上下文窗口。[contextTokens] 仍是默认值（视为“未
  /// 设置”）且模型在已知表中时，按模型自动推断（见 [ModelContextWindows]）；
  /// 用户显式填过的值一律尊重。本地地址（Ollama 等）的实际窗口取决于本地
  /// 加载参数，不做推断。
  int get effectiveContextTokens {
    if (contextTokens != defaultContextTokens) return contextTokens;
    if (isLocalBaseUrl(baseUrl)) return contextTokens;
    return ModelContextWindows.autoFor(model) ?? contextTokens;
  }

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

/// 常见模型的上下文窗口（按模型名推断，偏保守）。
///
/// 自动值封顶 [autoCap]：窗口越大，每次请求携带的历史越多、费用越高；需要
/// 更大窗口时可在服务商设置中手动填写。
abstract final class ModelContextWindows {
  static const autoCap = 128000;

  /// 自动采用的窗口；未知模型返回 null。
  static int? autoFor(String model) {
    final known = knownFor(model);
    if (known == null) return null;
    return known > autoCap ? autoCap : known;
  }

  /// 模型标称的上下文窗口；未知模型返回 null。
  static int? knownFor(String model) {
    final lower = model.trim().toLowerCase();
    if (lower.isEmpty) return null;
    final name = lower.contains('/') ? lower.split('/').last : lower;
    // 名称自带窗口大小：step-1-32k、moonshot-v1-128k 等。
    final sized = RegExp(r'-(\d{1,4})k(?:$|[-_.])').firstMatch(name);
    if (sized != null) return int.parse(sized.group(1)!) * 1000;
    if (name.startsWith('step-5')) return 1000000;
    if (name.startsWith('step-3.7') || name.startsWith('step-3.5')) {
      return 256000;
    }
    if (name.startsWith('step-3')) return 64000;
    if (name.startsWith('deepseek-')) return 128000;
    if (name.startsWith('gpt-5')) return 400000;
    if (name.startsWith('gpt-4.1')) return 1000000;
    if (name.startsWith('gpt-4o') || name.startsWith('gpt-4-turbo')) {
      return 128000;
    }
    if (name.startsWith('o1') || name.startsWith('o3') || name.startsWith('o4')) {
      return 200000;
    }
    if (name.startsWith('claude-')) return 200000;
    if (name.startsWith('gemini-')) return 1000000;
    if (name.startsWith('qwen3') ||
        name.startsWith('qwen-plus') ||
        name.startsWith('qwen-turbo') ||
        name.startsWith('qwen-long')) {
      return 128000;
    }
    if (name.startsWith('kimi-k2')) return 128000;
    if (name.startsWith('glm-4.5') || name.startsWith('glm-4.6')) {
      return 128000;
    }
    return null;
  }
}
