import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/plugins/plugin_store.dart';
import '../widgets/async_state_view.dart';
import '../widgets/confirm_action.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/floating_toast.dart';
import '../widgets/section_card.dart';
import 'skill_market_page.dart';

/// 插件页：Tab 1 = 声明式插件（JSON manifest）；Tab 2 = Skill 市场（GitHub）。
class PluginsPage extends ConsumerStatefulWidget {
  const PluginsPage({super.key});

  @override
  ConsumerState<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends ConsumerState<PluginsPage> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('插件'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '声明式插件'),
              Tab(text: 'Skill 市场'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _DeclarativePluginsView(),
            SkillMarketPage(),
          ],
        ),
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
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['json'], withData: true);
    if (result == null || result.files.isEmpty || !mounted) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    final manifest = utf8.decode(bytes);
    final store = PluginStore();
    if (!store.validateManifest(manifest)) {
      FloatingToast.show(context, '插件 manifest 格式无效');
      return;
    }
    final map = jsonDecode(manifest) as Map<String, dynamic>;
    final db = await ref.read(databaseProvider.future);
    await store.importPlugin(
        db: db,
        name: (map['name'] as String?) ?? '未命名插件',
        kind: (map['kind'] as String?) ?? 'tool',
        manifestJson: manifest);
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
    final confirmed = await showConfirmAction(context,
        title: '删除插件？',
        message: '将移除“${plugin.name}”及其配置。',
        confirmLabel: '删除');
    if (!confirmed || !mounted) return;
    try {
      final db = await ref.read(databaseProvider.future);
      await db.deletePlugin(plugin.id);
      await _load();
      if (mounted) FloatingToast.show(context, '插件已删除');
    } catch (error) {
      if (mounted) FloatingToast.show(context, '删除失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AsyncStateView(
          loading: _loading,
          error: _error,
          onRetry: _load,
          child: _plugins.isEmpty
              ? const EmptyStateView(
                  icon: Icons.extension_outlined,
                  title: '暂无插件',
                  message: '导入 JSON manifest 声明式工具包或 Agent 预设')
              : ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _plugins.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final plugin = _plugins[index];
                    return SectionCard(
                      child: ListTile(
                        leading: const Icon(Icons.extension_outlined),
                        title: Text(plugin.name),
                        subtitle: Text('${plugin.kind} · v${plugin.version}'),
                        trailing:
                            Row(mainAxisSize: MainAxisSize.min, children: [
                          Switch(
                              value: plugin.enabled,
                              onChanged: (v) => _toggle(plugin, v)),
                          IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(plugin)),
                        ]),
                      ),
                    );
                  },
                ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
              onPressed: _import,
              icon: const Icon(Icons.upload_file),
              label: const Text('导入插件')),
        ),
      ],
    );
  }
}
