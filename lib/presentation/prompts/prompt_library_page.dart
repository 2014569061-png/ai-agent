import 'package:flutter/material.dart';

import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/database/database_provider.dart';
import '../widgets/immersive_sheet.dart';
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
    final result = await showImmersiveDialog<(String, String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? '新建 Prompt' : '编辑 Prompt'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: '名称')),
                const SizedBox(height: 8),
                TextField(
                    controller: category,
                    decoration: const InputDecoration(labelText: '分类')),
                const SizedBox(height: 8),
                TextField(
                  controller: content,
                  maxLines: 6,
                  minLines: 3,
                  decoration: const InputDecoration(
                      labelText: '提示词内容', alignLabelWithHint: true),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context,
                (name.text.trim(), category.text.trim(), content.text.trim())),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    name.dispose();
    category.dispose();
    content.dispose();
    if (result == null || result.$1.isEmpty) return;
    final db = await DatabaseProvider.instance.database;
    final now = DateTime.now();
    await db.savePromptTemplate(PromptTemplate(
      id: existing?.id ?? 'prompt-${now.microsecondsSinceEpoch}',
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
    final confirmed = await showImmersiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text('确定删除“${template.name}”吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
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
                  style: const TextStyle(color: Color(0xFF627D98))),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Prompt 模板')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
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
              decoration: InputDecoration(
                hintText: '搜索 Prompt',
                prefixIcon: const Icon(Icons.search),
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
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? const Center(
                        child: Text('还没有 Prompt 模板，点击右下角新建。',
                            style: TextStyle(color: Color(0xFF627D98))))
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
    final theme = Theme.of(context);
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
                        child: Text(template.name,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          template.isFavorite ? Icons.star : Icons.star_border,
                          color: template.isFavorite
                              ? Colors.amber.shade600
                              : theme.colorScheme.outline,
                        ),
                        tooltip: template.isFavorite ? '取消收藏' : '收藏',
                        onPressed: () => _toggleFavorite(template),
                      ),
                    ],
                  ),
                  Chip(
                    label: Text(template.category,
                        style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    template.content,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.tonal(
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
                            style: TextStyle(color: Colors.red)),
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
