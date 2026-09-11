import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/memory_service.dart';
import '../../application/providers.dart';
import '../../infrastructure/database/app_database.dart';
import '../l10n/app_strings.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../widgets/async_state_view.dart';
import '../widgets/confirm_action.dart';
import '../widgets/floating_toast.dart';
import '../widgets/immersive_sheet.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/section_card.dart';

/// 长期记忆管理页：查看 / 编辑 / 删除 / 添加，以及注入总开关。
class MemoryPage extends ConsumerStatefulWidget {
  const MemoryPage({super.key});

  @override
  ConsumerState<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends ConsumerState<MemoryPage> {
  List<Memory> _memories = [];
  bool _loading = true;
  Object? _error;
  bool _enabled = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final service = ref.read(memoryServiceProvider);
      final enabled = await service.isEnabled();
      final database = await ref.read(databaseProvider.future);
      final memories = await database.allMemories();
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _memories = memories;
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

  Future<void> _toggleEnabled(bool value) async {
    await ref.read(memoryServiceProvider).setEnabled(value);
    if (mounted) setState(() => _enabled = value);
  }

  Future<void> _addOrEdit([Memory? memory]) async {
    final content = TextEditingController(text: memory?.content ?? '');
    final category = TextEditingController(text: memory?.category ?? 'general');
    var importance = memory?.importance ?? 1;

    final saved = await showImmersiveDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
              memory == null ? AppStrings.addMemory : AppStrings.editMemory),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: content,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '记忆内容')),
              const SizedBox(height: 12),
              TextField(
                  controller: category,
                  decoration: const InputDecoration(labelText: '分类')),
              const SizedBox(height: 12),
              Row(children: [
                const Text('权重'),
                Expanded(
                  child: Slider(
                    value: importance.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: '$importance',
                    onChanged: (v) =>
                        setDialogState(() => importance = v.round()),
                  ),
                ),
                Text('$importance'),
              ]),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(AppStrings.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('保存')),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;

    final service = ref.read(memoryServiceProvider);
    final database = await ref.read(databaseProvider.future);
    if (!mounted) return;
    final text = content.text.trim();
    if (text.isEmpty) {
      FloatingToast.show(context, '记忆内容不能为空');
      return;
    }
    if (memory == null) {
      await service.add(
          database: database,
          content: text,
          category:
              category.text.trim().isEmpty ? 'general' : category.text.trim(),
          importance: importance);
    } else {
      await service.update(
          database,
          memory.copyWith(
              content: text,
              category: category.text.trim().isEmpty
                  ? 'general'
                  : category.text.trim(),
              importance: importance));
    }
    await _load();
  }

  Future<void> _delete(Memory memory) async {
    final confirmed = await showConfirmAction(
      context,
      title: '删除记忆？',
      message: '确定要删除此条记忆吗？删除后 Agent 将不再检索此记忆。',
      confirmLabel: '删除',
      isDanger: true,
      bulletItems: [
        '记忆：${memory.content}',
        '分类：${memory.category}',
        '重要度：${memory.importance}/5',
      ],
    );
    if (!confirmed || !mounted) return;
    final database = await ref.read(databaseProvider.future);
    await ref.read(memoryServiceProvider).delete(database, memory.id);
    await _load();
    if (mounted) FloatingToast.show(context, '记忆已删除');
  }

  String _formatDate(DateTime time) {
    final y = time.year.toString().padLeft(4, '0');
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  Widget _buildMemoryCard(Memory memory, bool isDark) {
    final isPreference = memory.category.toLowerCase().contains('pref') ||
        memory.category.contains('偏好');
    final isFact = memory.category.toLowerCase().contains('fact') ||
        memory.category.contains('事实');
    final typeLabel = isPreference ? '偏好' : (isFact ? '事实' : memory.category);

    final isAuto = memory.sourceType == 'auto';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SectionCard(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isPreference
                          ? AppPalette.brand.withValues(alpha: 0.12)
                          : (isFact
                              ? AppPalette.success.withValues(alpha: 0.12)
                              : (isDark
                                  ? AppPalette.darkSurface
                                  : AppPalette.lightSurface)),
                      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                      border: Border.all(
                        color: isPreference
                            ? AppPalette.brand.withValues(alpha: 0.3)
                            : (isFact
                                ? AppPalette.success.withValues(alpha: 0.3)
                                : (isDark
                                    ? AppPalette.darkHairline
                                    : AppPalette.lightHairline)),
                      ),
                    ),
                    child: Text(
                      typeLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isPreference
                            ? AppPalette.brand
                            : (isFact
                                ? AppPalette.success
                                : (isDark
                                    ? AppPalette.darkText
                                    : AppPalette.lightText)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(AppTokens.radiusControl),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 13, color: Colors.amber),
                        const SizedBox(width: 2),
                        Text(
                          '重要度 ${memory.importance}/5',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.amber.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isAuto ? '自动沉淀' : '手动录入',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppPalette.darkTextMuted
                          : AppPalette.lightTextMuted,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: '编辑',
                    constraints:
                        const BoxConstraints(minWidth: 44, minHeight: 44),
                    onPressed: () => _addOrEdit(memory),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: '删除',
                    constraints:
                        const BoxConstraints(minWidth: 44, minHeight: 44),
                    onPressed: () => _delete(memory),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText(
                memory.content,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.schedule_rounded,
                      size: 12,
                      color: isDark
                          ? AppPalette.darkTextMuted
                          : AppPalette.lightTextMuted),
                  const SizedBox(width: 4),
                  Text(
                    '更新于 ${_formatDate(memory.updatedAt)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppPalette.darkTextMuted
                          : AppPalette.lightTextMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _memories.where((m) {
      if (_searchQuery.isEmpty) return true;
      return m.content.toLowerCase().contains(_searchQuery) ||
          m.category.toLowerCase().contains(_searchQuery);
    }).toList();

    return Scaffold(
      backgroundColor: isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas,
      appBar: NexusPageHeader(
        title: AppStrings.memoryEntry,
        subtitle: '跨会话事实与个性化偏好存储',
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: '添加记忆',
            onPressed: () => _addOrEdit(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEdit(),
        backgroundColor: AppPalette.brandAction,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        ),
        child: const Icon(Icons.add),
      ),
      body: AsyncStateView(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 搜索栏
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) =>
                      setState(() => _searchQuery = v.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: '搜索记忆内容或分类...',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? AppPalette.darkTextMuted
                          : AppPalette.lightTextMuted,
                    ),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    filled: true,
                    fillColor: isDark
                        ? AppPalette.darkSurface
                        : AppPalette.lightSurface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                      borderSide: BorderSide(
                        color: isDark
                            ? AppPalette.darkHairline
                            : AppPalette.lightHairline,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                      borderSide: BorderSide(
                        color: isDark
                            ? AppPalette.darkHairline
                            : AppPalette.lightHairline,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SectionCard(
              child: SwitchListTile(
                secondary: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppPalette.brandSoftDark
                        : AppPalette.brandSoftLight,
                    borderRadius:
                        BorderRadius.circular(AppTokens.radiusControl),
                  ),
                  child: const Icon(Icons.psychology_outlined,
                      size: 20, color: AppPalette.brand),
                ),
                title: const Text(
                  AppStrings.memoryEnabled,
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
                ),
                subtitle: Text(
                  AppStrings.memoryEnabledHint,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? AppPalette.darkTextMuted
                        : AppPalette.lightTextMuted,
                  ),
                ),
                value: _enabled,
                onChanged: _toggleEnabled,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.memoryHint,
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? AppPalette.darkTextMuted
                    : AppPalette.lightTextMuted,
              ),
            ),
            const SizedBox(height: 12),
            if (_memories.isEmpty)
              EmptyStateView(
                icon: Icons.psychology_outlined,
                title: '暂无记忆',
                message: '还没有记忆，Agent 会在聊天中自动为您沉淀长期记忆，或点击下方按钮手动添加',
                actionLabel: '添加记忆',
                onAction: () => _addOrEdit(),
              )
            else if (filtered.isEmpty)
              EmptyStateView(
                icon: Icons.search_off_rounded,
                title: '未找到相关记忆',
                message: '没有匹配 "$_searchQuery" 的记忆条目',
                actionLabel: '清空搜索',
                onAction: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              )
            else
              ...filtered.map((memory) => _buildMemoryCard(memory, isDark)),
          ],
        ),
      ),
    );
  }
}
