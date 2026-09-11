import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../infrastructure/providers/anthropic_provider.dart';
import '../../infrastructure/providers/gemini_provider.dart';
import '../../infrastructure/providers/openai_compatible_provider.dart';
import '../../infrastructure/providers/provider_config.dart';
import '../../infrastructure/providers/provider_config_store.dart';
import '../widgets/confirm_action.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_page_header.dart';
import 'model_list_page.dart';
import 'provider_presets.dart';
import 'settings_components.dart';

class ProviderDetailPage extends StatefulWidget {
  const ProviderDetailPage({super.key, this.config, this.preset});
  final ProviderConfig? config;
  final ProviderPreset? preset;

  @override
  State<ProviderDetailPage> createState() => _ProviderDetailPageState();
}

class _ProviderDetailPageState extends State<ProviderDetailPage> {
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _apiKey;
  late final TextEditingController _contextTokens;
  late final TextEditingController _inputPrice;
  late final TextEditingController _outputPrice;
  late final TextEditingController _cachedPrice;
  final _store = ProviderConfigStore();
  late ProviderType _type;
  ReasoningEffort _reasoning = ReasoningEffort.medium;
  bool _obscure = true;
  bool _saving = false;
  bool _testing = false;
  bool _advanced = false;
  bool _submitted = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    final config = widget.config;
    final preset = widget.preset;
    _name =
        TextEditingController(text: config?.name ?? preset?.name ?? 'Provider');
    _baseUrl =
        TextEditingController(text: config?.baseUrl ?? preset?.baseUrl ?? '');
    _model = TextEditingController(
        text: config?.model ?? preset?.defaultModel ?? '');
    _apiKey = TextEditingController(text: config?.apiKey ?? '');
    _contextTokens =
        TextEditingController(text: config?.contextTokens.toString() ?? '');
    _inputPrice = TextEditingController(
        text: config?.inputPricePerMillionCents?.toString() ?? '');
    _outputPrice = TextEditingController(
        text: config?.outputPricePerMillionCents?.toString() ?? '');
    _cachedPrice = TextEditingController(
        text: config?.cachedPricePerMillionCents?.toString() ?? '');
    _type = config?.type ?? preset?.type ?? ProviderType.openaiCompatible;
    _reasoning = config?.reasoningEffort ?? ReasoningEffort.medium;
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    _contextTokens.dispose();
    _inputPrice.dispose();
    _outputPrice.dispose();
    _cachedPrice.dispose();
    super.dispose();
  }

  int? _price(TextEditingController controller) {
    final raw = controller.text.trim();
    if (raw.isEmpty) return null;
    return int.tryParse(raw)?.clamp(0, 100000000).toInt();
  }

  ProviderConfig get _config => ProviderConfig(
        id: widget.config?.id ??
            'provider-${DateTime.now().millisecondsSinceEpoch}',
        name: _name.text.trim().isEmpty ? 'Provider' : _name.text.trim(),
        baseUrl: _baseUrl.text.trim(),
        model: _model.text.trim(),
        apiKey: _apiKey.text.trim(),
        type: _type,
        reasoningEffort: _reasoning,
        contextTokens: (int.tryParse(_contextTokens.text.trim()) ??
                ProviderConfig.defaultContextTokens)
            .clamp(4000, 2000000)
            .toInt(),
        inputPricePerMillionCents: _price(_inputPrice),
        outputPricePerMillionCents: _price(_outputPrice),
        cachedPricePerMillionCents: _price(_cachedPrice),
      );

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (_name.text.trim().isEmpty || _baseUrl.text.trim().isEmpty) {
      FloatingToast.show(context, '请完善服务商名称和 Base URL',
          tone: ToastTone.warning);
      return;
    }
    setState(() => _saving = true);
    try {
      final config = _config;
      await _store.save(config);
      if (mounted) {
        FloatingToast.show(context, '配置已保存');
        Navigator.pop(context, config);
      }
    } catch (error) {
      if (mounted) FloatingToast.error(context, error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _status = '正在测试连接…';
    });
    try {
      final config = _config;
      final result = switch (config.type) {
        ProviderType.anthropic =>
          await AnthropicProvider(config: config).testConnection(),
        ProviderType.gemini =>
          await GeminiProvider(config: config).testConnection(),
        _ => await OpenAiCompatibleProvider(config: config).testConnection(),
      };
      if (mounted) {
        setState(() => _status = result == null ? '连接测试成功' : '连接失败：$result');
      }
    } catch (error) {
      if (mounted) setState(() => _status = '连接失败：$error');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _chooseModel() async {
    final selected = await Navigator.push<String>(
        context,
        MaterialPageRoute(
            builder: (_) => ModelListPage(
                config: _config,
                preset: widget.preset ?? presetForConfig(_config))));
    if (selected != null && mounted) setState(() => _model.text = selected);
  }

  bool get _hasChanges {
    final origName = widget.config?.name ?? widget.preset?.name ?? 'Provider';
    final origBaseUrl = widget.config?.baseUrl ?? widget.preset?.baseUrl ?? '';
    final origModel = widget.config?.model ?? widget.preset?.defaultModel ?? '';
    final origApiKey = widget.config?.apiKey ?? '';
    final origType = widget.config?.type ??
        widget.preset?.type ??
        ProviderType.openaiCompatible;
    final origReasoning =
        widget.config?.reasoningEffort ?? ReasoningEffort.medium;
    return _name.text != origName ||
        _baseUrl.text != origBaseUrl ||
        _model.text != origModel ||
        _apiKey.text != origApiKey ||
        _type != origType ||
        _reasoning != origReasoning ||
        _contextTokens.text !=
            (widget.config?.contextTokens.toString() ?? '') ||
        _inputPrice.text !=
            (widget.config?.inputPricePerMillionCents?.toString() ?? '') ||
        _outputPrice.text !=
            (widget.config?.outputPricePerMillionCents?.toString() ?? '') ||
        _cachedPrice.text !=
            (widget.config?.cachedPricePerMillionCents?.toString() ?? '');
  }

  Future<bool> _showDiscardConfirm() async {
    return showConfirmAction(
      context,
      title: '放弃未保存的修改？',
      message: '当前服务商配置尚未保存，离开后修改将丢失。',
      confirmLabel: '放弃修改',
      cancelLabel: '继续编辑',
      isDanger: true,
    );
  }

  Future<void> _handlePop() async {
    if (!_hasChanges || _saving) {
      Navigator.pop(context);
      return;
    }
    final shouldDiscard = await _showDiscardConfirm();
    if (shouldDiscard && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preset = widget.preset ?? presetForConfig(_config);
    return PopScope(
      canPop: !_hasChanges || _saving,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldDiscard = await _showDiscardConfirm();
        if (shouldDiscard && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: settingsBgColor(context),
        appBar: NexusPageHeader(
          title: _name.text.isEmpty ? '服务商配置' : _name.text,
          subtitle: preset?.description,
          onBack: _handlePop,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 36),
          children: [
            const SettingsSectionTitle('基础配置'),
            SettingsGroupCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                TextField(
                  controller: _name,
                  decoration: InputDecoration(
                    labelText: '服务商名称 *',
                    helperText: '自定义名称，用于列表中标识该服务商',
                    errorText: (_submitted && _name.text.trim().isEmpty)
                        ? '服务商名称不能为空'
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<ProviderType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: '协议类型'),
                  items: const [
                    DropdownMenuItem(
                      value: ProviderType.openaiCompatible,
                      child: Text('OpenAI 兼容'),
                    ),
                    DropdownMenuItem(
                      value: ProviderType.anthropic,
                      child: Text('Anthropic'),
                    ),
                    DropdownMenuItem(
                      value: ProviderType.gemini,
                      child: Text('Gemini'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _type = value ?? _type),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _baseUrl,
                  decoration: InputDecoration(
                    labelText: 'Base URL *',
                    helperText: 'API 端点地址，如 https://api.openai.com/v1',
                    errorText: (_submitted && _baseUrl.text.trim().isEmpty)
                        ? 'Base URL 不能为空'
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _apiKey,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'API Key *',
                    helperText: _apiKey.text.trim().isNotEmpty
                        ? '已安全保存（本地存储）'
                        : '未填写，需要填写才能调用服务',
                    suffixIcon: SizedBox(
                      width: 48,
                      height: 48,
                      child: IconButton(
                        icon: Icon(_obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        tooltip: _obscure ? '显示密钥' : '隐藏密钥',
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
            const SettingsSectionTitle('模型选择'),
            SettingsGroupCard(
              children: [
                SettingsTile(
                  icon: Icons.view_list_rounded,
                  iconColor: settingsMutedColor(context),
                  title: _model.text.isEmpty ? '选择模型' : _model.text,
                  subtitle: '查看预设模型、远端模型或添加自定义模型',
                  onTap: _chooseModel,
                ),
              ],
            ),
            if (_status != null) ...[
              const SizedBox(height: 12),
              SettingsGroupCard(
                children: [
                  SettingsTile(
                    icon: _status!.startsWith('连接测试成功')
                        ? Icons.check_circle_rounded
                        : Icons.info_rounded,
                    iconColor: _status!.startsWith('连接测试成功')
                        ? AppPalette.success
                        : AppPalette.danger,
                    title: _status!,
                    showChevron: false,
                  ),
                ],
              ),
            ],
            const SettingsSectionTitle('高级设置'),
            SettingsGroupCard(
              children: [
                SettingsTile(
                  icon: Icons.tune_rounded,
                  iconColor: settingsMutedColor(context),
                  title: '高级参数',
                  subtitle: _advanced ? '点击收起' : '调整思考程度与上下文窗口',
                  showChevron: false,
                  trailingWidget: Icon(
                    _advanced ? Icons.expand_less : Icons.expand_more,
                    color: settingsMutedColor(context),
                  ),
                  onTap: () => setState(() => _advanced = !_advanced),
                ),
                if (_advanced) ...[
                  const SettingsDivider(indent: 16),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '思考程度',
                          style: TextStyle(
                            fontSize: 13,
                            color: settingsMutedColor(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<ReasoningEffort>(
                          segments: const [
                            ButtonSegment(
                              value: ReasoningEffort.low,
                              label: Text('低'),
                            ),
                            ButtonSegment(
                              value: ReasoningEffort.medium,
                              label: Text('中'),
                            ),
                            ButtonSegment(
                              value: ReasoningEffort.high,
                              label: Text('高'),
                            ),
                          ],
                          selected: {_reasoning},
                          onSelectionChanged: (value) =>
                              setState(() => _reasoning = value.first),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _contextTokens,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '上下文窗口上限（Token）',
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          '费用价目（分 / 百万 Token）',
                          style: TextStyle(
                            fontSize: 13,
                            color: settingsMutedColor(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '留空使用内置价目；缓存价格用于估算 prompt cache 节省。',
                          style: TextStyle(
                            fontSize: 12,
                            color: settingsMutedColor(context),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _inputPrice,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '输入 Token 价格',
                            suffixText: '分 / 1M',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _outputPrice,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '输出 Token 价格',
                            suffixText: '分 / 1M',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _cachedPrice,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '缓存 Token 价格',
                            suffixText: '分 / 1M',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            decoration: BoxDecoration(
              color: settingsBgColor(context),
              border: Border(
                top: BorderSide(
                  color: settingsDividerColor(context),
                  width: 0.8,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: AppTokens.kControlHeight,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusControl),
                        ),
                      ),
                      onPressed: _testing ? null : _test,
                      icon: _testing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.wifi_tethering),
                      label: const Text('测试连接'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: AppTokens.kControlHeight,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppPalette.brandAction,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusControl),
                        ),
                      ),
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_saving ? '保存中…' : '保存并启用'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
