import 'package:flutter/material.dart';

import '../../infrastructure/providers/provider_config.dart';
import '../../infrastructure/providers/provider_config_store.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/floating_toast.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profiles = await _store.loadAll();
    final active = await _store.load();
    if (mounted) {
      setState(() {
        _profiles = profiles;
        _active = active;
        _loading = false;
      });
    }
  }

  Future<void> _openPreset(ProviderPreset preset) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProviderDetailPage(preset: preset)),
    );
    _load();
  }

  Future<void> _openConfig(ProviderConfig config) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderDetailPage(
          config: config,
          preset: presetForConfig(config),
        ),
      ),
    );
    _load();
  }

  Future<void> _activate(ProviderConfig config) async {
    if (config.id == _active?.id) return;
    await _store.setActive(config.id);
    if (mounted) {
      FloatingToast.show(context, '已切换激活服务商：${config.name}');
    }
    _load();
  }

  Future<void> _delete(ProviderConfig config) async {
    final isActive = config.id == _active?.id;
    final otherExists = _profiles.length > 1;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除服务商“${config.name}”？'),
        content: Text(
          isActive && otherExists
              ? '该服务商当前处于激活状态。删除后，系统将自动切换到其他可用服务商。确定删除吗？'
              : '删除后该服务商配置与本地保存的密钥将被移除，确定删除吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _store.deleteProfile(config.id);
      if (mounted) {
        FloatingToast.show(context, '已删除服务商 ${config.name}');
      }
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final configuredUrls = _profiles.map((p) => p.baseUrl).toSet();
    final available = providerPresets
        .where((p) => !configuredUrls.contains(p.baseUrl))
        .toList();

    return Scaffold(
      backgroundColor: settingsBgColor(context),
      appBar: const NexusPageHeader(
        title: '模型提供商',
        subtitle: '管理大语言模型与 API 接入',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 36),
              children: [
                const SettingsSectionTitle('新增服务商'),
                SettingsGroupCard(
                  children: [
                    SettingsTile(
                      icon: Icons.api_rounded,
                      iconColor: const Color(0xFF007AFF),
                      title: '新增 OpenAI-compatible',
                      subtitle: '支持 GPT、DeepSeek、Kimi、GLM、Qwen 等',
                      onTap: () => _openPreset(providerPresets.first),
                    ),
                    const SettingsDivider(),
                    SettingsTile(
                      icon: Icons.auto_awesome_rounded,
                      iconColor: const Color(0xFFFF9500),
                      title: '新增官方 API',
                      subtitle: 'Anthropic Claude 或 Google Gemini',
                      onTap: () => _openPreset(
                        providerPresets.firstWhere(
                          (p) => p.type != ProviderType.openaiCompatible,
                        ),
                      ),
                    ),
                  ],
                ),
                SettingsSectionTitle('已配置服务商（共 ${_profiles.length} 个）'),
                if (_profiles.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      height: 160,
                      child: EmptyStateView(
                        icon: Icons.cloud_outlined,
                        title: '还没有服务商',
                        message: '从上方选择一个服务商开始配置',
                      ),
                    ),
                  )
                else
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
                        if (i < _profiles.length - 1)
                          const SettingsDivider(),
                      ],
                    ],
                  ),
                if (available.isNotEmpty) ...[
                  const SettingsSectionTitle('内置服务商预设'),
                  SettingsGroupCard(
                    children: [
                      for (var i = 0; i < available.length; i++) ...[
                        SettingsTile(
                          leading: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: const Color(0xFF5856D6),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              available[i].name.characters.first.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: available[i].name,
                          subtitle:
                              '${available[i].type.name} · ${available[i].models.length} 个预设模型',
                          trailingWidget: const Icon(
                            Icons.add_circle_outline_rounded,
                            size: 20,
                            color: Color(0xFF007AFF),
                          ),
                          onTap: () => _openPreset(available[i]),
                        ),
                        if (i < available.length - 1)
                          const SettingsDivider(),
                      ],
                    ],
                  ),
                ],
              ],
            ),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFF007AFF)
                      : (isDark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA)),
                  borderRadius: BorderRadius.circular(7),
                ),
                alignment: Alignment.center,
                child: Text(
                  config.name.characters.first.toUpperCase(),
                  style: TextStyle(
                    color: active
                        ? Colors.white
                        : (isDark ? Colors.white70 : Colors.black87),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
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
                              fontSize: 15,
                              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                        if (active) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF34C759).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '激活中',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF34C759),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${config.model.isEmpty ? "未选择模型" : config.model} · ${isConfigured ? "已配置 Key" : "未配置 Key"}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: settingsMutedColor(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                iconSize: 20,
                tooltip: active ? '当前处于激活状态' : '设为激活',
                icon: Icon(
                  active
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: active ? const Color(0xFF007AFF) : settingsMutedColor(context),
                ),
                onPressed: onActivate,
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
                    child: Text('删除', style: TextStyle(color: Color(0xFFFF3B30))),
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
