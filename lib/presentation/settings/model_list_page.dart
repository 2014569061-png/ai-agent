import '../theme/mobile_theme.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import 'package:flutter/material.dart';
import '../widgets/nexus_page_layout.dart';
import '../theme/desktop_theme.dart';
import '../widgets/desktop_resource_view.dart';

import '../../infrastructure/providers/openai_compatible_provider.dart';
import '../../domain/provider_config.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/nexus_sheet.dart';
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

  Widget _desktopModels() => DesktopResourceView<_DisplayModel>(
        title: '选择模型',
        icon: Icons.view_in_ar_outlined,
        description: '${widget.config.name} · 能力标签来自预设或服务返回，不代表经过实际调用验证。',
        items: _models,
        loading: _loading && _models.isEmpty,
        searchHint: '搜索模型名称或 Model ID',
        searchText: (model) => '${model.id} ${model.displayName}',
        filters: [
          DesktopResourceFilter('工具调用', (model) => model.capabilities.tools),
          DesktopResourceFilter('视觉输入', (model) => model.capabilities.vision),
          DesktopResourceFilter('JSON', (model) => model.capabilities.jsonMode)
        ],
        sorts: [
          DesktopResourceSort(
              '名称 A–Z', (a, b) => a.displayName.compareTo(b.displayName)),
          DesktopResourceSort('上下文：大到小',
              (a, b) => (b.contextTokens ?? 0).compareTo(a.contextTokens ?? 0))
        ],
        actions: [
          FilledButton.icon(
              onPressed: _addCustomModel,
              icon: const Icon(Icons.add),
              label: const Text('自定义模型')),
          OutlinedButton.icon(
              onPressed: _loading ||
                      widget.config.type != ProviderType.openaiCompatible
                  ? null
                  : _loadRemote,
              icon: const Icon(Icons.cloud_download_outlined),
              label: Text(_loading ? '正在获取…' : '获取远端列表'))
        ],
        banner: _error == null && !_loading
            ? null
            : Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                    leading: Icon(_loading ? Icons.sync : Icons.info_outline),
                    title: Text(_loading ? '正在读取兼容 API 的模型列表' : '远端列表读取失败'),
                    subtitle:
                        const Text('已有预设仍可选择，也可以手动填写 Model ID；不会自动保存服务商配置。'))),
        emptyTitle: '当前没有可显示的模型',
        emptyMessage: '使用兼容 API 获取列表，或手动填写服务商支持的 Model ID。',
        itemBuilder: (context, model) => DesktopResourceCard(
          key: ValueKey('desktop-model-${model.id}'),
          title: model.displayName,
          icon: Icons.auto_awesome_outlined,
          description: model.id,
          selected: model.id == widget.config.model,
          metadata: [
            if (model.id == widget.config.model) '当前选择',
            _remoteModels.any((item) => item.id == model.id) ? '远端返回' : '内置预设',
            if (model.contextTokens != null)
              '${formatContextTokens(model.contextTokens!)} 上下文'
            else
              '上下文未提供',
            if (model.capabilities.tools) '工具调用',
            if (model.capabilities.vision) '视觉输入',
            if (model.capabilities.jsonMode) 'JSON'
          ],
          onTap: () => Navigator.pop(context, model.id),
          actions: [
            OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, model.id),
                icon: const Icon(Icons.check, size: 16),
                label: const Text('选择此模型'))
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (DesktopTheme.maybeOf(context) != null) return _desktopModels();
    final models = _models;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;

    return Scaffold(
      backgroundColor: settingsBgColor(context),
      appBar: NexusPageHeader(title: widget.config.name, subtitle: '模型列表'),
      body: NexusPageLayout(
          child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 36),
        children: [
          const SettingsSectionTitle('获取与添加'),
          SettingsGroupCard(
            children: [
              SettingsTile(
                icon: Icons.cloud_download_outlined,
                iconColor: settingsMutedColor(context),
                title: '从远端自动获取',
                subtitle: _loading
                    ? '正在读取 /models…'
                    : '读取 ${widget.config.baseUrl} 的模型列表',
                trailingWidget: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: settingsMutedColor(context),
                      ),
                onTap: _loading ? null : _loadRemote,
              ),
              const SettingsDivider(),
              SettingsTile(
                icon: Icons.add_rounded,
                iconColor: settingsMutedColor(context),
                title: '添加自定义模型',
                subtitle: '手动填写展示名称与 Model ID',
                onTap: _addCustomModel,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Q4：与设置页 T2 一致的无描边浅底胶囊，聚焦时品牌色细描边。
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              style: TextStyle(
                fontSize: AppTokens.fontSizeBody,
                color: textColor,
              ),
              decoration: InputDecoration(
                hintText: '搜索模型名称或 ID…',
                hintStyle: TextStyle(
                  fontSize: AppTokens.fontSizeBody,
                  color: settingsMutedColor(context),
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: settingsMutedColor(context),
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        tooltip: '清空搜索',
                        onPressed: _searchController.clear,
                      )
                    : null,
                filled: true,
                fillColor: textColor.withValues(alpha: isDark ? 0.08 : 0.05),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(MobileTheme.controlRadius(context)),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(MobileTheme.controlRadius(context)),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(MobileTheme.controlRadius(context)),
                  borderSide: BorderSide(
                    color: AppPalette.brandTextFor(isDark),
                    width: 1.2,
                  ),
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
                  iconColor: AppPalette.danger,
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
                  if (i < models.length - 1) const SettingsDivider(indent: 16),
                ],
              ],
            ),
        ],
      )),
    );
  }

  Future<void> _addCustomModel() async {
    final idController = TextEditingController();
    final nameController = TextEditingController();
    final result = await showNexusDialog<String>(
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      idController.dispose();
      nameController.dispose();
    });
    if (result != null && result.isNotEmpty && mounted) {
      Navigator.pop(context, result);
    }
  }
}

class _DisplayModel {
  const _DisplayModel({
    required this.id,
    required this.displayName,
    required this.capabilities,
    this.contextTokens,
  });

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
        id: model.id,
        displayName: model.id,
        capabilities: model.capabilities,
      );

  final String id;
  final String displayName;
  final ModelCapabilities capabilities;
  final int? contextTokens;
}

/// 上下文长度的紧凑写法：128000 → 128K，1000000 → 1M（Q5）。
String formatContextTokens(int tokens) {
  if (tokens >= 1000000) {
    final m = (tokens / 100000).round() / 10;
    return m == m.truncateToDouble() ? '${m.toInt()}M' : '${m}M';
  }
  if (tokens >= 1000) return '${(tokens / 1000).round()}K';
  return '$tokens';
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
      if (model.contextTokens case final tokens?)
        '${formatContextTokens(tokens)} 上下文',
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            model.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppTokens.fontSizeBody,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w500,
                              color: isDark
                                  ? AppPalette.darkText
                                  : AppPalette.lightText,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (selected)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppPalette.darkBrandSoft
                                  : AppPalette.lightBrandSoft,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '默认',
                              style: TextStyle(
                                fontSize: AppTokens.fontSizeMetricSmall,
                                fontWeight: FontWeight.w600,
                                color: MobileTheme.brand(context),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      model.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppTokens.fontSizeFootnote,
                        fontFamily: AppTokens.fontFamilyMono,
                        color: settingsMutedColor(context),
                      ),
                    ),
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: 6),
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
                                      ? AppPalette.darkHairline
                                      : AppPalette.lightHairline,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  chip,
                                  style: TextStyle(
                                    fontSize: AppTokens.fontSizeMetricSmall,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
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
                Icon(
                  Icons.check_rounded,
                  size: 20,
                  color: MobileTheme.brand(context),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
