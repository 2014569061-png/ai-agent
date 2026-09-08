import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../infrastructure/database/app_database.dart';
import '../../application/error_humanizer.dart';
import '../history/history_page.dart';
import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/nexus_section.dart';
import '../widgets/section_card.dart';
import '../theme/app_tokens.dart';
import 'dashboard_provider.dart';
import 'widgets/kpi_card_grid.dart';
import 'widgets/run_status_list.dart';
import 'widgets/todo_section.dart';
import 'widgets/token_trend_card.dart';

/// 仪表盘（Dashboard）主页
/// Agent 工作负载与运行一屏总览
///
/// 实时性策略（轻量轮询）：页面打开期间每 [refreshInterval] 刷新一次数据，
/// 使运行中任务/待办数处于流动状态；离开页面即停止，无后台开销。
/// （事件驱动方案：后续 SQL 聚合下沉后可切换为 StreamProvider 监听任务表。）
class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key, this.onConversationSelected});

  final ValueChanged<Conversation>? onConversationSelected;

  static const Duration refreshInterval = Duration(seconds: 15);

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage>
    with WidgetsBindingObserver {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startRefreshTimer();
  }

  void _startRefreshTimer() {
    if (_refreshTimer != null) return;
    _refreshTimer = Timer.periodic(
      DashboardPage.refreshInterval,
      (_) {
        if (mounted) ref.invalidate(dashboardSummaryProvider);
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
    await ref.read(dashboardSummaryProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppTheme.semanticOf(context);
    final isDark = theme.brightness == Brightness.dark;
    final summaryAsync = ref.watch(dashboardSummaryProvider);

    return Scaffold(
      backgroundColor: semantic.canvas,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [
                    const Color(0xFF0D1424),
                    AppTheme.darkBackground,
                  ]
                : [
                    const Color(0xFFEFF4FB),
                    AppTheme.background,
                  ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 顶栏 Header
              NexusPageHeader(
                title: AppStrings.dashboard,
                subtitle: AppStrings.dashboardSubtitle,
                onBack: () => Navigator.of(context).pop(),
                actions: [
                  IconButton(
                    tooltip: AppStrings.refreshDashboard,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    onPressed: _refresh,
                  ),
                ],
              ),

              // 主内容区
              Expanded(
                child: summaryAsync.when(
                  loading: () => const _DashboardSkeleton(),
                  error: (err, stack) {
                    final humanized = humanizeError(err.toString());
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline_rounded,
                                size: 40, color: semantic.danger),
                            const SizedBox(height: 12),
                            Text(
                              humanized.summary,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 14, color: semantic.textPrimary),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.tonal(
                              onPressed: _refresh,
                              child: const Text(AppStrings.retry),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  data: (summary) => RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      children: [
                        // M1: 2×2 核心指标行
                        KpiCardGrid(kpis: summary.kpis),

                        const SizedBox(height: 14),

                        // M2: Token 7 天用量趋势
                        TokenTrendCard(days: summary.weeklyUsage),

                        const SizedBox(height: 14),

                        // M4: 待我处理聚合区（有待办时展示，无待办隐去）
                        TodoSection(
                          todos: summary.todos,
                          onConversationSelected: widget.onConversationSelected,
                        ),

                        // M3: 运行状态与最近任务
                        RunStatusList(
                          runs: summary.recentRuns,
                          onConversationSelected: widget.onConversationSelected,
                        ),

                        const SizedBox(height: 14),

                        // M5: 最近会话
                        _RecentConversationsSection(
                          conversations: summary.recentConversations,
                          onConversationSelected: widget.onConversationSelected,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
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
  final ValueChanged<Conversation>? onConversationSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppTheme.semanticOf(context);

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
            MaterialPageRoute(builder: (_) => const HistoryPage()),
          );
        },
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppStrings.viewAll, style: TextStyle(fontSize: 12)),
            SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: 16),
          ],
        ),
      ),
      child: SectionCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: conversations.isEmpty
            ? Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                child: Center(
                  child: Text(
                    AppStrings.noRecentConversations,
                    style:
                        TextStyle(fontSize: 13, color: semantic.mutedOnGlass),
                  ),
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: conversations.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  thickness: 0.6,
                  color: semantic.border.withValues(alpha: 0.35),
                  indent: 16,
                  endIndent: 16,
                ),
                itemBuilder: (ctx, index) {
                  final conv = conversations[index];
                  final timeStr = _formatTime(conv.updatedAt);

                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor:
                          theme.colorScheme.primary.withValues(alpha: 0.12),
                      child: Icon(
                        conv.isPinned
                            ? Icons.push_pin_rounded
                            : Icons.chat_bubble_outline_rounded,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    title: Text(
                      conv.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                    subtitle: Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 11,
                        color: semantic.mutedOnGlass,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: Colors.grey,
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      onConversationSelected?.call(conv);
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
