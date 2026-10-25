import '../widgets/nexus_sheet.dart';
import '../theme/mobile_theme.dart';
import 'dart:async';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import 'package:flutter/material.dart';
import '../widgets/nexus_page_layout.dart';
import '../theme/desktop_theme.dart';
import '../widgets/desktop_resource_view.dart';

import '../../domain/provider_config.dart';
import '../../domain/provider_template.dart';
import '../../domain/unique_id.dart';
import 'provider_template_import_page.dart';
import '../../infrastructure/providers/provider_config_store.dart';
import '../motion/nexus_page_route_factory.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/floating_toast.dart';
import '../widgets/confirm_action.dart';
import '../widgets/nexus_loading_skeleton.dart';
import '../widgets/nexus_page_header.dart';
import 'provider_detail_page.dart';
import 'provider_presets.dart';
import 'settings_components.dart';

class ProviderListPage extends StatefulWidget {
  const ProviderListPage({super.key});

  @override
  State<ProviderListPage> createState() => _ProviderListPageState();
}

class _ProviderListPageState extends State<ProviderListPage> {
  final _store = ProviderConfigStore();
  List<ProviderConfig> _profiles = const [];
  ProviderConfig? _active;
  bool _loading = true;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final profiles = await _store.loadAll();
      final active = await _store.load();
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _active = active;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = error;
        });
      }
    }
  }

  Future<void> _importTemplate() async {
    final template = await Navigator.of(context).push<ProviderTemplate>(
      NexusPageRoute.settingsPage(
          builder: (_) => const ProviderTemplateImportPage()),
    );
    if (template == null || !mounted) return;
    await _openConfig(ProviderConfig(
      id: UniqueId.generate('provider'),
      name: template.name,
      baseUrl: template.baseUrl.toString(),
      model: template.model,
      apiKey: '',
      type: ProviderType.values.byName(template.protocol),
      contextTokens: template.contextTokens,
    ));
  }

  Future<void> _openPreset(ProviderPreset preset) async {
    await Navigator.push(
      context,
      NexusPageRoute.settingsPage(
          builder: (_) => ProviderDetailPage(preset: preset)),
    );
    unawaited(_load());
  }

  Future<void> _openConfig(ProviderConfig config) async {
    await Navigator.push(
      context,
      NexusPageRoute.settingsPage(
        builder: (_) => ProviderDetailPage(
          config: config,
          preset: presetForConfig(config),
        ),
      ),
    );
    unawaited(_load());
  }

  Future<void> _activate(ProviderConfig config) async {
    if (config.id == _active?.id) return;
    await _store.setActive(config.id);
    if (mounted) {
      FloatingToast.show(context, '已切换激活服务商：${config.name}');
    }
    unawaited(_load());
  }

  Future<void> _delete(ProviderConfig config) async {
    final isActive = config.id == _active?.id;
    final otherExists = _profiles.length > 1;

    final confirmed = await showConfirmAction(
      context,
      title: '删除服务商“${config.name}”？',
      message: isActive && otherExists
          ? '该服务商当前处于激活状态。删除后，系统将自动切换到其他可用服务商。确定删除吗？'
          : '删除后该服务商配置与本地保存的密钥将被移除，确定删除吗？',
      confirmLabel: '删除',
      isDanger: true,
    );

    if (confirmed) {
      await _store.deleteProfile(config.id);
      if (mounted) {
        FloatingToast.show(context, '已删除服务商 ${config.name}');
      }
      unawaited(_load());
    }
  }

  Widget _desktopProviders(List<ProviderPreset> available) =>
      DesktopResourceView<_DesktopProviderEntry>(
        title: '模型与服务商',
        icon: Icons.hub_outlined,
        description: '管理 API 配置和当前默认服务商。内置预设仅是模板，不代表已连接。',
        items: [
          for (final config in _profiles) _DesktopProviderEntry(config: config),
          for (final preset in available) _DesktopProviderEntry(preset: preset)
        ],
        loading: _loading,
        error: _loadError,
        onReload: _load,
        searchHint: '搜索名称、模型或协议',
        searchText: (entry) =>
            '${entry.name} ${entry.config?.model ?? entry.preset?.defaultModel ?? ''} ${providerProtocolLabel(entry.type)}',
        filters: [
          DesktopResourceFilter('已配置', (entry) => entry.config != null),
          DesktopResourceFilter(
              '当前默认',
              (entry) =>
                  entry.config != null && entry.config!.id == _active?.id),
          DesktopResourceFilter('内置预设', (entry) => entry.preset != null)
        ],
        sorts: [
          DesktopResourceSort('名称 A–Z',
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()))
        ],
        actions: [
          OutlinedButton.icon(
              onPressed: _importTemplate,
              icon: const Icon(Icons.download_outlined),
              label: const Text('导入配置模板')),
          FilledButton.icon(
              onPressed: () => _openPreset(providerPresets.first),
              icon: const Icon(Icons.add),
              label: const Text('新增兼容 API')),
          OutlinedButton.icon(
              onPressed: () => _openPreset(providerPresets
                  .firstWhere((p) => p.type != ProviderType.openaiCompatible)),
              icon: const Icon(Icons.api_outlined),
              label: const Text('新增官方 API'))
        ],
        emptyTitle: '没有可显示的服务商',
        emptyMessage: '添加自定义 API 配置，或从内置预设开始。',
        itemBuilder: (context, entry) {
          final config = entry.config;
          final active = config != null && config.id == _active?.id;
          return DesktopResourceCard(
            key: ValueKey('desktop-provider-${config?.id ?? entry.name}'),
            title: entry.name,
            icon: Icons.api_outlined,
            selected: active,
            description:
                desktopEndpointLabel(config?.baseUrl ?? entry.preset!.baseUrl),
            metadata: [
              providerProtocolLabel(entry.type),
              if (config == null)
                '内置模板 · 尚未配置'
              else ...[
                active ? '当前默认' : '已保存配置',
                config.apiKey.trim().isEmpty ? '未填写密钥' : '已填写密钥 · 连接需测试',
                config.model.isEmpty ? '未选择模型' : config.model
              ]
            ],
            onTap: () => config == null
                ? _openPreset(entry.preset!)
                : _openConfig(config),
            actions: config == null
                ? [
                    OutlinedButton.icon(
                        onPressed: () => _openPreset(entry.preset!),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('使用此预设'))
                  ]
                : [
                    OutlinedButton.icon(
                        onPressed: () => _openConfig(config),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('编辑配置')),
                    TextButton(
                        onPressed: active ? null : () => _activate(config),
                        child: Text(active ? '当前默认' : '设为默认')),
                    TextButton.icon(
                        onPressed: () => _delete(config),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('删除'))
                  ],
          );
        },
      );

  void _showAddProvider(List<ProviderPreset> available) {
    showNexusSheet<void>(
        context: context,
        builder: (sheetContext) {
          void open(VoidCallback action) {
            Navigator.pop(sheetContext);
            action();
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('添加服务商', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.api_rounded),
                      title: const Text('OpenAI 兼容 API'),
                      subtitle: const Text('填写地址、密钥与模型'),
                      onTap: () =>
                          open(() => _openPreset(providerPresets.first))),
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.auto_awesome_outlined),
                      title: const Text('官方 API'),
                      subtitle: const Text('Anthropic Claude 或 Google Gemini'),
                      onTap: () => open(() => _openPreset(
                          providerPresets.firstWhere((p) =>
                              p.type != ProviderType.openaiCompatible)))),
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.download_outlined),
                      title: const Text('导入配置模板'),
                      subtitle: const Text('解析后核对接收方，不包含密钥'),
                      onTap: () => open(_importTemplate)),
                  if (available.isNotEmpty) ...[
                    const Divider(height: 24),
                    Text('从预设开始',
                        style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                    const SizedBox(height: 8),
                    for (final preset in available)
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: _ProviderMonogram(name: preset.name),
                          title: Text(preset.name),
                          subtitle: Text(providerProtocolLabel(preset.type)),
                          trailing:
                              const Icon(Icons.chevron_right_rounded, size: 20),
                          onTap: () => open(() => _openPreset(preset))),
                  ],
                ]),
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    final configuredUrls = _profiles.map((p) => p.baseUrl).toSet();
    final available = providerPresets
        .where((p) => !configuredUrls.contains(p.baseUrl))
        .toList();
    if (DesktopTheme.maybeOf(context) != null) {
      return _desktopProviders(available);
    }

    return Scaffold(
      backgroundColor: settingsBgColor(context),
      appBar: NexusPageHeader(
        title: '模型与服务商',
        actions: [
          if (_profiles.isNotEmpty)
            IconButton(
                tooltip: '添加服务商',
                onPressed: () => _showAddProvider(available),
                icon: const Icon(Icons.add_rounded))
        ],
      ),
      body: NexusPageLayout(
          child: _loadError != null
              ? EmptyStateView(
                  icon: Icons.error_outline,
                  title: '服务商读取失败',
                  actionLabel: '重试',
                  onAction: _load)
              : _loading
                  ? const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: NexusListSkeleton(itemCount: 4),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(0, 8, 0, 36),
                      children: [
                        if (_profiles.isEmpty)
                          EmptyStateView(
                            icon: Icons.dns_outlined,
                            title: '添加第一个模型服务',
                            message: '选择服务商并填写 API 配置，即可开始对话',
                            actionLabel: '添加服务商',
                            onAction: () => _showAddProvider(available),
                          )
                        else ...[
                          const SettingsSectionTitle('已配置服务商'),
                          SettingsGroupCard(
                            children: [
                              for (var i = 0; i < _profiles.length; i++) ...[
                                _ProviderTile(
                                  config: _profiles[i],
                                  active: _profiles[i].id == _active?.id,
                                  preset: presetForConfig(_profiles[i]),
                                  onTap: () => _openConfig(_profiles[i]),
                                  onActivate: () => _activate(_profiles[i]),
                                  onDelete: () => _delete(_profiles[i]),
                                ),
                                // R4：首字母方块 28，文字从 56 开始，分隔线对齐文字。
                                if (i < _profiles.length - 1)
                                  const SettingsDivider(indent: 56),
                              ],
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.fromLTRB(24, 12, 24, 0),
                            child: Text('点击服务商编辑配置，在更多选项中切换或管理。',
                                style: TextStyle(fontSize: 13)),
                          ),
                        ],
                      ],
                    )),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.config,
    required this.active,
    required this.preset,
    required this.onTap,
    required this.onActivate,
    required this.onDelete,
  });

  final ProviderConfig config;
  final bool active;
  final ProviderPreset? preset;
  final VoidCallback onTap;
  final VoidCallback onActivate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isConfigured = config.apiKey.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _ProviderMonogram(name: config.name, active: active),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            config.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppTokens.fontSizeBody,
                              fontWeight:
                                  active ? FontWeight.w600 : FontWeight.w500,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                        if (active) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: AppPalette.success.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '激活中',
                              style: TextStyle(
                                fontSize: AppTokens.fontSizeMetricSmall,
                                color: AppPalette.success,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // Q2：Key 状态放前面，模型名过长时只截断模型名。
                      '${isConfigured ? "已配置 Key" : "未配置 Key"} · ${config.model.isEmpty ? "未选择模型" : config.model}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppTokens.fontSizeFootnote,
                        fontFamily: AppTokens.fontFamilyMono,
                        color: settingsMutedColor(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: AppTokens.kMinTouchTarget,
                  minHeight: AppTokens.kMinTouchTarget,
                ),
                iconSize: 20,
                tooltip: active ? '当前处于激活状态' : '设为激活',
                icon: Icon(
                  active
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: active
                      ? MobileTheme.brand(context)
                      : settingsMutedColor(context),
                ),
                onPressed: onActivate,
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: AppTokens.kMinTouchTarget,
                  minHeight: AppTokens.kMinTouchTarget,
                ),
                tooltip: '更多选项',
                iconSize: 18,
                icon: Icon(
                  Icons.more_horiz_rounded,
                  color: settingsMutedColor(context),
                ),
                onSelected: (value) {
                  if (value == 'edit') onTap();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('编辑配置')),
                  const PopupMenuItem(
                    value: 'delete',
                    child:
                        Text('删除', style: TextStyle(color: AppPalette.danger)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 协议类型的中文展示名，与服务商配置页的下拉框一致。
String providerProtocolLabel(ProviderType type) => switch (type) {
      ProviderType.openaiCompatible => 'OpenAI 兼容',
      ProviderType.anthropic => 'Anthropic',
      ProviderType.gemini => 'Gemini',
      ProviderType.proxy => '代理',
    };

/// 服务商首字母方块：已配置与预设同一套浅填充，只有激活项用品牌色（Q3）。
class _ProviderMonogram extends StatelessWidget {
  const _ProviderMonogram({required this.name, this.active = false});

  final String name;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final letter = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: active
            ? MobileTheme.brand(context)
            : (isDark ? AppPalette.darkHairline : AppPalette.lightHairline),
        borderRadius: BorderRadius.circular(7),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: active
              ? Colors.white
              : (isDark ? AppPalette.darkText : AppPalette.lightText),
          fontSize: AppTokens.fontSizeCaption,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DesktopProviderEntry {
  const _DesktopProviderEntry({this.config, this.preset});
  final ProviderConfig? config;
  final ProviderPreset? preset;
  String get name => config?.name ?? preset!.name;
  ProviderType get type => config?.type ?? preset!.type;
}
