import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/database/database_provider.dart';
import '../../../domain/models.dart';
import '../../agents/agents_page.dart';
import '../../history/history_page.dart';
import '../../l10n/app_strings.dart';
import '../../settings/settings_page.dart';
import '../../widgets/brand_mark.dart';
import '../../widgets/floating_toast.dart';
import '../../widgets/immersive_sheet.dart';
import '../../widgets/immersive_action_sheet.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';

/// 侧边工作台目录抽屉 (Catalog Drawer) - 对标 DeepSeek 极简风格
/// 1. 分组标签 11/500 textFaint，上间距 24 / 下间距 8，无背景
/// 2. 会话条目高 44px、圆角 8px、左右内边距 12px、主文本 14/400 text 单行省略；悬停底 surface、选中底 brandSoft；行尾「⋯」仅悬停/选中时出现
/// 3. 搜索框高 36px pill、无描边、底 surface，聚焦补 1px brand 描边
/// 4. 底部身份区加 1px hairline 顶部齐线 + 12px 内边距，头像 28px
class ChatCatalogDrawer extends StatefulWidget {
  final String? currentWorkspacePath;
  final String activeModel;
  final String activeProviderName;
  final List<ChatMessage> messages;
  final bool isRunning;
  final bool planModeEnabled;
  final ApprovalMode approvalMode;
  final VoidCallback onNewConversation;
  final ValueChanged<Conversation> onSelectConversation;
  final VoidCallback onWorkspaceTap;
  final VoidCallback onModelTap;
  final VoidCallback onMcpMenu;
  final VoidCallback onPromptLibrary;
  final VoidCallback onPlanModeToggle;
  final VoidCallback? onApprovalModeTap;
  final VoidCallback? onMore;

  /// 会话被删除后回调（chat_page 据此在删除的是当前会话时新建会话）。
  final ValueChanged<String>? onConversationDeleted;
  final VoidCallback? onOpenHistory;

  final String? currentConversationId;
  final int contextTokens;
  final int liveContextTokens;

  const ChatCatalogDrawer({
    super.key,
    this.currentConversationId,
    required this.contextTokens,
    this.liveContextTokens = 0,
    required this.currentWorkspacePath,
    required this.activeModel,
    required this.activeProviderName,
    required this.messages,
    required this.isRunning,
    required this.planModeEnabled,
    this.approvalMode = ApprovalMode.ask,
    required this.onNewConversation,
    required this.onSelectConversation,
    required this.onWorkspaceTap,
    required this.onModelTap,
    required this.onMcpMenu,
    required this.onPromptLibrary,
    required this.onPlanModeToggle,
    this.onApprovalModeTap,
    this.onMore,
    this.onConversationDeleted,
    this.onOpenHistory,
  });

  @override
  State<ChatCatalogDrawer> createState() => _ChatCatalogDrawerState();
}

class _ChatCatalogDrawerState extends State<ChatCatalogDrawer> {
  List<Conversation> _recentConversations = [];
  bool _loadingHistory = true;
  String _filterQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final db = await DatabaseProvider.instance.database;
      final list = (await db.recentConversations()).take(30).toList();
      if (mounted) {
        setState(() {
          _recentConversations = list;
          _loadingHistory = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  /// 按时间分组：今天 / 7 天内 / 30 天内 / 更早（对标 DeepSeek 抽屉）。
  List<({String label, List<Conversation> items})> _groupConversations(
      List<Conversation> list) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final buckets = <String, List<Conversation>>{};
    for (final c in list) {
      final d = c.updatedAt;
      final days = today.difference(DateTime(d.year, d.month, d.day)).inDays;
      final label = days <= 0
          ? '今天'
          : days < 7
              ? '7 天内'
              : days < 30
                  ? '30 天内'
                  : '更早';
      buckets.putIfAbsent(label, () => <Conversation>[]).add(c);
    }
    return [
      for (final label in const ['今天', '7 天内', '30 天内', '更早'])
        if (buckets[label] != null) (label: label, items: buckets[label]!),
    ];
  }

  /// 长按会话：弹出操作表。
  Future<void> _showConversationActions(Conversation conversation) async {
    unawaited(HapticFeedback.mediumImpact());
    final action = await showImmersiveActionSheet<String>(
      context: context,
      title: conversation.title.isEmpty ? '新会话' : conversation.title,
      items: const [
        ActionSheetItem(
          icon: Icons.delete_outline_rounded,
          title: '删除会话',
          subtitle: '删除后无法恢复',
          value: 'delete',
        ),
      ],
    );
    if (action == 'delete') await _deleteConversation(conversation);
  }

  Future<void> _deleteConversation(Conversation conversation) async {
    final confirmed = await showImmersiveDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除会话'),
        content: Text(
            '确定删除“${conversation.title.isEmpty ? '新会话' : conversation.title}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final db = await DatabaseProvider.instance.database;
      await db.deleteConversation(conversation.id);
      widget.onConversationDeleted?.call(conversation.id);
      if (!mounted) return;
      unawaited(HapticFeedback.mediumImpact());
      FloatingToast.show(context, '已删除会话', tone: ToastTone.success);
      await _loadData();
    } catch (_) {
      if (mounted) FloatingToast.show(context, '删除失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final width = math.min(MediaQuery.sizeOf(context).width * 0.86, 320.0);
    final canvas = isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas;
    final hairline =
        isDark ? AppPalette.darkHairline : AppPalette.lightHairline;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    final filteredConversations = _filterQuery.isEmpty
        ? _recentConversations
        : _recentConversations
            .where((c) =>
                c.title.toLowerCase().contains(_filterQuery.toLowerCase()))
            .toList();

    return Drawer(
      width: width,
      backgroundColor: canvas,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      child: SafeArea(
        child: Column(
          children: [
            // 1. 顶部 Header 与「新建对话」按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      const BrandMark(size: 28, withGlow: false),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '会话',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                            color: textColor,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭目录',
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: textMuted,
                        onPressed: () => Navigator.pop(context),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 新建对话按钮 (44px 高，8px 圆角)
                  SizedBox(
                    width: double.infinity,
                    height: AppTokens.kControlHeight,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppPalette.brand,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusControl),
                        ),
                      ),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(context);
                        widget.onNewConversation();
                      },
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text(
                        '新建对话',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // 搜索框：高 36px pill、无描边、底 surface，聚焦补 1px brand 描边
                  _DrawerSearchBar(
                    onChanged: (val) =>
                        setState(() => _filterQuery = val.trim()),
                  ),
                ],
              ),
            ),

            Divider(height: 1, thickness: 1, color: hairline),

            // 2. 中间滚动区域
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                children: [
                  // 按时间分组：今天 / 7 天内 / 30 天内（对标 DeepSeek，只显示对话）
                  if (_loadingHistory)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(
                          child: SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))),
                    )
                  else if (filteredConversations.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _filterQuery.isEmpty ? '暂无历史会话' : '未找到匹配会话',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: textMuted,
                        ),
                      ),
                    )
                  else
                    for (final group
                        in _groupConversations(filteredConversations)) ...[
                      _SectionHeader(title: group.label),
                      ...group.items.map(
                        (c) => _HistoryTile(
                          conversation: c,
                          isSelected: c.id == widget.currentConversationId,
                          onTap: () {
                            Navigator.pop(context);
                            widget.onSelectConversation(c);
                          },
                          onLongPress: () => _showConversationActions(c),
                        ),
                      ),
                    ],

                  // 分组之外保留一个低调入口，避免收藏 / 批量管理能力失联
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () async {
                        Navigator.pop(context);
                        if (widget.onOpenHistory != null) {
                          widget.onOpenHistory!();
                        } else {
                          final selected =
                              await Navigator.of(context).push<Conversation>(
                            MaterialPageRoute(
                                builder: (_) => const HistoryPage()),
                          );
                          if (selected != null) {
                            widget.onSelectConversation(selected);
                          }
                        }
                      },
                      child: const Text('查看全部会话',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: AppPalette.brand,
                          )),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),

            // 3. 底部身份区：1px hairline 顶部齐线 + 12px 内边距，头像 28px
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: hairline, width: 1.0),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppPalette.darkBrandSoft
                          : AppPalette.lightBrandSoft,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.person_rounded,
                      size: 16,
                      color: AppPalette.brand,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          AppStrings.appTitle,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: textColor,
                          ),
                        ),
                        Text(
                          '本地就绪',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Agent 管理入口
                  IconButton(
                    tooltip: 'Agent 管理',
                    icon: const Icon(Icons.smart_toy_outlined, size: 20),
                    color: textMuted,
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AgentsPage()),
                      );
                    },
                  ),
                  // 设置入口（对标 DeepSeek 抽屉右下角 ⋯ 的位置）
                  IconButton(
                    tooltip: '设置',
                    icon: const Icon(Icons.settings_outlined, size: 20),
                    color: textMuted,
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SettingsPage()),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: '更多',
                    icon: const Icon(Icons.more_horiz_rounded, size: 20),
                    color: textMuted,
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onMore?.call();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 搜索框：高 36px pill、无描边、底 surface，聚焦补 1px brand 描边
class _DrawerSearchBar extends StatefulWidget {
  final ValueChanged<String> onChanged;
  const _DrawerSearchBar({required this.onChanged});

  @override
  State<_DrawerSearchBar> createState() => _DrawerSearchBarState();
}

class _DrawerSearchBarState extends State<_DrawerSearchBar> {
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _controller = TextEditingController();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _focused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppPalette.darkSurface : AppPalette.lightSurface;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textFaint =
        isDark ? AppPalette.darkTextFaint : AppPalette.lightTextFaint;

    return Container(
      height: AppTokens.kSearchBoxHeight,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border:
            _focused ? Border.all(color: AppPalette.brand, width: 1.0) : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 16, color: textFaint),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: widget.onChanged,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: textColor,
              ),
              decoration: InputDecoration(
                hintText: '搜索历史会话…',
                hintStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: textFaint,
                ),
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _controller.clear();
                widget.onChanged('');
                setState(() {});
              },
              child: Icon(Icons.close_rounded, size: 14, color: textFaint),
            ),
        ],
      ),
    );
  }
}

/// 分组标签 11/500 textFaint，上间距 24 / 下间距 8，无背景
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textFaint =
        isDark ? AppPalette.darkTextFaint : AppPalette.lightTextFaint;

    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: textFaint,
          letterSpacing: 0.04,
          height: 1.4,
        ),
      ),
    );
  }
}

/// 工作台/工具行组件
/// 会话条目高 44px、圆角 8px、左右内边距 12px、主文本 14/400 text 单行省略
/// 悬停底 surface、选中底 brandSoft；行尾「⋯」仅悬停/选中时出现
class _HistoryTile extends StatefulWidget {
  final Conversation conversation;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _HistoryTile({
    required this.conversation,
    this.isSelected = false,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<_HistoryTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppPalette.darkSurface : AppPalette.lightSurface;
    final brandSoft =
        isDark ? AppPalette.darkBrandSoft : AppPalette.lightBrandSoft;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    final bgColor = widget.isSelected
        ? brandSoft
        : (_isHovered ? surface : Colors.transparent);

    final showMore = _isHovered || widget.isSelected;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        height: AppTokens.kControlHeight, // 44px
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppTokens.radiusControl), // 8px
        ),
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12), // 左右内边距 12px
            child: Row(
              children: [
                Icon(
                  widget.conversation.isPinned
                      ? Icons.push_pin_rounded
                      : Icons.chat_bubble_outline_rounded,
                  size: 16,
                  color: widget.isSelected ? AppPalette.brand : textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.conversation.title.isEmpty
                        ? '新会话'
                        : widget.conversation.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: textColor,
                    ),
                  ),
                ),
                if (showMore)
                  Icon(
                    Icons.more_horiz_rounded,
                    size: 16,
                    color: textMuted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
