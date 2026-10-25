import '../../widgets/nexus_sheet.dart';
import '../../widgets/nexus_search_field.dart';
import '../../navigation/mobile_navigation_scope.dart';
import '../../theme/mobile_theme.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/database/database_provider.dart';
import '../../../domain/models.dart';
import '../../agents/agents_page.dart';
import '../../history/history_page.dart';
import '../../dashboard/dashboard_page.dart';
import '../../settings/settings_page.dart';
import '../../widgets/floating_toast.dart';
import '../../widgets/nexus_action_sheet.dart';
import '../../widgets/confirm_action.dart';
import '../../motion/nexus_page_route_factory.dart';
import '../../widgets/nexus_loading_skeleton.dart';
import '../../theme/app_appearance_controller.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/empty_state_view.dart';
import '../../widgets/glass_surface.dart';

/// 会话目录；手机分支采用紧凑导航、按需搜索和至少 48dp 触控区域。
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
  final VoidCallback? onTasks;
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
    this.onTasks,
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
  bool _mobileSearchVisible = false;
  final _mobileSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _mobileSearchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ChatCatalogDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The shell refreshes the drawer when it opens, including after new chats.
    if (MobileNavigationScope.maybeOf(context) != null) unawaited(_loadData());
  }

  Future<void> _loadData() async {
    try {
      final db = await DatabaseProvider.instance.database;
      final list = (await db.recentConversations(limit: 30)).toList();
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

  Future<void> _openHistory() async {
    Navigator.pop(context);
    if (widget.onOpenHistory != null) {
      widget.onOpenHistory!();
      return;
    }
    final selected = await Navigator.of(context).push<Conversation>(
      NexusPageRoute.detail(builder: (_) => const HistoryPage()),
    );
    if (selected != null) widget.onSelectConversation(selected);
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

  /// 长按或点击更多：弹出紧凑型底部操作表。
  Future<void> _showConversationActions(Conversation conversation) async {
    unawaited(HapticFeedback.mediumImpact());
    final action = await showNexusActionSheet<String>(
      context: context,
      title: conversation.title.isEmpty ? '新会话' : conversation.title,
      subtitle: conversation.updatedAt.toString().substring(0, 16),
      maxHeightRatio: 0.7,
      header: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 160),
          child: SingleChildScrollView(
            child: SelectableText(
                conversation.title.isEmpty ? '新会话' : conversation.title,
                style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
        const SizedBox(height: 8),
        Text(conversation.updatedAt.toLocal().toString().substring(0, 16),
            style: Theme.of(context).textTheme.bodySmall),
      ]),
      items: [
        const ActionSheetItem(
            icon: Icons.edit_outlined, title: '重命名', value: 'rename'),
        ActionSheetItem(
          icon: conversation.isPinned
              ? Icons.push_pin_rounded
              : Icons.push_pin_outlined,
          title: conversation.isPinned ? '取消置顶' : '置顶会话',
          value: 'pin',
        ),
        const ActionSheetItem(
          icon: Icons.delete_outline_rounded,
          title: '删除会话',
          subtitle: '删除后无法恢复',
          destructive: true,
          value: 'delete',
        ),
      ],
    );
    if (!mounted) return;
    if (action == 'rename') {
      await _renameConversation(conversation);
    } else if (action == 'delete') {
      await _deleteConversation(conversation);
    } else if (action == 'pin') {
      await _togglePin(conversation);
    }
  }

  Future<void> _renameConversation(Conversation conversation) async {
    final controller = TextEditingController(text: conversation.title);
    final result = await showNexusDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名会话'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(labelText: '标题'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('保存')),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (!mounted ||
        result == null ||
        result.isEmpty ||
        result == conversation.title) {
      return;
    }
    try {
      final db = await DatabaseProvider.instance.database;
      await db.saveConversation(
          conversation.copyWith(title: result, updatedAt: DateTime.now()));
      if (mounted) await _loadData();
    } catch (_) {
      if (mounted) {
        FloatingToast.show(context, '重命名失败，请重试', tone: ToastTone.warning);
      }
    }
  }

  Future<void> _togglePin(Conversation conversation) async {
    try {
      final db = await DatabaseProvider.instance.database;
      await db.saveConversation(conversation.copyWith(
        isPinned: !conversation.isPinned,
        updatedAt: DateTime.now(),
      ));
      if (!mounted) return;
      unawaited(HapticFeedback.selectionClick());
      await _loadData();
    } catch (_) {
      // 置顶没写成功时列表不会重排，用户很容易读成「点了没反应」，与删除失败
      // 的处理保持一致，给一条明确反馈。
      if (mounted) {
        FloatingToast.show(context, '置顶操作失败，请重试', tone: ToastTone.warning);
      }
    }
  }

  Future<void> _deleteConversation(Conversation conversation) async {
    final confirmed = await showConfirmAction(
      context,
      title: '删除会话',
      message:
          '确定删除“${conversation.title.isEmpty ? '新会话' : conversation.title}”吗？',
      confirmLabel: '删除',
      isDanger: true,
    );
    if (!confirmed) return;
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

  void _openMobileTools() {
    // Capture callbacks and navigator before the drawer can be unmounted.
    final catalog = widget;
    final navigator = Navigator.of(context);
    Navigator.pop(context);
    unawaited(showNexusSheet<void>(
      context: context,
      builder: (sheetContext) {
        void openTool(VoidCallback action) {
          Navigator.pop(sheetContext);
          action();
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Text('助手与工具',
                        style: Theme.of(sheetContext).textTheme.titleLarge)),
                ListTile(
                    title: const Text('Agent'),
                    leading: const Icon(Icons.smart_toy_outlined),
                    onTap: () => openTool(() => navigator.push(
                        NexusPageRoute.detail(
                            builder: (_) => const AgentsPage())))),
                ListTile(
                    title: const Text('模型与运行'),
                    leading: const Icon(Icons.tune_rounded),
                    onTap: () => openTool(catalog.onModelTap)),
                ListTile(
                    title: const Text('MCP 与工具'),
                    leading: const Icon(Icons.hub_outlined),
                    onTap: () => openTool(catalog.onMcpMenu)),
                ListTile(
                    title: const Text('提示词'),
                    leading: const Icon(Icons.notes_rounded),
                    onTap: () => openTool(catalog.onPromptLibrary)),
                ListTile(
                    title: const Text('运行与费用'),
                    leading: const Icon(Icons.space_dashboard_outlined),
                    onTap: () => openTool(() => navigator.push(
                        NexusPageRoute.detail(
                            builder: (_) => const DashboardPage())))),
                if (catalog.onMore != null)
                  ListTile(
                      title: const Text('会话与工具'),
                      leading: const Icon(Icons.more_horiz_rounded),
                      onTap: () => openTool(catalog.onMore!)),
              ]),
        );
      },
    ));
  }

  Widget _mobileDrawer(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final conversations = _recentConversations
        .where((conversation) => conversation.title
            .toLowerCase()
            .contains(_filterQuery.toLowerCase()))
        .toList();
    void open(VoidCallback action) {
      Navigator.pop(context);
      action();
    }

    return Drawer(
      width: math.min(MediaQuery.sizeOf(context).width * .86, 344),
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(16))),
      child: SafeArea(
        minimum:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 8, 0),
            child: Row(children: [
              Expanded(
                  child: Text('NEXUS',
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w500,
                          letterSpacing: .3,
                          color: colors.onSurface))),
              IconButton(
                  tooltip: _mobileSearchVisible ? '收起搜索' : '搜索最近对话',
                  isSelected: _mobileSearchVisible,
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    setState(() {
                      _mobileSearchVisible = !_mobileSearchVisible;
                      if (!_mobileSearchVisible) {
                        _mobileSearchController.clear();
                        _filterQuery = '';
                      }
                    });
                  },
                  icon: const Icon(Icons.search_rounded, size: 20)),
              IconButton(
                  tooltip: '收起导航菜单',
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded,
                      size: 21, color: colors.onSurfaceVariant)),
            ]),
          ),
          Expanded(
              child: ListView(
            key: ValueKey(_mobileSearchVisible),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            children: [
              if (_mobileSearchVisible) ...[
                NexusSearchField(
                    controller: _mobileSearchController,
                    hintText: '搜索最近对话',
                    subdued: true,
                    autofocus: true,
                    onSubmitted: (_) => FocusScope.of(context).unfocus(),
                    compact: true,
                    onChanged: (value) =>
                        setState(() => _filterQuery = value.trim()),
                    onClear: () {
                      _mobileSearchController.clear();
                      setState(() => _filterQuery = '');
                    }),
                const SizedBox(height: 8),
              ],
              if (!_mobileSearchVisible) ...[
                ListTile(
                  minTileHeight: 48,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  minLeadingWidth: 20,
                  horizontalTitleGap: 12,
                  leading:
                      Icon(Icons.add_rounded, size: 20, color: colors.primary),
                  title: const Text('新建对话',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w400)),
                  onTap: () => open(widget.onNewConversation),
                ),
                const SizedBox(height: 4),
                const MobilePrimaryNavigation(
                    destinations: [0, 1, 2], subtleSelection: true),
              ],
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text('最近对话',
                            style: TextStyle(
                                fontSize: 13,
                                color: colors.onSurfaceVariant)))),
                TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: colors.onSurfaceVariant,
                      textStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w400),
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: _openHistory,
                    child: const Text('全部')),
              ]),
              if (_loadingHistory)
                const NexusListSkeleton(itemCount: 3)
              else if (conversations.isEmpty)
                Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 20),
                    child: Text(
                        _filterQuery.isEmpty ? '开始对话后，会在这里留下记录' : '未找到匹配会话',
                        style: TextStyle(
                            fontSize: 13,
                            height: 1.6,
                            color: colors.onSurfaceVariant)))
              else
                for (final group in _groupConversations(conversations)) ...[
                  if (group.label != '今天')
                    Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                        child: Text(group.label,
                            style: TextStyle(
                                fontSize: 12, color: colors.onSurfaceVariant))),
                  ...group.items.map((conversation) => _HistoryTile(
                        conversation: conversation,
                        isSelected:
                            conversation.id == widget.currentConversationId,
                        onTap: () => open(
                            () => widget.onSelectConversation(conversation)),
                        onLongPress: () =>
                            _showConversationActions(conversation),
                        onMoreTap: () => _showConversationActions(conversation),
                      )),
                ],
            ],
          )),
          if (!_mobileSearchVisible)
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Divider(
                      height: 1, thickness: .7, color: colors.outlineVariant),
                  ListTile(
                      minTileHeight: 48,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      minLeadingWidth: 20,
                      horizontalTitleGap: 12,
                      leading: Icon(Icons.more_horiz_rounded,
                          size: 20, color: colors.onSurfaceVariant),
                      title: const Text('助手与工具',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w400)),
                      onTap: _openMobileTools),
                  const MobilePrimaryNavigation(
                      destinations: [3], subtleSelection: true),
                ])),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (MobileNavigationScope.maybeOf(context) != null) {
      return _mobileDrawer(context);
    }
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

    final intensity = AppAppearanceController.resolvedGlassIntensity;
    final isGlass = intensity != GlassIntensity.flat;

    Widget drawerContent = SafeArea(
      child: Column(
        children: [
          // 1. 顶部搜索框（方案一 Pure Zen × Linear Pro）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: _DrawerSearchBar(
              onChanged: (val) => setState(() => _filterQuery = val.trim()),
            ),
          ),

          // 2. 中间滚动区域：主要功能入口 + 最近对话列表
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              children: [
                Divider(height: 1, thickness: 0.6, color: hairline),
                _DrawerNavTile(
                  icon: Icons.space_dashboard_outlined,
                  iconColor: MobileTheme.brand(context),
                  title: '仪表盘',
                  info: '运行与费用',
                  infoColor: MobileTheme.brand(context),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(NexusPageRoute.detail(
                        builder: (_) => const DashboardPage()));
                  },
                ),
                Divider(height: 1, thickness: 0.6, color: hairline),
                if (widget.onTasks != null)
                  _DrawerNavTile(
                    icon: Icons.inbox_outlined,
                    iconColor: AppPalette.success,
                    title: '任务收件箱',
                    info: '处理',
                    infoColor: AppPalette.success,
                    onTap: () {
                      Navigator.pop(context);
                      widget.onTasks!();
                    },
                  ),
                if (widget.onTasks != null)
                  Divider(height: 1, thickness: 0.6, color: hairline),
                _DrawerNavTile(
                  icon: Icons.folder_open_rounded,
                  iconColor: AppPalette.success,
                  title: '项目工作台',
                  info: widget.currentWorkspacePath == null ||
                          widget.currentWorkspacePath!.isEmpty
                      ? '选择项目'
                      : widget.currentWorkspacePath!
                          .split(RegExp(r'[\\/]'))
                          .last,
                  infoColor: AppPalette.success,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onWorkspaceTap();
                  },
                ),
                Divider(height: 1, thickness: 0.6, color: hairline),
                _DrawerNavTile(
                  icon: Icons.smart_toy_outlined,
                  iconColor: AppPalette.warning,
                  title: 'Agent',
                  info: '编排',
                  infoColor: AppPalette.warning,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(NexusPageRoute.detail(
                        builder: (_) => const AgentsPage()));
                  },
                ),
                Divider(height: 1, thickness: 0.6, color: hairline),
                _DrawerNavTile(
                  icon: Icons.hub_outlined,
                  iconColor: AppPalette.warning,
                  title: 'MCP 与工具',
                  info: '管理',
                  infoColor: AppPalette.warning,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onMcpMenu();
                  },
                ),
                Divider(height: 1, thickness: 0.6, color: hairline),
                _DrawerNavTile(
                  icon: Icons.tune_rounded,
                  iconColor: textMuted,
                  title: '模型与运行',
                  info:
                      widget.activeModel.isEmpty ? '选择模型' : widget.activeModel,
                  infoColor: textMuted,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onModelTap();
                  },
                ),
                Divider(height: 1, thickness: 0.6, color: hairline),
                if (widget.onMore != null)
                  _DrawerNavTile(
                    icon: Icons.more_horiz_rounded,
                    iconColor: textMuted,
                    title: '会话与工具',
                    info: '更多',
                    infoColor: textMuted,
                    onTap: () {
                      Navigator.pop(context);
                      widget.onMore!();
                    },
                  ),
                if (widget.onMore != null)
                  Divider(height: 1, thickness: 0.6, color: hairline),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text(
                      '最近对话',
                      style: TextStyle(
                        fontSize: AppTokens.fontSizeBadge,
                        fontWeight: FontWeight.w600,
                        color: textMuted,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: _openHistory,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '查看全部',
                              style: TextStyle(
                                fontSize: AppTokens.fontSizeBadge,
                                fontWeight: FontWeight.w500,
                                color: MobileTheme.brand(context),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 14,
                              color: MobileTheme.brand(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // 按时间分组：今天 / 7 天内 / 30 天内（对标 DeepSeek，只显示对话）
                if (_loadingHistory)
                  const SizedBox(
                    height: 220,
                    child: NexusListSkeleton(itemCount: 4),
                  )
                else if (filteredConversations.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: EmptyStateView.compact(
                      icon: _filterQuery.isEmpty
                          ? Icons.history_rounded
                          : Icons.search_off_rounded,
                      title: _filterQuery.isEmpty ? '暂无历史会话' : '未找到匹配会话',
                    ),
                  )
                else
                  for (final group
                      in _groupConversations(filteredConversations)) ...[
                    ...group.items.map(
                      (c) => _HistoryTile(
                        conversation: c,
                        isSelected: c.id == widget.currentConversationId,
                        onTap: () {
                          Navigator.pop(context);
                          widget.onSelectConversation(c);
                        },
                        onLongPress: () => _showConversationActions(c),
                        onMoreTap: () => _showConversationActions(c),
                      ),
                    ),
                  ],
                const SizedBox(height: 16),
              ],
            ),
          ),

          // 3. 底部 NEXUS Pro · 设置 栏（对标方案一）
          InkWell(
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(NexusPageRoute.settingsPage(
                  builder: (_) => const SettingsPage()));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: hairline, width: 0.8),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                          MobileTheme.controlRadius(context)),
                      color: isDark
                          ? AppPalette.brandSoftDark
                          : AppPalette.brandSoftLight,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'N',
                      style: TextStyle(
                        fontSize: AppTokens.fontSizeCaption,
                        fontWeight: FontWeight.w700,
                        color: MobileTheme.brand(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NEXUS · 设置',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppTokens.fontSizeSubhead,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          widget.contextTokens > 0
                              ? '${widget.activeModel.isEmpty ? '未配置模型' : widget.activeModel} · ${widget.liveContextTokens}/${widget.contextTokens} tok'
                              : (widget.activeModel.isEmpty
                                  ? '点击管理模型、权限与环境'
                                  : widget.activeModel),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppTokens.fontSizeBadge,
                            fontFamily: AppTokens.fontFamilyMono,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: textMuted,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (isGlass) {
      drawerContent = Container(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: hairline, width: 1.0),
          ),
        ),
        child: GlassSurface(
          role: GlassRole.overlay,
          variant: GlassVariant.regular,
          intensity: intensity,
          borderRadius: BorderRadius.zero,
          outlined: false,
          blurSigma: 26,
          refraction: 18,
          edgeWidth: 20,
          gloss: 0.45,
          tint: isDark
              ? AppPalette.darkCanvas.withValues(alpha: 0.92)
              : Colors.white.withValues(alpha: 0.96),
          child: drawerContent,
        ),
      );
    }

    return Drawer(
      width: width,
      backgroundColor: isGlass ? Colors.transparent : canvas,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      child: Semantics(
        namesRoute: true,
        label: '会话目录',
        child: drawerContent,
      ),
    );
  }
}

class _DrawerNavTile extends StatefulWidget {
  const _DrawerNavTile({
    required this.icon,
    this.iconColor,
    required this.title,
    this.info,
    this.infoColor,
    required this.onTap,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? info;
  final Color? infoColor;
  final VoidCallback onTap;

  @override
  State<_DrawerNavTile> createState() => _DrawerNavTileState();
}

class _DrawerNavTileState extends State<_DrawerNavTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppPalette.darkSurface : AppPalette.lightSurface;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textFaint =
        isDark ? AppPalette.darkTextFaint : AppPalette.lightTextMuted;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        height: 44,
        margin: const EdgeInsets.symmetric(vertical: 1),
        decoration: BoxDecoration(
          color: _isHovered ? surface : Colors.transparent,
          borderRadius:
              BorderRadius.circular(MobileTheme.controlRadius(context)),
        ),
        child: Semantics(
          button: true,
          container: true,
          label: widget.title,
          value: widget.info,
          hint: '打开${widget.title}',
          child: InkWell(
            onTap: widget.onTap,
            borderRadius:
                BorderRadius.circular(MobileTheme.controlRadius(context)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: (widget.iconColor ?? textColor)
                          .withValues(alpha: isDark ? 0.16 : 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      widget.icon,
                      size: 16,
                      color: widget.iconColor ?? textColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppTokens.fontSizeSubhead,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                  if (widget.info != null && widget.info!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 110),
                        child: Text(
                          widget.info!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: AppTokens.fontSizeBadge,
                              fontWeight: FontWeight.w600,
                              color: widget.infoColor ?? textFaint),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
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
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textFaint =
        isDark ? AppPalette.darkTextFaint : AppPalette.lightTextMuted;

    return Container(
      height: AppTokens.kSearchBoxHeight,
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black)
            .withValues(alpha: isDark ? 0.08 : 0.04),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border: _focused
            ? Border.all(color: MobileTheme.brand(context), width: 1.0)
            : Border.all(
                color: (isDark ? Colors.white : Colors.black)
                    .withValues(alpha: isDark ? 0.12 : 0.07),
                width: 0.8,
              ),
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
                fontSize: AppTokens.fontSizeSubhead,
                fontWeight: FontWeight.w400,
                color: textColor,
              ),
              decoration: InputDecoration(
                hintText: '搜索最近对话...',
                hintStyle: TextStyle(
                  fontSize: AppTokens.fontSizeSubhead,
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
            SizedBox(
              width: 48,
              height: 48,
              child: IconButton(
                tooltip: '清除搜索',
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                  setState(() {});
                },
                icon: Icon(Icons.close_rounded, size: 14, color: textFaint),
              ),
            ),
        ],
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
  final VoidCallback? onMoreTap;

  const _HistoryTile({
    required this.conversation,
    this.isSelected = false,
    required this.onTap,
    this.onLongPress,
    this.onMoreTap,
  });

  @override
  State<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<_HistoryTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    if (MobileNavigationScope.maybeOf(context) != null) {
      final colors = Theme.of(context).colorScheme;
      return Semantics(
        customSemanticsActions: {
          const CustomSemanticsAction(label: '会话操作'): () =>
              widget.onMoreTap?.call(),
        },
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          minTileHeight: 48,
          leading: widget.conversation.isPinned
              ? Icon(Icons.push_pin_outlined,
                  size: 18, color: colors.onSurfaceVariant)
              : null,
          minLeadingWidth: 18,
          horizontalTitleGap: 8,
          title: Text(
              widget.conversation.title.isEmpty
                  ? '新对话'
                  : widget.conversation.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w400)),
          selected: widget.isSelected,
          selectedColor: colors.onSurface,
          selectedTileColor:
              colors.surfaceContainerHighest.withValues(alpha: .5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          trailing: widget.isSelected
              ? IconButton(
                  tooltip: '会话操作',
                  onPressed: widget.onMoreTap,
                  icon: const Icon(Icons.more_horiz_rounded, size: 19))
              : null,
        ),
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brandSoft =
        isDark ? AppPalette.darkBrandSoft : AppPalette.lightBrandSoft;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    final bgColor = widget.isSelected
        ? (isDark
            ? brandSoft.withValues(alpha: 0.85)
            : brandSoft.withValues(alpha: 0.90))
        : (_isHovered
            ? (isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.black.withValues(alpha: 0.04))
            : Colors.transparent);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        height: AppTokens.kMinTouchTarget,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius:
              BorderRadius.circular(MobileTheme.controlRadius(context)), // 8px
        ),
        child: Semantics(
          button: true,
          container: true,
          label: widget.conversation.title.isEmpty
              ? '新会话'
              : widget.conversation.title,
          hint: widget.isSelected ? '当前会话' : '打开会话',
          child: InkWell(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            borderRadius:
                BorderRadius.circular(MobileTheme.controlRadius(context)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12), // 左右内边距 12px
              child: Row(
                children: [
                  Icon(
                    widget.conversation.isPinned
                        ? Icons.push_pin_rounded
                        : Icons.chat_bubble_outline_rounded,
                    size: 16,
                    color: widget.isSelected
                        ? MobileTheme.brand(context)
                        : textMuted,
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
                        fontSize: AppTokens.fontSizeSubhead,
                        fontWeight: widget.isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: widget.isSelected
                            ? MobileTheme.brand(context)
                            : textColor,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '更多会话操作',
                    onPressed: widget.onMoreTap ?? widget.onLongPress,
                    icon: Icon(Icons.more_horiz_rounded,
                        size: 18, color: textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
