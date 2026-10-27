import '../theme/desktop_theme.dart';
import '../theme/mobile_theme.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../widgets/nexus_page_layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/plugins/plugin_store.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../widgets/async_state_view.dart';
import '../widgets/confirm_action.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/section_card.dart';
import 'skill_market_page.dart';
import '../widgets/nexus_switch.dart';
import '../../application/local_error_copy.dart';

/// 插件页：Tab 1 = 声明式插件（JSON manifest）；Tab 2 = Skill 市场（GitHub）。
class PluginsPage extends ConsumerStatefulWidget {
  const PluginsPage({super.key});

  @override
  ConsumerState<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends ConsumerState<PluginsPage> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: MobileTheme.pageBackground(context),
        appBar: NexusPageHeader(
          title: 'Skills 与插件',
          subtitle: '声明式工具包与 GitHub Skill 市场',
          bottom: TabBar(
            indicatorColor: MobileTheme.brand(context),
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor:
                isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted,
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(text: '声明式插件'),
              Tab(text: 'Skill 市场'),
            ],
          ),
        ),
        body: const NexusPageLayout(
            child: TabBarView(
          children: [
            _DeclarativePluginsView(),
            SkillMarketPage(),
          ],
        )),
      ),
    );
  }
}

class _DeclarativePluginsView extends ConsumerStatefulWidget {
  const _DeclarativePluginsView();

  @override
  ConsumerState<_DeclarativePluginsView> createState() =>
      _DeclarativePluginsViewState();
}

class _DeclarativePluginsViewState
    extends ConsumerState<_DeclarativePluginsView> {
  bool _loading = true;
  Object? _error;
  List<Plugin> _plugins = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final db = await ref.read(databaseProvider.future);
      final plugins = await db.allPlugins();
      if (!mounted) return;
      setState(() {
        _plugins = plugins;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _import() async {
    final picked = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['json']);
    if (picked.isEmpty || !mounted) return;
    final Uint8List bytes;
    try {
      bytes = await picked.first.readAsBytes();
    } catch (_) {
      return;
    }
    // 读字节是异步的，中间可能已经离场。
    if (!mounted) return;
    final manifest = utf8.decode(bytes);
    final store = PluginStore();
    final manifestError = store.manifestError(manifest);
    if (manifestError != null) {
      FloatingToast.show(context, '插件 manifest 无效：$manifestError');
      return;
    }
    final map = jsonDecode(manifest) as Map<String, dynamic>;
    final pluginName = (map['name'] as String?) ?? '未命名插件';
    final pluginKind = (map['kind'] as String?) ?? 'tool';
    final pluginVersion = (map['version'] as String?) ?? '1.0.0';
    final tools = (map['tools'] as List?) ?? [];

    final confirmed = await showConfirmAction(
      context,
      title: '导入插件？',
      message: '即将安装声明式插件“$pluginName”。请核对以下权限与声明范围：',
      confirmLabel: '确认导入',
      bulletItems: [
        '插件名称：$pluginName',
        '插件类型：$pluginKind',
        '声明版本：v$pluginVersion',
        if (tools.isNotEmpty) '包含工具：${tools.length} 个声明式工具',
        '权限范围：受应用内受控沙箱与二次确认策略保护',
      ],
    );
    if (!confirmed || !mounted) return;

    final db = await ref.read(databaseProvider.future);
    await store.importPlugin(
        db: db, name: pluginName, kind: pluginKind, manifestJson: manifest);
    await store.importAgents(db);
    await _load();
    if (mounted) FloatingToast.show(context, '插件已导入');
  }

  Future<void> _toggle(Plugin plugin, bool enabled) async {
    final db = await ref.read(databaseProvider.future);
    await db.savePlugin(plugin.copyWith(enabled: enabled));
    await _load();
  }

  Future<void> _delete(Plugin plugin) async {
    final confirmed = await showConfirmAction(
      context,
      title: '删除插件？',
      message: '将移除“${plugin.name}”及其本地配置。',
      confirmLabel: '删除',
      isDanger: true,
      bulletItems: [
        '插件名称：${plugin.name}',
        '插件类型：${plugin.kind}',
        '版本：v${plugin.version}',
      ],
    );
    if (!confirmed || !mounted) return;
    try {
      final db = await ref.read(databaseProvider.future);
      await db.deletePlugin(plugin.id);
      await _load();
      if (mounted) FloatingToast.show(context, '插件已删除');
    } catch (error) {
      if (mounted) FloatingToast.show(context, LocalErrorCopy.of(error, action: '删除').headline());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        AsyncStateView(
          loading: _loading,
          error: _error,
          onRetry: _load,
          child: _plugins.isEmpty
              ? EmptyStateView(
                  icon: Icons.extension_outlined,
                  title: '暂无插件',
                  message: '导入 JSON manifest 声明式工具包或 Agent 预设',
                  actionLabel: '导入插件',
                  onAction: _import,
                )
              : ListView.separated(
                  padding: DesktopTheme.maybeOf(context) == null
                      ? const EdgeInsets.fromLTRB(20, 8, 20, 104)
                      : const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _plugins.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final plugin = _plugins[index];
                    return SectionCard(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: plugin.enabled
                                        ? (isDark
                                            ? AppPalette.brandSoftDark
                                            : AppPalette.brandSoftLight)
                                        : (isDark
                                            ? AppPalette.darkSurface
                                            : AppPalette.lightSurface),
                                    borderRadius: BorderRadius.circular(
                                        MobileTheme.controlRadius(context)),
                                    border: Border.all(
                                      color: plugin.enabled
                                          ? MobileTheme.brand(context)
                                          : (isDark
                                              ? AppPalette.darkHairline
                                              : AppPalette.lightHairline),
                                    ),
                                  ),
                                  child: Icon(Icons.extension_outlined,
                                      size: 20,
                                      color: MobileTheme.brand(context)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        plugin.name,
                                        style: const TextStyle(
                                          fontSize: AppTokens.fontSizeBody,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: plugin.enabled
                                                  ? AppPalette.success
                                                      .withValues(alpha: 0.12)
                                                  : (isDark
                                                      ? AppPalette.darkSurface
                                                      : AppPalette
                                                          .lightSurface),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      MobileTheme.controlRadius(
                                                          context)),
                                            ),
                                            child: Text(
                                              plugin.enabled ? '已启用' : '已停用',
                                              style: TextStyle(
                                                fontSize: AppTokens
                                                    .fontSizeMetricSmall,
                                                fontWeight: FontWeight.w600,
                                                color: plugin.enabled
                                                    ? AppPalette.success
                                                    : (isDark
                                                        ? AppPalette
                                                            .darkTextMuted
                                                        : AppPalette
                                                            .lightTextMuted),
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: isDark
                                                  ? AppPalette.darkSurface
                                                  : AppPalette.lightSurface,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      MobileTheme.controlRadius(
                                                          context)),
                                              border: Border.all(
                                                color: isDark
                                                    ? AppPalette.darkHairline
                                                    : AppPalette.lightHairline,
                                              ),
                                            ),
                                            child: Text(
                                              'JSON 声明式',
                                              style: TextStyle(
                                                  fontSize: AppTokens
                                                      .fontSizeMetricSmall,
                                                  fontWeight: FontWeight.w600,
                                                  color: isDark
                                                      ? AppPalette.darkTextMuted
                                                      : AppPalette
                                                          .lightTextMuted),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: MobileTheme.brand(context)
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      MobileTheme.controlRadius(
                                                          context)),
                                            ),
                                            child: Text(
                                              plugin.kind == 'tool'
                                                  ? '受控工具'
                                                  : 'Agent 预设',
                                              style: TextStyle(
                                                fontSize: AppTokens
                                                    .fontSizeMetricSmall,
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    MobileTheme.brand(context),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                NexusSwitch(
                                  value: plugin.enabled,
                                  onChanged: (v) => _toggle(plugin, v),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded,
                                      size: 20),
                                  tooltip: '删除插件',
                                  constraints: const BoxConstraints(
                                      minWidth: 44, minHeight: 44),
                                  onPressed: () => _delete(plugin),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '版本 v${plugin.version} · 类型 ${plugin.kind}',
                              style: TextStyle(
                                fontSize: AppTokens.fontSizeFootnote,
                                fontFamily: AppTokens.fontFamilyMono,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                                color: isDark
                                    ? AppPalette.darkTextMuted
                                    : AppPalette.lightTextMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (DesktopTheme.maybeOf(context) != null ||
            _loading ||
            _error != null ||
            _plugins.isNotEmpty)
          Positioned(
            right: DesktopTheme.maybeOf(context) == null ? 20 : 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              onPressed: _import,
              backgroundColor: MobileTheme.brand(context),
              foregroundColor: Colors.white,
              elevation: 0,
              focusElevation: 0,
              hoverElevation: 0,
              highlightElevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(MobileTheme.controlRadius(context)),
              ),
              icon: const Icon(Icons.upload_file),
              label: const Text('导入插件'),
            ),
          ),
      ],
    );
  }
}
