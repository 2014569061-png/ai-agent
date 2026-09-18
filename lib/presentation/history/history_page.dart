import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/unique_id.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/database/database_provider.dart';
import '../../application/mojibake_repair.dart';
import '../theme/app_appearance_controller.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../motion/nexus_motion.dart';
import '../widgets/async_state_view.dart';
import '../widgets/confirm_action.dart';
import '../widgets/floating_toast.dart';
import '../widgets/glass_surface.dart';
import '../widgets/nexus_sheet.dart';
import '../widgets/nexus_action_sheet.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/section_card.dart';

typedef HistoryConversationsLoader = Future<List<Conversation>> Function();
typedef HistoryConversationsPageLoader = Future<List<Conversation>> Function({
  required int limit,
  required int offset,
});

/// 历史会话管理页'///
/// Conversation history management.
class HistoryPage extends StatefulWidget {
  final ValueChanged<Conversation>? onConversationSelected;
  final HistoryConversationsLoader? loadConversations;
  final HistoryConversationsPageLoader? loadConversationPage;

  const HistoryPage({
    super.key,
    this.onConversationSelected,
    this.loadConversations,
    this.loadConversationPage,
  });
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  static const _pageSize = 50;
  final _searchController = TextEditingController();
  String _query = '';
  String _filterType = 'all'; // 'all' | 'favorite' | 'pinned'
  List<Conversation> _conversations = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _pagedMode = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final paged = widget.loadConversations == null &&
          _query.trim().isEmpty &&
          _filterType == 'all';
      final conversations =
          paged ? await _loadPage(offset: 0) : await _loadAll();
      if (!mounted) return;
      setState(() {
        _conversations = _repairTitles(conversations);
        _pagedMode = paged;
        _hasMore = paged && conversations.length >= _pageSize;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      FloatingToast.error(context, '加载历史会话失败', rawDetail: error.toString());
    }
  }

  Future<List<Conversation>> _loadAll() async {
    final loader = widget.loadConversations;
    if (loader != null) return loader();
    return (await DatabaseProvider.instance.database).recentConversations();
  }

  Future<List<Conversation>> _loadPage({required int offset}) async {
    final loader = widget.loadConversationPage;
    if (loader != null) {
      return loader(limit: _pageSize, offset: offset);
    }
    return (await DatabaseProvider.instance.database)
        .recentConversations(limit: _pageSize, offset: offset);
  }

  List<Conversation> _repairTitles(List<Conversation> conversations) =>
      conversations
          .map((conversation) => conversation.copyWith(
                title: MojibakeRepair.repair(conversation.title),
              ))
          .toList(growable: false);

  Future<void> _loadMore() async {
    if (!_pagedMode || !_hasMore || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _loadPage(offset: _conversations.length);
      if (!mounted) return;
      setState(() {
        _conversations = [..._conversations, ..._repairTitles(page)];
        _hasMore = page.length >= _pageSize;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      FloatingToast.error(context, '加载更多会话失败', rawDetail: error.toString());
    }
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    unawaited(_reload());
  }

  List<Conversation> get _filtered {
    var list = _conversations;
    if (_filterType == 'favorite') {
      list = list.where((c) => c.isFavorite).toList();
    } else if (_filterType == 'pinned') {
      list = list.where((c) => c.isPinned).toList();
    }
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return list;
    return list.where((c) => c.title.toLowerCase().contains(query)).toList();
  }

  String _timeGroup(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(date.year, date.month, date.day);
    final differenceInDays = today.difference(itemDate).inDays;

    if (differenceInDays == 0) return '今天';
    if (differenceInDays == 1) return '昨天';
    if (differenceInDays <= 7) return '过去 7 天';
    if (differenceInDays <= 30) return '过去 30 天';
    return '${date.year} 年';
  }

  Map<String, List<Conversation>> _groupConversations(List<Conversation> list) {
    final groups = <String, List<Conversation>>{};
    if (_filterType == 'all') {
      final pinned = list.where((c) => c.isPinned).toList();
      if (pinned.isNotEmpty) {
        groups['置顶会话'] = pinned;
      }
    }
    for (final conv in list) {
      if (_filterType == 'all' && conv.isPinned) continue;
      final group = _timeGroup(conv.updatedAt);
      groups.putIfAbsent(group, () => []).add(conv);
    }
    return groups;
  }

  List<_HistoryRow> _rowsFor(Map<String, List<Conversation>> grouped) {
    final rows = <_HistoryRow>[];
    for (final entry in grouped.entries) {
      rows.add(_HistoryGroupRow(entry.key, entry.value.length));
      rows.addAll(entry.value.map(_HistoryConversationRow.new));
    }
    return rows;
  }

  Future<AppDatabase> _db() => DatabaseProvider.instance.database;

  Future<void> _rename(Conversation conversation) async {
    final controller = TextEditingController(text: conversation.title);
    final result = await showNexusDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名会话'),
        content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: '标题')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('保存')),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (result == null || result.isEmpty) return;
    final db = await _db();
    await db.saveConversation(
        conversation.copyWith(title: result, updatedAt: DateTime.now()));
    await _reload();
  }

  Future<void> _togglePinned(Conversation conversation) async {
    final db = await _db();
    await db.saveConversation(conversation.copyWith(
        isPinned: !conversation.isPinned, updatedAt: DateTime.now()));
    await _reload();
  }

  Future<void> _toggleFavorite(Conversation conversation) async {
    final db = await _db();
    await db.saveConversation(conversation.copyWith(
        isFavorite: !conversation.isFavorite, updatedAt: DateTime.now()));
    await _reload();
  }

  Future<void> _delete(Conversation conversation) async {
    final confirmed = await showConfirmAction(
      context,
      title: '删除会话',
      message: '确定删除“${conversation.title}”吗？',
      confirmLabel: '删除',
      isDanger: true,
    );
    if (!confirmed) return;
    final db = await _db();
    await db.deleteConversation(conversation.id);
    await _reload();
    if (mounted) {
      unawaited(HapticFeedback.mediumImpact());
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已删除“${conversation.title}”'),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: '撤销',
            onPressed: () async {
              await db.saveConversation(conversation);
              await _reload();
              if (mounted) {
                FloatingToast.show(context, '已恢复会话', tone: ToastTone.success);
              }
            },
          ),
        ),
      );
    }
  }

  Future<void> _newConversation() async {
    final db = await _db();
    final now = DateTime.now();
    final conversation = Conversation(
      id: UniqueId.generate('conversation', now: now),
      title: '新会话',
      agentId: null,
      mode: 'chat',
      isPinned: false,
      isFavorite: false,
      tagsJson: '[]',
      createdAt: now,
      updatedAt: now,
    );
    await db.saveConversation(conversation);
    if (mounted) Navigator.pop(context, conversation);
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟';
    if (diff.inDays < 1) return '${diff.inHours} 小时';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
  }

  Widget _filterChip(String label, String value, IconData icon) {
    final selected = _filterType == value;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isFlat =
        AppAppearanceController.resolvedGlassIntensity == GlassIntensity.flat;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        if (_filterType == value) return;
        setState(() => _filterType = value);
        unawaited(_reload());
      },
      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
      child: AnimatedContainer(
        duration: NexusMotion.durationFast(context),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? AppPalette.brandSoftDark : AppPalette.brandSoftLight)
              : (isDark
                  ? (isFlat
                      ? AppPalette.darkSurface
                      : AppPalette.darkSurface.withValues(alpha: 0.55))
                  : (isFlat
                      ? AppPalette.lightSurface
                      : AppPalette.lightSurface.withValues(alpha: 0.65))),
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          border: Border.all(
            color: selected
                ? AppPalette.brand
                : (isDark
                    ? AppPalette.darkHairline
                    : (isFlat
                        ? AppPalette.lightHairline
                        : const Color(0x80FFFFFF))),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected
                  ? AppPalette.brand
                  : (isDark
                      ? AppPalette.darkTextMuted
                      : AppPalette.lightTextMuted),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: selected
                    ? AppPalette.brand
                    : (isDark
                        ? AppPalette.darkTextMuted
                        : AppPalette.lightTextMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final grouped = _groupConversations(filtered);
    final rows = _rowsFor(grouped);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isFlat =
        AppAppearanceController.resolvedGlassIntensity == GlassIntensity.flat;

    return Scaffold(
      backgroundColor: isFlat
          ? (isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas)
          : Colors.transparent,
      appBar: const NexusPageHeader(
        title: '历史会话',
        subtitle: '搜索、置顶与管理历史记录',
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: isFlat
                ? TextField(
                    controller: _searchController,
                    onChanged: _onQueryChanged,
                    decoration: InputDecoration(
                      hintText: '搜索会话标题',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              tooltip: '清空',
                              onPressed: () {
                                _searchController.clear();
                                _onQueryChanged('');
                              },
                            )
                          : null,
                      isDense: true,
                    ),
                  )
                : GlassSurface(
                    role: GlassRole.control,
                    variant: GlassVariant.clear,
                    intensity: AppAppearanceController.resolvedGlassIntensity,
                    borderRadius:
                        BorderRadius.circular(AppTokens.radiusControl),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onQueryChanged,
                      decoration: InputDecoration(
                        hintText: '搜索会话标题',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                tooltip: '清空',
                                onPressed: () {
                                  _searchController.clear();
                                  _onQueryChanged('');
                                },
                              )
                            : null,
                        isDense: true,
                      ),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _filterChip('全部', 'all', Icons.forum_outlined),
                const SizedBox(width: 8),
                _filterChip('收藏', 'favorite', Icons.star_rounded),
                const SizedBox(width: 8),
                _filterChip('置顶', 'pinned', Icons.push_pin_rounded),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: AsyncStateView(
              loading: _loading,
              isEmpty: filtered.isEmpty,
              emptyIcon: Icons.forum_outlined,
              emptyTitle: _conversations.isEmpty
                  ? '还没有会话'
                  : (_filterType == 'favorite'
                      ? '暂无收藏的会话'
                      : (_filterType == 'pinned' ? '暂无置顶会话' : '未找到匹配的会话')),
              emptySubtitle: _conversations.isEmpty ? '开启新会话以记录交流历史' : null,
              emptyAction: _conversations.isEmpty
                  ? FilledButton(
                      onPressed: _newConversation,
                      child: const Text('新建会话'),
                    )
                  : null,
              onRetry: _reload,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 88),
                itemCount: rows.length +
                    (_pagedMode && (_hasMore || _loadingMore) ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= rows.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: _loadingMore
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : TextButton(
                                onPressed: _loadMore,
                                child: const Text('加载更多'),
                              ),
                      ),
                    );
                  }
                  final row = rows[index];
                  if (row is _HistoryGroupRow) {
                    return _groupHeader(row, isDark);
                  }
                  final conversation =
                      (row as _HistoryConversationRow).conversation;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _conversationTile(conversation),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _conversationTile(Conversation conversation) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SectionCard(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: ListTile(
        leading: Icon(
          conversation.isPinned ? Icons.push_pin : Icons.chat_bubble_outline,
          color: conversation.isPinned
              ? AppPalette.brand
              : (isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted),
        ),
        title: Row(
          children: [
            if (conversation.isFavorite) ...[
              const Icon(Icons.star, size: 16, color: AppPalette.warning),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                conversation.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          _relativeTime(conversation.updatedAt),
          style: TextStyle(
            fontSize: 13,
            color:
                isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted,
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.more_vert),
          tooltip: '更多操作',
          onPressed: () => _showConversationActions(conversation),
        ),
        onTap: () {
          final callback = widget.onConversationSelected;
          if (callback != null) {
            callback(conversation);
          } else {
            Navigator.pop(context, conversation);
          }
        },
      ),
    );
  }

  Widget _groupHeader(_HistoryGroupRow row, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        children: [
          Text(
            row.title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color:
                  isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: isDark ? AppPalette.darkSurface : AppPalette.lightSurface,
              borderRadius: BorderRadius.circular(AppTokens.radiusPill),
              border: Border.all(
                color:
                    isDark ? AppPalette.darkHairline : AppPalette.lightHairline,
              ),
            ),
            child: Text(
              '${row.count}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? AppPalette.darkTextMuted
                    : AppPalette.lightTextMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 会话行操作菜单：紧凑型底部操作表。
  Future<void> _showConversationActions(Conversation conversation) async {
    final action = await showNexusActionSheet<String>(
      context: context,
      title: conversation.title.isEmpty ? '新会话' : conversation.title,
      subtitle: _relativeTime(conversation.updatedAt),
      maxHeightRatio: 0.42,
      items: [
        ActionSheetItem(
          icon: conversation.isPinned
              ? Icons.push_pin_rounded
              : Icons.push_pin_outlined,
          title: conversation.isPinned ? '取消置顶' : '置顶会话',
          value: 'pin',
        ),
        ActionSheetItem(
          icon: conversation.isFavorite
              ? Icons.star_rounded
              : Icons.star_outline_rounded,
          title: conversation.isFavorite ? '取消收藏' : '收藏会话',
          value: 'favorite',
        ),
        const ActionSheetItem(
          icon: Icons.edit_outlined,
          title: '重命名',
          value: 'rename',
        ),
        const ActionSheetItem(
          icon: Icons.delete_outline_rounded,
          title: '删除会话',
          destructive: true,
          value: 'delete',
        ),
      ],
    );
    switch (action) {
      case 'pin':
        unawaited(_togglePinned(conversation));
      case 'favorite':
        unawaited(_toggleFavorite(conversation));
      case 'rename':
        unawaited(_rename(conversation));
      case 'delete':
        unawaited(_delete(conversation));
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

sealed class _HistoryRow {
  const _HistoryRow();
}

class _HistoryGroupRow extends _HistoryRow {
  const _HistoryGroupRow(this.title, this.count);

  final String title;
  final int count;
}

class _HistoryConversationRow extends _HistoryRow {
  const _HistoryConversationRow(this.conversation);

  final Conversation conversation;
}
