import '../widgets/nexus_search_field.dart';
import '../theme/mobile_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/nexus_page_layout.dart';
import '../theme/desktop_theme.dart';
import '../widgets/desktop_resource_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/memory_service.dart';
import '../../application/providers.dart';
import '../../infrastructure/database/app_database.dart';
import '../l10n/app_strings.dart';
import '../motion/nexus_motion.dart';
import '../motion/nexus_staggered_entrance.dart';
import '../theme/app_palette.dart';
import '../theme/app_status_colors.dart';
import '../theme/app_tokens.dart';
import '../widgets/async_state_view.dart';
import '../widgets/confirm_action.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_sheet.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/section_card.dart';
import '../widgets/nexus_switch.dart';

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
    try {
      await ref.read(memoryServiceProvider).setEnabled(value);
      if (mounted) setState(() => _enabled = value);
    } catch (_) {
      if (mounted) FloatingToast.show(context, '自动注入设置未保存，仍保留原状态');
    }
  }

  Future<void> _addOrEdit([Memory? memory]) async {
    final content = TextEditingController(text: memory?.content ?? '');
    final category = TextEditingController(text: memory?.category ?? 'general');
    var importance = memory?.importance ?? 1;
    var saving = false, confirming = false;
    String? error;
    try {
      final saved = await showNexusDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) =>
              StatefulBuilder(builder: (dialogContext, setDialogState) {
                Future<void> cancel() async {
                  if (saving || confirming) return;
                  final changed = content.text != (memory?.content ?? '') ||
                      category.text != (memory?.category ?? 'general') ||
                      importance != (memory?.importance ?? 1);
                  if (changed) {
                    confirming = true;
                    final discard = await showConfirmAction(dialogContext,
                        title: '放弃未保存修改？',
                        message: '草稿尚未写入记忆，可以返回继续编辑。',
                        confirmLabel: '放弃修改',
                        isDanger: true);
                    confirming = false;
                    if (!discard) return;
                  }
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, false);
                  }
                }

                Future<void> save() async {
                  if (saving) return;
                  setDialogState(() {
                    saving = true;
                    error = null;
                  });
                  try {
                    final text = content.text.trim();
                    if (text.isEmpty || text.length > 3500) {
                      throw const FormatException('记忆内容必须为1–3500字符');
                    }
                    final database = await ref.read(databaseProvider.future);
                    final service = ref.read(memoryServiceProvider);
                    final scope = category.text.trim().isEmpty
                        ? 'general'
                        : category.text.trim();
                    if (memory == null) {
                      await service.add(
                          database: database,
                          content: text,
                          category: scope,
                          importance: importance);
                    } else {
                      await service.update(
                          database,
                          memory.copyWith(
                              content: text,
                              category: scope,
                              importance: importance,
                              sourceType: 'manual'),
                          expectedMemory: memory);
                    }
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext, true);
                    }
                  } on MemoryConflictException {
                    if (dialogContext.mounted) {
                      setDialogState(() {
                        saving = false;
                        error = '记录已被修改或删除，未覆盖新版本。草稿仍在此处，可先复制草稿，再取消并刷新查看新记录。';
                      });
                    }
                  } on FormatException catch (e) {
                    if (dialogContext.mounted) {
                      setDialogState(() {
                        saving = false;
                        error = e.message;
                      });
                    }
                  } catch (_) {
                    if (dialogContext.mounted) {
                      setDialogState(() {
                        saving = false;
                        error = '保存未确认，草稿已保留。请检查存储状态后重试。';
                      });
                    }
                  }
                }

                return PopScope(
                    canPop: false,
                    onPopInvokedWithResult: (didPop, result) {
                      if (!didPop) cancel();
                    },
                    child: AlertDialog(
                        backgroundColor: Theme.of(dialogContext)
                            .colorScheme
                            .surface
                            .withValues(alpha: 1),
                        title: Text(memory == null
                            ? AppStrings.addMemory
                            : AppStrings.editMemory),
                        content: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              TextField(
                                  controller: content,
                                  maxLines: 3,
                                  maxLength: 3500,
                                  enabled: !saving,
                                  decoration:
                                      const InputDecoration(labelText: '记忆内容')),
                              const SizedBox(height: 12),
                              TextField(
                                  controller: category,
                                  enabled: !saving,
                                  decoration:
                                      const InputDecoration(labelText: '分类')),
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
                                        onChanged: saving
                                            ? null
                                            : (v) => setDialogState(
                                                () => importance = v.round()))),
                                Text('$importance')
                              ]),
                              if (error != null) ...[
                                SelectableText(error!),
                                TextButton(
                                    onPressed: () async {
                                      await Clipboard.setData(
                                          ClipboardData(text: content.text));
                                    },
                                    child: const Text('复制未保存草稿'))
                              ],
                            ])),
                        actions: [
                          TextButton(
                              onPressed: saving ? null : cancel,
                              child: const Text(AppStrings.cancel)),
                          FilledButton(
                              onPressed: saving ? null : save,
                              child: Text(saving ? '保存中' : '保存'))
                        ]));
              }));
      if (saved == true && mounted) await _load();
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        content.dispose();
        category.dispose();
      });
    }
  }

  Future<void> _delete(Memory memory) async {
    final confirmed = await showConfirmAction(
      context,
      title: '删除记忆？',
      message:
          '删除此记录并保留私密遗忘指纹，阻止助手重新保存同样内容；若有来源会话，也停止从该会话自动写入记忆（包括其他条目）。不会撤回历史消息、已发送上下文或外部/旧备份；跨来源语义改写无法可靠识别。你仍可手动保存，但不会重新开启自动重学。',
      confirmLabel: '删除',
      isDanger: true,
      bulletItems: [
        '记忆：${memory.content}',
        '分类：${memory.category}',
        '来源：${MemoryService.sourceLabel(memory.sourceType)}',
        '重要度：${memory.importance}/5',
      ],
    );
    if (!confirmed || !mounted) return;
    final database = await ref.read(databaseProvider.future);
    try {
      await ref
          .read(memoryServiceProvider)
          .delete(database, memory.id, expectedMemory: memory);
    } catch (_) {
      if (mounted) FloatingToast.show(context, '记录已变化或删除未确认，未覆盖新内容；请刷新核实');
      return;
    }
    await _load();
    if (mounted) FloatingToast.show(context, '记忆已遗忘，自动重学保护已保存');
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

    final sourceLabel = MemoryService.sourceLabel(memory.sourceType);
    final categoryColors = AppStatusColors.resolve(
        context,
        isPreference
            ? AppStatusTone.brand
            : isFact
                ? AppStatusTone.success
                : AppStatusTone.neutral);
    final importanceColors =
        AppStatusColors.resolve(context, AppStatusTone.warning);
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SectionCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    key: ValueKey('memory-category-${memory.id}'),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: categoryColors.background,
                      borderRadius: BorderRadius.circular(
                          MobileTheme.controlRadius(context)),
                      border: Border.all(
                        color: highContrast
                            ? categoryColors.foreground
                            : categoryColors.foreground.withValues(alpha: .3),
                      ),
                    ),
                    child: Text(
                      typeLabel,
                      style: TextStyle(
                        fontSize: AppTokens.fontSizeBadge,
                        fontWeight: FontWeight.w600,
                        color: categoryColors.foreground,
                      ),
                    ),
                  ),
                  Container(
                    key: ValueKey('memory-importance-${memory.id}'),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: importanceColors.background,
                      borderRadius: BorderRadius.circular(
                          MobileTheme.controlRadius(context)),
                      border: Border.all(
                        color: highContrast
                            ? importanceColors.foreground
                            : importanceColors.foreground
                                .withValues(alpha: .25),
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded,
                            size: 13, color: importanceColors.foreground),
                        const SizedBox(width: 4),
                        Text(
                          '重要度 ',
                          style: TextStyle(
                            fontSize: AppTokens.fontSizeBadge,
                            fontWeight: FontWeight.w500,
                            color: importanceColors.foreground,
                          ),
                        ),
                        Text(
                          '${memory.importance}/5',
                          style: TextStyle(
                            fontSize: AppTokens.fontSizeBadge,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: importanceColors.foreground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    sourceLabel,
                    style: TextStyle(
                      fontSize: AppTokens.fontSizeBadge,
                      color: isDark
                          ? AppPalette.darkTextMuted
                          : AppPalette.lightTextMuted,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: '编辑',
                    constraints:
                        const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: () => _addOrEdit(memory),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: '删除',
                    constraints:
                        const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: () => _delete(memory),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText(
                '记忆标识：${memory.id}\n范围：${memory.category}\n来源会话：${memory.sourceConversationId ?? '未记录'}'
                '${memory.sourceType == 'manual' || memory.sourceType == 'auto' || memory.sourceType == 'agent' ? '' : '\n原始来源类型：${memory.sourceType}'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              SelectableText(
                memory.content,
                style: const TextStyle(
                  fontSize: AppTokens.fontSizeSubhead,
                  fontWeight: FontWeight.w400,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(Icons.schedule_rounded,
                      size: 12,
                      color: isDark
                          ? AppPalette.darkTextMuted
                          : AppPalette.lightTextMuted),
                  Text(
                    '更新于 ${_formatDate(memory.updatedAt)}',
                    style: TextStyle(
                      fontSize: AppTokens.fontSizeBadge,
                      fontFeatures: const [FontFeature.tabularFigures()],
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

  Widget _desktopMemories() => DesktopResourceView<Memory>(
        title: '记忆',
        icon: Icons.psychology_outlined,
        description: '管理跨会话的事实与偏好，保留来源与重要度，随时编辑或删除。',
        items: _memories,
        loading: _loading,
        error: _error,
        onReload: _load,
        searchHint: '搜索记忆内容或分类',
        searchText: (memory) => '${memory.content} ${memory.category}',
        filters: [
          DesktopResourceFilter(
              '手动录入', (memory) => memory.sourceType == 'manual'),
          DesktopResourceFilter(
              '助手写入', (memory) => memory.sourceType == 'agent'),
          DesktopResourceFilter(
              '自动沉淀', (memory) => memory.sourceType == 'auto'),
          DesktopResourceFilter('高重要度', (memory) => memory.importance >= 4)
        ],
        sorts: [
          DesktopResourceSort(
              '最近更新', (a, b) => b.updatedAt.compareTo(a.updatedAt)),
          DesktopResourceSort(
              '重要度：高到低', (a, b) => b.importance.compareTo(a.importance))
        ],
        banner: Card(
            margin: EdgeInsets.zero,
            child: SwitchListTile(
                title: const Text('启用长期记忆'),
                subtitle: const Text('自动注入会将选中记忆随请求发送给当前模型服务；关闭不撤销显式工具读取权限。'),
                value: _enabled,
                onChanged: _loading || _error != null ? null : _toggleEnabled)),
        actions: [
          FilledButton.icon(
              onPressed: () => _addOrEdit(),
              icon: const Icon(Icons.add),
              label: const Text('添加记忆'))
        ],
        emptyTitle: '还没有长期记忆',
        emptyMessage: '添加事实或偏好，让之后的会话获得相关上下文。',
        itemBuilder: (context, memory) => DesktopResourceCard(
          key: ValueKey('desktop-memory-${memory.id}'),
          title: memory.category,
          icon: Icons.bookmark_border_rounded,
          metadata: [
            MemoryService.sourceLabel(memory.sourceType),
            '来源会话 ${memory.sourceConversationId ?? '未记录'}',
            '重要度 ${memory.importance}/5',
            '更新于 ${_formatDate(memory.updatedAt)}'
          ],
          content: SelectableText(memory.content,
              style: Theme.of(context).textTheme.bodyMedium),
          actions: [
            OutlinedButton.icon(
                onPressed: () => _addOrEdit(memory),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('编辑记忆')),
            TextButton.icon(
                onPressed: () => _delete(memory),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('删除'))
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (DesktopTheme.maybeOf(context) != null) return _desktopMemories();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _memories.where((m) {
      if (_searchQuery.isEmpty) return true;
      return m.content.toLowerCase().contains(_searchQuery) ||
          m.category.toLowerCase().contains(_searchQuery);
    }).toList();

    return Scaffold(
      backgroundColor: MobileTheme.pageBackground(context),
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
      body: NexusPageLayout(
          child: AsyncStateView(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: NexusStaggeredEntrance(
          child: ListView(
            physics: NexusMotion.listPhysics,
            padding: const EdgeInsets.all(16),
            children: [
              // 搜索栏
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: NexusSearchField(
                  controller: _searchController,
                  hintText: '搜索记忆内容或分类…',
                  onChanged: (value) =>
                      setState(() => _searchQuery = value.trim().toLowerCase()),
                  onClear: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
              ),
              SectionCard(
                child: NexusSwitchListTile(
                  secondary: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppPalette.brandSoftDark
                          : AppPalette.brandSoftLight,
                      borderRadius: BorderRadius.circular(
                          MobileTheme.controlRadius(context)),
                    ),
                    child: Icon(Icons.psychology_outlined,
                        size: 20, color: MobileTheme.brand(context)),
                  ),
                  title: const Text(
                    AppStrings.memoryEnabled,
                    style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: AppTokens.fontSizeBody),
                  ),
                  subtitle: Text(
                    AppStrings.memoryEnabledHint,
                    style: TextStyle(
                      fontSize: AppTokens.fontSizeCaption,
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
                  fontSize: AppTokens.fontSizeCaption,
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
                ...filtered.indexed.map((entry) => NexusStaggeredItem(
                      index: entry.$1,
                      child: _buildMemoryCard(entry.$2, isDark),
                    )),
            ],
          ),
        ),
      )),
    );
  }
}
