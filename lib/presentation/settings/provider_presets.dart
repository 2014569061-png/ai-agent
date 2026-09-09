import '../../infrastructure/providers/provider_config.dart';

class ProviderPresetModel {
  const ProviderPresetModel({
    required this.id,
    required this.displayName,
    this.contextTokens,
    this.reasoning = false,
    this.vision = false,
    this.tools = true,
    this.jsonMode = true,
  });

  final String id;
  final String displayName;
  final int? contextTokens;
  final bool reasoning;
  final bool vision;
  final bool tools;
  final bool jsonMode;
}

class ProviderPreset {
  const ProviderPreset({
    required this.name,
    required this.baseUrl,
    required this.defaultModel,
    this.type = ProviderType.openaiCompatible,
    this.description = '',
    this.models = const [],
  });

  final String name;
  final String baseUrl;
  final String defaultModel;
  final ProviderType type;
  final String description;
  final List<ProviderPresetModel> models;
}

const providerPresets = <ProviderPreset>[
  ProviderPreset(
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    defaultModel: 'gpt-5',
    description: 'GPT 系列官方 API',
    models: [
      ProviderPresetModel(
          id: 'gpt-5', displayName: 'GPT-5', reasoning: true, vision: true),
      ProviderPresetModel(id: 'gpt-4o', displayName: 'GPT-4o', vision: true),
      ProviderPresetModel(
          id: 'gpt-4o-mini', displayName: 'GPT-4o mini', vision: true),
    ],
  ),
  ProviderPreset(
    name: 'Claude',
    baseUrl: 'https://api.anthropic.com',
    defaultModel: 'claude-sonnet-4-20250514',
    type: ProviderType.anthropic,
    description: 'Anthropic Claude Messages API',
    models: [
      ProviderPresetModel(
          id: 'claude-sonnet-4-20250514',
          displayName: 'Claude Sonnet 4',
          vision: true),
      ProviderPresetModel(
          id: 'claude-3-7-sonnet-20250219',
          displayName: 'Claude 3.7 Sonnet',
          vision: true,
          reasoning: true),
      ProviderPresetModel(
          id: 'claude-3-5-haiku-20241022',
          displayName: 'Claude 3.5 Haiku',
          vision: true),
    ],
  ),
  ProviderPreset(
    name: 'Gemini',
    baseUrl: 'https://generativelanguage.googleapis.com',
    defaultModel: 'gemini-2.5-flash',
    type: ProviderType.gemini,
    description: 'Google Gemini API',
    models: [
      ProviderPresetModel(
          id: 'gemini-2.5-pro',
          displayName: 'Gemini 2.5 Pro',
          reasoning: true,
          vision: true),
      ProviderPresetModel(
          id: 'gemini-2.5-flash',
          displayName: 'Gemini 2.5 Flash',
          vision: true),
    ],
  ),
  ProviderPreset(
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    defaultModel: 'deepseek-chat',
    description: 'DeepSeek Chat / Reasoner',
    models: [
      ProviderPresetModel(
          id: 'deepseek-chat',
          displayName: 'DeepSeek-V3',
          contextTokens: 64000),
      ProviderPresetModel(
          id: 'deepseek-reasoner',
          displayName: 'DeepSeek-R1',
          contextTokens: 64000,
          reasoning: true),
    ],
  ),
  ProviderPreset(
    name: 'Kimi（月之暗面）',
    baseUrl: 'https://api.moonshot.cn/v1',
    defaultModel: 'moonshot-v1-8k',
    description: 'Moonshot Kimi OpenAI 兼容 API',
    models: [
      ProviderPresetModel(
          id: 'moonshot-v1-8k',
          displayName: 'Moonshot 8K',
          contextTokens: 8000),
      ProviderPresetModel(
          id: 'moonshot-v1-32k',
          displayName: 'Moonshot 32K',
          contextTokens: 32000),
      ProviderPresetModel(
          id: 'moonshot-v1-128k',
          displayName: 'Moonshot 128K',
          contextTokens: 128000),
    ],
  ),
  ProviderPreset(
    name: 'Qwen（通义千问）',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    defaultModel: 'qwen-plus',
    description: '阿里云百炼 OpenAI 兼容 API',
    models: [
      ProviderPresetModel(
          id: 'qwen-plus', displayName: 'Qwen Plus', contextTokens: 128000),
      ProviderPresetModel(
          id: 'qwen-max', displayName: 'Qwen Max', contextTokens: 32768),
      ProviderPresetModel(
          id: 'qwen-turbo', displayName: 'Qwen Turbo', contextTokens: 128000),
    ],
  ),
  ProviderPreset(
    name: 'GLM（智谱）',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    defaultModel: 'glm-4-air',
    description: '智谱 GLM OpenAI 兼容 API',
    models: [
      ProviderPresetModel(
          id: 'glm-4-plus',
          displayName: 'GLM-4 Plus',
          contextTokens: 128000,
          reasoning: true),
      ProviderPresetModel(
          id: 'glm-4-air', displayName: 'GLM-4 Air', contextTokens: 128000),
      ProviderPresetModel(
          id: 'glm-4-flash', displayName: 'GLM-4 Flash', contextTokens: 128000),
    ],
  ),
  ProviderPreset(
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    defaultModel: 'openai/gpt-5',
    description: '多模型聚合 API',
    models: [ProviderPresetModel(id: 'openai/gpt-5', displayName: 'GPT-5')],
  ),
  ProviderPreset(
    name: 'Ollama',
    baseUrl: 'http://localhost:11434/v1',
    defaultModel: 'llama3.2',
    description: '本地 Ollama 模型',
    models: [ProviderPresetModel(id: 'llama3.2', displayName: 'Llama 3.2')],
  ),
];

ProviderPreset? presetForConfig(ProviderConfig config) {
  for (final preset in providerPresets) {
    if (preset.baseUrl == config.baseUrl || preset.name == config.name) {
      return preset;
    }
  }
  return null;
}
