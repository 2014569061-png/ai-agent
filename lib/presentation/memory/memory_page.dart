import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/memory_service.dart';
import '../../application/providers.dart';
import '../../infrastructure/database/app_database.dart';
import '../l10n/app_strings.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../widgets/async_state_view.dart';
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
    final confirmed = await showImmersiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除记忆'),
        content: Text(memory.content),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(AppStrings.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(AppStrings.delete)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final database = await ref.read(databaseProvider.future);
    await ref.read(memoryServiceProvider).delete(database, memory.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
        backgroundColor: AppPalette.brand,
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
              const EmptyStateView(
                icon: Icons.psychology_outlined,
                title: '暂无记忆',
                message: '还没有记忆，Agent 会在聊天中自动为您沉淀长期记忆，或点击右下角手动添加',
              )
            else
              ..._memories.map((memory) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SectionCard(
                      child: ListTile(
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppPalette.darkSurface
                                : AppPalette.lightSurface,
                            borderRadius: BorderRadius.circular(
                                AppTokens.radiusControl),
                            border: Border.all(
                              color: isDark
                                  ? AppPalette.darkHairline
                                  : AppPalette.lightHairline,
                            ),
                          ),
                          child: Icon(
                            Icons.bookmark_outline,
                            size: 18,
                            color: isDark
                                ? AppPalette.darkText
                                : AppPalette.lightText,
                          ),
                        ),
                        title: Text(
                          memory.content,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          '${memory.category} · 权重 ${memory.importance} · ${memory.sourceType == "auto" ? "自动" : "手动"}',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? AppPalette.darkTextMuted
                                : AppPalette.lightTextMuted,
                          ),
                        ),
                        trailing:
                            Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _addOrEdit(memory)),
                          IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(memory)),
                        ]),
                      ),
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}
