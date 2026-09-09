import 'package:flutter/material.dart';

import '../../infrastructure/providers/openai_compatible_provider.dart';
import '../../infrastructure/providers/provider_config.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/nexus_page_header.dart';
import 'provider_presets.dart';
import 'settings_components.dart';

class ModelListPage extends StatefulWidget {
  const ModelListPage({super.key, required this.config, this.preset});

  final ProviderConfig config;
  final ProviderPreset? preset;

  @override
  State<ModelListPage> createState() => _ModelListPageState();
}

class _ModelListPageState extends State<ModelListPage> {
  final _searchController = TextEditingController();
  List<ModelInfo> _remoteModels = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.config.type == ProviderType.openaiCompatible &&
        widget.config.apiKey.trim().isNotEmpty) {
      _loadRemote();
    }
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRemote() async {
    if (widget.config.apiKey.trim().isEmpty &&
        !ProviderConfig.isLocalBaseUrl(widget.config.baseUrl)) {
      setState(() => _error = '请先在配置页填写 API Key');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final models =
          await OpenAiCompatibleProvider(config: widget.config).listModels();
      if (!mounted) return;
      setState(() => _remoteModels = models);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_DisplayModel> get _models {
    final byId = <String, _DisplayModel>{};
    for (final item in widget.preset?.models ?? const <ProviderPresetModel>[]) {
      byId[item.id] = _DisplayModel.fromPreset(item);
    }
    for (final item in _remoteModels) {
      byId[item.id] = _DisplayModel.fromRemote(item);
    }
    final query = _searchController.text.trim().toLowerCase();
    return byId.values.where((item) {
      return query.isEmpty ||
          item.id.toLowerCase().contains(query) ||
          item.displayName.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  @override
  Widget build(BuildContext context) {
    final models = _models;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: settingsBgColor(context),
      appBar: NexusPageHeader(title: widget.config.name, subtitle: '模型列表'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 36),
        children: [
          const SettingsSectionTitle('获取与添加'),
          SettingsGroupCard(
            children: [
              SettingsTile(
                icon: Icons.cloud_download_rounded,
                iconColor: const Color(0xFF007AFF),
                title: '从远端自动获取',
                subtitle: _loading
                    ? '正在读取 /models…'
                    : '读取 ${widget.config.baseUrl} 的模型列表',
                trailingWidget: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: Color(0xFF8E8E93),
                      ),
                onTap: _loading ? null : _loadRemote,
              ),
              const SettingsDivider(),
              SettingsTile(
                icon: Icons.add_rounded,
                iconColor: const Color(0xFF34C759),
                title: '添加自定义模型',
                subtitle: '手动填写展示名称与 Model ID',
                onTap: _addCustomModel,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // iOS Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: '搜索模型名称或 ID…',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: settingsMutedColor(context),
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: settingsMutedColor(context),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 34),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          child: Icon(
                            Icons.cancel_rounded,
                            size: 16,
                            color: settingsMutedColor(context),
                          ),
                        )
                      : null,
                  suffixIconConstraints: const BoxConstraints(minWidth: 32),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  isDense: true,
                ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            SettingsGroupCard(
              children: [
                SettingsTile(
                  icon: Icons.error_outline_rounded,
                  iconColor: const Color(0xFFFF3B30),
                  title: '远端模型获取失败',
                  subtitle: _error!,
                  showChevron: false,
                  trailingWidget: TextButton(
                    onPressed: _loadRemote,
                    child: const Text('重试'),
                  ),
                ),
              ],
            ),
          ],
          SettingsSectionTitle('模型列表（共 ${models.length} 个）'),
          if (models.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 200,
                child: EmptyStateView(
                  icon: Icons.view_list_outlined,
                  title: '暂无模型',
                  message: '请刷新远端列表或添加自定义模型',
                ),
              ),
            )
          else
            SettingsGroupCard(
              children: [
                for (var i = 0; i < models.length; i++) ...[
                  _ModelTile(
                    model: models[i],
                    selected: models[i].id == widget.config.model,
                    onTap: () => Navigator.pop(context, models[i].id),
                  ),
                  if (i < models.length - 1)
                    const SettingsDivider(indent: 16),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _addCustomModel() async {
    final idController = TextEditingController();
    final nameController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加自定义模型'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '展示名称')),
          TextField(
              controller: idController,
              decoration: const InputDecoration(labelText: 'Model ID')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, idController.text.trim()),
              child: const Text('使用模型')),
        ],
      ),
    );
    idController.dispose();
    nameController.dispose();
    if (result != null && result.isNotEmpty && mounted) {
      Navigator.pop(context, result);
    }
  }
}

class _DisplayModel {
  const _DisplayModel(
      {required this.id,
      required this.displayName,
      required this.capabilities,
      this.contextTokens});

  factory _DisplayModel.fromPreset(ProviderPresetModel model) => _DisplayModel(
        id: model.id,
        displayName: model.displayName,
        contextTokens: model.contextTokens,
        capabilities: ModelCapabilities(
            streaming: true,
            tools: model.tools,
            vision: model.vision,
            jsonMode: model.jsonMode),
      );

  factory _DisplayModel.fromRemote(ModelInfo model) => _DisplayModel(
      id: model.id, displayName: model.id, capabilities: model.capabilities);

  final String id;
  final String displayName;
  final ModelCapabilities capabilities;
  final int? contextTokens;
}

class _ModelTile extends StatelessWidget {
  const _ModelTile(
      {required this.model, required this.selected, required this.onTap});
  final _DisplayModel model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chips = <String>[
      if (model.contextTokens != null) '${model.contextTokens} 上下文',
      if (model.capabilities.tools) '工具',
      if (model.capabilities.vision) '视觉',
      if (model.capabilities.jsonMode) 'JSON',
    ];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      model.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      model.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: settingsMutedColor(context),
                      ),
                    ),
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: chips
                            .map(
                              (chip) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF2C2C2E)
                                      : const Color(0xFFE5E5EA),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  chip,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: settingsMutedColor(context),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.check_rounded,
                  size: 20,
                  color: Color(0xFF007AFF),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
