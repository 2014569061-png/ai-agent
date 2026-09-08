import 'dart:io';

import '../l10n/app_strings.dart';
import '../widgets/floating_toast.dart';
import '../widgets/immersive_dropdown.dart';
import '../widgets/immersive_sheet.dart';
import '../widgets/section_card.dart';
import '../widgets/nexus_page_header.dart';
import '../theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../application/chat_controller.dart';
import '../../application/autonomous_delegation.dart';
import '../../application/error_humanizer.dart';
import '../../domain/models.dart';
import 'update_sheet.dart';
import '../../infrastructure/mcp/mcp_server_config.dart';
import '../../infrastructure/providers/provider_config.dart';
import '../../infrastructure/providers/provider_config_store.dart';
import '../../infrastructure/providers/openai_compatible_provider.dart';
import '../../infrastructure/providers/proxy_provider.dart';
import '../../infrastructure/providers/anthropic_provider.dart';
import '../../infrastructure/providers/gemini_provider.dart';
import '../theme/app_theme_controller.dart';
import '../chat/chat_layout_controller.dart';
import '../memory/memory_page.dart';
import '../knowledge/knowledge_page.dart';
import '../scheduled/scheduled_tasks_page.dart';
import '../sync/sync_page.dart';
import '../vault/vault_page.dart';
import '../audit/audit_log_page.dart';
import '../diagnostics/log_viewer_page.dart';
import '../account/compliance_page.dart';
import '../feedback/feedback_page.dart';
import '../plugins/plugins_page.dart';
import '../mcp/mcp_servers_page.dart';
import '../../application/app_lock_service.dart';
import '../../application/mcp_service.dart';
import '../../infrastructure/observability/sentry_service.dart';
import '../../infrastructure/system/battery_optimization.dart';
import '../../infrastructure/update/update_service.dart';
import '../onboarding/onboarding_page.dart';
import '../../infrastructure/background_service.dart';

class _ProviderTemplate {
  const _ProviderTemplate(this.name, this.baseUrl, this.model,
      {this.type = ProviderType.openaiCompatible});
  final String name;
  final String baseUrl;
  final String model;
  final ProviderType type;
}

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String? _saveBannerMessage;
  String? _testStatusMessage;

  static const _adaptiveWidth = 'adaptive';
  static const _compactWidth = 'compact';
  static const _standardWidth = 'standard';
  static const _wideWidth = 'wide';
  static const _customWidth = 'custom';

  static const _templates = <_ProviderTemplate>[
    _ProviderTemplate('OpenAI', 'https://api.openai.com/v1', 'gpt-4o-mini'),
    _ProviderTemplate(
        'Anthropic', 'https://api.anthropic.com', 'claude-3-5-sonnet-20241022',
        type: ProviderType.anthropic),
    _ProviderTemplate('Gemini', 'https://generativelanguage.googleapis.com',
        'gemini-1.5-flash',
        type: ProviderType.gemini),
    _ProviderTemplate(
        'DeepSeek', 'https://api.deepseek.com/v1', 'deepseek-chat'),
    _ProviderTemplate(
        'OpenRouter', 'https://openrouter.ai/api/v1', 'openai/gpt-4o-mini'),
    _ProviderTemplate(
        'Groq', 'https://api.groq.com/openai/v1', 'llama-3.3-70b-versatile'),
    _ProviderTemplate('Together AI', 'https://api.together.xyz/v1',
        'meta-llama/Llama-3.3-70B-Instruct-Turbo'),
    _ProviderTemplate('Ollama', 'http://localhost:11434/v1', 'llama3.2'),
  ];
  final _name = TextEditingController();
  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  final _apiKey = TextEditingController();
  final _tavilyKey = TextEditingController();
  final _contextTokens = TextEditingController();
  final _store = ProviderConfigStore();
  final _mcpService = McpService();
  List<ProviderConfig> _profiles = [];
  String _selectedId = 'default';
  ProviderType _type = ProviderType.openaiCompatible;
  ReasoningEffort _reasoningEffort = ReasoningEffort.medium;
  bool _loading = true;
  String? _loadError;
  bool _saving = false;
  bool _testing = false;
  bool _loadingModels = false;
  bool _obscureApiKey = true;
  bool _showAdvanced = true;
  List<ModelInfo> _models = [];
  List<McpServerConfig> _mcpServers = [];
  final _appLock = AppLockService();
  bool _appLockEnabled = false;
  bool _appLockSupported = false;
  bool _crashReportEnabled = false;
  bool _ignoringBattery = true;
  final _autonomousDelegation = AutonomousDelegationService();
  bool _autonomousDelegationEnabled = true;

  bool get _isInsecureRemoteUrl {
    final uri = Uri.tryParse(_baseUrl.text.trim());
    return uri?.scheme.toLowerCase() == 'http' &&
        !ProviderConfig.isLocalBaseUrl(_baseUrl.text.trim());
  }

  String _widthOption(double widthFactor) {
    if (widthFactor == ChatLayoutController.adaptive) return _adaptiveWidth;
    if (widthFactor == .62) return _compactWidth;
    if (widthFactor == .72) return _standardWidth;
    if (widthFactor == .86) return _wideWidth;
    return _customWidth;
  }

  double _defaultCustomWidth(double widthFactor) =>
      _widthOption(widthFactor) == _customWidth
          ? widthFactor
          : ChatLayoutController.customDefault;

  final BackgroundService _backgroundService = BackgroundService();
  final UpdateService _updateService = UpdateService();
  final String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _name.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    _tavilyKey.dispose();
    _contextTokens.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统电池授权弹窗返回后刷新豁免状态。
    if (state == AppLifecycleState.resumed && !kIsWeb) {
      BatteryOptimization.isIgnoring().then((ignoring) {
        if (mounted && ignoring != _ignoringBattery) {
          setState(() => _ignoringBattery = ignoring);
        }
      });
    }
  }

  Future<void> _load() async {
    try {
      final config = await _store.load();
      _profiles = await _store.loadAll();
      _fill(config);
      _tavilyKey.text = await _store.readToolKey('tavily');
      _mcpServers = await _mcpService.loadAll();
      _appLockEnabled = await _appLock.isEnabled();
      _appLockSupported = await _appLock.canUseBiometrics();
      _crashReportEnabled = await SentryService.isEnabled();
      _autonomousDelegationEnabled = await _autonomousDelegation.isEnabled();
      // 计划模式已迁移到 chatControllerProvider 单一数据源；这里只做旧值的只读迁移。
      final legacyPrefs = await SharedPreferences.getInstance();
      final legacyPlanMode = legacyPrefs.getBool('plan_mode');
      if (legacyPlanMode != null) {
        ref.read(chatControllerProvider.notifier).setPlanMode(legacyPlanMode);
        await legacyPrefs.remove('plan_mode');
      }
      if (!kIsWeb) {
        try {
          _ignoringBattery = await BatteryOptimization.isIgnoring();
        } catch (_) {}
      }
    } catch (error) {
      _loadError = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fill(ProviderConfig config) {
    _selectedId = config.id;
    _type = config.type;
    _name.text = config.name;
    _baseUrl.text = config.baseUrl;
    _model.text = config.model;
    _apiKey.text = config.apiKey;
    _reasoningEffort = config.reasoningEffort;
    _contextTokens.text = config.contextTokens.toString();
  }

  Future<void> _toggleAppLock(bool value) async {
    if (value) {
      // 开启前先验证一次身份，确认设备生物识别可用。
      final ok = await _appLock.authenticate();
      if (!ok) {
        if (mounted) FloatingToast.show(context, '身份验证未通过，未开启应用锁');
        return;
      }
    }
    await _appLock.setEnabled(value);
    if (mounted) setState(() => _appLockEnabled = value);
  }

  Future<void> _toggleCrashReport(bool value) async {
    await SentryService.setEnabled(value);
    if (mounted) {
      setState(() => _crashReportEnabled = value);
      FloatingToast.show(context, value ? '已开启匿名崩溃上报' : '已关闭崩溃上报');
    }
  }

  Future<void> _toggleAutonomousDelegation(bool value) async {
    await _autonomousDelegation.setEnabled(value);
    if (mounted) {
      setState(() => _autonomousDelegationEnabled = value);
      FloatingToast.show(
        context,
        value ? '已开启自主委派子 Agent' : '已关闭自主委派（子 Agent 调用需逐次审批）',
      );
    }
  }

  Future<void> _togglePlanMode(bool value) async {
    ref.read(chatControllerProvider.notifier).setPlanMode(value);
  }

  Future<void> _requestBatteryExemption() async {
    final launched = await BatteryOptimization.requestIgnore();
    if (!mounted) return;
    if (!launched) {
      FloatingToast.show(context, '当前系统不支持，请手动前往系统设置');
    }
  }

  Future<void> _checkUpdate() async {
    final result = await _updateService.checkUpdate();
    if (!mounted) return;
    switch (result.status) {
      case UpdateCheckStatus.update:
        showImmersiveSheet(
          context: context,
          builder: (_) => UpdateSheet(info: result.info!),
        );
      case UpdateCheckStatus.upToDate:
        FloatingToast.show(
            context, '当前已是最新版本 v${result.currentVersion ?? _appVersion}');
      case UpdateCheckStatus.failed:
        FloatingToast.show(context, result.error ?? '检测失败');
    }
  }

  void _select(String? id) {
    if (id == null) return;
    _fill(_profiles.firstWhere((profile) => profile.id == id));
    setState(() {});
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final id = _selectedId == 'default' && _profiles.isEmpty
          ? 'provider-${DateTime.now().millisecondsSinceEpoch}'
          : _selectedId;
      final parsedContextTokens = int.tryParse(_contextTokens.text.trim());
      final contextTokens = parsedContextTokens == null
          ? ProviderConfig.defaultContextTokens
          : parsedContextTokens.clamp(4000, 2000000).toInt();
      await _store.save(ProviderConfig(
          id: id,
          name: _name.text.trim().isEmpty ? 'Provider' : _name.text.trim(),
          baseUrl: _baseUrl.text,
          model: _model.text,
          apiKey: _apiKey.text,
          type: _type,
          reasoningEffort: _reasoningEffort,
          contextTokens: contextTokens));
      await _store.saveToolKey('tavily', _tavilyKey.text);
      _profiles = await _store.loadAll();
      _selectedId = id;
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveBannerMessage =
            '配置已保存成功，当前生效服务商：${_name.text.trim().isEmpty ? "默认服务商" : _name.text.trim()}';
      });
      FloatingToast.show(context, AppStrings.providerConfigSaved);
    } catch (error) {
      if (mounted) FloatingToast.error(context, error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  ProviderConfig get _currentConfig => ProviderConfig(
        id: _selectedId,
        name: _name.text.trim(),
        baseUrl: _baseUrl.text.trim(),
        model: _model.text.trim(),
        apiKey: _apiKey.text.trim(),
        type: _type,
        reasoningEffort: _reasoningEffort,
        contextTokens: (int.tryParse(_contextTokens.text.trim()) ??
                ProviderConfig.defaultContextTokens)
            .clamp(4000, 2000000)
            .toInt(),
      );

  Future<String?> _runTestConnection() {
    final config = _currentConfig;
    switch (config.type) {
      case ProviderType.anthropic:
        return AnthropicProvider(config: config).testConnection();
      case ProviderType.gemini:
        return GeminiProvider(config: config).testConnection();
      case ProviderType.openaiCompatible:
        return OpenAiCompatibleProvider(config: config).testConnection();
      case ProviderType.proxy:
        return ProxyProvider(
                backendBaseUrl: config.baseUrl,
                managedKey: config.apiKey,
                model: config.model)
            .testConnection();
    }
  }

  Future<void> _testConnection() async {
    if (_baseUrl.text.trim().isEmpty || _apiKey.text.trim().isEmpty) {
      FloatingToast.show(context, AppStrings.fillBaseUrlAndKey);
      return;
    }
    setState(() {
      _testing = true;
      _testStatusMessage = '正在连接 ${_baseUrl.text.trim()}…';
      _saveBannerMessage = null;
    });
    String? error;
    try {
      error = await _runTestConnection();
    } catch (exception) {
      error = exception.toString();
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testStatusMessage = error == null ? '连接测试成功，服务响应正常！' : '连接测试失败：$error';
    });
    if (error == null) {
      // 测试成功的就是当前输入配置；立即持久化，确保聊天发送读取到同一份配置。
      final config = _currentConfig;
      await _store.save(config);
      _profiles = await _store.loadAll();
      _selectedId = config.id;
      if (!mounted) return;
      setState(() {});
      FloatingToast.show(context, AppStrings.connectionSuccess);
      return;
    }
    FloatingToast.show(
      context,
      '连接失败：$error',
      tone: ToastTone.danger,
      persistent: true,
      actions: [
        FloatingCapsuleAction(
          label: '重试',
          onPressed: _testConnection,
        ),
      ],
    );
  }

  Future<void> _loadModels() async {
    if (_type != ProviderType.openaiCompatible) {
      FloatingToast.show(context, AppStrings.onlyOpenAiCompatible);
      return;
    }
    if (_baseUrl.text.trim().isEmpty || _apiKey.text.trim().isEmpty) return;
    setState(() => _loadingModels = true);
    try {
      _models =
          await OpenAiCompatibleProvider(config: _currentConfig).listModels();
      if (mounted) setState(() {});
      if (mounted && _models.isEmpty) {
        FloatingToast.show(context, AppStrings.noModelsReturned);
      }
    } catch (error) {
      if (mounted) FloatingToast.show(context, '获取模型失败：$error');
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(
                humanizeError(_loadError ?? '').summary,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _loadError = null;
                  });
                  _load();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ]),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: NexusPageHeader(
        title: AppStrings.providerSettings,
        bottom: TabBar(
          controller: _tabController,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: const [
            Tab(text: '服务商与模型'),
            Tab(text: 'Agent与工具'),
            Tab(text: '系统与安全'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: _buildProviderTab(context),
          ),
          ListView(
            padding: const EdgeInsets.all(16),
            children: _buildAgentAndToolsTab(context),
          ),
          ListView(
            padding: const EdgeInsets.all(16),
            children: _buildSystemAndSecurityTab(context),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 分组 1: 服务商与模型
  // ==========================================
  List<Widget> _buildProviderTab(BuildContext context) {
    return [
      if (_saveBannerMessage != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.success.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: AppTheme.success, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _saveBannerMessage!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.success,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () => setState(() => _saveBannerMessage = null),
                ),
              ],
            ),
          ),
        ),
      if (_testStatusMessage != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: (_testStatusMessage!.contains('成功')
                      ? AppTheme.success
                      : (_testStatusMessage!.contains('失败')
                          ? AppTheme.danger
                          : AppTheme.brandBright))
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (_testStatusMessage!.contains('成功')
                        ? AppTheme.success
                        : (_testStatusMessage!.contains('失败')
                            ? AppTheme.danger
                            : AppTheme.brandBright))
                    .withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _testStatusMessage!.contains('成功')
                      ? Icons.check_circle_outline_rounded
                      : (_testStatusMessage!.contains('失败')
                          ? Icons.error_outline_rounded
                          : Icons.sync_rounded),
                  size: 18,
                  color: _testStatusMessage!.contains('成功')
                      ? AppTheme.success
                      : (_testStatusMessage!.contains('失败')
                          ? AppTheme.danger
                          : AppTheme.brandBright),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _testStatusMessage!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _testStatusMessage!.contains('成功')
                          ? AppTheme.success
                          : (_testStatusMessage!.contains('失败')
                              ? AppTheme.danger
                              : AppTheme.brandBright),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () => setState(() => _testStatusMessage = null),
                ),
              ],
            ),
          ),
        ),
      const _SectionHeader(icon: Icons.cloud_outlined, title: '服务商选择'),
      SectionCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ImmersiveDropdown<String>(
                labelText: AppStrings.quickApplyTemplate,
                items: _templates
                    .map((template) => DropdownMenuItem(
                        value: template.name, child: Text(template.name)))
                    .toList(),
                onChanged: (name) {
                  if (name == null) return;
                  final template =
                      _templates.firstWhere((item) => item.name == name);
                  setState(() {
                    _name.text = template.name;
                    _baseUrl.text = template.baseUrl;
                    _model.text = template.model;
                    _type = template.type;
                    _models = [];
                  });
                },
              ),
              const SizedBox(height: 16),
              ImmersiveDropdown<ProviderType>(
                labelText: AppStrings.protocolType,
                initialValue: _type,
                items: const [
                  DropdownMenuItem(
                      value: ProviderType.openaiCompatible,
                      child: Text('OpenAI 兼容')),
                  DropdownMenuItem(
                      value: ProviderType.anthropic, child: Text('Anthropic')),
                  DropdownMenuItem(
                      value: ProviderType.gemini, child: Text('Gemini')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _type = value);
                },
              ),
              if (_profiles.isNotEmpty) ...[
                const SizedBox(height: 16),
                ImmersiveDropdown<String>(
                    labelText: AppStrings.savedProviders,
                    initialValue: _selectedId,
                    items: _profiles
                        .map<DropdownMenuItem<String>>((p) =>
                            DropdownMenuItem<String>(
                                value: p.id, child: Text(p.name)))
                        .toList(),
                    onChanged: _select),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      const _SectionHeader(icon: Icons.link_outlined, title: '连接配置'),
      SectionCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: AppStrings.providerName,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _baseUrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: AppStrings.baseUrl,
                ),
              ),
              if (_isInsecureRemoteUrl) ...[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 16, color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '远程服务使用 HTTP，API Key 和对话内容可能被窃听。生产环境建议改用 HTTPS。',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _model,
                    decoration: const InputDecoration(
                      labelText: AppStrings.modelName,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _loadingModels ? null : _loadModels,
                  icon: _loadingModels
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                  tooltip: '获取模型列表',
                ),
              ]),
              if (_models.isNotEmpty) ...[
                const SizedBox(height: 10),
                ImmersiveDropdown<String>(
                    labelText: '从列表选择',
                    initialValue: _models.any((item) => item.id == _model.text)
                        ? _model.text
                        : null,
                    items: _models
                        .map<DropdownMenuItem<String>>((item) =>
                            DropdownMenuItem<String>(
                                value: item.id,
                                child: Text(item.id,
                                    overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _model.text = value);
                      }
                    }),
                const SizedBox(height: 8),
                if (_models.any((item) => item.id == _model.text))
                  Builder(builder: (context) {
                    final capabilities = _models
                        .firstWhere((item) => item.id == _model.text)
                        .capabilities;
                    return Wrap(spacing: 6, children: [
                      if (capabilities.streaming) const Chip(label: Text('流式')),
                      if (capabilities.tools) const Chip(label: Text('工具调用')),
                      if (capabilities.vision) const Chip(label: Text('视觉')),
                      if (capabilities.jsonMode)
                        const Chip(label: Text('JSON')),
                    ]);
                  }),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: _apiKey,
                obscureText: _obscureApiKey,
                decoration: InputDecoration(
                  labelText: AppStrings.apiKey,
                  suffixIcon: IconButton(
                    icon: Icon(_obscureApiKey
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setState(() => _obscureApiKey = !_obscureApiKey),
                  ),
                  helperText:
                      kIsWeb ? 'web 端密钥保存在浏览器 localStorage（明文），请注意使用环境' : null,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      GestureDetector(
        onTap: () => setState(() => _showAdvanced = !_showAdvanced),
        child: Row(
          children: [
            const _SectionHeader(icon: Icons.tune_outlined, title: '模型与高级参数'),
            const Spacer(),
            Icon(_showAdvanced ? Icons.expand_less : Icons.expand_more,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
          ],
        ),
      ),
      if (_showAdvanced)
        SectionCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: _tavilyKey,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: AppStrings.tavilyApiKey,
                ),
              ),
              const SizedBox(height: 16),
              Text('思考程度',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              SegmentedButton<ReasoningEffort>(
                segments: const [
                  ButtonSegment(value: ReasoningEffort.low, label: Text('低')),
                  ButtonSegment(
                      value: ReasoningEffort.medium, label: Text('中')),
                  ButtonSegment(value: ReasoningEffort.high, label: Text('高')),
                ],
                selected: {_reasoningEffort},
                onSelectionChanged: (selected) {
                  setState(() => _reasoningEffort = selected.first);
                },
              ),
              const SizedBox(height: 16),
              Text(
                '上下文窗口上限（Token）',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _contextTokens,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: '${ProviderConfig.defaultContextTokens}',
                  helperText: '留空默认 128k Token。若服务商支持更大（如 1M/2M），可在此填入。',
                ),
              ),
            ]),
          ),
        ),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(
            child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label:
                    Text(_saving ? AppStrings.saving : AppStrings.saveConfig))),
        const SizedBox(width: 8),
        Expanded(
            child: OutlinedButton.icon(
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_tethering),
                label: Text(_testing
                    ? AppStrings.testing
                    : AppStrings.testConnection))),
      ]),
      const SizedBox(height: 24),
    ];
  }

  // ==========================================
  // 分组 2: Agent 与工具
  // ==========================================
  List<Widget> _buildAgentAndToolsTab(BuildContext context) {
    return [
      _buildMcpSection(context),
      const SizedBox(height: 16),
      const _SectionHeader(
          icon: Icons.auto_awesome_outlined, title: 'Agent 增强能力'),
      SectionCard(
        child: Column(children: [
          ListTile(
            minVerticalPadding: 6,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            leading: const Icon(Icons.psychology_outlined),
            title: const Text(AppStrings.memoryEntry),
            subtitle: const Text(AppStrings.memoryHint),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const MemoryPage())),
          ),
          const Divider(height: 1, indent: 56, endIndent: 16),
          ListTile(
            minVerticalPadding: 6,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            leading: const Icon(Icons.library_books_outlined),
            title: const Text('知识库'),
            subtitle: const Text('文档入库 + 对话检索注入（RAG）'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const KnowledgePage())),
          ),
          const Divider(height: 1, indent: 56, endIndent: 16),
          ListTile(
            minVerticalPadding: 6,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('定时任务'),
            subtitle: const Text('到点自动运行 Agent 并通知结果'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ScheduledTasksPage())),
          ),
          if (!kIsWeb) ...[
            const Divider(height: 1, indent: 56, endIndent: 16),
            ListTile(
              minVerticalPadding: 6,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: const Icon(Icons.battery_saver_outlined),
              title: const Text('电池优化豁免'),
              subtitle: Text(_ignoringBattery
                  ? '已加入系统白名单，定时任务可按时触发'
                  : '未加入白名单，激进省电可能导致定时任务延迟'),
              trailing: _ignoringBattery
                  ? const Icon(Icons.check_circle, color: AppTheme.success)
                  : const Icon(Icons.chevron_right),
              onTap: _requestBatteryExemption,
            ),
          ],
          const Divider(height: 1, indent: 56, endIndent: 16),
          SwitchListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            secondary: const Icon(Icons.checklist),
            title: const Text('计划模式'),
            subtitle: const Text('先输出执行计划，确认后才调用工具'),
            value: ref.watch(chatControllerProvider).planMode,
            onChanged: (value) => _togglePlanMode(value),
          ),
          const Divider(height: 1, indent: 56, endIndent: 16),
          ListTile(
            minVerticalPadding: 6,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            leading: const Icon(Icons.extension_outlined),
            title: const Text('插件'),
            subtitle: const Text('导入声明式工具包 / Agent 预设'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const PluginsPage())),
          ),
        ]),
      ),
      const SizedBox(height: 24),
    ];
  }

  // ==========================================
  // 分组 3: 系统与安全
  // ==========================================
  List<Widget> _buildSystemAndSecurityTab(BuildContext context) {
    return [
      _buildAccountSection(context),
      const SizedBox(height: 16),
      const _SectionHeader(icon: Icons.security_outlined, title: '安全与隐私'),
      SectionCard(
        child: Column(children: [
          SwitchListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            secondary: const Icon(Icons.fingerprint),
            title: const Text(AppStrings.appLock),
            subtitle: Text(
                _appLockSupported ? AppStrings.appLockHint : '当前设备不支持生物识别'),
            value: _appLockEnabled,
            onChanged: _appLockSupported ? _toggleAppLock : null,
          ),
          const Divider(height: 1, indent: 56, endIndent: 16),
          ListTile(
            minVerticalPadding: 6,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            leading: const Icon(Icons.shield_outlined),
            title: const Text('隐私保险箱'),
            subtitle: const Text('加密导出 / 密码导入全量数据'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const VaultPage())),
          ),
          const Divider(height: 1, indent: 56, endIndent: 16),
          SwitchListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            secondary: const Icon(Icons.smart_toy_outlined),
            title: const Text('自主委派子 Agent'),
            subtitle: const Text('主 Agent 可自动派生子任务；关闭后子 Agent 调用需逐次审批'),
            value: _autonomousDelegationEnabled,
            onChanged: _toggleAutonomousDelegation,
          ),
          const Divider(height: 1, indent: 56, endIndent: 16),
          ListTile(
            minVerticalPadding: 6,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            leading: const Icon(Icons.security_outlined),
            title: const Text('审计日志'),
            subtitle: const Text('工具调用审批链路记录与导出'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const AuditLogPage())),
          ),
          const Divider(height: 1, indent: 56, endIndent: 16),
          ListTile(
            minVerticalPadding: 6,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('诊断日志'),
            subtitle: const Text('查看模型、工具和文件操作的运行日志'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const LogViewerPage())),
          ),
          const Divider(height: 1, indent: 56, endIndent: 16),
          ListTile(
            minVerticalPadding: 6,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            leading: const Icon(Icons.cloud_sync_outlined),
            title: const Text('云同步（Pro）'),
            subtitle: const Text('恢复码 + 端到端加密多设备同步'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SyncPage())),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      const _SectionHeader(icon: Icons.wallpaper_outlined, title: '聊天背景'),
      SectionCard(
        child: FutureBuilder<BackgroundConfig>(
          future: _backgroundService.load(),
          builder: (context, snapshot) {
            final current =
                snapshot.data ?? const BackgroundConfig(mode: 'default');
            Widget option(String mode, String title, String subtitle,
                {Widget? leading, VoidCallback? onTap}) {
              final selected = current.mode == mode;
              return ListTile(
                leading: leading ??
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).hintColor,
                    ),
                title: Text(title),
                subtitle: Text(subtitle),
                onTap: onTap ??
                    () async {
                      await _backgroundService.setMode(mode);
                      if (mounted) setState(() {});
                    },
              );
            }

            return Column(children: [
              option('default', '默认(跟随主题)', '浅色纯白渐变 / 深色纯黑,与顶栏最统一'),
              option('clouds', '云朵栈桥', '内置插画背景',
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Image.asset(BackgroundService.cloudsAsset,
                          fit: BoxFit.cover),
                    ),
                  )),
              option(
                current.mode == 'custom' ? 'custom' : 'custom_pick',
                '自定义图片',
                current.mode == 'custom' ? '使用相册选择的图片(点此重新选择)' : '从相册选择一张图片',
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child:
                        (current.mode == 'custom' && current.customPath != null)
                            ? Image.file(File(current.customPath!),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.broken_image_outlined))
                            : const Icon(Icons.image_outlined),
                  ),
                ),
                onTap: () async {
                  try {
                    final x = await ImagePicker()
                        .pickImage(source: ImageSource.gallery);
                    if (x == null) return;
                    await _backgroundService.setCustomBackground(x.path);
                    if (mounted) setState(() {});
                  } catch (_) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(content: Text('选图失败,请重试')),
                    );
                  }
                },
              ),
            ]);
          },
        ),
      ),
      const SizedBox(height: 16),
      const _SectionHeader(icon: Icons.tune_outlined, title: '界面与其他'),
      SectionCard(
        child: Column(children: [
          ValueListenableBuilder<ThemeMode>(
            valueListenable: AppThemeController.mode,
            builder: (context, mode, _) => SwitchListTile(
              secondary: Icon(mode == ThemeMode.light
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined),
              title: const Text(AppStrings.dayMode),
              subtitle: Text(mode == ThemeMode.light
                  ? AppStrings.dayModeSubtitle
                  : AppStrings.darkModeSubtitle),
              value: mode == ThemeMode.light,
              onChanged: AppThemeController.setDayMode,
            ),
          ),
          const Divider(height: 1),
          ValueListenableBuilder<double>(
            valueListenable: ChatLayoutController.widthFactor,
            builder: (context, widthFactor, _) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('对话气泡宽度', style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 12),
                    ImmersiveDropdown<String>(
                      key: ValueKey(_widthOption(widthFactor)),
                      labelText: '宽度模式',
                      initialValue: _widthOption(widthFactor),
                      items: const [
                        DropdownMenuItem(
                            value: _adaptiveWidth, child: Text('自适应')),
                        DropdownMenuItem(
                            value: _compactWidth, child: Text('紧凑')),
                        DropdownMenuItem(
                            value: _standardWidth, child: Text('标准')),
                        DropdownMenuItem(value: _wideWidth, child: Text('宽松')),
                        DropdownMenuItem(
                            value: _customWidth, child: Text('自定义')),
                      ],
                      onChanged: (selection) {
                        if (selection == null) return;
                        final value = switch (selection) {
                          _adaptiveWidth => ChatLayoutController.adaptive,
                          _compactWidth => .62,
                          _standardWidth => .72,
                          _wideWidth => .86,
                          _ => _defaultCustomWidth(widthFactor),
                        };
                        ChatLayoutController.setWidthFactor(value);
                      },
                    ),
                    if (_widthOption(widthFactor) == _customWidth) ...[
                      const SizedBox(height: 8),
                      Slider(
                        value: widthFactor
                            .clamp(ChatLayoutController.customMin,
                                ChatLayoutController.customMax)
                            .toDouble(),
                        min: ChatLayoutController.customMin,
                        max: ChatLayoutController.customMax,
                        divisions: 10,
                        label: '${(widthFactor * 100).round()}%',
                        onChanged: ChatLayoutController.updateWidthFactor,
                        onChangeEnd: ChatLayoutController.setWidthFactor,
                      ),
                    ],
                  ]),
            ),
          ),
          const Divider(height: 1, indent: 56, endIndent: 16),
          SwitchListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            secondary: const Icon(Icons.bug_report_outlined),
            title: const Text(AppStrings.crashReport),
            subtitle: const Text(AppStrings.crashReportHint),
            value: _crashReportEnabled,
            onChanged: _toggleCrashReport,
          ),
          const Divider(height: 1, indent: 56, endIndent: 16),
          ListTile(
            minVerticalPadding: 6,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            leading: const Icon(Icons.feedback_outlined),
            title: const Text('意见反馈'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const FeedbackPage())),
          ),
          const Divider(height: 1, indent: 56, endIndent: 16),
          ListTile(
            minVerticalPadding: 6,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            leading: const Icon(Icons.system_update_alt),
            title: const Text(AppStrings.checkUpdate),
            trailing: const Icon(Icons.chevron_right),
            onTap: _checkUpdate,
          ),
          const Divider(height: 1, indent: 56, endIndent: 16),
          ListTile(
            minVerticalPadding: 6,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            leading: const Icon(Icons.help_outline),
            title: const Text('新手引导'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OnboardingPage())),
          ),
        ]),
      ),
      const SizedBox(height: 40),
    ];
  }

  // --- MCP 服务器管理 ---

  Widget _buildMcpSection(BuildContext context) {
    final mutedColor = AppTheme.semanticOf(context).mutedOnGlass;
    return SectionCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
                child: Text(AppStrings.mcpServers,
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            IconButton(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const McpServersPage())),
              icon: const Icon(Icons.open_in_new),
              tooltip: '打开 MCP 管理页',
            ),
            IconButton(
              onPressed: () => _addMcpServer(context),
              icon: const Icon(Icons.add_link),
              tooltip: AppStrings.addMcpServer,
            ),
          ]),
          const SizedBox(height: 4),
          Text(AppStrings.mcpServersHint,
              style: TextStyle(fontSize: 12, color: mutedColor)),
          const SizedBox(height: 8),
          if (_mcpServers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(AppStrings.noMcpServers,
                  style: TextStyle(color: mutedColor)),
            )
          else
            ..._mcpServers.map((server) => SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(server.kind == McpServerKind.http
                      ? Icons.dns_outlined
                      : Icons.terminal),
                  title: Text(server.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    server.kind == McpServerKind.http
                        ? (server.url ?? '')
                        : '${server.command ?? ''} ${server.args.join(' ')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  value: server.enabled,
                  onChanged: (value) => _toggleMcpServer(server, value),
                )),
          if (_mcpServers.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _clearMcpServers,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text(AppStrings.clearAll),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _buildAccountSection(BuildContext context) {
    // v0.6 聚焦使用体验，暂不开放账号、充值和用量功能。
    return Column(children: [
      const _SectionHeader(icon: Icons.privacy_tip_outlined, title: '隐私与合规'),
      SectionCard(
        child: ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('用户协议与隐私政策'),
          subtitle: const Text('了解数据处理与隐私'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const CompliancePage())),
        ),
      ),
    ]);
  }

  Future<void> _addMcpServer(BuildContext context) async {
    final name = TextEditingController();
    final url = TextEditingController();
    final command = TextEditingController();
    final args = TextEditingController();
    var kind = McpServerKind.http;

    final saved = await showImmersiveDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text(AppStrings.addMcpServer),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ImmersiveDropdown<McpServerKind>(
                labelText: AppStrings.connectionMethod,
                initialValue: kind,
                items: [
                  const DropdownMenuItem(
                      value: McpServerKind.http,
                      child: Text(AppStrings.streamableHttp)),
                  // stdio 需要 spawn 子进程：Web 与 Android 均不支持，隐藏选项避免静默失败。
                  if (!(kIsWeb ||
                      defaultTargetPlatform == TargetPlatform.android))
                    const DropdownMenuItem(
                        value: McpServerKind.stdio,
                        child: Text(AppStrings.stdioProcess)),
                ],
                onChanged: (value) =>
                    setDialogState(() => kind = value ?? McpServerKind.http),
              ),
              const SizedBox(height: 12),
              TextField(
                  controller: name,
                  decoration: const InputDecoration(
                      labelText: AppStrings.serverName,
                      border: InputBorder.none)),
              const SizedBox(height: 12),
              if (kind == McpServerKind.http)
                TextField(
                    controller: url,
                    decoration: const InputDecoration(
                        labelText: AppStrings.serverUrl,
                        border: InputBorder.none))
              else ...[
                TextField(
                    controller: command,
                    decoration: const InputDecoration(
                        labelText: AppStrings.command,
                        border: InputBorder.none)),
                const SizedBox(height: 12),
                TextField(
                    controller: args,
                    decoration: const InputDecoration(
                        labelText: AppStrings.argsSpaceSeparated,
                        border: InputBorder.none)),
              ],
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(AppStrings.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(AppStrings.add)),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;

    final trimmedName = name.text.trim();
    final id = 'mcp-${DateTime.now().millisecondsSinceEpoch}';
    final server = McpServerConfig(
      id: id,
      name: trimmedName.isEmpty ? 'MCP Server' : trimmedName,
      kind: kind,
      url: kind == McpServerKind.http ? url.text.trim() : null,
      command: kind == McpServerKind.stdio ? command.text.trim() : null,
      args: args.text.trim().isEmpty
          ? const []
          : args.text.trim().split(RegExp(r'\s+')),
    );
    if (kind == McpServerKind.http && server.url!.isEmpty) {
      if (context.mounted) {
        FloatingToast.show(context, AppStrings.fillServerUrl);
      }
      return;
    }
    await _mcpService.save(server);
    _mcpServers = await _mcpService.loadAll();
    if (mounted) setState(() {});
  }

  Future<void> _toggleMcpServer(McpServerConfig server, bool enabled) async {
    await _mcpService.toggleServer(server.id, enabled);
    _mcpServers = await _mcpService.loadAll();
    if (mounted) setState(() {});
  }

  Future<void> _clearMcpServers() async {
    final confirmed = await showImmersiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.clearMcpServers),
        content: const Text(AppStrings.clearMcpServersConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(AppStrings.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(AppStrings.clear)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _mcpService.clear();
    _mcpServers = await _mcpService.loadAll();
    if (mounted) setState(() {});
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
