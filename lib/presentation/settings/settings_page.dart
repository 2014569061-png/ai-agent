import '../l10n/app_strings.dart';
import '../widgets/floating_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../domain/models.dart';
import '../../infrastructure/mcp/mcp_server_config.dart';
import '../../infrastructure/providers/provider_config.dart';
import '../../infrastructure/providers/provider_config_store.dart';
import '../../infrastructure/providers/openai_compatible_provider.dart';
import '../../infrastructure/providers/anthropic_provider.dart';
import '../../infrastructure/providers/gemini_provider.dart';
import '../theme/app_theme_controller.dart';

class _ProviderTemplate {
  const _ProviderTemplate(this.name, this.baseUrl, this.model, {this.type = ProviderType.openaiCompatible});
  final String name;
  final String baseUrl;
  final String model;
  final ProviderType type;
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _templates = <_ProviderTemplate>[
    _ProviderTemplate('OpenAI', 'https://api.openai.com/v1', 'gpt-4o-mini'),
    _ProviderTemplate('Anthropic', 'https://api.anthropic.com', 'claude-3-5-sonnet-20241022', type: ProviderType.anthropic),
    _ProviderTemplate('Gemini', 'https://generativelanguage.googleapis.com', 'gemini-1.5-flash', type: ProviderType.gemini),
    _ProviderTemplate('DeepSeek', 'https://api.deepseek.com/v1', 'deepseek-chat'),
    _ProviderTemplate('OpenRouter', 'https://openrouter.ai/api/v1', 'openai/gpt-4o-mini'),
    _ProviderTemplate('Groq', 'https://api.groq.com/openai/v1', 'llama-3.3-70b-versatile'),
    _ProviderTemplate('Together AI', 'https://api.together.xyz/v1', 'meta-llama/Llama-3.3-70B-Instruct-Turbo'),
    _ProviderTemplate('Ollama', 'http://localhost:11434/v1', 'llama3.2'),
  ];
  final _name = TextEditingController();
  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  final _apiKey = TextEditingController();
  final _tavilyKey = TextEditingController();
  final _store = ProviderConfigStore();
  List<ProviderConfig> _profiles = [];
  String _selectedId = 'default';
  ProviderType _type = ProviderType.openaiCompatible;
  ReasoningEffort _reasoningEffort = ReasoningEffort.medium;
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _loadingModels = false;
  List<ModelInfo> _models = [];
  List<McpServerConfig> _mcpServers = [];

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final config = await _store.load();
    _profiles = await _store.loadAll();
    _fill(config);
    _tavilyKey.text = await _store.readToolKey('tavily');
    _mcpServers = await McpServerStore().loadAll();
    if (mounted) setState(() => _loading = false);
  }

  void _fill(ProviderConfig config) {
    _selectedId = config.id;
    _type = config.type;
    _name.text = config.name;
    _baseUrl.text = config.baseUrl;
    _model.text = config.model;
    _apiKey.text = config.apiKey;
    _reasoningEffort = config.reasoningEffort;
  }

  void _select(String? id) {
    if (id == null) return;
    _fill(_profiles.firstWhere((profile) => profile.id == id));
    setState(() {});
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final id = _selectedId == 'default' && _profiles.isEmpty ? 'provider-${DateTime.now().millisecondsSinceEpoch}' : _selectedId;
    await _store.save(ProviderConfig(id: id, name: _name.text.trim().isEmpty ? 'Provider' : _name.text.trim(), baseUrl: _baseUrl.text, model: _model.text, apiKey: _apiKey.text, type: _type, reasoningEffort: _reasoningEffort));
    await _store.saveToolKey('tavily', _tavilyKey.text);
    _profiles = await _store.loadAll();
    _selectedId = id;
    if (!mounted) return;
    setState(() => _saving = false);
    FloatingToast.show(context, AppStrings.providerConfigSaved);
  }

  ProviderConfig get _currentConfig => ProviderConfig(
        id: _selectedId,
        name: _name.text.trim(),
        baseUrl: _baseUrl.text.trim(),
        model: _model.text.trim(),
        apiKey: _apiKey.text.trim(),
        type: _type,
        reasoningEffort: _reasoningEffort,
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
    }
  }

  Future<void> _testConnection() async {
    if (_baseUrl.text.trim().isEmpty || _apiKey.text.trim().isEmpty) {
      FloatingToast.show(context, AppStrings.fillBaseUrlAndKey);
      return;
    }
    setState(() => _testing = true);
    final error = await _runTestConnection();
    if (!mounted) return;
    setState(() => _testing = false);
    FloatingToast.show(context, error == null ? AppStrings.connectionSuccess : '连接失败：$error');
  }

  Future<void> _loadModels() async {
    if (_type != ProviderType.openaiCompatible) {
      FloatingToast.show(context, AppStrings.onlyOpenAiCompatible);
      return;
    }
    if (_baseUrl.text.trim().isEmpty || _apiKey.text.trim().isEmpty) return;
    setState(() => _loadingModels = true);
    try {
      _models = await OpenAiCompatibleProvider(config: _currentConfig).listModels();
      if (mounted) setState(() {});
      if (mounted && _models.isEmpty) FloatingToast.show(context, AppStrings.noModelsReturned);
    } catch (error) {
      if (mounted) FloatingToast.show(context, '获取模型失败：$error');
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  @override Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(appBar: AppBar(title: const Text(AppStrings.providerSettings)), body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text(AppStrings.modelServiceConfig, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        initialValue: null,
        items: _templates.map((template) => DropdownMenuItem(value: template.name, child: Text(template.name))).toList(),
        onChanged: (name) {
          if (name == null) return;
          final template = _templates.firstWhere((item) => item.name == name);
          setState(() {
            _name.text = template.name;
            _baseUrl.text = template.baseUrl;
            _model.text = template.model;
            _type = template.type;
            _models = [];
          });
        },
        decoration: const InputDecoration(labelText: AppStrings.quickApplyTemplate, border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<ProviderType>(
        initialValue: _type,
        items: const [
          DropdownMenuItem(value: ProviderType.openaiCompatible, child: Text('OpenAI 兼容')),
          DropdownMenuItem(value: ProviderType.anthropic, child: Text('Anthropic')),
          DropdownMenuItem(value: ProviderType.gemini, child: Text('Gemini')),
        ],
        onChanged: (value) {
          if (value != null) setState(() => _type = value);
        },
        decoration: const InputDecoration(labelText: AppStrings.protocolType, border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      if (_profiles.isNotEmpty) ...[
        DropdownButtonFormField<String>(initialValue: _selectedId, items: _profiles.map<DropdownMenuItem<String>>((p) => DropdownMenuItem<String>(value: p.id, child: Text(p.name))).toList(), onChanged: _select, decoration: const InputDecoration(labelText: AppStrings.savedProviders, border: OutlineInputBorder())),
        const SizedBox(height: 12),
      ],
      TextField(controller: _name, decoration: const InputDecoration(labelText: AppStrings.providerName, border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: _baseUrl, decoration: const InputDecoration(labelText: AppStrings.baseUrl, border: OutlineInputBorder())),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: TextField(controller: _model, decoration: const InputDecoration(labelText: AppStrings.modelName, border: OutlineInputBorder()))),
        const SizedBox(width: 8),
        IconButton(onPressed: _loadingModels ? null : _loadModels, icon: _loadingModels ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh), tooltip: '获取模型列表'),
      ]),
      if (_models.isNotEmpty) ...[
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(initialValue: _models.any((item) => item.id == _model.text) ? _model.text : null, items: _models.map<DropdownMenuItem<String>>((item) => DropdownMenuItem<String>(value: item.id, child: Text(item.id, overflow: TextOverflow.ellipsis))).toList(), onChanged: (value) { if (value != null) setState(() => _model.text = value); }, decoration: const InputDecoration(labelText: '从列表选择', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        if (_models.any((item) => item.id == _model.text))
          Builder(builder: (context) {
            final capabilities = _models.firstWhere((item) => item.id == _model.text).capabilities;
            return Wrap(spacing: 6, children: [
              if (capabilities.streaming) const Chip(label: Text('流式')),
              if (capabilities.tools) const Chip(label: Text('工具调用')),
              if (capabilities.vision) const Chip(label: Text('视觉')),
              if (capabilities.jsonMode) const Chip(label: Text('JSON')),
            ]);
          }),
      ],
      const SizedBox(height: 12),
      TextField(controller: _apiKey, obscureText: true, decoration: const InputDecoration(labelText: AppStrings.apiKey, border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: _tavilyKey, obscureText: true, decoration: const InputDecoration(labelText: AppStrings.tavilyApiKey, border: OutlineInputBorder())),
      const SizedBox(height: 16),
      // 思考程度：仅推理模型（OpenAI o1/o3/GPT-5、Claude 3.7+ thinking、Gemini 2.0 thinking）生效，其他模型忽略该参数。
      Text('思考程度', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 6),
      SegmentedButton<ReasoningEffort>(
        segments: const [
          ButtonSegment(value: ReasoningEffort.off, label: Text('关')),
          ButtonSegment(value: ReasoningEffort.low, label: Text('低')),
          ButtonSegment(value: ReasoningEffort.medium, label: Text('中')),
          ButtonSegment(value: ReasoningEffort.high, label: Text('高')),
        ],
        selected: {_reasoningEffort},
        onSelectionChanged: (selection) => setState(() => _reasoningEffort = selection.first),
        showSelectedIcon: false,
        style: ButtonStyle(visualDensity: VisualDensity.compact),
      ),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(child: FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save_outlined), label: Text(_saving ? AppStrings.saving : AppStrings.saveConfig))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(onPressed: _testing ? null : _testConnection, icon: _testing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_tethering), label: Text(_testing ? AppStrings.testing : AppStrings.testConnection))),
      ]),
      const SizedBox(height: 12),
      const Text(AppStrings.apiKeySecureStorage),
      const SizedBox(height: 20),
      ValueListenableBuilder<ThemeMode>(
        valueListenable: AppThemeController.mode,
        builder: (context, mode, _) => Card(
          child: SwitchListTile(
            secondary: Icon(mode == ThemeMode.light ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            title: const Text(AppStrings.dayMode),
            subtitle: Text(mode == ThemeMode.light ? AppStrings.dayModeSubtitle : AppStrings.darkModeSubtitle),
            value: mode == ThemeMode.light,
            onChanged: AppThemeController.setDayMode,
          ),
        ),
      ),
      const SizedBox(height: 16),
      _buildMcpSection(context),
    ]));
  }

  // --- MCP 服务器管理 ---

  Widget _buildMcpSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text(AppStrings.mcpServers, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            IconButton(
              onPressed: () => _addMcpServer(context),
              icon: const Icon(Icons.add_link),
              tooltip: AppStrings.addMcpServer,
            ),
          ]),
          const SizedBox(height: 4),
          const Text(AppStrings.mcpServersHint, style: TextStyle(fontSize: 12, color: Color(0xFF627D98))),
          const SizedBox(height: 8),
          if (_mcpServers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(AppStrings.noMcpServers, style: TextStyle(color: Color(0xFF627D98))),
            )
          else
            ..._mcpServers.map((server) => SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(server.kind == McpServerKind.http ? Icons.dns_outlined : Icons.terminal),
                  title: Text(server.name, maxLines: 1, overflow: TextOverflow.ellipsis),
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

  Future<void> _addMcpServer(BuildContext context) async {
    final name = TextEditingController();
    final url = TextEditingController();
    final command = TextEditingController();
    final args = TextEditingController();
    var kind = McpServerKind.http;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text(AppStrings.addMcpServer),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<McpServerKind>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: AppStrings.connectionMethod, border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: McpServerKind.http, child: Text(AppStrings.streamableHttp)),
                  // stdio 需要 spawn 子进程：Web 与 Android 均不支持，隐藏选项避免静默失败。
                  if (!(kIsWeb || defaultTargetPlatform == TargetPlatform.android))
                    const DropdownMenuItem(value: McpServerKind.stdio, child: Text(AppStrings.stdioProcess)),
                ],
                onChanged: (value) => setDialogState(() => kind = value ?? McpServerKind.http),
              ),
              const SizedBox(height: 12),
              TextField(controller: name, decoration: const InputDecoration(labelText: AppStrings.serverName, border: OutlineInputBorder())),
              const SizedBox(height: 12),
              if (kind == McpServerKind.http)
                TextField(controller: url, decoration: const InputDecoration(labelText: AppStrings.serverUrl, border: OutlineInputBorder()))
              else ...[
                TextField(controller: command, decoration: const InputDecoration(labelText: AppStrings.command, border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: args, decoration: const InputDecoration(labelText: AppStrings.argsSpaceSeparated, border: OutlineInputBorder())),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(AppStrings.cancel)),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text(AppStrings.add)),
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
      args: args.text.trim().isEmpty ? const [] : args.text.trim().split(RegExp(r'\s+')),
    );
    if (kind == McpServerKind.http && server.url!.isEmpty) {
      if (context.mounted) {
        FloatingToast.show(context, AppStrings.fillServerUrl);
      }
      return;
    }
    await McpServerStore().save(server);
    _mcpServers = await McpServerStore().loadAll();
    if (mounted) setState(() {});
  }

  Future<void> _toggleMcpServer(McpServerConfig server, bool enabled) async {
    await McpServerStore().save(server.copyWith(enabled: enabled));
    _mcpServers = await McpServerStore().loadAll();
    if (mounted) setState(() {});
  }

  Future<void> _clearMcpServers() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.clearMcpServers),
        content: const Text(AppStrings.clearMcpServersConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(AppStrings.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text(AppStrings.clear)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await McpServerStore().saveAll(const []);
    _mcpServers = await McpServerStore().loadAll();
    if (mounted) setState(() {});
  }

  @override void dispose() { _name.dispose(); _baseUrl.dispose(); _model.dispose(); _apiKey.dispose(); _tavilyKey.dispose(); super.dispose(); }
}
