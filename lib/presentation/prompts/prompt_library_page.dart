import 'package:flutter/material.dart';

import '../../domain/unique_id.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/database/database_provider.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/confirm_action.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/immersive_sheet.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/section_card.dart';

/// Prompt application mode.
enum PromptApplyMode {
  systemPrompt,
  input,

  /// 'Prompt 内容插入到聊天输入框'  input,
}

class PromptApplyResult {
  const PromptApplyResult({required this.mode, required this.content});
  final PromptApplyMode mode;
  final String content;
}

/// Prompt template library.
class PromptLibraryPage extends StatefulWidget {
  const PromptLibraryPage({super.key});

  @override
  State<PromptLibraryPage> createState() => _PromptLibraryPageState();
}

class _PromptLibraryPageState extends State<PromptLibraryPage> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _categoryFilter;
  bool _favoritesOnly = false;
  List<PromptTemplate> _templates = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final db = await DatabaseProvider.instance.database;
    final templates = await db.allPromptTemplates();
    if (!mounted) return;
    setState(() {
      _templates = templates;
      _loading = false;
    });
  }

  Set<String> get _categories => _templates
      .map((t) => t.category)
      .where((c) => c.trim().isNotEmpty)
      .toSet();

  List<PromptTemplate> get _filtered {
    final query = _query.trim().toLowerCase();
    return _templates.where((t) {
      if (_favoritesOnly && !t.isFavorite) return false;
      if (_categoryFilter != null && t.category != _categoryFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      return t.name.toLowerCase().contains(query) ||
          t.content.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _edit([PromptTemplate? existing]) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final category = TextEditingController(text: existing?.category ?? '通用');
    final content = TextEditingController(text: existing?.content ?? '');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final result = await showModalBottomSheet<(String, String, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          isDark ? AppPalette.darkSurface : AppPalette.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTokens.radiusModal)),
      ),
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.85,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Row(
                      children: [
                        Text(
                          existing == null ? '新建 Prompt' : '编辑 Prompt',
                          style: Theme.of(sheetContext)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          tooltip: '关闭',
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: isDark
                        ? AppPalette.darkHairline
                        : AppPalette.lightHairline,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: name,
                            decoration: const InputDecoration(
                              labelText: '模板名称 *',
                              hintText: '如：代码评审、周报撰写',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: category,
                            decoration: const InputDecoration(
                              labelText: '分类',
                              hintText: '如：通用、开发、写作',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: content,
                            maxLines: 8,
                            minLines: 4,
                            decoration: const InputDecoration(
                              labelText: '提示词内容 *',
                              hintText: '输入具体提示词内容...',
                              alignLabelWithHint: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppPalette.darkSurface
                          : AppPalette.lightSurface,
                      border: Border(
                        top: BorderSide(
                          color: isDark
                              ? AppPalette.darkHairline
                              : AppPalette.lightHairline,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(
                                  AppTokens.kMinTouchTarget),
                            ),
                            onPressed: () => Navigator.pop(sheetContext),
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(
                                  AppTokens.kMinTouchTarget),
                              backgroundColor: AppPalette.brandAction,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () {
                              final n = name.text.trim();
                              final c = content.text.trim();
                              if (n.isEmpty || c.isEmpty) return;
                              Navigator.pop(
                                  sheetContext, (n, category.text.trim(), c));
                            },
                            child: const Text('保存'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      name.dispose();
      category.dispose();
      content.dispose();
    });
    if (result == null || result.$1.isEmpty) return;
    final db = await DatabaseProvider.instance.database;
    final now = DateTime.now();
    await db.savePromptTemplate(PromptTemplate(
      id: existing?.id ?? UniqueId.generate('prompt', now: now),
      name: result.$1,
      content: result.$3,
      category: result.$2.isEmpty ? '通用' : result.$2,
      tagsJson: existing?.tagsJson ?? '[]',
      isFavorite: existing?.isFavorite ?? false,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    ));
    await _reload();
  }

  Future<void> _toggleFavorite(PromptTemplate template) async {
    final db = await DatabaseProvider.instance.database;
    await db.savePromptTemplate(template.copyWith(
        isFavorite: !template.isFavorite, updatedAt: DateTime.now()));
    await _reload();
  }

  Future<void> _delete(PromptTemplate template) async {
    final confirmed = await showConfirmAction(
      context,
      title: '删除 Prompt',
      message: '确定删除“${template.name}”吗？',
      confirmLabel: '删除',
      isDanger: true,
    );
    if (!confirmed) return;
    final db = await DatabaseProvider.instance.database;
    await db.deletePromptTemplate(template.id);
    await _reload();
  }

  void _use(PromptTemplate template) {
    showImmersiveSheet<PromptApplyMode>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(template.name,
                  style: Theme.of(context).textTheme.titleLarge),
              Text('分类：${template.category}',
                  style: TextStyle(
                      color: AppTheme.semanticOf(context).mutedOnGlass)),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.smart_toy_outlined),
                title: const Text('作为系统提示词'),
                subtitle: const Text('作为当前会话 Agent 系统提示'),
                onTap: () =>
                    Navigator.pop(context, PromptApplyMode.systemPrompt),
              ),
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: const Text('插入到输入框'),
                subtitle: const Text('把提示词内容填入聊天输入'),
                onTap: () => Navigator.pop(context, PromptApplyMode.input),
              ),
            ],
          ),
        ),
      ),
    ).then((mode) {
      if (mode != null && mounted) {
        Navigator.pop(
            context, PromptApplyResult(mode: mode, content: template.content));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final categories = _categories.toList()..sort();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas,
      appBar: const NexusPageHeader(
        title: 'Prompt 模板',
        subtitle: '分类管理与快速调用常用提示词',
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        backgroundColor: AppPalette.brand,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        ),
        icon: const Icon(Icons.add),
        label: const Text('新建 Prompt'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: '搜索 Prompt',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('收藏'),
                  selected: _favoritesOnly,
                  onSelected: (value) => setState(() => _favoritesOnly = value),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('全部'),
                  selected: _categoryFilter == null,
                  onSelected: (_) => setState(() => _categoryFilter = null),
                ),
                const SizedBox(width: 8),
                ...categories.map(
                  (category) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(category),
                      selected: _categoryFilter == category,
                      onSelected: (_) =>
                          setState(() => _categoryFilter = category),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : filtered.isEmpty
                    ? const EmptyStateView(
                        icon: Icons.lightbulb_outline,
                        title: '暂无 Prompt 模板',
                        message: '点击右下角按钮新建你的第一个 Prompt 模板。',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final template = filtered[index];
                          return _promptCard(template);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _promptCard(PromptTemplate template) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SectionCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          template.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          template.isFavorite ? Icons.star : Icons.star_border,
                          color: template.isFavorite
                              ? AppPalette.warning
                              : (isDark
                                  ? AppPalette.darkTextMuted
                                  : AppPalette.lightTextMuted),
                        ),
                        tooltip: template.isFavorite ? '取消收藏' : '收藏',
                        onPressed: () => _toggleFavorite(template),
                      ),
                    ],
                  ),
                  Chip(
                    backgroundColor: isDark
                        ? AppPalette.darkSurface
                        : AppPalette.lightSurface,
                    side: BorderSide(
                      color: isDark
                          ? AppPalette.darkHairline
                          : AppPalette.lightHairline,
                    ),
                    label: Text(
                      template.category,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? AppPalette.darkTextMuted
                            : AppPalette.lightTextMuted,
                      ),
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    template.content,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? AppPalette.darkTextMuted
                          : AppPalette.lightTextMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton(
                        style: FilledButton.styleFrom(
                          elevation: 0,
                          backgroundColor: AppPalette.brand,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppTokens.radiusControl),
                          ),
                        ),
                        onPressed: () => _use(template),
                        child: const Text('使用'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                          onPressed: () => _edit(template),
                          child: const Text('编辑')),
                      TextButton(
                        onPressed: () => _delete(template),
                        child: const Text('删除',
                            style: TextStyle(color: AppPalette.danger)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
