import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/skills/skill_installer.dart';
import '../../infrastructure/skills/skill_store.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../widgets/async_state_view.dart';
import '../widgets/confirm_action.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/floating_toast.dart';
import '../widgets/section_card.dart';

/// Skill 市场（v0.6）：通过 GitHub 地址安装纯指令 + 静态资源的 Skill 包。
class SkillMarketPage extends ConsumerStatefulWidget {
  const SkillMarketPage({super.key});

  @override
  ConsumerState<SkillMarketPage> createState() => _SkillMarketPageState();
}

class _SkillMarketPageState extends ConsumerState<SkillMarketPage> {
  final _urlController = TextEditingController();
  final _installer = SkillInstaller();
  final _store = SkillStore();
  bool _loading = true;
  bool _previewing = false;
  bool _installing = false;
  Object? _error;
  SkillPackPreview? _previewPack;
  List<SkillPack> _installed = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = await ref.read(databaseProvider.future);
      final packs = await _store.all(db);
      if (!mounted) return;
      setState(() {
        _installed = packs;
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

  Future<void> _preview() async {
    final input = _urlController.text;
    if (input.trim().isEmpty) {
      FloatingToast.show(context, '请输入 GitHub 仓库地址或 owner/repo');
      return;
    }
    setState(() {
      _previewing = true;
      _previewPack = null;
    });
    try {
      final preview = await _installer.fetchPreview(input);
      if (!mounted) return;
      setState(() {
        _previewPack = preview;
        _previewing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _previewing = false);
      FloatingToast.show(context, '解析失败：$error');
    }
  }

  Future<void> _install() async {
    final preview = _previewPack;
    if (preview == null) return;
    final confirmed = await showConfirmAction(
      context,
      title: '安装第三方 Skill？',
      message:
          '来自 ${preview.source.label}\n\n${preview.metadata.name}：${preview.metadata.description}\n\nSkill 只包含指令与静态资源，不含可执行代码。',
      confirmLabel: '安装',
    );
    if (!confirmed || !mounted) return;
    setState(() => _installing = true);
    try {
      final db = await ref.read(databaseProvider.future);
      await _installer.install(db, preview);
      setState(() {
        _installing = false;
        _previewPack = null;
        _urlController.clear();
      });
      await _load();
      if (mounted) FloatingToast.show(context, 'Skill 已安装');
    } catch (error) {
      if (!mounted) return;
      setState(() => _installing = false);
      FloatingToast.show(context, '安装失败：$error');
    }
  }

  Future<void> _update(SkillPack pack) async {
    try {
      final preview = await _installer.fetchPreview(pack.source);
      final db = await ref.read(databaseProvider.future);
      await _installer.install(db, preview);
      await _load();
      if (mounted) FloatingToast.show(context, 'Skill 已更新');
    } catch (error) {
      if (!mounted) return;
      FloatingToast.show(context, '更新失败：$error');
    }
  }

  Future<void> _toggle(SkillPack pack, bool enabled) async {
    try {
      final db = await ref.read(databaseProvider.future);
      await _store.setEnabled(db, pack, enabled);
      await _load();
    } catch (error) {
      if (!mounted) return;
      FloatingToast.show(context, '操作失败：$error');
    }
  }

  Future<void> _delete(SkillPack pack) async {
    final confirmed = await showConfirmAction(
      context,
      title: '删除 Skill？',
      message: '将移除“${pack.name}”及其本地文件。',
      confirmLabel: '删除',
    );
    if (!confirmed || !mounted) return;
    try {
      final db = await ref.read(databaseProvider.future);
      await _store.delete(db, pack);
      await _load();
      if (mounted) FloatingToast.show(context, 'Skill 已删除');
    } catch (error) {
      if (!mounted) return;
      FloatingToast.show(context, '删除失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    hintText: 'GitHub 仓库地址或 owner/repo',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppTokens.radiusControl),
                      borderSide: BorderSide(
                        color: isDark
                            ? AppPalette.darkHairline
                            : AppPalette.lightHairline,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppTokens.radiusControl),
                      borderSide: const BorderSide(color: AppPalette.brand),
                    ),
                  ),
                  onSubmitted: (_) => _preview(),
                ),
              ),
              const SizedBox(width: 8),
              _previewing
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : FilledButton(
                      style: FilledButton.styleFrom(
                        elevation: 0,
                        backgroundColor: isDark
                            ? AppPalette.darkSurface
                            : AppPalette.lightSurface,
                        foregroundColor: isDark
                            ? AppPalette.darkText
                            : AppPalette.lightText,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusControl),
                          side: BorderSide(
                            color: isDark
                                ? AppPalette.darkHairline
                                : AppPalette.lightHairline,
                          ),
                        ),
                      ),
                      onPressed: _preview,
                      child: const Text('解析预览'),
                    ),
            ],
          ),
        ),
        if (_previewPack != null) _buildPreviewCard(),
        Divider(
          height: 1,
          color: isDark ? AppPalette.darkHairline : AppPalette.lightHairline,
        ),
        Expanded(
          child: AsyncStateView(
            loading: _loading,
            error: _error,
            onRetry: _load,
            child: _installed.isEmpty
                ? const EmptyStateView(
                    icon: Icons.extension_outlined,
                    title: '暂无 Skill',
                    message: '粘贴 GitHub 地址安装你的第一个 Skill',
                  )
                : ListView.separated(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _installed.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final pack = _installed[index];
                      return SectionCard(
                        child: ListTile(
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppPalette.brandSoftDark
                                  : AppPalette.brandSoftLight,
                              borderRadius: BorderRadius.circular(
                                  AppTokens.radiusControl),
                            ),
                            child: const Icon(Icons.menu_book_outlined,
                                size: 20, color: AppPalette.brand),
                          ),
                          title: Text(
                            pack.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            '${pack.description}\n${pack.source} · v${pack.version}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? AppPalette.darkTextMuted
                                  : AppPalette.lightTextMuted,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '检查更新',
                                icon: const Icon(Icons.refresh),
                                onPressed: () => _update(pack),
                              ),
                              Switch(
                                value: pack.enabled,
                                onChanged: (v) => _toggle(pack, v),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _delete(pack),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final preview = _previewPack!;
    return SectionCard(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${preview.metadata.name}  v${preview.metadata.version}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                _installing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : FilledButton(
                        style: FilledButton.styleFrom(
                          elevation: 0,
                          backgroundColor: AppPalette.brand,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppTokens.radiusControl),
                          ),
                        ),
                        onPressed: () => _install(),
                        child: const Text('安装'),
                      ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              preview.metadata.description,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppPalette.darkText : AppPalette.lightText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '来源：${preview.source.label} · ${preview.fileList.length} 个文件 · ${(preview.totalBytes / 1024).toStringAsFixed(1)} KB',
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? AppPalette.darkTextMuted
                    : AppPalette.lightTextMuted,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: preview.metadata.tags
                  .map((tag) => Chip(
                        backgroundColor: isDark
                            ? AppPalette.darkSurface
                            : AppPalette.lightSurface,
                        side: BorderSide(
                          color: isDark
                              ? AppPalette.darkHairline
                              : AppPalette.lightHairline,
                        ),
                        labelStyle: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? AppPalette.darkTextMuted
                              : AppPalette.lightTextMuted,
                        ),
                        label: Text(tag),
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}
