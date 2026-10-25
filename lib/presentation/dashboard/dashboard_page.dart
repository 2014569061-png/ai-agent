import '../theme/mobile_theme.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import '../widgets/nexus_page_layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../application/error_humanizer.dart';
import '../../application/nexus_guard.dart';
import '../history/history_page.dart';
import '../jobs/jobs_inbox_page.dart';
import '../../application/jobs/job_board_providers.dart';
import '../l10n/app_strings.dart';
import '../motion/nexus_page_route_factory.dart';
import '../motion/nexus_motion.dart';
import '../motion/nexus_staggered_entrance.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../theme/desktop_theme.dart';
import '../widgets/desktop_page_summary.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/glass_scroll_edge.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/nexus_section.dart';
import '../widgets/section_card.dart';
import '../theme/app_tokens.dart';
import 'dashboard_provider.dart';
import 'widgets/kpi_card_grid.dart';
import 'widgets/run_status_list.dart';
import 'widgets/todo_section.dart';
import 'widgets/token_trend_card.dart';
import 'widgets/token_usage_hero.dart';

/// 仪表盘（Dashboard）主页
/// Agent 工作负载与运行一屏总览
///
/// 实时性策略（轻量轮询）：页面打开期间每 [refreshInterval] 刷新一次数据，
/// 使运行中任务/待办数处于流动状态；离开页面即停止，无后台开销。
/// （事件驱动方案：后续 SQL 聚合下沉后可切换为 StreamProvider 监听任务表。）
class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage(
      {super.key, this.onConversationSelected, this.initialDeveloperMode});

  final ValueChanged<String>? onConversationSelected;
  final bool? initialDeveloperMode;

  static const Duration refreshInterval = Duration(seconds: 15);

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage>
    with WidgetsBindingObserver {
  static const _developerModeKey = 'dashboard.developer_mode';
  Timer? _refreshTimer;
  bool _developerMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startRefreshTimer();
    Future.microtask(_loadPresentationMode);
  }

  Future<void> _loadPresentationMode() async {
    if (widget.initialDeveloperMode != null) {
      if (mounted) {
        setState(() => _developerMode = widget.initialDeveloperMode!);
      }
      return;
    }
    // 可忽略：读不到偏好时保持默认「简化视图」，这是更保守的呈现方式，
    // 不影响任何数据正确性。经由 application 层的 NexusGuard 记录，
    // 避免 presentation 直接依赖 infrastructure（见 layering_test）。
    final preferences = await NexusGuard.silentlyAsync<SharedPreferences>(
      'dashboard-load-presentation-mode',
      SharedPreferences.getInstance,
    );
    if (preferences != null && mounted) {
      setState(() =>
          _developerMode = preferences.getBool(_developerModeKey) ?? false);
    }
  }

  Future<void> _togglePresentationMode() async {
    final next = !_developerMode;
    setState(() => _developerMode = next);
    // 可忽略：写入失败只影响「下次启动是否记住」，本次切换已在内存生效。
    await NexusGuard.silentlyAsync<bool>(
      'dashboard-persist-presentation-mode',
      () async {
        final preferences = await SharedPreferences.getInstance();
        return preferences.setBool(_developerModeKey, next);
      },
    );
  }

  void _startRefreshTimer() {
    if (_refreshTimer != null) return;
    _refreshTimer = Timer.periodic(
      DashboardPage.refreshInterval,
      (_) {
        if (!mounted) return;
        ref.invalidate(dashboardSummaryProvider);
        ref.invalidate(inboxUnreadProvider);
      },
    );
  }

  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _startRefreshTimer();
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _stopRefreshTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopRefreshTimer();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(dashboardSummaryProvider);
    ref.invalidate(inboxUnreadProvider);
    await ref.read(dashboardSummaryProvider.future);
  }

  Future<void> _openInbox() async {
    await Navigator.of(context).push(NexusPageRoute.detail(
      builder: (_) => JobsInboxPage(
        onConversationSelected: widget.onConversationSelected,
      ),
    ));
    if (mounted) ref.invalidate(inboxUnreadProvider);
  }

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);

    final desktop = DesktopTheme.maybeOf(context);

    return Scaffold(
      backgroundColor: MobileTheme.pageBackground(context),
      appBar: NexusPageHeader(
        title: AppStrings.dashboard,
        subtitle: AppStrings.dashboardSubtitle,
        onBack: () => Navigator.of(context).pop(),
        actions: [
          Builder(builder: (context) {
            final unread = ref.watch(inboxUnreadProvider).value ?? 0;
            return IconButton(
              tooltip: unread > 0 ? '任务与收件箱（$unread 条未读）' : '任务与收件箱',
              icon: Badge(
                isLabelVisible: unread > 0,
                label: Text(unread > 99 ? '99+' : '$unread'),
                child: const Icon(Icons.inbox_outlined, size: 20),
              ),
              onPressed: _openInbox,
            );
          }),
          IconButton(
            tooltip: _developerMode ? '切换到简洁模式' : '切换到开发者模式',
            icon: Icon(_developerMode
                ? Icons.visibility_outlined
                : Icons.analytics_outlined),
            onPressed: _togglePresentationMode,
          ),
        ],
      ),
      body: NexusPageLayout(
          child: summaryAsync.when(
        loading: () => const _DashboardSkeleton(),
        error: (err, stack) {
          final humanized = humanizeError(err.toString());
          return EmptyStateView(
            icon: Icons.error_outline_rounded,
            title: humanized.summary,
            actionLabel: AppStrings.retry,
            onAction: _refresh,
          );
        },
        data: (summary) => GlassScrollEdge(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: NexusStaggeredEntrance(
              child: ListView(
                physics: NexusMotion.listPhysics,
                // U1 节奏：分区之间统一 24、同组（性能卡 + KPI）之间 12。
                // NexusSection 自带 bottom 16（待办条目另有 8），这里只补差值。
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  if (desktop != null)
                    DesktopPageSummary(items: [
                      (
                        icon: Icons.checklist_outlined,
                        label: '待办事项',
                        value: '${summary.todos.length}'
                      ),
                      (
                        icon: Icons.forum_outlined,
                        label: '近期会话',
                        value: '${summary.recentConversations.length}'
                      ),
                      (
                        icon: Icons.bolt_outlined,
                        label: '近期运行',
                        value: '${summary.recentRuns.length}'
                      ),
                    ]),
                  if (summary.todos.isEmpty &&
                      summary.recentRuns.isEmpty &&
                      summary.recentConversations.isEmpty)
                    const EmptyStateView.compact(
                      icon: Icons.insights_outlined,
                      title: '还没有运行记录',
                      message: '从助手开始对话，运行记录和用量会显示在这里。',
                    ),
                  // 默认只突出待处理事项与最近会话；技术指标收进开发者模式。
                  if (summary.todos.isNotEmpty)
                    NexusStaggeredItem(
                      index: 0,
                      child: TodoSection(
                        todos: summary.todos,
                        onConversationSelected: widget.onConversationSelected,
                      ),
                    ),
                  if (!_developerMode && summary.recentRuns.isNotEmpty) ...[
                    NexusStaggeredItem(
                      index: 1,
                      child: RunStatusList(
                        runs: summary.recentRuns,
                        onConversationSelected: widget.onConversationSelected,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (_developerMode) ...[
                    NexusStaggeredItem(
                      index: 1,
                      child: TokenUsageHero(
                          days: summary.weeklyUsage,
                          costBudget: summary.costBudget,
                          onBudgetChanged: () =>
                              ref.invalidate(dashboardSummaryProvider)),
                    ),
                    const SizedBox(height: 12),
                    NexusStaggeredItem(
                      index: 2,
                      child: KpiCardGrid(kpis: summary.kpis),
                    ),
                    const SizedBox(height: 24),
                    NexusStaggeredItem(
                      index: 3,
                      child: RunStatusList(
                        runs: summary.recentRuns,
                        onConversationSelected: widget.onConversationSelected,
                      ),
                    ),
                    const SizedBox(height: 8),
                    NexusStaggeredItem(
                      index: 4,
                      child: TokenTrendCard(days: summary.weeklyUsage),
                    ),
                    const SizedBox(height: 24),
                  ] else
                    NexusStaggeredItem(
                      index: 2,
                      child: SectionCard(
                        child: ListTile(
                          leading: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: MobileTheme.brand(context)
                                  .withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Icon(Icons.insights_rounded,
                                size: 18, color: MobileTheme.brand(context)),
                          ),
                          title: const Text('性能详情'),
                          subtitle: const Text('Token、费用、运行指标与趋势'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: _togglePresentationMode,
                        ),
                      ),
                    ),
                  if (!_developerMode) const SizedBox(height: 24),
                  if (summary.recentConversations.isNotEmpty)
                    NexusStaggeredItem(
                      index: _developerMode ? 5 : 3,
                      child: _RecentConversationsSection(
                        conversations: summary.recentConversations,
                        onConversationSelected: widget.onConversationSelected,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      )),
    );
  }
}

/// KPI 骨架屏：加载期以静态色块占位，避免整页 spinner 闪烁跳动。
/// 仅作占位，不承载可读性语义，深浅色随主题。
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    final semantic = AppTheme.semanticOf(context);
    final block = semantic.surfaceTint;

    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        // M0 占位：Hero
        _SkeletonCard(height: 168, color: block),
        const SizedBox(height: 14),
        // M1 占位：2×2
        Row(
          children: [
            Expanded(
              child: _SkeletonCard(height: 84, color: block),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SkeletonCard(height: 84, color: block),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _SkeletonCard(height: 84, color: block),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SkeletonCard(height: 84, color: block),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SkeletonCard(height: 180, color: block),
        const SizedBox(height: 14),
        _SkeletonCard(height: 120, color: block),
      ],
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(MobileTheme.cardRadius(context)),
      ),
    );
  }
}

class _RecentConversationsSection extends StatelessWidget {
  const _RecentConversationsSection({
    required this.conversations,
    this.onConversationSelected,
  });

  final List<Conversation> conversations;
  final ValueChanged<String>? onConversationSelected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hairline =
        isDark ? AppPalette.darkHairline : AppPalette.lightHairline;
    final surface = isDark ? AppPalette.darkSurface : AppPalette.lightSurface;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final textFaint =
        isDark ? AppPalette.darkTextFaint : AppPalette.lightTextMuted;

    return NexusSection(
      title: AppStrings.recentConversations,
      icon: Icons.history_rounded,
      trailing: TextButton(
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        onPressed: () {
          Navigator.of(context).push(
            NexusPageRoute.detail(builder: (_) => const HistoryPage()),
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppStrings.viewAll,
                style: TextStyle(
                    fontSize: AppTokens.fontSizeFootnote, color: textMuted)),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: 16, color: textMuted),
          ],
        ),
      ),
      child: SectionCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: conversations.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                child: EmptyStateView.compact(
                  icon: Icons.history_rounded,
                  title: AppStrings.noRecentConversations,
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: conversations.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  thickness: 1.0,
                  color: hairline,
                  indent: 16,
                  endIndent: 16,
                ),
                itemBuilder: (ctx, index) {
                  final conv = conversations[index];
                  final timeStr = _formatTime(conv.updatedAt);

                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    leading: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: hairline, width: 1.0),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        conv.isPinned
                            ? Icons.push_pin_rounded
                            : Icons.chat_bubble_outline_rounded,
                        size: 15,
                        color: textMuted,
                      ),
                    ),
                    title: Text(
                      conv.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: AppTokens.fontSizeSubhead,
                        color: textColor,
                      ),
                    ),
                    subtitle: Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: AppTokens.fontSizeBadge,
                        color: textFaint,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: textFaint,
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      onConversationSelected?.call(conv.id);
                    },
                  );
                },
              ),
      ),
    );
  }

  /// 短时间格式：MM-dd HH:mm（与历史页一致，避免各处手写 padLeft）。
  static String _formatTime(DateTime t) {
    final mm = t.month.toString().padLeft(2, '0');
    final dd = t.day.toString().padLeft(2, '0');
    final hh = t.hour.toString().padLeft(2, '0');
    final min = t.minute.toString().padLeft(2, '0');
    return '$mm-$dd $hh:$min';
  }
}
