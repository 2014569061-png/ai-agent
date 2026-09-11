import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../application/providers.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/skills/skill_installer.dart';
import '../../infrastructure/skills/skill_parser.dart';
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

  Future<void> _pickArchive() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip', 'gz', 'tgz'],
      withData: true,
    );
    final file = result?.files.singleOrNull;
    if (file == null) return;
    try {
      final bytes = file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null || bytes.isEmpty) {
        throw SkillValidationException('无法读取所选压缩包');
      }
      setState(() {
        _previewing = true;
        _previewPack = null;
      });
      final preview = await _installer.previewFromArchiveBytes(
        bytes,
        GithubSkillRef.localArchive(file.name),
      );
      if (!mounted) return;
      setState(() {
        _previewPack = preview;
        _previewing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _previewing = false);
      FloatingToast.show(context, '压缩包解析失败：$error');
    }
  }

  Future<void> _install() async {
    final preview = _previewPack;
    if (preview == null) return;
    final confirmed = await showConfirmAction(
      context,
      title: '安装第三方 Skill？',
      message: '即将从 ${preview.source.label} 安装并注册该 Skill。请核对权限与安全范围：',
      confirmLabel: '安装并启用',
      bulletItems: [
        'Skill 名称：${preview.metadata.name} v${preview.metadata.version}',
        '功能描述：${preview.metadata.description}',
        '安全性质：静态纯指令与提示词，无系统底层二进制可执行权限',
        '包含文件：${preview.fileList.length} 个文件 (${(preview.totalBytes / 1024).toStringAsFixed(1)} KB)',
        '调用范围：仅在会话命中触发意图时注入提示词上下文',
      ],
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
      message: '确定要删除“${pack.name}”及其本地文件吗？',
      confirmLabel: '删除',
      isDanger: true,
      bulletItems: [
        '名称：${pack.name} v${pack.version}',
        '来源：${pack.source}',
        '描述：${pack.description}',
      ],
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
              IconButton(
                tooltip: '导入 Skill 压缩包',
                onPressed: _previewing ? null : _pickArchive,
                icon: const Icon(Icons.folder_zip_outlined),
              ),
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
                        foregroundColor:
                            isDark ? AppPalette.darkText : AppPalette.lightText,
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
                ? EmptyStateView(
                    icon: Icons.extension_outlined,
                    title: '暂无 Skill',
                    message: '粘贴 GitHub 地址或导入 ZIP / tar.gz 安装 Skill',
                    actionLabel: '导入 Skill 压缩包',
                    onAction: _pickArchive,
                  )
                : ListView.separated(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _installed.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final pack = _installed[index];
                      final isLocal = pack.source.startsWith('本地压缩包');

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
                                      color: pack.enabled
                                          ? (isDark
                                              ? AppPalette.brandSoftDark
                                              : AppPalette.brandSoftLight)
                                          : (isDark
                                              ? AppPalette.darkSurface
                                              : AppPalette.lightSurface),
                                      borderRadius: BorderRadius.circular(
                                          AppTokens.radiusControl),
                                      border: Border.all(
                                        color: pack.enabled
                                            ? AppPalette.brand
                                            : (isDark
                                                ? AppPalette.darkHairline
                                                : AppPalette.lightHairline),
                                      ),
                                    ),
                                    child: const Icon(Icons.menu_book_outlined,
                                        size: 20,
                                        color: AppPalette.brandAction),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          pack.name,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: pack.enabled
                                                    ? AppPalette.success
                                                        .withValues(alpha: 0.12)
                                                    : (isDark
                                                        ? AppPalette.darkSurface
                                                        : AppPalette
                                                            .lightSurface),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        AppTokens.radiusPill),
                                              ),
                                              child: Text(
                                                pack.enabled ? '已启用' : '已停用',
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: pack.enabled
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
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: isDark
                                                    ? AppPalette.darkSurface
                                                    : AppPalette.lightSurface,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        AppTokens.radiusPill),
                                                border: Border.all(
                                                  color: isDark
                                                      ? AppPalette.darkHairline
                                                      : AppPalette
                                                          .lightHairline,
                                                ),
                                              ),
                                              child: Text(
                                                isLocal ? '本地压缩包' : 'GitHub',
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w500,
                                                  color: isDark
                                                      ? AppPalette.darkTextMuted
                                                      : AppPalette
                                                          .lightTextMuted,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: AppPalette.brand
                                                    .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        AppTokens.radiusPill),
                                              ),
                                              child: const Text(
                                                '纯指令静态资源',
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w500,
                                                  color: AppPalette.brand,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: pack.enabled,
                                    onChanged: (v) => _toggle(pack, v),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert_rounded,
                                        size: 20),
                                    tooltip: '更多操作',
                                    onSelected: (action) {
                                      if (action == 'update') {
                                        _update(pack);
                                      } else if (action == 'delete') {
                                        _delete(pack);
                                      }
                                    },
                                    itemBuilder: (ctx) => [
                                      if (!isLocal)
                                        const PopupMenuItem(
                                          value: 'update',
                                          child: Row(
                                            children: [
                                              Icon(Icons.refresh_rounded,
                                                  size: 18),
                                              SizedBox(width: 8),
                                              Text('检查更新'),
                                            ],
                                          ),
                                        ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_outline_rounded,
                                                size: 18,
                                                color: AppPalette.danger),
                                            SizedBox(width: 8),
                                            Text('删除 Skill',
                                                style: TextStyle(
                                                    color: AppPalette.danger)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (pack.description.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  pack.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: isDark
                                        ? AppPalette.darkTextMuted
                                        : AppPalette.lightTextMuted,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                '${pack.source} · v${pack.version}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? AppPalette.darkTextFaint
                                      : AppPalette.lightTextFaint,
                                ),
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
                          backgroundColor: AppPalette.brandAction,
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
