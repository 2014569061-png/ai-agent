import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/database/database_provider.dart';
import '../../application/mojibake_repair.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/floating_toast.dart';
import '../widgets/immersive_sheet.dart';
import '../widgets/section_card.dart';

/// 历史会话管理页'///
/// Conversation history management.
class HistoryPage extends StatefulWidget {
  final ValueChanged<Conversation>? onConversationSelected;

  const HistoryPage({super.key, this.onConversationSelected});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _searchController = TextEditingController();
  String _query = '';
  String _filterType = 'all'; // 'all' | 'favorite' | 'pinned'
  List<Conversation> _conversations = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final database = await DatabaseProvider.instance.database;
    final conversations = await database.recentConversations();
    if (!mounted) return;
    setState(() {
      _conversations = conversations
          .map((conversation) => conversation.copyWith(
                title: MojibakeRepair.repair(conversation.title),
              ))
          .toList();
      _loading = false;
    });
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
    return list
        .where((c) => c.title.toLowerCase().contains(query))
        .toList();
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

  Future<AppDatabase> _db() => DatabaseProvider.instance.database;

  Future<void> _rename(Conversation conversation) async {
    final controller = TextEditingController(text: conversation.title);
    final result = await showImmersiveDialog<String>(
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
    controller.dispose();
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
    final confirmed = await showImmersiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除会话'),
        content: Text('确定删除“${conversation.title}”吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    final db = await _db();
    await db.deleteConversation(conversation.id);
    await _reload();
    if (mounted) {
      HapticFeedback.mediumImpact();
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
      id: 'conversation-${now.microsecondsSinceEpoch}',
      title: '新会话',
      agentId: null,
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
    final theme = Theme.of(context);
    final semantic = AppTheme.semanticOf(context);

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _filterType = value);
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.15)
              : semantic.surfaceTint.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.5)
                : semantic.border.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected
                  ? theme.colorScheme.primary
                  : semantic.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? theme.colorScheme.primary
                    : semantic.textMuted,
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
    final semantic = AppTheme.semanticOf(context);

    return Scaffold(
      appBar: AppBar(title: const Text('历史会话')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newConversation,
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('新建会话'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: '搜索会话标题',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: '清空',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                isDense: true,
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
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? EmptyStateView(
                        icon: Icons.forum_outlined,
                        title: _conversations.isEmpty
                            ? '还没有会话'
                            : (_filterType == 'favorite'
                                ? '暂无收藏的会话'
                                : (_filterType == 'pinned'
                                    ? '暂无置顶会话'
                                    : '未找到匹配的会话')),
                        message: _conversations.isEmpty ? '点击右下角新建会话' : null,
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 88),
                        children: [
                          for (final entry in grouped.entries) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                              child: Row(
                                children: [
                                  Text(
                                    entry.key,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: semantic.textMuted,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: semantic.surfaceTint,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${entry.value.length}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: semantic.textMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            for (final conversation in entry.value)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: _conversationTile(conversation),
                              ),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _conversationTile(Conversation conversation) {
    final theme = Theme.of(context);
    return SectionCard(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: ListTile(
        leading: Icon(
          conversation.isPinned ? Icons.push_pin : Icons.chat_bubble_outline,
          color: conversation.isPinned
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
        ),
        title: Row(
          children: [
            if (conversation.isFavorite) ...[
              Icon(Icons.star, size: 16, color: Colors.amber.shade600),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                conversation.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Text(_relativeTime(conversation.updatedAt)),
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

  /// 会话行操作菜单：与全应用一致的沉浸式毛玻璃面板。
  Future<void> _showConversationActions(Conversation conversation) async {
    final action = await showImmersiveSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: Text(conversation.isPinned ? '取消置顶' : '置顶'),
              onTap: () => Navigator.pop(sheetContext, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: Text(conversation.isFavorite ? '取消收藏' : '收藏'),
              onTap: () => Navigator.pop(sheetContext, 'favorite'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('重命名'),
              onTap: () => Navigator.pop(sheetContext, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除'),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'pin':
        _togglePinned(conversation);
      case 'favorite':
        _toggleFavorite(conversation);
      case 'rename':
        _rename(conversation);
      case 'delete':
        _delete(conversation);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
